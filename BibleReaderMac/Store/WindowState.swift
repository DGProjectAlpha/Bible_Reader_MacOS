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
    case search

    var label: String {
        switch self {
        case .strongs: return "Strong's"
        case .crossRefs: return "Cross-Refs"
        case .search: return "Search"
        }
    }

    var icon: String {
        switch self {
        case .strongs: return "textformat.abc"
        case .crossRefs: return "link"
        case .search: return "magnifyingglass"
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

/// Per-window state — each window gets its own instance with independent
/// panes, sidebar selection, and navigation. The shared BibleStore holds
/// global data (translations, bookmarks, history).
@MainActor
class WindowState: ObservableObject {
    @Published var panes: [ReaderPane] = [ReaderPane()]
    @Published var windowTitle: String = "BibleReader"

    // Sidebar state
    @Published var selectedSidebarTab: SidebarTab = .bookmarks
    @Published var selectedSidebarItem: SidebarItem? = .reader // legacy, kept for compat

    // Inspector state
    @Published var showInspector: Bool = false
    @Published var inspectorTab: InspectorTab = .strongs

    // Strong's context passed from verse word click
    @Published var inspectorStrongsVerseId: String?
    @Published var inspectorStrongsFilePath: String?
    @Published var inspectorStrongsDisplayRef: String?

    // Cross-refs context passed from verse number click
    @Published var inspectorCrossRefVerseId: String?

    // Search state
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

    func showStrongsInspector(verseId: String, displayRef: String, filePath: String) {
        inspectorStrongsVerseId = verseId
        inspectorStrongsDisplayRef = displayRef
        inspectorStrongsFilePath = filePath
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
        inspectorTab = .search
        showInspector = true
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
