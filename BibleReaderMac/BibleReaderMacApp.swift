import SwiftUI

@main
struct BibleReaderMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var bibleStore = BibleStore()
    @StateObject private var importHandler = FileImportHandler()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bibleStore)
                .frame(minWidth: 800, minHeight: 500)
                .onOpenURL { url in
                    guard url.pathExtension.lowercased() == "brbmod" else { return }
                    Task {
                        _ = await importHandler.importFile(at: url, into: bibleStore)
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1200, height: 800)
        .commands {
            // Keep default New Window (Cmd+N) behavior from WindowGroup
            CommandMenu("Bible") {
                Button("Import Module...") {
                    NotificationCenter.default.post(name: .importModule, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command])

                Button("Manage Translations") {
                    NotificationCenter.default.post(name: .manageTranslations, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Divider()

                Button("Search...") {
                    NotificationCenter.default.post(name: .globalSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command])

                Divider()

                Button("Add Translation Pane") {
                    NotificationCenter.default.post(name: .addTranslationPane, object: nil)
                }
                .keyboardShortcut("\\", modifiers: [.command])
            }

            CommandMenu("View") {
                // Sidebar tabs
                Button("Bookmarks Sidebar") {
                    NotificationCenter.default.post(
                        name: .switchSidebarTab,
                        object: nil,
                        userInfo: ["tab": SidebarTab.bookmarks]
                    )
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("Notes Sidebar") {
                    NotificationCenter.default.post(
                        name: .switchSidebarTab,
                        object: nil,
                        userInfo: ["tab": SidebarTab.notes]
                    )
                }
                .keyboardShortcut("2", modifiers: [.command])

                Button("Modules Sidebar") {
                    NotificationCenter.default.post(
                        name: .switchSidebarTab,
                        object: nil,
                        userInfo: ["tab": SidebarTab.modules]
                    )
                }
                .keyboardShortcut("3", modifiers: [.command])

                Divider()

                // Inspector toggles
                Button("Toggle Strong's") {
                    NotificationCenter.default.post(name: .toggleStrongsInspector, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .option])

                Button("Toggle Cross-References") {
                    NotificationCenter.default.post(name: .toggleCrossRefsInspector, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .option])

                Divider()

                // Font size
                Button("Increase Font Size") {
                    let current = UserDefaults.standard.double(forKey: "fontSize")
                    let size = current > 0 ? current : 15
                    UserDefaults.standard.set(min(36, size + 1), forKey: "fontSize")
                }
                .keyboardShortcut("+", modifiers: [.command])

                Button("Decrease Font Size") {
                    let current = UserDefaults.standard.double(forKey: "fontSize")
                    let size = current > 0 ? current : 15
                    UserDefaults.standard.set(max(10, size - 1), forKey: "fontSize")
                }
                .keyboardShortcut("-", modifiers: [.command])

                Button("Reset Font Size") {
                    UserDefaults.standard.set(15.0, forKey: "fontSize")
                }
                .keyboardShortcut("0", modifiers: [.command])
            }

            CommandMenu("Bookmarks") {
                Button("Bookmark Current Verse") {
                    NotificationCenter.default.post(name: .bookmarkCurrentVerse, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command])
            }

            CommandMenu("Navigate") {
                Button("Previous Chapter") {
                    NotificationCenter.default.post(name: .navigatePreviousChapter, object: nil)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])

                Button("Next Chapter") {
                    NotificationCenter.default.post(name: .navigateNextChapter, object: nil)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])

                Divider()

                Button("Previous Book") {
                    NotificationCenter.default.post(name: .navigatePreviousBook, object: nil)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])

                Button("Next Book") {
                    NotificationCenter.default.post(name: .navigateNextBook, object: nil)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(bibleStore)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    // Module management
    static let importModule = Notification.Name("importModule")
    static let manageTranslations = Notification.Name("manageTranslations")
    static let importModuleFile = Notification.Name("importModuleFile")
    static let translationRemoved = Notification.Name("translationRemoved")

    // Navigation
    static let navigatePreviousChapter = Notification.Name("navigatePreviousChapter")
    static let navigateNextChapter = Notification.Name("navigateNextChapter")
    static let navigatePreviousBook = Notification.Name("navigatePreviousBook")
    static let navigateNextBook = Notification.Name("navigateNextBook")
    static let addTranslationPane = Notification.Name("addTranslationPane")
    static let bookmarkCurrentVerse = Notification.Name("bookmarkCurrentVerse")
    static let navigateToReader = Notification.Name("navigateToReader")
    static let navigateToVerse = Notification.Name("navigateToVerse")

    // Search and references
    static let globalSearch = Notification.Name("globalSearch")
    static let showCrossReferences = Notification.Name("showCrossReferences")
    static let crossRefLookup = Notification.Name("crossRefLookup")

    // Sidebar tab switching (Cmd+1/2/3)
    static let switchSidebarTab = Notification.Name("switchSidebarTab")

    // Inspector toggles
    static let toggleStrongsInspector = Notification.Name("toggleStrongsInspector")
    static let toggleCrossRefsInspector = Notification.Name("toggleCrossRefsInspector")

}
