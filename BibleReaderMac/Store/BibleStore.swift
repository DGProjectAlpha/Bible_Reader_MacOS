import Foundation
import SwiftUI
import Combine

class ReaderPane: ObservableObject, Identifiable {
    let id: UUID
    @Published var selectedTranslationId: UUID = UUID()
    @Published var selectedBook: String = "Genesis"
    @Published var selectedChapter: Int = 1
    @Published var verses: [Verse] = []

    /// Versification scheme string from the currently selected translation (set by BibleStore).
    var versificationScheme: String = "kjv"

    var chapterCount: Int {
        let scheme = VersificationScheme.from(versificationScheme)
        return VersificationService.shared.chapterCount(book: selectedBook, scheme: scheme)
    }

    init(id: UUID = UUID()) {
        self.id = id
    }
}

@MainActor
class BibleStore: ObservableObject {
    @Published var loadedTranslations: [Translation] = []
    @Published var panes: [ReaderPane] = [ReaderPane()]
    @Published var bookmarks: [Bookmark] = []
    @Published var notes: [Note] = []
    @Published var readingHistory: [ReadingHistoryEntry] = []
    @Published var searchResults: [SearchResult] = []

    private let moduleManager = ModuleManager.shared
    private let userDataService = UserDataService.shared

    static var modulesDirectory: URL {
        ModuleManager.shared.modulesDirectory
    }

    init() {
        // Scan disk for modules — picks up manually-added files and validates everything
        moduleManager.scanModules()
        loadedTranslations = moduleManager.loadTranslations()
        bookmarks = userDataService.loadBookmarks()
        readingHistory = userDataService.loadHistory()
        restoreLastPosition()
    }

    /// Restore the first pane to the last viewed book/chapter/translation on startup.
    private func restoreLastPosition() {
        guard let last = userDataService.lastViewedPosition(),
              let pane = panes.first else { return }

        // Match the translation by abbreviation
        if let translation = loadedTranslations.first(where: { $0.abbreviation == last.translationAbbreviation }) {
            pane.selectedTranslationId = translation.id
        }

        pane.selectedBook = last.book
        pane.selectedChapter = last.chapter
    }

    // MARK: - Bookmarks

    func addBookmark(verseId: String, translationId: UUID, label: String? = nil) {
        // Don't duplicate
        guard !bookmarks.contains(where: { $0.verseId == verseId && $0.translationId == translationId }) else { return }
        let bookmark = Bookmark(verseId: verseId, translationId: translationId, label: label)
        userDataService.insertBookmark(bookmark)
        bookmarks.insert(bookmark, at: 0)
    }

    func removeBookmark(_ id: UUID) {
        userDataService.deleteBookmark(id)
        bookmarks.removeAll { $0.id == id }
    }

    func isBookmarked(verseId: String, translationId: UUID) -> Bool {
        bookmarks.contains { $0.verseId == verseId && $0.translationId == translationId }
    }

    func updateBookmarkNote(id: UUID, note: String?) {
        userDataService.updateBookmarkNote(id, note: note)
        if let idx = bookmarks.firstIndex(where: { $0.id == id }) {
            bookmarks[idx].note = note
            bookmarks[idx].updatedAt = Date()
        }
    }

    func updateBookmarkLabel(id: UUID, label: String?) {
        userDataService.updateBookmarkLabel(id, label: label)
        // Reload from DB since label is let
        bookmarks = userDataService.loadBookmarks()
    }

    func bookmarkFor(verseId: String, translationId: UUID) -> Bookmark? {
        bookmarks.first { $0.verseId == verseId && $0.translationId == translationId }
    }

    // MARK: - Reading History

    func recordHistory(book: String, chapter: Int, verse: Int? = nil, translationAbbreviation: String) {
        // Deduplicate consecutive identical entries
        if userDataService.lastEntryMatches(book: book, chapter: chapter, verse: verse, translationAbbreviation: translationAbbreviation) {
            return
        }
        let entry = ReadingHistoryEntry(book: book, chapter: chapter, verse: verse, translationAbbreviation: translationAbbreviation)
        userDataService.insertHistoryEntry(entry)
        userDataService.trimHistory(keepLast: 500)
        // Refresh in-memory list
        readingHistory = userDataService.loadHistory()
    }

    func clearHistory() {
        userDataService.clearHistory()
        readingHistory.removeAll()
    }

    func addPane() {
        let pane = ReaderPane()
        if let firstTranslation = loadedTranslations.first {
            pane.selectedTranslationId = firstTranslation.id
        }
        panes.append(pane)
    }

    func removePane(_ id: UUID) {
        guard panes.count > 1 else { return }
        panes.removeAll { $0.id == id }
    }

    func importModule(from url: URL) async throws {
        let translation = try moduleManager.importModule(from: url)
        loadedTranslations.append(translation)
    }

