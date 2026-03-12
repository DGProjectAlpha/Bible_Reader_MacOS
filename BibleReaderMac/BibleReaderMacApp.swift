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
            CommandMenu(L("menu.bible")) {
                Button(L("menu.import_module")) {
                    NotificationCenter.default.post(name: .importModule, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command])

                Button(L("menu.manage_translations")) {
                    NotificationCenter.default.post(name: .manageTranslations, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Divider()

                Button(L("menu.search")) {
                    NotificationCenter.default.post(name: .globalSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command])

                Divider()

                Button(L("menu.add_pane")) {
                    NotificationCenter.default.post(name: .addTranslationPane, object: nil)
                }
                .keyboardShortcut("\\", modifiers: [.command])
            }

            CommandMenu(L("menu.view")) {
                // Sidebar tabs
                Button(L("menu.bookmarks_sidebar")) {
                    NotificationCenter.default.post(
                        name: .switchSidebarTab,
                        object: nil,
                        userInfo: ["tab": SidebarTab.bookmarks]
                    )
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button(L("menu.notes_sidebar")) {
                    NotificationCenter.default.post(
                        name: .switchSidebarTab,
                        object: nil,
                        userInfo: ["tab": SidebarTab.notes]
                    )
                }
                .keyboardShortcut("2", modifiers: [.command])

                Button(L("menu.modules_sidebar")) {
                    NotificationCenter.default.post(
                        name: .switchSidebarTab,
                        object: nil,
                        userInfo: ["tab": SidebarTab.modules]
                    )
                }
                .keyboardShortcut("3", modifiers: [.command])

                Divider()

                // Inspector toggles
                Button(L("menu.toggle_strongs")) {
                    NotificationCenter.default.post(name: .toggleStrongsInspector, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .option])

                Button(L("menu.toggle_crossrefs")) {
                    NotificationCenter.default.post(name: .toggleCrossRefsInspector, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .option])

                Divider()

                // Font size
                Button(L("menu.increase_font")) {
                    let current = UserDefaults.standard.double(forKey: "fontSize")
                    let size = current > 0 ? current : 15
                    UserDefaults.standard.set(min(36, size + 1), forKey: "fontSize")
                }
                .keyboardShortcut("+", modifiers: [.command])

                Button(L("menu.decrease_font")) {
                    let current = UserDefaults.standard.double(forKey: "fontSize")
                    let size = current > 0 ? current : 15
                    UserDefaults.standard.set(max(10, size - 1), forKey: "fontSize")
                }
                .keyboardShortcut("-", modifiers: [.command])

                Button(L("menu.reset_font")) {
                    UserDefaults.standard.set(15.0, forKey: "fontSize")
                }
                .keyboardShortcut("0", modifiers: [.command])
            }

            CommandMenu(L("menu.bookmarks")) {
                Button(L("menu.bookmark_verse")) {
                    NotificationCenter.default.post(name: .bookmarkCurrentVerse, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command])
            }

            CommandMenu(L("menu.navigate")) {
                Button(L("menu.prev_chapter")) {
                    NotificationCenter.default.post(name: .navigatePreviousChapter, object: nil)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])

                Button(L("menu.next_chapter")) {
                    NotificationCenter.default.post(name: .navigateNextChapter, object: nil)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])

                Divider()

                Button(L("menu.prev_book")) {
                    NotificationCenter.default.post(name: .navigatePreviousBook, object: nil)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])

                Button(L("menu.next_book")) {
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
