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
                .task {
                    bibleStore.onNavigate = { location in
                        await userDataStore.addToHistory(location)
                    }
                    try? await bibleStore.loadModules()
                    await userDataStore.load()
                }
        }
        .commands {
            CommandMenu("Inspector") {
                Button("Strong's Numbers") {
                    uiStateStore.inspectorTab = .strongs
                    uiStateStore.inspectorVisible = true
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Cross-References") {
                    uiStateStore.inspectorTab = .crossRef
                    uiStateStore.inspectorVisible = true
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Notes") {
                    uiStateStore.inspectorTab = .notes
                    uiStateStore.inspectorVisible = true
                }
                .keyboardShortcut("3", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(uiStateStore)
        }
    }
}
