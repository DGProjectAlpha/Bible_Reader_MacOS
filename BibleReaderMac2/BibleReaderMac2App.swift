import SwiftUI

@main
struct BibleReaderMac2App: App {
    @State private var bibleStore = BibleStore()
    @State private var userDataStore = UserDataStore()
    @State private var uiStateStore = UIStateStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(bibleStore)
                .environment(userDataStore)
                .environment(uiStateStore)
                .environment(\.locale, Locale(identifier: uiStateStore.appLanguage))
                .task {
                    bibleStore.onNavigate = { location in
                        await userDataStore.addToHistory(location)
                    }
                    try? await bibleStore.loadModules()
                    await userDataStore.load()
                }
        }
        .commands {
            CommandMenu(String(localized: "menu.sidebar")) {
                Button(String(localized: "menu.strongsNumbers")) {
                    uiStateStore.sidebarVisible = true
                    uiStateStore.expandedSidebarSections.insert(SidebarSection.strongs.rawValue)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button(String(localized: "menu.crossReferences")) {
                    uiStateStore.sidebarVisible = true
                    uiStateStore.expandedSidebarSections.insert(SidebarSection.crossReferences.rawValue)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button(String(localized: "menu.notes")) {
                    uiStateStore.sidebarVisible = true
                    uiStateStore.expandedSidebarSections.insert(SidebarSection.notes.rawValue)
                }
                .keyboardShortcut("3", modifiers: .command)

                Button(String(localized: "menu.search")) {
                    uiStateStore.sidebarVisible = true
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(bibleStore)
                .environment(userDataStore)
                .environment(uiStateStore)
                .environment(\.locale, Locale(identifier: uiStateStore.appLanguage))
        }
    }
}
