import SwiftUI

@main
struct BibleReaderMacApp: App {
    @StateObject private var bibleStore = BibleStore()
    @StateObject private var importHandler = FileImportHandler()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bibleStore)
                .frame(minWidth: 900, minHeight: 600)
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
            CommandGroup(replacing: .newItem) {}
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
                    bibleStore.addPane()
                }
                .keyboardShortcut("\\", modifiers: [.command])
            }

            CommandMenu("View") {
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

            CommandMenu("Navigate") {
                Button("Previous Chapter") {
                    navigateChapter(delta: -1)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])

                Button("Next Chapter") {
                    navigateChapter(delta: 1)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])

                Divider()

                Button("Previous Book") {
                    navigateBook(delta: -1)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])

                Button("Next Book") {
                    navigateBook(delta: 1)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(bibleStore)
        }
    }

    // MARK: - Navigation Helpers

    private func navigateChapter(delta: Int) {
        guard let pane = bibleStore.panes.first else { return }
        let newChapter = pane.selectedChapter + delta
        if newChapter >= 1 && newChapter <= pane.chapterCount {
            pane.selectedChapter = newChapter
            bibleStore.loadVerses(for: pane)
        }
    }

    private func navigateBook(delta: Int) {
        guard let pane = bibleStore.panes.first else { return }
        guard let idx = BibleBooks.all.firstIndex(of: pane.selectedBook) else { return }
        let newIdx = idx + delta
        guard newIdx >= 0 && newIdx < BibleBooks.all.count else { return }
        pane.selectedBook = BibleBooks.all[newIdx]
        pane.selectedChapter = 1
        bibleStore.loadVerses(for: pane)
    }
}

extension Notification.Name {
    static let importModule = Notification.Name("importModule")
    static let manageTranslations = Notification.Name("manageTranslations")
    static let globalSearch = Notification.Name("globalSearch")
    static let showCrossReferences = Notification.Name("showCrossReferences")
    static let crossRefLookup = Notification.Name("crossRefLookup")
}
