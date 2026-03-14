import SwiftUI

struct ContentView: View {
    @Environment(BibleStore.self) private var bibleStore
    @Environment(UserDataStore.self) private var userDataStore
    @Environment(UIStateStore.self) private var uiStateStore

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
