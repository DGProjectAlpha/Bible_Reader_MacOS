import Foundation

@MainActor @Observable
final class BibleStore {
    var modules: [Module] = []
    var activeModuleId: String = ""
    var panes: [ReadingPane] = []
    var activePaneId: UUID? = nil
    var loadingState: LoadingState = .idle
    var syncEnabled: Bool = false
    var syncedLocation: BibleLocation? = nil
    var syncedVerseId: String? = nil

    var onNavigate: ((BibleLocation) async -> Void)?

    private var chapterCache: [String: [Verse]] = [:]

    private let databaseService = DatabaseService.shared

    // MARK: - Module Loading

    func loadModules() async throws {
        loadingState = .loading

        let discovered = ModuleManager.discoverModules()
        var loaded: [Module] = []

        for info in discovered {
            do {
                try await databaseService.openModule(id: info.id, path: info.path)
                let books = try await databaseService.fetchBooks(moduleId: info.id)

                let metadata = try? await databaseService.fetchMetadata(moduleId: info.id)
                let name = metadata?["name"] ?? info.id
                let abbreviation = metadata?["abbreviation"] ?? info.id.uppercased()
                let language = metadata?["language"] ?? "en"
                let scheme = VersificationScheme.from(metadata?["versification"] ?? "kjv")

                let sortedBooks = books.sorted { a, b in
                    let ia = BibleBooks.sortIndex(for: a.name) ?? Int.max
                    let ib = BibleBooks.sortIndex(for: b.name) ?? Int.max
                    return ia < ib
                }

                // Register modules that have a strongs table for fallback lookups
                if let hasStrongs = try? await databaseService.hasTable(moduleId: info.id, name: "strongs"),
                   hasStrongs {
                    await StrongsService.shared.registerStrongsCapableModule(info.id)
                }

                loaded.append(Module(
                    id: info.id,
                    name: name,
                    abbreviation: abbreviation,
                    language: language,
                    books: sortedBooks,
                    versificationScheme: scheme
                ))
            } catch {
                // Skip modules that fail to open
                continue
            }
        }

        modules = loaded

        if activeModuleId.isEmpty, let first = modules.first {
            activeModuleId = first.id
        }

        if panes.isEmpty, let firstModule = modules.first, let firstBook = firstModule.books.first {
            let location = BibleLocation(moduleId: firstModule.id, book: firstBook.id, chapter: 1)
            let pane = ReadingPane(id: UUID(), location: location, splitDirection: .horizontal)
            panes = [pane]
            activePaneId = pane.id
            await onNavigate?(location)
        }

        loadingState = .loaded
    }

    // MARK: - Chapter Loading

    func loadChapter(moduleId: String, book: String, chapter: Int) async throws -> [Verse] {
        let cacheKey = "\(moduleId).\(book).\(chapter)"

        if let cached = chapterCache[cacheKey] {
            return cached
        }

        let verses = try await databaseService.fetchVerses(moduleId: moduleId, book: book, chapter: chapter)
        chapterCache[cacheKey] = verses
        return verses
    }

    // MARK: - Navigation

    func navigate(paneId: UUID, to location: BibleLocation) async {
        guard let index = panes.firstIndex(where: { $0.id == paneId }) else { return }
        panes[index].location = location

        _ = try? await loadChapter(moduleId: location.moduleId, book: location.book, chapter: location.chapter)
        await onNavigate?(location)

        if syncEnabled {
            syncedLocation = location
            for i in panes.indices where panes[i].id != paneId {
                let otherModuleId = panes[i].location.moduleId
                let converted = convertPosition(
                    book: location.book, chapter: location.chapter, verse: 1,
                    from: location.moduleId, to: otherModuleId
                )
                let syncedLoc = BibleLocation(moduleId: otherModuleId, book: converted.book, chapter: converted.chapter)
                panes[i].location = syncedLoc
                _ = try? await loadChapter(moduleId: otherModuleId, book: converted.book, chapter: converted.chapter)
            }
        }
    }

