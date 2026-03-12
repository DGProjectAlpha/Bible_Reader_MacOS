import Foundation
import SwiftUI
import Combine

// MARK: - ReaderPane (plain value type — no ObservableObject, no @Published)

struct ReaderPane: Identifiable {
    let id: UUID
    var translationId: UUID
    var book: String
    var chapter: Int
    var verses: [Verse]
    var versificationScheme: String
    var verticalBuddyId: UUID?
    /// Whether this pane participates in cross-pane sync (navigation + scroll).
    var isSyncEnabled: Bool

    var chapterCount: Int {
        let scheme = VersificationScheme.from(versificationScheme)
        return VersificationService.shared.chapterCount(book: book, scheme: scheme)
    }

    init(id: UUID = UUID(), translationId: UUID, book: String = "Genesis", chapter: Int = 1) {
        self.id = id
        self.translationId = translationId
        self.book = book
        self.chapter = chapter
        self.verses = []
        self.versificationScheme = "kjv"
        self.verticalBuddyId = nil
        self.isSyncEnabled = false
    }
}

// MARK: - BibleStore

@MainActor
class BibleStore: ObservableObject {
    @Published var loadedTranslations: [Translation] = []
    @Published var bookmarks: [Bookmark] = [] { didSet { rebuildBookmarkIndex() } }
    @Published var notes: [Note] = [] { didSet { rebuildNoteIndex() } }
    @Published var highlights: [Highlight] = [] { didSet { rebuildHighlightIndex() } }
    @Published var readingHistory: [ReadingHistoryEntry] = []
    @Published var searchResults: [SearchResult] = []

    // O(1) lookup indices
    private var bookmarkIndex: Set<String> = []
    private var bookmarkByVerse: [String: Bookmark] = [:]
    private var highlightByVerse: [String: Highlight] = [:]
    private var noteByVerse: [String: Note] = [:]

    private func verseKey(_ verseId: String, _ translationId: UUID) -> String {
        "\(verseId)|\(translationId.uuidString)"
    }
    private func rebuildBookmarkIndex() {
        bookmarkIndex = Set(bookmarks.map { verseKey($0.verseId, $0.translationId) })
        bookmarkByVerse = Dictionary(bookmarks.map { (verseKey($0.verseId, $0.translationId), $0) }, uniquingKeysWith: { first, _ in first })
    }
    private func rebuildHighlightIndex() {
        highlightByVerse = Dictionary(highlights.map { (verseKey($0.verseId, $0.translationId), $0) }, uniquingKeysWith: { _, last in last })
    }
    private func rebuildNoteIndex() {
        noteByVerse = Dictionary(notes.map { (verseKey($0.verseId, $0.translationId), $0) }, uniquingKeysWith: { first, _ in first })
    }

    private let moduleManager = ModuleManager.shared
    private let userDataService = UserDataService.shared

    static var modulesDirectory: URL {
        ModuleManager.shared.modulesDirectory
    }

    init() {
        moduleManager.scanModules()
        loadedTranslations = moduleManager.loadTranslations()
        bookmarks = userDataService.loadBookmarks()
        highlights = userDataService.loadHighlights()
        notes = userDataService.loadNotes()
        readingHistory = userDataService.loadHistory()
        rebuildBookmarkIndex()
        rebuildHighlightIndex()
        rebuildNoteIndex()
        registerStrongsCapableModules()
    }

    /// Register any loaded modules that have a `strongs` table so they can serve
    /// as fallback concordance sources for modules (like RST) that don't.
    private func registerStrongsCapableModules() {
        for translation in loadedTranslations {
            if let conn = try? ModuleConnectionPool.shared.connection(for: translation.filePath),
               (try? conn.tableExists("strongs")) == true {
                StrongsService.registerStrongsCapableModule(translation.filePath)
            }
        }
    }

    // MARK: - Translation helpers

    func firstTranslationId() -> UUID? {
        loadedTranslations.first?.id
    }

    func translation(for id: UUID) -> Translation? {
        loadedTranslations.first { $0.id == id }
    }

