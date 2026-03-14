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
        ).first ?? FileManager.default.temporaryDirectory
        let dir = appSupport
            .appendingPathComponent("BibleReaderMac2", isDirectory: true)
            .appendingPathComponent("Modules", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Import

    /// Copies a .brbmod file from sourceURL into the user modules directory.
    /// Throws if a file with the same name already exists.
    static func importModule(from sourceURL: URL) throws -> ModuleInfo {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let destination = userModulesDirectory().appendingPathComponent(sourceURL.lastPathComponent)

        if FileManager.default.fileExists(atPath: destination.path) {
            throw ModuleImportError.alreadyExists(sourceURL.lastPathComponent)
        }

        try FileManager.default.copyItem(at: sourceURL, to: destination)

        let filename = destination.deletingPathExtension().lastPathComponent
        return ModuleInfo(id: filename, path: destination, source: .user)
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

enum ModuleImportError: LocalizedError {
    case alreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .alreadyExists(let name):
            return "A module named \"\(name)\" already exists."
        }
    }
}