    func removeTranslation(_ id: UUID) {
        guard let translation = loadedTranslations.first(where: { $0.id == id }) else { return }
        moduleManager.removeModule(filePath: translation.filePath)
        loadedTranslations.removeAll { $0.id == id }
        // Clear any panes that pointed at this translation
        for pane in panes where pane.selectedTranslationId == id {
            pane.selectedTranslationId = loadedTranslations.first?.id ?? UUID()
        }
    }

    /// Reorder translations via drag/drop or list move.
    func reorderTranslations(from source: IndexSet, to destination: Int) {
        loadedTranslations.move(fromOffsets: source, toOffset: destination)
    }

    /// Re-scan disk for any new or removed modules.
    func refreshModules() {
        moduleManager.scanModules()
        loadedTranslations = moduleManager.loadTranslations()
    }

    /// Check if a module abbreviation is already installed.
    func isModuleInstalled(abbreviation: String) -> Bool {
        moduleManager.isInstalled(abbreviation: abbreviation)
    }

    /// Validate a module file before importing.
    func validateModule(at url: URL) -> ModuleValidationResult {
        moduleManager.validate(fileURL: url)
    }

    /// Load verses for a pane, updating its published verses array.
    func loadVerses(for pane: ReaderPane) {
        guard let translation = loadedTranslations.first(where: { $0.id == pane.selectedTranslationId }) else {
            pane.verses = []
            return
        }
        // Keep pane's versification scheme in sync with the selected translation
        pane.versificationScheme = translation.versificationScheme
        do {
            pane.verses = try ModuleService.loadVerses(
                from: translation.filePath,
                book: pane.selectedBook,
                chapter: pane.selectedChapter
            )
            // Record reading history
            recordHistory(book: pane.selectedBook, chapter: pane.selectedChapter, translationAbbreviation: translation.abbreviation)
        } catch {
            print("Failed to load verses: \(error.localizedDescription)")
            pane.verses = []
        }
    }

    /// Convert a pane's current book/chapter/verse position from one translation's
    /// versification scheme to another when the user switches translations.
    /// Returns true if the position was adjusted.
    @discardableResult
    func convertPanePosition(for pane: ReaderPane, from oldTranslationId: UUID, to newTranslationId: UUID, currentVerse: Int? = nil) -> Bool {
        guard let oldTranslation = loadedTranslations.first(where: { $0.id == oldTranslationId }),
              let newTranslation = loadedTranslations.first(where: { $0.id == newTranslationId }) else {
            return false
        }

        let sourceScheme = VersificationScheme.from(oldTranslation.versificationScheme)
        let targetScheme = VersificationScheme.from(newTranslation.versificationScheme)

        // Same scheme — no conversion needed
        guard sourceScheme != targetScheme else { return false }

        let versification = VersificationService.shared
        let verse = currentVerse ?? 1

        // Convert current position
        let converted = versification.convert(
            book: pane.selectedBook,
            chapter: pane.selectedChapter,
            verse: verse,
            from: sourceScheme,
            to: targetScheme
        )

        var changed = false

        // Update book if it changed (e.g., "1 Kingdoms" ↔ "1 Samuel")
        if converted.book != pane.selectedBook {
            pane.selectedBook = converted.book
            changed = true
        }

        // Clamp chapter to valid range for the target scheme
        let maxChapter = versification.chapterCount(book: converted.book, scheme: targetScheme)
        let newChapter = min(converted.chapter, max(1, maxChapter))
        if newChapter != pane.selectedChapter {
            pane.selectedChapter = newChapter
            changed = true
        }

        return changed
    }

    /// Search across a specific translation.
    func search(query: String, translationId: UUID, scope: SearchScope = .bible, currentBook: String? = nil, currentChapter: Int? = nil) {
        guard let translation = loadedTranslations.first(where: { $0.id == translationId }) else {
            searchResults = []
            return
        }
        do {
            searchResults = try ModuleService.search(
                in: translation.filePath,
                query: query,
                scope: scope,
                currentBook: currentBook,
                currentChapter: currentChapter
            ).map { result in
                SearchResult(
                    translationAbbreviation: translation.abbreviation,
                    book: result.book,
                    chapter: result.chapter,
                    verse: result.verse,
                    text: result.text,
                    matchRange: result.matchRange
                )
            }
        } catch {
            print("Search failed: \(error.localizedDescription)")
            searchResults = []
        }
    }

    /// Get list of books from the actual module database.
    func listBooks(translationId: UUID) -> [(book: String, chapterCount: Int)] {
        guard let translation = loadedTranslations.first(where: { $0.id == translationId }) else {
            return []
        }
        return (try? ModuleService.listBooks(from: translation.filePath)) ?? []
    }

    // MARK: - Module Info

    /// Get detailed cached info for a loaded translation.
    func moduleInfo(for translationId: UUID) -> CachedModuleInfo? {
        guard let translation = loadedTranslations.first(where: { $0.id == translationId }) else { return nil }
        return moduleManager.getCachedInfo(for: translation.filePath)
    }
}