    func navigatePreviousChapter() async {
        guard let paneId = activePaneId,
              let pane = panes.first(where: { $0.id == paneId }),
              let module = modules.first(where: { $0.id == pane.location.moduleId }) else { return }

        let loc = pane.location
        if loc.chapter > 1 {
            await navigate(paneId: paneId, to: BibleLocation(moduleId: loc.moduleId, book: loc.book, chapter: loc.chapter - 1))
        } else if let bookIndex = module.books.firstIndex(where: { $0.id == loc.book }), bookIndex > 0 {
            let prevBook = module.books[bookIndex - 1]
            await navigate(paneId: paneId, to: BibleLocation(moduleId: loc.moduleId, book: prevBook.id, chapter: prevBook.chapterCount))
        }
    }

    func navigateNextChapter() async {
        guard let paneId = activePaneId,
              let pane = panes.first(where: { $0.id == paneId }),
              let module = modules.first(where: { $0.id == pane.location.moduleId }) else { return }

        let loc = pane.location
        let currentBook = module.books.first(where: { $0.id == loc.book })
        let maxChapter = currentBook?.chapterCount ?? 1

        if loc.chapter < maxChapter {
            await navigate(paneId: paneId, to: BibleLocation(moduleId: loc.moduleId, book: loc.book, chapter: loc.chapter + 1))
        } else if let bookIndex = module.books.firstIndex(where: { $0.id == loc.book }), bookIndex < module.books.count - 1 {
            let nextBook = module.books[bookIndex + 1]
            await navigate(paneId: paneId, to: BibleLocation(moduleId: loc.moduleId, book: nextBook.id, chapter: 1))
        }
    }

    // MARK: - Search

    func searchVerses(moduleId: String, query: String) async throws -> [Verse] {
        guard !query.isEmpty else { return [] }
        return try await databaseService.searchVerses(moduleId: moduleId, query: query)
    }

    // MARK: - Versification

    private let versificationService = VersificationService.shared

    func chapterCount(book: String, moduleId: String) -> Int {
        let scheme = modules.first(where: { $0.id == moduleId })?.versificationScheme ?? .kjv
        return versificationService.chapterCount(book: book, scheme: scheme)
    }

    func convertPosition(book: String, chapter: Int, verse: Int,
                         from sourceModuleId: String, to targetModuleId: String) -> (book: String, chapter: Int, verse: Int) {
        guard let srcModule = modules.first(where: { $0.id == sourceModuleId }),
              let dstModule = modules.first(where: { $0.id == targetModuleId }) else {
            return (book, chapter, verse)
        }
        let src = srcModule.versificationScheme
        let dst = dstModule.versificationScheme
        guard src != dst else { return (book, chapter, verse) }
        let converted = versificationService.convert(book: book, chapter: chapter, verse: verse, from: src, to: dst)
        let maxCh = versificationService.chapterCount(book: converted.book, scheme: dst)
        return (converted.book, min(converted.chapter, max(1, maxCh)), converted.verse)
    }

    func versificationScheme(for moduleId: String) -> VersificationScheme {
        modules.first(where: { $0.id == moduleId })?.versificationScheme ?? .kjv
    }

    // MARK: - Pane Management

    func addPane(direction: SplitDirection = .horizontal) {
        guard panes.count < 8 else { return }
        let location: BibleLocation
        let insertIndex: Int
        if let activeIndex = panes.firstIndex(where: { $0.id == activePaneId }) {
            location = panes[activeIndex].location
            insertIndex = activeIndex + 1
        } else if let firstModule = modules.first, let firstBook = firstModule.books.first {
            location = BibleLocation(moduleId: firstModule.id, book: firstBook.id, chapter: 1)
            insertIndex = panes.count
        } else {
            return
        }

        let pane = ReadingPane(id: UUID(), location: location, splitDirection: direction)
        panes.insert(pane, at: insertIndex)
        activePaneId = pane.id
    }

    func removePane(id: UUID) {
        panes.removeAll { $0.id == id }
        if activePaneId == id {
            activePaneId = panes.first?.id
        }
    }

    func setActivePane(id: UUID) {
        guard panes.contains(where: { $0.id == id }) else { return }
        activePaneId = id
    }

    // MARK: - Panel Sync

    func toggleSync() {
        syncEnabled.toggle()
    }

    func syncScrollPosition(verseId: String) {
        syncedVerseId = verseId
    }
}
