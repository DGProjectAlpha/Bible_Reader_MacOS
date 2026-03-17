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
                .environment(\EnvironmentValues.locale, Locale(identifier: uiStateStore.appLanguage))
                .preferredColorScheme(uiStateStore.appearanceMode.colorScheme)
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
                    uiStateStore.sidebarVisibility = .all
                    uiStateStore.expandedSidebarSections.insert(SidebarSection.strongs.rawValue)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button(String(localized: "menu.crossReferences")) {
                    uiStateStore.sidebarVisibility = .all
                    uiStateStore.expandedSidebarSections.insert(SidebarSection.crossReferences.rawValue)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button(String(localized: "menu.notes")) {
                    uiStateStore.sidebarVisibility = .all
                    uiStateStore.expandedSidebarSections.insert(SidebarSection.notes.rawValue)
                }
                .keyboardShortcut("3", modifiers: .command)

                Button(String(localized: "menu.search")) {
                    uiStateStore.sidebarVisibility = .all
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }

        Window("Bible Reader — Tools", id: "tools-window") {
            FloatingToolsView()
                .environment(bibleStore)
                .environment(userDataStore)
                .environment(uiStateStore)
                .environment(\EnvironmentValues.locale, Locale(identifier: uiStateStore.appLanguage))
                .preferredColorScheme(uiStateStore.appearanceMode.colorScheme)
                .background(.ultraThinMaterial)
                .frame(minWidth: 350, minHeight: 400)
                .onAppear {
                    DispatchQueue.main.async {
                        if let window = NSApp.windows.first(where: { $0.title == "Bible Reader — Tools" }) {
                            window.level = .normal
                            window.isMovableByWindowBackground = true
                            window.minSize = NSSize(width: 350, height: 400)
                            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenPrimary]
                        }
                    }
                }
                .onDisappear {
                    // Fallback: also handled by willCloseNotification in FloatingToolsView
                    if uiStateStore.isToolsWindowDetached {
                        uiStateStore.isToolsWindowDetached = false
                        uiStateStore.sidebarVisibility = .all
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 500, height: 600)
        .defaultPosition(.trailing)

        WindowGroup(for: UUID.self) { $paneId in
            if let paneId {
                DetachedPaneView(paneId: paneId)
                    .environment(bibleStore)
                    .environment(userDataStore)
                    .environment(uiStateStore)
                    .environment(\EnvironmentValues.locale, Locale(identifier: uiStateStore.appLanguage))
                    .preferredColorScheme(uiStateStore.appearanceMode.colorScheme)
            }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 600, height: 800)

        Settings {
            SettingsView()
                .environment(bibleStore)
                .environment(userDataStore)
                .environment(uiStateStore)
                .environment(\EnvironmentValues.locale, Locale(identifier: uiStateStore.appLanguage))
                .preferredColorScheme(uiStateStore.appearanceMode.colorScheme)
        }
    }
}
