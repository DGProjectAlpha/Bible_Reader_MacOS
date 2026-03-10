import Foundation

// MARK: - Treasury of Scripture Knowledge (TSK) Service

/// Loads and queries TSK cross-reference data from bundled JSON.
/// Data format: { "Gen.1.1": ["Ps.96.5", ...], ... }
enum TSKService {

    private static var data: [String: [String]] = [:]
    private static var loaded = false

    /// Load TSK data from the bundled JSON file. Safe to call multiple times.
    static func loadIfNeeded() {
        guard !loaded else { return }
        guard let url = Bundle.main.url(forResource: "tskCrossRefs", withExtension: "json") else {
            print("[TSK] tskCrossRefs.json not found in bundle")
            loaded = true
            return
        }
        do {
            let jsonData = try Data(contentsOf: url)
            data = try JSONDecoder().decode([String: [String]].self, from: jsonData)
            loaded = true
            print("[TSK] Loaded \(data.count) entries")
        } catch {
            print("[TSK] Failed to load: \(error)")
            loaded = true
        }
    }

    /// Get cross-references for a verse given in app format "Book:Chapter:Verse".
    static func getRefs(for verseId: String) -> [TSKRef] {
        loadIfNeeded()
        guard let parts = parseAppVerseId(verseId) else { return [] }
        guard let abbr = bookToTSK[parts.book] else { return [] }

        let key = "\(abbr).\(parts.chapter).\(parts.verse)"
        guard let rawRefs = data[key] else { return [] }

        return rawRefs.compactMap { parseTSKRef($0) }
    }

    // MARK: - TSK Ref Parsing

    struct TSKRef {
        let book: String      // Full book name (app format)
        let chapter: Int
        let verse: Int
        /// App verse ID format: "Book:Chapter:Verse"
        var verseId: String { "\(book):\(chapter):\(verse)" }
        /// Display label: "John 3:16"
        var label: String { "\(book) \(chapter):\(verse)" }
    }

    /// Parse a TSK ref string like "Gen.1.1" or "1Cor.3.16" into a structured object.
    private static func parseTSKRef(_ ref: String) -> TSKRef? {
        let lastDot = ref.lastIndex(of: ".")
        guard let lastDot else { return nil }
        let beforeLast = ref[ref.startIndex..<lastDot]
        guard let secondLastDot = beforeLast.lastIndex(of: ".") else { return nil }

        let abbr = String(ref[ref.startIndex..<secondLastDot])
        let chapterStr = String(ref[ref.index(after: secondLastDot)..<lastDot])
        let verseStr = String(ref[ref.index(after: lastDot)...])

        guard let chapter = Int(chapterStr), let verse = Int(verseStr) else { return nil }
        guard let book = tskToBook[abbr] else { return nil }

        return TSKRef(book: book, chapter: chapter, verse: verse)
    }

    /// Parse app verse ID "Book:Chapter:Verse" into components.
    private static func parseAppVerseId(_ verseId: String) -> (book: String, chapter: Int, verse: Int)? {
        let parts = verseId.components(separatedBy: ":")
        guard parts.count >= 3,
              let chapter = Int(parts[parts.count - 2]),
              let verse = Int(parts[parts.count - 1]) else { return nil }
        let book = parts.dropLast(2).joined(separator: ":")
        guard !book.isEmpty else { return nil }
        return (book, chapter, verse)
    }

    // MARK: - Book Name Mappings

    private static let bookToTSK: [String: String] = [
        "Genesis": "Gen", "Exodus": "Exod", "Leviticus": "Lev", "Numbers": "Num",
        "Deuteronomy": "Deut", "Joshua": "Josh", "Judges": "Judg", "Ruth": "Ruth",
        "1 Samuel": "1Sam", "2 Samuel": "2Sam", "1 Kings": "1Kgs", "2 Kings": "2Kgs",
        "1 Chronicles": "1Chr", "2 Chronicles": "2Chr", "Ezra": "Ezra",
        "Nehemiah": "Neh", "Esther": "Esth", "Job": "Job", "Psalms": "Ps",
        "Proverbs": "Prov", "Ecclesiastes": "Eccl", "Song of Solomon": "Song",
        "Isaiah": "Isa", "Jeremiah": "Jer", "Lamentations": "Lam", "Ezekiel": "Ezek",
        "Daniel": "Dan", "Hosea": "Hos", "Joel": "Joel", "Amos": "Amos",
        "Obadiah": "Obad", "Jonah": "Jonah", "Micah": "Mic", "Nahum": "Nah",
        "Habakkuk": "Hab", "Zephaniah": "Zeph", "Haggai": "Hag", "Zechariah": "Zech",
        "Malachi": "Mal", "Matthew": "Matt", "Mark": "Mark", "Luke": "Luke",
        "John": "John", "Acts": "Acts", "Romans": "Rom", "1 Corinthians": "1Cor",
        "2 Corinthians": "2Cor", "Galatians": "Gal", "Ephesians": "Eph",
        "Philippians": "Phil", "Colossians": "Col", "1 Thessalonians": "1Thess",
        "2 Thessalonians": "2Thess", "1 Timothy": "1Tim", "2 Timothy": "2Tim",
        "Titus": "Titus", "Philemon": "Phlm", "Hebrews": "Heb", "James": "Jas",
        "1 Peter": "1Pet", "2 Peter": "2Pet", "1 John": "1John", "2 John": "2John",
        "3 John": "3John", "Jude": "Jude", "Revelation": "Rev",
    ]

    private static let tskToBook: [String: String] = {
        Dictionary(uniqueKeysWithValues: bookToTSK.map { ($0.value, $0.key) })
    }()
}
