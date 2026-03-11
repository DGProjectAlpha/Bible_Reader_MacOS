import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set activation policy to regular (dock icon, menu bar)
        NSApplication.shared.setActivationPolicy(.regular)

        // Allow window tabbing for multi-window support
        NSWindow.allowsAutomaticWindowTabbing = true

        // Register default preferences
        registerDefaults()

        print("[AppDelegate] Application launched — multi-window enabled")
    }

    func applicationWillTerminate(_ notification: Notification) {
        print("[AppDelegate] Application terminating — state saved")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Multi-window app: keep running when all windows are closed
        // User can reopen via Cmd+N or dock icon click
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Allow immediate termination — no unsaved document state
        return .terminateNow
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // If no windows visible, bring the first window forward
        if !NSApplication.shared.windows.contains(where: { $0.isVisible && !$0.isMiniaturized }),
           let window = NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Reopen main window when user clicks dock icon with no visible windows
            if let window = NSApplication.shared.windows.first {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }

    // MARK: - File Handling

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        guard url.pathExtension.lowercased() == "brbmod" else { return false }
        NotificationCenter.default.post(name: .importModuleFile, object: url)
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            _ = application(sender, openFile: filename)
        }
    }

    // MARK: - Defaults

    private func registerDefaults() {
        let defaults: [String: Any] = [
            "fontSize": 15.0,
            "lineSpacing": 1.3,
            "wordSpacing": 0.0,
            "versesPerLine": false,
            "showVerseNumbers": true,
            "windowRestoration": true,
            "syncScrolling": true,
            "restoreLastPosition": true,
            "activeProfile": "Default",
            "profileList": "Default",
            "readerTheme": "auto",
            "accentColorName": "blue",
            "verseHighlightOpacity": 0.12,
            "showChapterTitles": true,
            "fontFamily": "System",
            "verseNumberStyle": "superscript",
            "paragraphMode": false
        ]
        UserDefaults.standard.register(defaults: defaults)
    }
}
