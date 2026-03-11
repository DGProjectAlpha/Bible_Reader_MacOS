import Foundation
import SwiftUI
import Combine

// MARK: - Sidebar Tab (left panel)

enum SidebarTab: String, CaseIterable, Hashable {
    case bookmarks
    case notes
    case modules

    var label: String {
        switch self {
        case .bookmarks: return "Bookmarks"
        case .notes: return "Notes"
        case .modules: return "Modules"
        }
    }

    var icon: String {
        switch self {
        case .bookmarks: return "bookmark.fill"
        case .notes: return "note.text"
        case .modules: return "books.vertical"
        }
    }
}

// MARK: - Inspector Tab (right panel)

enum InspectorTab: String, CaseIterable, Hashable {
    case strongs
    case crossRefs

    var label: String {
        switch self {
        case .strongs: return "Strong's"
        case .crossRefs: return "Cross-Refs"
        }
    }

    var icon: String {
        switch self {
        case .strongs: return "textformat.abc"
        case .crossRefs: return "link"
        }
    }
}

// MARK: - Legacy SidebarItem (kept for notification compatibility during migration)

enum SidebarItem: Hashable {
    case reader
    case search
    case strongs
    case bookmarks
    case history
    case notes
    case crossRefs
}

// MARK: - Split Direction

enum SplitDirection {
    case horizontal  // split right
    case vertical    // split down
}

/// Per-window state — each window gets its own instance with independent
/// panes, sidebar selection, and navigation. The shared BibleStore holds
/// global data (translations, bookmarks, history).
@MainActor
class WindowState: ObservableObject {
    @Published var panes: [ReaderPane] = [ReaderPane()]
    @Published var windowTitle: String = "BibleReader"

    // Sidebar state
    @Published var showSidebar: Bool = false
    @Published var selectedSidebarTab: SidebarTab = .bookmarks
    @Published var selectedSidebarItem: SidebarItem? = .reader // legacy, kept for compat

    // Inspector state
    @Published var showInspector: Bool = false
    @Published var inspectorTab: InspectorTab = .strongs

    // Strong's context passed from verse word click
    @Published var inspectorStrongsVerseId: String?
    @Published var inspectorStrongsFilePath: String?
    @Published var inspectorStrongsDisplayRef: String?
    @Published var inspectorStrongsWordIndex: Int?  // auto-expand this word in sidebar

    // Cross-refs context passed from verse number click
    @Published var inspectorCrossRefVerseId: String?

    // Search state
    @Published var showSearchPanel: Bool = false
    @Published var searchQuery: String = ""

    private var titleCancellables = Set<AnyCancellable>()

    init() {
        observePaneChanges()
    }

    /// Initialize with a specific book/chapter (e.g. from a history entry or cross-ref link)
    convenience init(book: String, chapter: Int, translationId: UUID? = nil) {
        self.init()
        guard let pane = panes.first else { return }
        pane.selectedBook = book
        pane.selectedChapter = chapter
        if let tId = translationId {
            pane.selectedTranslationId = tId
        }
        updateTitle()
    }

    // MARK: - Inspector Helpers

    func showStrongsInspector(verseId: String, displayRef: String, filePath: String, wordIndex: Int? = nil) {
        inspectorStrongsVerseId = verseId
        inspectorStrongsDisplayRef = displayRef
        inspectorStrongsFilePath = filePath
        inspectorStrongsWordIndex = wordIndex
        inspectorTab = .strongs
        showInspector = true
    }

    func showCrossRefsInspector(verseId: String) {
        inspectorCrossRefVerseId = verseId
        inspectorTab = .crossRefs
        showInspector = true
    }

    func showSearchInspector(query: String = "") {
        if !query.isEmpty {
            searchQuery = query
        }
        showSearchPanel = true
    }

    func toggleSidebar() {
        showSidebar.toggle()
    }

    func toggleSearchPanel() {
        showSearchPanel.toggle()
    }

    func toggleInspector(tab: InspectorTab) {
        if showInspector && inspectorTab == tab {
            showInspector = false
        } else {
            inspectorTab = tab
            showInspector = true
        }
    }

    // MARK: - Pane Management

    func addPane(translationId: UUID? = nil) {
        let pane = ReaderPane()
        if let tId = translationId {
            pane.selectedTranslationId = tId
        }
        panes.append(pane)
        observePaneChanges()
    }

    /// Split a specific pane — inserts a new pane adjacent to the source pane.
    /// The direction is stored for future layout use; currently the new pane
    /// is inserted immediately after the source pane in the array.
    func splitPane(_ sourcePaneId: UUID, direction: SplitDirection, translationId: UUID? = nil) {
        guard panes.count < 8 else { return }
        let newPane = ReaderPane()
        // Copy the source pane's current book/chapter/translation to the new pane
        if let source = panes.first(where: { $0.id == sourcePaneId }) {
            newPane.selectedBook = source.selectedBook
            newPane.selectedChapter = source.selectedChapter
            newPane.selectedTranslationId = translationId ?? source.selectedTranslationId
            newPane.versificationScheme = source.versificationScheme
        } else if let tId = translationId {
            newPane.selectedTranslationId = tId
        }
        // Insert right after the source pane
        if let idx = panes.firstIndex(where: { $0.id == sourcePaneId }) {
            panes.insert(newPane, at: idx + 1)
        } else {
            panes.append(newPane)
        }
        observePaneChanges()
    }

    func removePane(_ id: UUID) {
        guard panes.count > 1 else { return }
        panes.removeAll { $0.id == id }
        observePaneChanges()
    }

    // MARK: - Window Title

    private func observePaneChanges() {
        titleCancellables.removeAll()
        // Observe the first pane's book/chapter for the window title
        guard let pane = panes.first else { return }
        pane.$selectedBook
            .combineLatest(pane.$selectedChapter)
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.updateTitle()
            }
            .store(in: &titleCancellables)
        updateTitle()
    }

    func updateTitle() {
        guard let pane = panes.first else {
            windowTitle = "BibleReader"
            return
        }
        windowTitle = "\(pane.selectedBook) \(pane.selectedChapter) — BibleReader"
    }
}
