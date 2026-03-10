import Foundation

// MARK: - Module Validation

enum ModuleValidationError: LocalizedError {
    case fileNotFound(String)
    case notSQLite(String)
    case missingTable(String, String)   // (table, file)
    case missingMetadataKey(String, String) // (key, file)
    case corruptData(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): return "Module file not found: \(path)"
        case .notSQLite(let path): return "Not a valid SQLite file: \(path)"
        case .missingTable(let table, let file): return "Required table '\(table)' missing in \(file)"
        case .missingMetadataKey(let key, let file): return "Required metadata key '\(key)' missing in \(file)"
        case .corruptData(let msg): return "Corrupt module data: \(msg)"
        }
    }
}

/// Validation result for a .brbmod file.
struct ModuleValidationResult {
    let filePath: String
    let isValid: Bool
    let metadata: ModuleMetadata?
    let bookCount: Int
    let verseCount: Int
    let hasWordTags: Bool
    let hasCrossRefs: Bool
    let errors: [ModuleValidationError]

    var summary: String {
        guard isValid, let meta = metadata else {
            return "INVALID: \(errors.map { $0.localizedDescription }.joined(separator: "; "))"
        }
        var parts = ["\(meta.name) (\(meta.abbreviation))", "\(bookCount) books", "\(verseCount) verses"]
        if hasWordTags { parts.append("Strong's tags") }
        if hasCrossRefs { parts.append("cross-refs") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Cached Module Info

/// Lightweight cached info about a discovered module on disk.
struct CachedModuleInfo: Codable, Identifiable {
    let id: UUID
    let filePath: String
    let fileName: String
    let metadata: ModuleMetadata
    let bookCount: Int
    let totalVerses: Int
    let hasWordTags: Bool
    let hasCrossRefs: Bool
    let fileSize: UInt64
    let lastModified: Date
    let cachedAt: Date
}

// MARK: - ModuleManager

/// Manages discovery, validation, caching, and lifecycle of .brbmod translation modules.
/// Thread-safe singleton — all public methods are safe to call from any thread.
final class ModuleManager {
    static let shared = ModuleManager()

    /// Directory where modules are stored.
    let modulesDirectory: URL

    /// URL for the metadata cache file.
    private let cacheFileURL: URL

    /// In-memory cache: filePath -> CachedModuleInfo
    private var cache: [String: CachedModuleInfo] = [:]
    private let lock = NSLock()

    private let fileManager = FileManager.default

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("BibleReader", isDirectory: true)
        self.modulesDirectory = appDir.appendingPathComponent("Modules", isDirectory: true)
        self.cacheFileURL = appDir.appendingPathComponent("module_cache.json")

        // Ensure directories exist
        try? fileManager.createDirectory(at: modulesDirectory, withIntermediateDirectories: true)

        // Seed bundled modules on first launch
        seedBundledModules()

        // Load persisted cache
        loadCache()
    }

    // MARK: - Public API

    /// Scan the modules directory, validate new/changed files, and return all available modules.
    /// Removes cache entries for files that no longer exist on disk.
    @discardableResult
    func scanModules() -> [CachedModuleInfo] {
        let moduleFiles = discoverModuleFiles()
        let existingPaths = Set(moduleFiles.map(\.path))

        lock.lock()
        // Purge cache entries whose files are gone
        let stalePaths = cache.keys.filter { !existingPaths.contains($0) }
        for path in stalePaths {
            cache.removeValue(forKey: path)
            ModuleConnectionPool.shared.close(filePath: path)
        }
        lock.unlock()

        // Validate and cache any new or modified modules
        for fileURL in moduleFiles {
            let path = fileURL.path
            if let cached = getCachedInfo(for: path), !isFileModified(path, since: cached.lastModified) {
                continue // Cache still valid
            }
            // Need to (re)validate
            if let info = validateAndCache(fileURL: fileURL) {
                lock.lock()
                cache[path] = info
                lock.unlock()
            } else {
                // Invalid module — remove from cache if it was there
                lock.lock()
                cache.removeValue(forKey: path)
                lock.unlock()
            }
        }

        persistCache()
        return listCachedModules()
    }

    /// List all currently cached (validated) modules, sorted by abbreviation.
    func listCachedModules() -> [CachedModuleInfo] {
        lock.lock()
        defer { lock.unlock() }
        return cache.values.sorted { $0.metadata.abbreviation < $1.metadata.abbreviation }
    }

    /// Get cached info for a specific file path.
    func getCachedInfo(for filePath: String) -> CachedModuleInfo? {
        lock.lock()
        defer { lock.unlock() }
        return cache[filePath]
    }

    /// Find a cached module by abbreviation (case-insensitive).
    func findModule(abbreviation: String) -> CachedModuleInfo? {
        let abbr = abbreviation.uppercased()
        lock.lock()
        defer { lock.unlock() }
        return cache.values.first { $0.metadata.abbreviation.uppercased() == abbr }
    }

    /// Validate a .brbmod file without adding it to the cache.
    /// Use this to check a file before importing.
    func validate(fileURL: URL) -> ModuleValidationResult {
        return performValidation(fileURL: fileURL)
    }

    /// Import a module: copy to modules directory, validate, cache, and return the Translation.
    /// Throws if validation fails.
    func importModule(from sourceURL: URL) throws -> Translation {
        let fileName = sourceURL.lastPathComponent
        let destination = modulesDirectory.appendingPathComponent(fileName)

        // If same file already exists, remove it first (re-import / update)
        if fileManager.fileExists(atPath: destination.path) {
            // Close any open connection before overwriting
            ModuleConnectionPool.shared.close(filePath: destination.path)
            try fileManager.removeItem(at: destination)
        }

        // If JSON format, convert to SQLite first
        if JSONModuleConverter.isJSONModule(at: sourceURL) {
            let convertedURL = try JSONModuleConverter.convertToSQLite(jsonURL: sourceURL)
            defer { try? fileManager.removeItem(at: convertedURL) }
            try fileManager.copyItem(at: convertedURL, to: destination)
        } else {
            // Copy to modules directory
            try fileManager.copyItem(at: sourceURL, to: destination)
        }

        // Validate
        let result = performValidation(fileURL: destination)
        guard result.isValid, let metadata = result.metadata else {
            // Clean up invalid file
            try? fileManager.removeItem(at: destination)
            let errorMsg = result.errors.first?.localizedDescription ?? "Unknown validation error"
            throw ModuleValidationError.corruptData(errorMsg)
        }

        // Cache it
        let info = makeCachedInfo(
            fileURL: destination,
            metadata: metadata,
            bookCount: result.bookCount,
            totalVerses: result.verseCount,
            hasWordTags: result.hasWordTags,
            hasCrossRefs: result.hasCrossRefs
        )

        lock.lock()
        cache[destination.path] = info
        lock.unlock()
        persistCache()

        return Translation(
            id: info.id,
            metadata: metadata,
            filePath: destination.path
        )
    }

    /// Remove a module from disk and cache. Closes its database connection.
    func removeModule(filePath: String) {
        ModuleConnectionPool.shared.close(filePath: filePath)
        try? fileManager.removeItem(atPath: filePath)

        lock.lock()
        cache.removeValue(forKey: filePath)
        lock.unlock()
        persistCache()
    }

    /// Remove a module by abbreviation.
    func removeModule(abbreviation: String) {
        guard let info = findModule(abbreviation: abbreviation) else { return }
        removeModule(filePath: info.filePath)
    }

    /// Check if a module with the given abbreviation is already installed.
    func isInstalled(abbreviation: String) -> Bool {
        return findModule(abbreviation: abbreviation) != nil
    }

    /// Build Translation objects from cached info for all valid modules.
    func loadTranslations() -> [Translation] {
        return listCachedModules().map { info in
            Translation(
                id: info.id,
                metadata: info.metadata,
                filePath: info.filePath
            )
        }
    }

    /// Clear the entire cache and close all connections.
    func resetCache() {
        ModuleConnectionPool.shared.closeAll()
        lock.lock()
        cache.removeAll()
        lock.unlock()
        try? fileManager.removeItem(at: cacheFileURL)
    }

    // MARK: - Bundled Modules

    /// Copy bundled .brbmod files from the app bundle to the modules directory if not already present.
    private func seedBundledModules() {
        guard let bundledURL = Bundle.main.url(forResource: "BundledModules", withExtension: nil) else { return }
        guard let contents = try? fileManager.contentsOfDirectory(
            at: bundledURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for fileURL in contents where fileURL.pathExtension.lowercased() == "brbmod" {
            let destination = modulesDirectory.appendingPathComponent(fileURL.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) { continue }
            try? fileManager.copyItem(at: fileURL, to: destination)
        }
    }

    // MARK: - Discovery

    /// Find all .brbmod files in the modules directory.
    private func discoverModuleFiles() -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: modulesDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents.filter { $0.pathExtension.lowercased() == "brbmod" }
    }

    /// Check if the file has been modified since a given date.
    private func isFileModified(_ path: String, since date: Date) -> Bool {
        guard let attrs = try? fileManager.attributesOfItem(atPath: path),
              let modDate = attrs[.modificationDate] as? Date else {
            return true // Can't read attrs — assume modified
        }
        return modDate > date
    }

    // MARK: - Validation

    private func performValidation(fileURL: URL) -> ModuleValidationResult {
        let path = fileURL.path
        var errors: [ModuleValidationError] = []

        // 1. File exists?
        guard fileManager.fileExists(atPath: path) else {
            return ModuleValidationResult(
                filePath: path, isValid: false, metadata: nil,
                bookCount: 0, verseCount: 0, hasWordTags: false, hasCrossRefs: false,
                errors: [.fileNotFound(path)]
            )
        }

        // 1b. If JSON format, do a lightweight JSON validation instead of SQLite
        if JSONModuleConverter.isJSONModule(at: fileURL) {
            return performJSONValidation(fileURL: fileURL)
        }

        // 2. Can open as SQLite?
        let conn: ModuleConnection
        do {
            conn = try ModuleConnection(filePath: path)
        } catch {
            return ModuleValidationResult(
                filePath: path, isValid: false, metadata: nil,
                bookCount: 0, verseCount: 0, hasWordTags: false, hasCrossRefs: false,
                errors: [.notSQLite(path)]
            )
        }

        // 3. Required tables: metadata, verses
        for table in ["metadata", "verses"] {
            do {
                guard try conn.tableExists(table) else {
                    errors.append(.missingTable(table, fileURL.lastPathComponent))
                    continue
                }
            } catch {
                errors.append(.missingTable(table, fileURL.lastPathComponent))
            }
        }

        if !errors.isEmpty {
            return ModuleValidationResult(
                filePath: path, isValid: false, metadata: nil,
                bookCount: 0, verseCount: 0, hasWordTags: false, hasCrossRefs: false,
                errors: errors
            )
        }

        // 4. Read metadata
        let metadata: ModuleMetadata
        do {
            metadata = try conn.readMetadata()
        } catch {
            return ModuleValidationResult(
                filePath: path, isValid: false, metadata: nil,
                bookCount: 0, verseCount: 0, hasWordTags: false, hasCrossRefs: false,
                errors: [.missingMetadataKey("name", fileURL.lastPathComponent)]
            )
        }

        // 5. Count books and verses
        let books = (try? conn.listBooks()) ?? []
        let bookCount = books.count
        let totalVerses: Int
        do {
            let rows = try conn.query("SELECT COUNT(*) FROM verses") { stmt in
                ModuleConnection.int(stmt, 0)
            }
            totalVerses = rows.first ?? 0
        } catch {
            totalVerses = 0
        }

        // 6. Optional tables
        let hasWordTags = (try? conn.tableExists("word_tags")) ?? false
        let hasCrossRefs = (try? conn.tableExists("cross_references")) ?? false

        // 7. Sanity check — at least 1 book and 1 verse
        if bookCount == 0 {
            errors.append(.corruptData("Module contains no books"))
        }
        if totalVerses == 0 {
            errors.append(.corruptData("Module contains no verses"))
        }

        return ModuleValidationResult(
            filePath: path,
            isValid: errors.isEmpty,
            metadata: metadata,
            bookCount: bookCount,
            verseCount: totalVerses,
            hasWordTags: hasWordTags,
            hasCrossRefs: hasCrossRefs,
            errors: errors
        )
    }

    /// Validate a JSON-format .brbmod file.
    private func performJSONValidation(fileURL: URL) -> ModuleValidationResult {
        let path = fileURL.path

        do {
            let data = try Data(contentsOf: fileURL)
            let module = try JSONDecoder().decode(JSONBrbMod.self, from: data)

            let meta = module.meta
            let moduleFormat: ModuleFormat = (meta.format == "tagged") ? .tagged : .plain
            let hasWordTags = meta.format == "tagged"

            let bookCount = module.data.count
            var totalVerses = 0
            for book in module.data {
                for chapter in book.chapters {
                    totalVerses += chapter.count
                }
            }

            var errors: [ModuleValidationError] = []
            if bookCount == 0 {
                errors.append(.corruptData("Module contains no books"))
            }
            if totalVerses == 0 {
                errors.append(.corruptData("Module contains no verses"))
            }

            // Build book_names map for display
            let nameMap = JSONModuleConverter.russianToEnglishMap()
            var bookNames: [String: String] = [:]
            for book in module.data {
                if let eng = nameMap[book.name] {
                    bookNames[eng] = book.name
                }
            }

            let metadata = ModuleMetadata(
                name: meta.name,
                abbreviation: meta.abbreviation,
                language: meta.language,
                format: moduleFormat,
                version: meta.version,
                versificationScheme: "kjv",
                copyright: meta.copyright,
                notes: meta.notes,
                bookNames: bookNames.isEmpty ? nil : bookNames
            )

            return ModuleValidationResult(
                filePath: path,
                isValid: errors.isEmpty,
                metadata: metadata,
                bookCount: bookCount,
                verseCount: totalVerses,
                hasWordTags: hasWordTags,
                hasCrossRefs: false,
                errors: errors
            )
        } catch {
            return ModuleValidationResult(
                filePath: path, isValid: false, metadata: nil,
                bookCount: 0, verseCount: 0, hasWordTags: false, hasCrossRefs: false,
                errors: [.corruptData("Invalid JSON module: \(error.localizedDescription)")]
            )
        }
    }

    // MARK: - Caching

    private func validateAndCache(fileURL: URL) -> CachedModuleInfo? {
        let result = performValidation(fileURL: fileURL)
        guard result.isValid, let metadata = result.metadata else { return nil }

        return makeCachedInfo(
            fileURL: fileURL,
            metadata: metadata,
            bookCount: result.bookCount,
            totalVerses: result.verseCount,
            hasWordTags: result.hasWordTags,
            hasCrossRefs: result.hasCrossRefs
        )
    }

    private func makeCachedInfo(
        fileURL: URL,
        metadata: ModuleMetadata,
        bookCount: Int,
        totalVerses: Int,
        hasWordTags: Bool,
        hasCrossRefs: Bool
    ) -> CachedModuleInfo {
        let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attrs?[.size] as? UInt64) ?? 0
        let lastModified = (attrs?[.modificationDate] as? Date) ?? Date()

        return CachedModuleInfo(
            id: UUID(),
            filePath: fileURL.path,
            fileName: fileURL.lastPathComponent,
            metadata: metadata,
            bookCount: bookCount,
            totalVerses: totalVerses,
            hasWordTags: hasWordTags,
            hasCrossRefs: hasCrossRefs,
            fileSize: fileSize,
            lastModified: lastModified,
            cachedAt: Date()
        )
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheFileURL),
              let entries = try? JSONDecoder().decode([CachedModuleInfo].self, from: data) else { return }

        lock.lock()
        defer { lock.unlock() }
        for entry in entries {
            // Only restore if file still exists
            if fileManager.fileExists(atPath: entry.filePath) {
                cache[entry.filePath] = entry
            }
        }
    }

    private func persistCache() {
        lock.lock()
        let entries = Array(cache.values)
        lock.unlock()

        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: cacheFileURL, options: .atomic)
    }
}
