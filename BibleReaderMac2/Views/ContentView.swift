import SwiftUI

struct ContentView: View {
    @Environment(BibleStore.self) private var bibleStore
    @Environment(UserDataStore.self) private var userDataStore
    @Environment(UIStateStore.self) private var uiStateStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var uiState = uiStateStore

        NavigationSplitView(columnVisibility: $uiState.sidebarVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            ReaderArea()
        }
        .navigationTitle("Bible Reader")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    uiStateStore.isToolsWindowDetached = true
                    uiStateStore.sidebarVisibility = .detailOnly
                    openWindow(id: "tools-window")
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .help("Detach sidebar to floating window")
                .disabled(uiStateStore.isToolsWindowDetached)
            }

            ToolbarItemGroup(placement: .automatic) {
                Button {
                    if uiStateStore.fontSize > 10 {
                        uiStateStore.fontSize -= 1
                    }
                } label: {
                    Image(systemName: "textformat.size.smaller")
                }
                .help(String(localized: "toolbar.decreaseFontSize"))

                Button {
                    if uiStateStore.fontSize < 40 {
                        uiStateStore.fontSize += 1
                    }
                } label: {
                    Image(systemName: "textformat.size.larger")
                }
                .help(String(localized: "toolbar.increaseFontSize"))
            }

            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help(String(localized: "toolbar.settings"))
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
