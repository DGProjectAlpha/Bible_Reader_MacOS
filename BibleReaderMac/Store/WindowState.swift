import Foundation
import SwiftUI
import Combine

/// Per-window state — each window gets its own instance with independent
/// panes, sidebar selection, and navigation. The shared BibleStore holds
/// global data (translations, bookmarks, history).
@MainActor
class WindowState: ObservableObject {
    @Published var panes: [ReaderPane] = [ReaderPane()]
    @Published var selectedSidebarItem: SidebarItem? = .reader
    @Published var windowTitle: String = "BibleReader"

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
