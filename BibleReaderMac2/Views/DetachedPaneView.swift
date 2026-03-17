import SwiftUI

struct DetachedPaneView: View {
    @Environment(BibleStore.self) private var bibleStore
    @Environment(UIStateStore.self) private var uiState
    @Environment(\.dismissWindow) private var dismissWindow

    let paneId: UUID

    private var pane: ReadingPane? {
        bibleStore.panes.first(where: { $0.id == paneId })
    }

    private var windowTitle: String {
        guard let pane else { return "Bible Reader" }
        let loc = pane.location
        let moduleName = bibleStore.modules.first(where: { $0.id == loc.moduleId })?.abbreviation ?? loc.moduleId
        let bookName = bibleStore.modules
            .first(where: { $0.id == loc.moduleId })?
            .books.first(where: { $0.id == loc.book })?.name ?? loc.book
        return "\(moduleName) — \(bookName) \(loc.chapter)"
    }

    private var windowIdentifier: String {
        "detached-pane-\(paneId.uuidString)"
    }

    var body: some View {
        Group {
            if let pane {
                ReaderView(pane: pane, isDetached: true)
            } else {
                ContentUnavailableView(
                    "Pane Closed",
                    systemImage: "xmark.rectangle",
                    description: Text("This pane has been removed.")
                )
            }
        }
        .navigationTitle(windowTitle)
        .frame(minWidth: 400, minHeight: 500)
        .onAppear {
            // Tag the NSWindow so we can identify it on close, and enable fullscreen
            DispatchQueue.main.async {
                for window in NSApp.windows where window.identifier == nil || window.identifier?.rawValue.isEmpty == true {
                    if window.contentView?.subviews.isEmpty == false,
                       window.title == windowTitle || window.title == "Bible Reader" {
                        window.identifier = NSUserInterfaceItemIdentifier(windowIdentifier)
                        window.collectionBehavior.insert(.fullScreenPrimary)
                        break
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  window.identifier?.rawValue == windowIdentifier else { return }
            uiState.detachedPaneIds.remove(paneId)
        }
        .onDisappear {
            // Fallback: also handled by willCloseNotification above
            uiState.detachedPaneIds.remove(paneId)
        }
        .onChange(of: pane == nil) { _, isNil in
            // If pane was deleted from BibleStore, close this window gracefully
            if isNil {
                uiState.detachedPaneIds.remove(paneId)
                dismissWindow(value: paneId)
            }
        }
    }
}
