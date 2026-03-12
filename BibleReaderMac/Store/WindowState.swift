import Foundation
import SwiftUI
import Combine

// MARK: - Sidebar Tab

enum SidebarTab: String, CaseIterable, Hashable {
    case bookmarks, notes, modules

    var label: String {
        switch self {
        case .bookmarks: return L("tab.bookmarks")
        case .notes:     return L("tab.notes")
        case .modules:   return L("tab.modules")
        }
    }

    var icon: String {
        switch self {
        case .bookmarks: return "bookmark.fill"
        case .notes:     return "note.text"
        case .modules:   return "books.vertical"
        }
    }
}

// MARK: - Inspector Tab

enum InspectorTab: String, CaseIterable, Hashable {
    case strongs, crossRefs

    var label: String {
        switch self {
        case .strongs:   return L("tab.strongs")
        case .crossRefs: return L("tab.crossrefs")
        }
    }

    var icon: String {
        switch self {
        case .strongs:   return "textformat.abc"
        case .crossRefs: return "link"
        }
    }
}

// MARK: - Legacy SidebarItem

enum SidebarItem: Hashable {
    case reader, search, strongs, bookmarks, history, notes, crossRefs
}

// MARK: - Split Direction

enum SplitDirection {
    case horizontal
    case vertical
}

// MARK: - WindowState

@MainActor
class WindowState: ObservableObject {
    @Published var panes: [ReaderPane] = []
    @Published var windowTitle: String = "BibleReader"

    // Sidebar
    @Published var showSidebar: Bool = false
    @Published var selectedSidebarTab: SidebarTab = .bookmarks
    @Published var selectedSidebarItem: SidebarItem? = .reader

    // Inspector
    @Published var showInspector: Bool = false
    @Published var inspectorTab: InspectorTab = .strongs
    @Published var inspectorStrongsVerseId: String?
    @Published var inspectorStrongsFilePath: String?
    @Published var inspectorStrongsDisplayRef: String?
    @Published var inspectorStrongsWordIndex: Int?
    @Published var inspectorCrossRefVerseId: String?

    // Search
    @Published var showSearchPanel: Bool = false
    @Published var searchQuery: String = ""
    @Published var searchResults: [SearchResult] = []
    @Published var searchIsSearching: Bool = false
    @Published var searchResultsCapped: Bool = false
    @Published var searchHasSearched: Bool = false

    // Last active pane for cross-ref navigation targeting
    @Published var lastActivePaneId: UUID?

    init() {
        // Panes are added externally once translations are loaded (see ContentView.handleOnAppear)
    }

    // MARK: - Pane creation

    /// Create the first pane with a valid translation ID. Called from ContentView after store loads.
    func createInitialPane(translationId: UUID, book: String = "Genesis", chapter: Int = 1) {
        let pane = ReaderPane(translationId: translationId, book: book, chapter: chapter)
        panes = [pane]
        updateTitle()
    }

    // MARK: - Pane mutation (always via these methods to keep @Published firing)

    func navigate(paneId: UUID, book: String? = nil, chapter: Int? = nil, translationId: UUID? = nil) {
        guard let idx = panes.firstIndex(where: { $0.id == paneId }) else { return }
        if let book = book  { panes[idx].book = book }
        if let ch = chapter { panes[idx].chapter = ch }
        if let tId = translationId { panes[idx].translationId = tId }
        updateTitle()
    }

    func setVerses(paneId: UUID, verses: [Verse], versificationScheme: String) {
        guard let idx = panes.firstIndex(where: { $0.id == paneId }) else { return }
        panes[idx].verses = verses
        panes[idx].versificationScheme = versificationScheme
    }

    // MARK: - Pane management

    func addPane(translationId: UUID, book: String = "Genesis", chapter: Int = 1) {
        let pane = ReaderPane(translationId: translationId, book: book, chapter: chapter)
        panes.append(pane)
    }

    func splitPane(_ sourcePaneId: UUID, direction: SplitDirection) {
        guard panes.count < 8,
              let idx = panes.firstIndex(where: { $0.id == sourcePaneId }) else { return }
        let source = panes[idx]
        var newPane = ReaderPane(translationId: source.translationId, book: source.book, chapter: source.chapter)
        newPane.versificationScheme = source.versificationScheme
        if direction == .vertical {
            newPane.verticalBuddyId = sourcePaneId
        }
        panes.insert(newPane, at: idx + 1)
    }

    func togglePaneSync(_ id: UUID) {
        guard let idx = panes.firstIndex(where: { $0.id == id }) else { return }
        panes[idx].isSyncEnabled.toggle()
    }

    func removePane(_ id: UUID) {
        guard panes.count > 1 else { return }
        for idx in panes.indices where panes[idx].verticalBuddyId == id {
            panes[idx].verticalBuddyId = nil
        }
        panes.removeAll { $0.id == id }
    }

    // MARK: - Inspector

    func showStrongsInspector(verseId: String, displayRef: String, filePath: String, wordIndex: Int? = nil) {
        inspectorStrongsVerseId = verseId
        inspectorStrongsDisplayRef = displayRef
        inspectorStrongsFilePath = filePath
        inspectorStrongsWordIndex = wordIndex
        inspectorTab = .strongs
        withAnimation(.easeInOut(duration: 0.25)) { showInspector = true }
    }

    func showCrossRefsInspector(verseId: String) {
        inspectorCrossRefVerseId = verseId
        inspectorTab = .crossRefs
        withAnimation(.easeInOut(duration: 0.25)) { showInspector = true }
    }

    func showSearchInspector(query: String = "") {
        if !query.isEmpty { searchQuery = query }
        showSearchPanel = true
    }

    func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.25)) { showSidebar.toggle() }
    }

    func toggleSearchPanel() {
        showSearchPanel.toggle()
    }

    func toggleInspector(tab: InspectorTab) {
        withAnimation(.easeInOut(duration: 0.25)) {
            if showInspector && inspectorTab == tab {
                showInspector = false
            } else {
                inspectorTab = tab
                showInspector = true
            }
        }
    }

    // MARK: - Title

    func updateTitle() {
        guard let pane = panes.first else {
            windowTitle = "BibleReader"
            return
        }
        windowTitle = "\(pane.book) \(pane.chapter) — BibleReader"
        // Persist last position so ContentView can restore on next launch
        UserDefaults.standard.set(pane.book, forKey: "lastBook")
        UserDefaults.standard.set(pane.chapter, forKey: "lastChapter")
    }
}
