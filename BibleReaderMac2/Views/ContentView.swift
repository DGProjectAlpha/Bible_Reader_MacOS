import SwiftUI

struct ContentView: View {
    @Environment(BibleStore.self) private var bibleStore
    @Environment(UserDataStore.self) private var userDataStore
    @Environment(UIStateStore.self) private var uiStateStore

    var body: some View {
        HSplitView {
            // Sidebar
            if uiStateStore.sidebarVisible {
                SidebarView()
                    .frame(minWidth: 220, idealWidth: 280, maxWidth: 350)
                    .background(.ultraThinMaterial)
                    .transition(.identity)
            }

            // Reader Area (detail)
            ReaderArea()
                .frame(minWidth: 400)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(nil) {
                        uiStateStore.sidebarVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.leading")
                }
                .help("Toggle Sidebar")
            }

            ToolbarItemGroup(placement: .automatic) {
                Button {
                    Task { await bibleStore.navigatePreviousChapter() }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Previous Chapter")
                .keyboardShortcut("[", modifiers: .command)

                Button {
                    Task { await bibleStore.navigateNextChapter() }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .help("Next Chapter")
                .keyboardShortcut("]", modifiers: .command)
            }

            ToolbarItemGroup(placement: .automatic) {
                Button {
                    if uiStateStore.fontSize > 10 {
                        uiStateStore.fontSize -= 1
                    }
                } label: {
                    Image(systemName: "textformat.size.smaller")
                }
                .help("Decrease Font Size")

                Button {
                    if uiStateStore.fontSize < 40 {
                        uiStateStore.fontSize += 1
                    }
                } label: {
                    Image(systemName: "textformat.size.larger")
                }
                .help("Increase Font Size")
            }

            ToolbarItemGroup(placement: .automatic) {
                Button {
                    withAnimation(nil) {
                        bibleStore.addPane(direction: .horizontal)
                    }
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                }
                .help("Split Right")

                Button {
                    withAnimation(nil) {
                        bibleStore.addPane(direction: .vertical)
                    }
                } label: {
                    Image(systemName: "rectangle.split.1x2")
                }
                .help("Split Down")
            }

            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        .animation(nil, value: uiStateStore.sidebarVisible)
    }

}
