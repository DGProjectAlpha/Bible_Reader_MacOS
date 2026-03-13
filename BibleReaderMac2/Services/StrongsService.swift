import Foundation

// MARK: - Resolved Word Tag

struct ResolvedWordTag: Identifiable, Hashable {
    var id: Int { wordTag.wordIndex }
    let wordTag: WordTag
    let entry: StrongsEntry?

    var word: String { wordTag.word }
    var strongsNumber: String? { wordTag.strongsNumber }
}

// MARK: - Verse Reference (for Strong's search results)

struct StrongsVerseReference: Identifiable {
    let id = UUID()
    let book: String
    let chapter: Int
    let verse: Int
    let text: String

    var displayRef: String { "\(book) \(chapter):\(verse)" }
}

// MARK: - StrongsService

actor StrongsService {
    static let shared = StrongsService()

    private var cache: [String: StrongsEntry] = [:]
    private let databaseService = DatabaseService.shared

    /// Module IDs known to have a "strongs" table — used as fallback sources.
    private var strongsCapableModules: [String] = []

    /// Reverse index: English word → Strong's numbers (built from bundled JSON)
    private var reverseIndex: [String: [String]]?

    /// Cached bundled JSON dictionaries
    private var hebrewJSON: [String: [String: Any]]?
    private var greekJSON: [String: [String: Any]]?
    private var jsonLoaded = false

    private init() {}

    // MARK: - Registration

    func registerStrongsCapableModule(_ moduleId: String) {
        if !strongsCapableModules.contains(moduleId) {
            strongsCapableModules.append(moduleId)
        }
    }

    // MARK: - Word Tags + Resolution

    /// Fetch word tags for a verse and resolve each to its Strong's entry.
    func resolvedWordTags(moduleId: String, book: String, chapter: Int, verse: Int) async -> [ResolvedWordTag] {
        let tags: [WordTag]
        do {
            tags = try await databaseService.fetchWordTags(moduleId: moduleId, book: book, chapter: chapter, verse: verse)
        } catch {
            return []
        }

        guard !tags.isEmpty else { return [] }

        // Collect unique Strong's numbers and batch resolve
        let numbers = Array(Set(tags.compactMap(\.strongsNumber)))
        let entries = await batchLookup(numbers, preferredModule: moduleId)

        return tags.map { tag in
            let entry = tag.strongsNumber.flatMap { entries[$0] }
            return ResolvedWordTag(wordTag: tag, entry: entry)
        }
    }

    // MARK: - Single Lookup

    func lookup(_ number: String, preferredModule: String) async -> StrongsEntry? {
        if let cached = cache[number] { return cached }

        // Try preferred module first
        if let entry = try? await databaseService.fetchStrongsEntry(moduleId: preferredModule, number: number) {
            cache[number] = entry
            return entry
        }

        // Fallback to other strongs-capable modules
        for fallbackId in strongsCapableModules where fallbackId != preferredModule {
            if let entry = try? await databaseService.fetchStrongsEntry(moduleId: fallbackId, number: number) {
                cache[number] = entry
                return entry
            }
        }

        // Final fallback: bundled JSON files
        if let entry = loadFromBundledJSON(number: number) {
            cache[number] = entry
            return entry
        }

        return nil
    }

    // MARK: - Batch Lookup

    func batchLookup(_ numbers: [String], preferredModule: String) async -> [String: StrongsEntry] {
        var results: [String: StrongsEntry] = [:]
        var uncached: [String] = []

        for num in numbers {
            if let cached = cache[num] {
                results[num] = cached
            } else {
                uncached.append(num)
            }
        }

        guard !uncached.isEmpty else { return results }

        // Try preferred module
        if let entries = try? await databaseService.fetchStrongsEntries(moduleId: preferredModule, numbers: uncached) {
            for (num, entry) in entries {
                cache[num] = entry
                results[num] = entry
            }
            uncached = uncached.filter { results[$0] == nil }
        }

        // Fallback modules
        if !uncached.isEmpty {
            for fallbackId in strongsCapableModules where fallbackId != preferredModule {
                if let entries = try? await databaseService.fetchStrongsEntries(moduleId: fallbackId, numbers: uncached) {
                    for (num, entry) in entries {
                        cache[num] = entry
                        results[num] = entry
                    }
                    uncached = uncached.filter { results[$0] == nil }
                }
                if uncached.isEmpty { break }
            }
        }

        // Final fallback: bundled JSON
        for num in uncached {
            if let entry = loadFromBundledJSON(number: num) {
                cache[num] = entry
                results[num] = entry
            }
        }

        return results
    }

    // MARK: - Find Verses by Strong's Number

    func findVersesByStrongs(_ number: String, moduleId: String) async -> [StrongsVerseReference] {
        guard let results = try? await databaseService.findVersesByStrongs(moduleId: moduleId, number: number) else {
            return []
        }
        return results.map { r in
            StrongsVerseReference(book: r.book, chapter: r.chapter, verse: r.verse, text: r.text)
        }
    }

    // MARK: - Search Similar (reverse index)

    /// Search for Strong's entries by English word using reverse-index lookup.
    func searchSimilar(word: String, preferredModule: String, limit: Int = 10) async -> (exact: StrongsEntry?, similar: [StrongsEntry]) {
        let normalized = word.lowercased()
            .replacingOccurrences(of: "[^a-z]", with: "", options: .regularExpression)
        guard !normalized.isEmpty else { return (nil, []) }

        ensureReverseIndex()
        guard let nums = reverseIndex?[normalized] else { return (nil, []) }

        // Look up entries
        var candidates: [StrongsEntry] = []
        for num in nums.prefix(limit) {
            if let entry = await lookup(num, preferredModule: preferredModule) {
                candidates.append(entry)
            }
        }
        guard !candidates.isEmpty else { return (nil, []) }

        // Find best match by kjv_def scoring
        var bestIdx = 0
        var bestScore = Self.scoreEntry(candidates[0], normalized: normalized)
        for i in 1..<candidates.count {
            let s = Self.scoreEntry(candidates[i], normalized: normalized)
            if s > bestScore { bestScore = s; bestIdx = i }
        }

        let exact = candidates[bestIdx]
        var similar = candidates
        similar.remove(at: bestIdx)
        return (exact, similar)
    }

    // MARK: - Find Similar by Definition

    func findSimilarByDefinition(number: String, preferredModule: String, limit: Int = 15) async -> [StrongsEntry] {
        guard let selectedEntry = await lookup(number, preferredModule: preferredModule),
              let kjvDef = selectedEntry.kjvDefinition, !kjvDef.isEmpty else {
            return []
        }

        let selectedWords = Self.tokenizeDefinition(kjvDef)
        guard !selectedWords.isEmpty else { return [] }

        ensureReverseIndex()
        guard let idx = reverseIndex else { return [] }

        // Collect candidate numbers from all definition words
        var candidateScores: [String: Int] = [:]
        for word in selectedWords {
            guard let nums = idx[word] else { continue }
            for num in nums where num != number {
                candidateScores[num, default: 0] += 1
            }
        }

        guard !candidateScores.isEmpty else { return [] }

        let topCandidates = candidateScores
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }

        let entries = await batchLookup(topCandidates, preferredModule: preferredModule)
        return topCandidates.compactMap { entries[$0] }
    }

    // MARK: - Cache

    func clearCache() {
        cache.removeAll()
        reverseIndex = nil
        hebrewJSON = nil
        greekJSON = nil
        jsonLoaded = false
    }

    // MARK: - Private: Bundled JSON Fallback

    private func loadFromBundledJSON(number: String) -> StrongsEntry? {
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

    private func findBundledJSON(_ filename: String) -> URL? {
        if let url = Bundle.main.url(forResource: filename, withExtension: "json") {
            return url
        }
        if let url = Bundle.main.url(forResource: filename, withExtension: "json", subdirectory: "BundledModules") {
            return url
        }
        if let resourceURL = Bundle.main.resourceURL {
            let manual = resourceURL.appendingPathComponent("BundledModules/\(filename).json")
            if FileManager.default.fileExists(atPath: manual.path) {
                return manual
            }
        }
        return nil
    }

    private func ensureJSONLoaded() {
        guard !jsonLoaded else { return }
        jsonLoaded = true

        for (filename, isHebrew) in [("strongs-hebrew", true), ("strongs-greek", false)] {
            guard let url = findBundledJSON(filename),
                  let data = try? Data(contentsOf: url),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
                continue
            }
            if isHebrew { hebrewJSON = dict } else { greekJSON = dict }
        }
    }

    // MARK: - Private: Reverse Index

    private func ensureReverseIndex() {
        guard reverseIndex == nil else { return }
        ensureJSONLoaded()

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

        if let h = hebrewJSON { addEntries(h) }
        if let g = greekJSON { addEntries(g) }

        reverseIndex = index
    }

    // MARK: - Private: Scoring

    private static let stopWords: Set<String> = [
        "the", "and", "for", "that", "with", "from", "this", "which", "have",
        "not", "but", "are", "was", "were", "been", "being", "has", "had",
        "its", "also", "into", "more", "some", "such", "than", "them",
        "then", "these", "they", "will", "would", "could", "should",
        "can", "may", "might", "shall", "about", "after", "before",
        "between", "through", "against", "under", "over", "above"
    ]

    private static func scoreEntry(_ entry: StrongsEntry, normalized: String) -> Int {
        let kjv = (entry.kjvDefinition ?? "").lowercased()
            .replacingOccurrences(of: "[^a-z\\s]", with: " ", options: .regularExpression)
        let tokens = kjv.split(separator: " ").map(String.init)
        if tokens.first == normalized { return 3 }
        if tokens.contains(normalized) { return 2 }
        return 1
    }

    private static func tokenizeDefinition(_ text: String) -> Set<String> {
        let cleaned = text.lowercased()
            .replacingOccurrences(of: "[^a-z\\s-]", with: " ", options: .regularExpression)
        let words = cleaned.split(separator: " ")
            .map { $0.replacingOccurrences(of: "-", with: "") }
            .filter { $0.count > 2 && !stopWords.contains($0) }
        return Set(words)
    }
}
