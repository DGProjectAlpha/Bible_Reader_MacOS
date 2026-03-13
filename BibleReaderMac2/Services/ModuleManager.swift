import Foundation

// MARK: - ModuleManager

/// Discovers .brbmod files in the app bundle and user's Application Support directory.
/// Simple struct with static methods — no actor isolation needed.
struct ModuleManager {

    /// All locations where modules can be found.
    static func discoverModules() -> [ModuleInfo] {
        var results: [ModuleInfo] = []

        // 1. App bundle — BundledModules/
        if let bundledURL = Bundle.main.url(forResource: "BundledModules", withExtension: nil) {
            results += modulesIn(directory: bundledURL, source: .bundled)
        }

        // 2. User modules — ~/Library/Application Support/BibleReaderMac2/Modules/
        let userDir = userModulesDirectory()
        results += modulesIn(directory: userDir, source: .user)

        return results
    }

    /// Path to the user's writable modules directory. Creates it if needed.
    static func userModulesDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport
            .appendingPathComponent("BibleReaderMac2", isDirectory: true)
            .appendingPathComponent("Modules", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Private

    private static func modulesIn(directory: URL, source: ModuleSource) -> [ModuleInfo] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents
            .filter { $0.pathExtension.lowercased() == "brbmod" }
            .map { url in
                let filename = url.deletingPathExtension().lastPathComponent
                return ModuleInfo(id: filename, path: url, source: source)
            }
    }
}

// MARK: - Supporting Types

struct ModuleInfo: Identifiable {
    let id: String       // filename without extension
    let path: URL
    let source: ModuleSource
}

enum ModuleSource {
    case bundled
    case user
}
