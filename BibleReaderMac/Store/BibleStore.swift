import Foundation
import SwiftUI
import Combine

class ReaderPane: ObservableObject, Identifiable {
    let id: UUID
    @Published var selectedTranslationId: UUID = UUID()
    @Published var selectedBook: String = "Genesis"
    @Published var selectedChapter: Int = 1
    @Published var verses: [Verse] = []

    var chapterCount: Int {
        BibleBooks.chapterCounts[selectedBook] ?? 1
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
    @Published var searchResults: [SearchResult] = []

    private let moduleManager = ModuleManager.shared

    static var modulesDirectory: URL {
        ModuleManager.shared.modulesDirectory
    }

    init() {
        // Scan disk for modules — picks up manually-added files and validates everything
        moduleManager.scanModules()
        loadedTranslations = moduleManager.loadTranslations()
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
        do {
            pane.verses = try ModuleService.loadVerses(
                from: translation.filePath,
                book: pane.selectedBook,
                chapter: pane.selectedChapter
            )
        } catch {
            print("Failed to load verses: \(error.localizedDescription)")
            pane.verses = []
        }
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
