import SwiftUI

struct ContentView: View {
    @Environment(BibleStore.self) private var bibleStore
    @Environment(UserDataStore.self) private var userDataStore
    @Environment(UIStateStore.self) private var uiStateStore

    var body: some View {
        @Bindable var uiState = uiStateStore

        HSplitView {
            // Sidebar
            if uiStateStore.sidebarVisible {
                SidebarView()
                    .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
                    .transition(.move(edge: .leading))
            }

            // Reader Area (detail)
            ReaderArea()
                .frame(minWidth: 400)

            // Inspector
            if uiStateStore.inspectorVisible {
                InspectorView()
                    .frame(minWidth: 200, idealWidth: 300, maxWidth: 400)
                    .transition(.move(edge: .trailing))
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
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
                    if uiStateStore.fontSize < 32 {
                        uiStateStore.fontSize += 1
                    }
                } label: {
                    Image(systemName: "textformat.size.larger")
                }
                .help("Increase Font Size")
            }

            ToolbarItemGroup(placement: .automatic) {
                Button {
                    withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                        bibleStore.addPane(direction: .horizontal)
                    }
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                }
                .help("Split Right")

                Button {
                    withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                        bibleStore.addPane(direction: .vertical)
                    }
                } label: {
                    Image(systemName: "rectangle.split.1x2")
                }
                .help("Split Down")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                .keyboardShortcut(",", modifiers: .command)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    uiStateStore.searchVisible.toggle()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Search")
                .keyboardShortcut("f", modifiers: .command)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                        uiStateStore.inspectorVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .help("Toggle Inspector")
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.2), value: uiStateStore.sidebarVisible)
        .animation(.spring(duration: 0.35, bounce: 0.2), value: uiStateStore.inspectorVisible)
        .sheet(isPresented: $uiState.searchVisible) {
            SearchView()
                .presentationBackground(.glass)
        }
    }

}
