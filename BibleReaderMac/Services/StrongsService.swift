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
        guard !wordTags.isEmpty else {
            print("[StrongsService] No word tags found for verse: \(verseId)")
            return []
        }

        // Collect all unique Strong's numbers
        let allNumbers = Array(Set(wordTags.flatMap { $0.strongsNumbers }))
        let entries = batchLookup(allNumbers, in: filePath)

        if entries.isEmpty && !allNumbers.isEmpty {
            print("[StrongsService] WARNING: Found \(allNumbers.count) Strong's numbers but resolved 0 entries. Numbers: \(allNumbers.prefix(5))")
            // Check if strongs table exists
            let hasTable = (try? conn.tableExists("strongs")) ?? false
            print("[StrongsService] Module has strongs table: \(hasTable), filePath: \(filePath)")
        }

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
        reverseIndexLock.lock()
        reverseIndex = nil
        reverseIndexLock.unlock()
        jsonLock.lock()
        hebrewJSON = nil
        greekJSON = nil
        jsonLoaded = false
        jsonLock.unlock()
    }

    // MARK: - Find Verses by Strong's Number

    /// A verse reference returned by findVersesByStrongs.
    struct VerseReference: Identifiable {
        let id = UUID()
        let book: String
        let chapter: Int
        let verse: Int
        let text: String

        var displayRef: String { "\(book) \(chapter):\(verse)" }
    }

    /// Search the word_tags table for all verses containing a given Strong's number.
    /// Uses the same filePath (KJV module) to look up verse text. Caps at 300 results.
    static func findVersesByStrongs(_ number: String, filePath: String) -> [VerseReference] {
        guard let conn = try? ModuleConnectionPool.shared.connection(for: filePath),
              (try? conn.tableExists("word_tags")) == true else {
            return []
        }

        // Get all distinct verse_ids that contain this Strong's number
        let verseIds = (try? conn.query(
            "SELECT DISTINCT verse_id FROM word_tags WHERE strongs_number = ?1 ORDER BY rowid LIMIT 300",
            bindings: [number]
        ) { stmt in
            ModuleConnection.text(stmt, 0)
        }) ?? []

        guard !verseIds.isEmpty else { return [] }

        // Parse verse IDs into components
        struct ParsedRef {
            let verseId: String
            let book: String
            let chapter: Int
            let verse: Int
        }
        var parsed: [ParsedRef] = []
        for vid in verseIds {
            let parts = vid.split(separator: ":")
            guard parts.count >= 3,
                  let chapter = Int(parts[parts.count - 2]),
                  let verse = Int(parts[parts.count - 1]) else { continue }
            let book = parts.dropLast(2).joined(separator: ":")
            parsed.append(ParsedRef(verseId: vid, book: book, chapter: chapter, verse: verse))
        }
        guard !parsed.isEmpty else { return [] }

        // Batch load all verse texts with a single IN query instead of N individual queries
        let placeholders = parsed.enumerated().map { "?\($0.offset + 1)" }.joined(separator: ",")
        let textRows = (try? conn.query(
            "SELECT verse_id, text FROM verses WHERE verse_id IN (\(placeholders))",
            bindings: parsed.map { $0.verseId }
        ) { stmt in
            (ModuleConnection.text(stmt, 0), ModuleConnection.text(stmt, 1))
        }) ?? []
        let textByVerseId = Dictionary(textRows, uniquingKeysWith: { first, _ in first })

        return parsed.map { ref in
            VerseReference(
                book: ref.book,
                chapter: ref.chapter,
                verse: ref.verse,
                text: textByVerseId[ref.verseId] ?? ""
            )
        }
    }

    // MARK: - Similar Entries (Reverse Index)

    private static var reverseIndex: [String: [String]]? = nil
    private static let reverseIndexLock = NSLock()

    /// Build a reverse index from normalized English words to Strong's numbers,
    /// using the bundled JSON data (kjv_def and strongs_def fields).
    private static func buildReverseIndex() -> [String: [String]] {
        var index: [String: [String]] = [:]

        func addEntries(_ dict: [String: [String: Any]]) {
            for (num, entry) in dict {
                let kjv = entry["kjv_def"] as? String ?? ""
                let def = entry["strongs_def"] as? String ?? ""
                let text = "\(kjv) \(def)".lowercased()
                let words = Set(
                    text.replacingOccurrences(of: "[^a-z\\s-]", with: " ", options: .regularExpression)
                        .split(separator: " ")
                        .map { $0.replacingOccurrences(of: "-", with: "") }
                        .filter { $0.count > 2 }
                )
                for word in words {
                    index[word, default: []].append(num)
                }
            }
        }

        // Load bundled JSON
        for filename in ["strongs-hebrew", "strongs-greek"] {
            guard let url = findBundledJSON(filename), let data = try? Data(contentsOf: url),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
                continue
            }
            addEntries(dict)
        }

        return index
    }

    /// Score how well an entry matches the clicked word.
    /// 3: word is the first token in kjv_def; 2: exact word match; 1: appears somewhere.
    private static func scoreEntry(_ entry: StrongsEntry, normalized: String) -> Int {
        let kjv = (entry.kjvDefinition ?? "").lowercased()
            .replacingOccurrences(of: "[^a-z\\s]", with: " ", options: .regularExpression)
        let tokens = kjv.split(separator: " ").map(String.init)
        if tokens.first == normalized { return 3 }
        if tokens.contains(normalized) { return 2 }
        return 1
    }

    /// Search for similar Strong's entries by English word (reverse-index lookup).
    /// Returns (exact: best match, similar: other matches), like the Windows version.
    static func searchSimilar(word: String, filePath: String, limit: Int = 10) -> (exact: StrongsEntry?, similar: [StrongsEntry]) {
        let normalized = word.lowercased()
            .replacingOccurrences(of: "[^a-z]", with: "", options: .regularExpression)
        guard !normalized.isEmpty else { return (nil, []) }

        reverseIndexLock.lock()
        if reverseIndex == nil {
            reverseIndex = buildReverseIndex()
        }
        let idx = reverseIndex!
        reverseIndexLock.unlock()

        guard let nums = idx[normalized] else { return (nil, []) }

        // Look up entries
        let candidates: [StrongsEntry] = nums.prefix(limit).compactMap { num in
            lookup(num, in: filePath)
        }
        guard !candidates.isEmpty else { return (nil, []) }

        // Find best match
        var bestIdx = 0
        var bestScore = scoreEntry(candidates[0], normalized: normalized)
        for i in 1..<candidates.count {
            let s = scoreEntry(candidates[i], normalized: normalized)
            if s > bestScore { bestScore = s; bestIdx = i }
        }

        let exact = candidates[bestIdx]
        var similar = candidates
        similar.remove(at: bestIdx)
        return (exact, similar)
    }

    // MARK: - Similar by Definition (Windows-style)

    /// Stop words excluded from definition matching.
    private static let stopWords: Set<String> = [
        "the", "and", "for", "that", "with", "from", "this", "which", "have",
        "not", "but", "are", "was", "were", "been", "being", "has", "had",
        "its", "also", "into", "more", "some", "such", "than", "them",
        "then", "these", "they", "will", "would", "could", "should",
        "can", "may", "might", "shall", "about", "after", "before",
        "between", "through", "against", "under", "over", "above"
    ]

    /// Tokenize a definition string into normalized words for matching.
    private static func tokenizeDefinition(_ text: String) -> Set<String> {
        let cleaned = text.lowercased()
            .replacingOccurrences(of: "[^a-z\\s-]", with: " ", options: .regularExpression)
        let words = cleaned.split(separator: " ")
            .map { $0.replacingOccurrences(of: "-", with: "") }
            .filter { $0.count > 2 && !stopWords.contains($0) }
        return Set(words)
    }

    /// Find similar Strong's entries by matching kjv_def words of the selected entry
    /// against all other entries. This matches the Windows BibleReader algorithm:
    /// tokenize the selected entry's kjv_def, find entries sharing definition words,
    /// score by overlap count.
    static func findSimilarByDefinition(number: String, filePath: String, limit: Int = 15) -> [StrongsEntry] {
        // Look up the selected entry
        guard let selectedEntry = lookup(number, in: filePath),
              let kjvDef = selectedEntry.kjvDefinition, !kjvDef.isEmpty else {
            return []
        }

        // Tokenize the selected entry's kjv_def
        let selectedWords = tokenizeDefinition(kjvDef)
        guard !selectedWords.isEmpty else { return [] }

        // Build reverse index if needed
        reverseIndexLock.lock()
        if reverseIndex == nil {
            reverseIndex = buildReverseIndex()
        }
        let idx = reverseIndex!
        reverseIndexLock.unlock()

        // Collect candidate numbers from all definition words
        var candidateScores: [String: Int] = [:]
        for word in selectedWords {
            guard let nums = idx[word] else { continue }
            for num in nums where num != number {
                candidateScores[num, default: 0] += 1
            }
        }

        guard !candidateScores.isEmpty else { return [] }

        // Sort by overlap score descending, take top results
        let topCandidates = candidateScores
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }

        // Resolve entries
        let entries = batchLookup(topCandidates, in: filePath)

        // Return in score order
        return topCandidates.compactMap { entries[$0] }
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

    /// Cached parsed JSON dictionaries to avoid re-reading large files.
    private static var hebrewJSON: [String: [String: Any]]?
    private static var greekJSON: [String: [String: Any]]?
    private static var jsonLoaded = false
    private static let jsonLock = NSLock()

    /// Locate a bundled JSON file by trying multiple paths.
    private static func findBundledJSON(_ filename: String) -> URL? {
        // Direct bundle lookup
        if let url = Bundle.main.url(forResource: filename, withExtension: "json") {
            return url
        }
        // Subdirectory lookup (folder reference)
        if let url = Bundle.main.url(forResource: filename, withExtension: "json", subdirectory: "BundledModules") {
            return url
        }
        // Manual path construction for folder references
        if let resourceURL = Bundle.main.resourceURL {
            let manual = resourceURL.appendingPathComponent("BundledModules/\(filename).json")
            if FileManager.default.fileExists(atPath: manual.path) {
                return manual
            }
        }
        return nil
    }

    /// Load and cache both JSON dictionaries on first access.
    private static func ensureJSONLoaded() {
        jsonLock.lock()
        defer { jsonLock.unlock() }
        guard !jsonLoaded else { return }
        jsonLoaded = true

        for (filename, isHebrew) in [("strongs-hebrew", true), ("strongs-greek", false)] {
            guard let url = findBundledJSON(filename),
                  let data = try? Data(contentsOf: url),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
                continue
            }
            if isHebrew {
                hebrewJSON = dict
            } else {
                greekJSON = dict
            }
        }
    }

    /// Load a Strong's entry from bundled strongs-hebrew.json / strongs-greek.json.
    private static func loadFromBundledJSON(number: String) -> StrongsEntry? {
        ensureJSONLoaded()

        let isHebrew = number.hasPrefix("H")
        let dict = isHebrew ? hebrewJSON : greekJSON
        guard let entry = dict?[number] else { return nil }

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