    // MARK: - Verse Loading

    /// Load verses for a given translation/book/chapter. Returns the loaded verses.
    func loadVerses(translationId: UUID, book: String, chapter: Int) -> [Verse] {
        guard let translation = translation(for: translationId) else { return [] }
        do {
            var verses = try ModuleService.loadVerses(
                from: translation.filePath,
                book: book,
                chapter: chapter
            )
            if translation.metadata.format == .tagged {
                let tagsByVerse = try ModuleService.loadWordTagsForChapter(
                    from: translation.filePath,
                    book: book,
                    chapter: chapter
                )
                if !tagsByVerse.isEmpty {
                    verses = verses.map { verse in
                        if let tags = tagsByVerse[verse.id], !tags.isEmpty {
                            return Verse(book: verse.book, chapter: verse.chapter,
                                        number: verse.number, text: verse.text, wordTags: tags)
                        }
                        return verse
                    }
                }
            }
            recordHistory(book: book, chapter: chapter, translationAbbreviation: translation.abbreviation)
            return verses
        } catch {
            print("Failed to load verses: \(error)")
            return []
        }
    }

    // MARK: - Bookmarks

    func addBookmark(verseId: String, translationId: UUID, label: String? = nil) {
        guard !isBookmarked(verseId: verseId, translationId: translationId) else { return }
        let bookmark = Bookmark(verseId: verseId, translationId: translationId, label: label)
        userDataService.insertBookmark(bookmark)
        bookmarks.insert(bookmark, at: 0)
    }

    func removeBookmark(_ id: UUID) {
        if let bm = bookmarks.first(where: { $0.id == id }) {
            bookmarkIndex.remove(verseKey(bm.verseId, bm.translationId))
        }
        userDataService.deleteBookmark(id)
        bookmarks.removeAll { $0.id == id }
    }

    func isBookmarked(verseId: String, translationId: UUID) -> Bool {
        bookmarkIndex.contains(verseKey(verseId, translationId))
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
        bookmarks = userDataService.loadBookmarks()
    }

    func bookmarkFor(verseId: String, translationId: UUID) -> Bookmark? {
        bookmarkByVerse[verseKey(verseId, translationId)]
    }

    // MARK: - Highlights

    func setHighlight(verseId: String, translationId: UUID, color: HighlightColor) {
        highlights.removeAll { $0.verseId == verseId && $0.translationId == translationId }
        let highlight = Highlight(verseId: verseId, translationId: translationId, color: color)
        userDataService.insertHighlight(highlight)
        highlights.append(highlight)
    }

    func removeHighlight(verseId: String, translationId: UUID) {
        userDataService.deleteHighlight(verseId: verseId, translationId: translationId)
        highlights.removeAll { $0.verseId == verseId && $0.translationId == translationId }
    }

    func highlightFor(verseId: String, translationId: UUID) -> Highlight? {
        highlightByVerse[verseKey(verseId, translationId)]
    }

    // MARK: - Notes

    func addNote(verseId: String, translationId: UUID, content: String) {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let idx = notes.firstIndex(where: { $0.verseId == verseId && $0.translationId == translationId }) {
            notes[idx].content = content
            notes[idx].updatedAt = Date()
            userDataService.updateNote(id: notes[idx].id, content: content)
        } else {
            let note = Note(verseId: verseId, translationId: translationId, content: content)
            userDataService.insertNote(note)
            notes.insert(note, at: 0)
        }
    }

    func removeNote(_ id: UUID) {
        userDataService.deleteNote(id)
        notes.removeAll { $0.id == id }
        rebuildNoteIndex()
    }

    func noteFor(verseId: String, translationId: UUID) -> Note? {
        noteByVerse[verseKey(verseId, translationId)]
    }

    // MARK: - Reading History

