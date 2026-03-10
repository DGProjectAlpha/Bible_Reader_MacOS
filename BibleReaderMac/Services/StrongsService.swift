import Foundation

// MARK: - Strong's Concordance Service

/// Loads Strong's concordance entries from .brbmod module databases.
/// Falls back to bundled JSON files if no `strongs` table exists in the module.
enum StrongsService {

    // MARK: - Cache

    private static var cache: [String: StrongsEntry] = [:]
    private static let cacheLock = NSLock()

    /// Look up a single Strong's entry by number (e.g. "H7225", "G3056").
    /// Checks in-memory cache first, then queries the module database.
    static func lookup(_ number: String, in filePath: String) -> StrongsEntry? {
        cacheLock.lock()
        if let cached = cache[number] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        // Try loading from the module's strongs table
        if let entry = queryModule(number: number, filePath: filePath) {
            cacheLock.lock()
            cache[number] = entry
            cacheLock.unlock()
            return entry
        }

        // Try bundled JSON fallback
        if let entry = loadFromBundledJSON(number: number) {
            cacheLock.lock()
            cache[number] = entry
            cacheLock.unlock()
            return entry
        }

        return nil
    }

    /// Batch lookup for multiple Strong's numbers. Returns entries keyed by number.
    static func batchLookup(_ numbers: [String], in filePath: String) -> [String: StrongsEntry] {
        var results: [String: StrongsEntry] = [:]

        // Check cache first
        var uncached: [String] = []
        cacheLock.lock()
        for num in numbers {
            if let cached = cache[num] {
                results[num] = cached
            } else {
                uncached.append(num)
            }
        }
        cacheLock.unlock()

        guard !uncached.isEmpty else { return results }

        // Batch query from module
        let moduleEntries = batchQueryModule(numbers: uncached, filePath: filePath)
        var stillMissing: [String] = []

        cacheLock.lock()
        for (num, entry) in moduleEntries {
            cache[num] = entry
            results[num] = entry
        }
        for num in uncached where moduleEntries[num] == nil {
            stillMissing.append(num)
        }
        cacheLock.unlock()

        // Fallback to bundled JSON for any remaining
        for num in stillMissing {
            if let entry = loadFromBundledJSON(number: num) {
                cacheLock.lock()
                cache[num] = entry
                cacheLock.unlock()
                results[num] = entry
            }
        }

        return results
    }

    /// Load all word tags for a verse, then resolve their Strong's entries.
    static func entriesForVerse(verseId: String, filePath: String) -> [ResolvedWordTag] {
        guard let conn = try? ModuleConnectionPool.shared.connection(for: filePath) else {
            return []
        }

        let wordTags = (try? conn.loadWordTags(verseId: verseId)) ?? []
        guard !wordTags.isEmpty else { return [] }

        // Collect all unique Strong's numbers
        let allNumbers = Array(Set(wordTags.flatMap { $0.strongsNumbers }))
        let entries = batchLookup(allNumbers, in: filePath)

        return wordTags.map { tag in
            let resolvedEntries = tag.strongsNumbers.compactMap { entries[$0] }
            return ResolvedWordTag(wordTag: tag, entries: resolvedEntries)
        }
    }

    /// Clear the in-memory cache.
    static func clearCache() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
    }

    // MARK: - Module Database Query

    private static func queryModule(number: String, filePath: String) -> StrongsEntry? {
        guard let conn = try? ModuleConnectionPool.shared.connection(for: filePath),
              (try? conn.tableExists("strongs")) == true else {
            return nil
        }

        let rows = try? conn.query(
            "SELECT number, lemma, transliteration, pronunciation, derivation, strongs_def, kjv_def FROM strongs WHERE number = ?1 LIMIT 1",
            bindings: [number]
        ) { stmt in
            StrongsEntry(
                number: ModuleConnection.text(stmt, 0),
                lemma: ModuleConnection.text(stmt, 1),
                transliteration: ModuleConnection.text(stmt, 2),
                pronunciation: ModuleConnection.text(stmt, 3).isEmpty ? nil : ModuleConnection.text(stmt, 3),
                derivation: ModuleConnection.text(stmt, 4).isEmpty ? nil : ModuleConnection.text(stmt, 4),
                strongsDefinition: ModuleConnection.text(stmt, 5).isEmpty ? nil : ModuleConnection.text(stmt, 5),
                kjvDefinition: ModuleConnection.text(stmt, 6).isEmpty ? nil : ModuleConnection.text(stmt, 6)
            )
        }

        return rows?.first
    }

    private static func batchQueryModule(numbers: [String], filePath: String) -> [String: StrongsEntry] {
        guard let conn = try? ModuleConnectionPool.shared.connection(for: filePath),
              (try? conn.tableExists("strongs")) == true,
              !numbers.isEmpty else {
            return [:]
        }

        // Build parameterized IN clause
        let placeholders = numbers.enumerated().map { "?\($0.offset + 1)" }.joined(separator: ",")
        let sql = "SELECT number, lemma, transliteration, pronunciation, derivation, strongs_def, kjv_def FROM strongs WHERE number IN (\(placeholders))"

        let rows = try? conn.query(sql, bindings: numbers) { stmt in
            StrongsEntry(
                number: ModuleConnection.text(stmt, 0),
                lemma: ModuleConnection.text(stmt, 1),
                transliteration: ModuleConnection.text(stmt, 2),
                pronunciation: ModuleConnection.text(stmt, 3).isEmpty ? nil : ModuleConnection.text(stmt, 3),
                derivation: ModuleConnection.text(stmt, 4).isEmpty ? nil : ModuleConnection.text(stmt, 4),
                strongsDefinition: ModuleConnection.text(stmt, 5).isEmpty ? nil : ModuleConnection.text(stmt, 5),
                kjvDefinition: ModuleConnection.text(stmt, 6).isEmpty ? nil : ModuleConnection.text(stmt, 6)
            )
        }

        var result: [String: StrongsEntry] = [:]
        for entry in rows ?? [] {
            result[entry.number] = entry
        }
        return result
    }

    // MARK: - Bundled JSON Fallback

    /// Load a Strong's entry from bundled strongs-hebrew.json / strongs-greek.json.
    private static func loadFromBundledJSON(number: String) -> StrongsEntry? {
        let isHebrew = number.hasPrefix("H")
        let filename = isHebrew ? "strongs-hebrew" : "strongs-greek"

        guard let url = Bundle.main.url(forResource: filename, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        // Parse as dictionary keyed by Strong's number
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]],
              let entry = dict[number] else {
            return nil
        }

        return StrongsEntry(
            number: number,
            lemma: entry["lemma"] as? String ?? "",
            transliteration: entry["xlit"] as? String ?? entry["translit"] as? String ?? "",
            pronunciation: entry["pron"] as? String,
            derivation: entry["derivation"] as? String,
            strongsDefinition: entry["strongs_def"] as? String,
            kjvDefinition: entry["kjv_def"] as? String
        )
    }
}

// MARK: - Resolved Word Tag

/// A word tag with its Strong's concordance entries fully resolved.
struct ResolvedWordTag: Identifiable, Hashable {
    var id: Int { wordTag.wordIndex }
    let wordTag: WordTag
    let entries: [StrongsEntry]

    var word: String { wordTag.word }
    var strongsNumbers: [String] { wordTag.strongsNumbers }

    /// Primary entry (first resolved Strong's number).
    var primaryEntry: StrongsEntry? { entries.first }
}