    func recordHistory(book: String, chapter: Int, verse: Int? = nil, translationAbbreviation: String) {
        if userDataService.lastEntryMatches(book: book, chapter: chapter, verse: verse, translationAbbreviation: translationAbbreviation) {
            return
        }
        let entry = ReadingHistoryEntry(book: book, chapter: chapter, verse: verse, translationAbbreviation: translationAbbreviation)
        userDataService.insertHistoryEntry(entry)
        userDataService.trimHistory(keepLast: 500)
        readingHistory = userDataService.loadHistory()
    }

    func clearHistory() {
        userDataService.clearHistory()
        readingHistory.removeAll()
    }

    // MARK: - Module Management

    func importModule(from url: URL) async throws {
        let translation = try moduleManager.importModule(from: url)
        loadedTranslations.append(translation)
        // Register as strongs-capable if applicable
        if let conn = try? ModuleConnectionPool.shared.connection(for: translation.filePath),
           (try? conn.tableExists("strongs")) == true {
            StrongsService.registerStrongsCapableModule(translation.filePath)
        }
    }

    func removeTranslation(_ id: UUID) {
        guard let translation = loadedTranslations.first(where: { $0.id == id }) else { return }
        moduleManager.removeModule(filePath: translation.filePath)
        loadedTranslations.removeAll { $0.id == id }
        NotificationCenter.default.post(name: .translationRemoved, object: nil, userInfo: ["translationId": id])
    }

    func reorderTranslations(from source: IndexSet, to destination: Int) {
        loadedTranslations.move(fromOffsets: source, toOffset: destination)
    }

    func refreshModules() {
        moduleManager.scanModules()
        loadedTranslations = moduleManager.loadTranslations()
    }

    func isModuleInstalled(abbreviation: String) -> Bool {
        moduleManager.isInstalled(abbreviation: abbreviation)
    }

    func validateModule(at url: URL) -> ModuleValidationResult {
        moduleManager.validate(fileURL: url)
    }

    func moduleInfo(for translationId: UUID) -> CachedModuleInfo? {
        guard let translation = loadedTranslations.first(where: { $0.id == translationId }) else { return nil }
        return moduleManager.getCachedInfo(for: translation.filePath)
    }

    func listBooks(translationId: UUID) -> [(book: String, chapterCount: Int)] {
        guard let translation = loadedTranslations.first(where: { $0.id == translationId }) else { return [] }
        return (try? ModuleService.listBooks(from: translation.filePath)) ?? []
    }

    // MARK: - Profile Management

    func switchProfile(to profileName: String) {
        userDataService.setActiveProfile(profileName)
        reloadUserData()
    }

    func deleteProfileData(_ profileName: String) {
        userDataService.deleteProfileData(profileName)
    }

    func clearAllUserData() {
        userDataService.clearBookmarks()
        userDataService.clearHighlights()
        userDataService.clearNotes()
        userDataService.clearHistory()
        reloadUserData()
    }

    private func reloadUserData() {
        bookmarks = userDataService.loadBookmarks()
        highlights = userDataService.loadHighlights()
        notes = userDataService.loadNotes()
        readingHistory = userDataService.loadHistory()
    }

    // MARK: - Versification

    func versificationScheme(for translationId: UUID) -> String {
        translation(for: translationId)?.versificationScheme ?? "kjv"
    }

    func convertPosition(book: String, chapter: Int, verse: Int,
                         from oldTranslationId: UUID, to newTranslationId: UUID) -> (book: String, chapter: Int) {
        guard let oldT = translation(for: oldTranslationId),
              let newT = translation(for: newTranslationId) else { return (book, chapter) }
        let src = VersificationScheme.from(oldT.versificationScheme)
        let dst = VersificationScheme.from(newT.versificationScheme)
        guard src != dst else { return (book, chapter) }
        let converted = VersificationService.shared.convert(book: book, chapter: chapter, verse: verse, from: src, to: dst)
        let maxCh = VersificationService.shared.chapterCount(book: converted.book, scheme: dst)
        return (converted.book, min(converted.chapter, max(1, maxCh)))
    }

    // MARK: - Search

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
            print("Search failed: \(error)")
            searchResults = []
        }
    }
}
