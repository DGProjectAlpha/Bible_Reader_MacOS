import Foundation

// MARK: - Versification Schemes

/// Supported versification schemes for Bible modules.
enum VersificationScheme: String, Codable, Hashable, CaseIterable {
    case kjv      = "kjv"       // Protestant standard (KJV, ESV, NIV, NLT, etc.)
    case lxx      = "lxx"       // Septuagint (Greek OT, used by Orthodox traditions)
    case synodal  = "synodal"   // Russian Synodal numbering
    case vulgate  = "vulgate"   // Latin Vulgate numbering

    static func from(_ string: String) -> VersificationScheme {
        VersificationScheme(rawValue: string.lowercased()) ?? .kjv
    }
}

/// A canonical verse reference used as the internal interchange format.
/// All versification schemes normalize TO and FROM this format (which uses KJV numbering).
struct CanonicalRef: Hashable {
    let book: String
    let chapter: Int
    let verse: Int

    var verseKey: VerseKey { VerseKey(book: book, chapter: chapter, verse: verse) }
    var id: String { "\(book):\(chapter):\(verse)" }
}

// MARK: - Versification Service

/// Maps variant versification schemes to a common canonical (KJV-based) reference system.
///
/// Key differences handled:
/// - **Psalms numbering**: LXX/Vulgate Psalms 9-146 are offset by -1 from KJV (LXX Ps 9 = KJV Ps 9-10, etc.)
/// - **Psalm superscriptions**: Synodal/LXX count superscriptions as verse 1, shifting all verses +1
/// - **3 Kingdoms / 4 Kingdoms**: LXX names for 1 Kings / 2 Kings
/// - **1 Esdras / 2 Esdras**: LXX split of Ezra-Nehemiah
/// - **Daniel additions**: LXX includes Prayer of Azariah (Dan 3:24-90), Susanna (Dan 13), Bel (Dan 14)
/// - **Malachi 3-4**: Synodal has Malachi 3 where KJV has Malachi 3-4 (Synodal 3:19-24 = KJV 4:1-6)
/// - **Joel chapters**: Synodal/LXX Joel has 4 chapters; KJV Joel has 3 (Synodal 2:28-32 → KJV 3:1-5, Synodal 3-4 → KJV 3)
final class VersificationService {

    static let shared = VersificationService()
    private init() {}

    // MARK: - Public API

    /// Normalize a verse reference from a given scheme to canonical (KJV) numbering.
    func toCanonical(book: String, chapter: Int, verse: Int, scheme: VersificationScheme) -> CanonicalRef {
        switch scheme {
        case .kjv:
            return CanonicalRef(book: book, chapter: chapter, verse: verse)
        case .lxx:
            return lxxToCanonical(book: book, chapter: chapter, verse: verse)
        case .synodal:
            return synodalToCanonical(book: book, chapter: chapter, verse: verse)
        case .vulgate:
            return vulgateToCanonical(book: book, chapter: chapter, verse: verse)
        }
    }

    /// Convert a canonical (KJV) reference to the target scheme's numbering.
    func fromCanonical(_ ref: CanonicalRef, to scheme: VersificationScheme) -> (book: String, chapter: Int, verse: Int) {
        switch scheme {
        case .kjv:
            return (ref.book, ref.chapter, ref.verse)
        case .lxx:
            return canonicalToLxx(ref)
        case .synodal:
            return canonicalToSynodal(ref)
        case .vulgate:
            return canonicalToVulgate(ref)
        }
    }

    /// Convert a verse reference between two arbitrary schemes.
    func convert(book: String, chapter: Int, verse: Int,
                 from source: VersificationScheme, to target: VersificationScheme) -> (book: String, chapter: Int, verse: Int) {
        if source == target { return (book, chapter, verse) }
        let canonical = toCanonical(book: book, chapter: chapter, verse: verse, scheme: source)
        return fromCanonical(canonical, to: target)
    }

    /// Returns the chapter count for a book in the given scheme.
    func chapterCount(book: String, scheme: VersificationScheme) -> Int {
        if let override = schemeChapterOverrides[scheme]?[book] {
            return override
        }
        return BibleBooks.chapterCounts[book] ?? 0
    }

    // MARK: - Psalm Numbering Tables

    /// Psalms where LXX/Vulgate numbering diverges from KJV/Hebrew.
    /// LXX combines KJV 9+10 → LXX 9, then LXX 10-112 = KJV 11-113,
    /// LXX splits KJV 147 → LXX 146+147, netting back to 150 total.
    ///
    /// Map: KJV Psalm number → LXX Psalm number (for the divergent range)
    private static let kjvPsalmToLxx: [Int: Int] = {
        var map = [Int: Int]()
        // KJV 1-8 = LXX 1-8 (identical)
        // KJV 9-10 merged into LXX 9
        map[9] = 9
        map[10] = 9  // KJV 10 is part of LXX 9
        // KJV 11-113 = LXX 10-112 (offset -1)
        for kjv in 11...113 {
            map[kjv] = kjv - 1
        }
        // KJV 114-115 merged into LXX 113
        map[114] = 113
        map[115] = 113
        // KJV 116:1-9 = LXX 114, KJV 116:10-19 = LXX 115
        map[116] = 114 // approximate: chapter-level only; verse split handled separately
        // KJV 117-146 = LXX 116-145 (offset -1)
        for kjv in 117...146 {
            map[kjv] = kjv - 1
        }
        // KJV 147:1-11 = LXX 146, KJV 147:12-20 = LXX 147
        map[147] = 146 // approximate at chapter level
        // KJV 148-150 = LXX 148-150 (identical)
        return map
    }()

    /// Reverse: LXX Psalm → KJV Psalm (first KJV psalm in the range)
    private static let lxxPsalmToKjv: [Int: Int] = {
        var map = [Int: Int]()
        // LXX 1-8 = KJV 1-8
        // LXX 9 = KJV 9 (+ KJV 10)
        map[9] = 9
        // LXX 10-112 = KJV 11-113
        for lxx in 10...112 {
            map[lxx] = lxx + 1
        }
        // LXX 113 = KJV 114 (+ KJV 115)
        map[113] = 114
        // LXX 114 = KJV 116:1-9
        map[114] = 116
        // LXX 115 = KJV 116:10-19
        map[115] = 116
        // LXX 116-145 = KJV 117-146
        for lxx in 116...145 {
            map[lxx] = lxx + 1
        }
        // LXX 146 = KJV 147:1-11
        map[146] = 147
        // LXX 147 = KJV 147:12-20
        map[147] = 147
        return map
    }()

    // MARK: - Synodal Psalm Superscription Offsets

    /// Psalms that have superscriptions counted as verse 1 in Synodal but not in KJV.
    /// In these Psalms, Synodal verse N = KJV verse N-1.
    private static let psalmsWithSuperscriptionOffset: Set<Int> = [
        3, 4, 5, 6, 7, 8, 9, 12, 13, 18, 19, 20, 21, 22, 30, 31, 34, 36, 38, 39,
        40, 41, 42, 44, 45, 46, 47, 48, 49, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60,
        61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 75, 76, 77, 80, 81, 83, 84, 85, 88,
        89, 92, 98, 100, 101, 102, 108, 109, 110, 140, 142
    ]

    // MARK: - Chapter Count Overrides per Scheme

    private let schemeChapterOverrides: [VersificationScheme: [String: Int]] = [
        .lxx: [
            "Daniel": 14,    // LXX adds Susanna (13) and Bel & Dragon (14)
        ],
        .synodal: [
            "Joel": 4,       // Synodal has 4 chapters vs KJV's 3
            "Malachi": 3,    // Synodal keeps Malachi as 3 chapters (KJV 4:1-6 = Synodal 3:19-24)
        ],
        .vulgate: [
            "Daniel": 14,
        ],
    ]

    // MARK: - LXX ↔ Canonical

    private func lxxToCanonical(book: String, chapter: Int, verse: Int) -> CanonicalRef {
        // LXX book name normalization
        let normalizedBook = lxxBookToCanonical(book)

        if normalizedBook == "Psalms" {
            if let kjvPsalm = Self.lxxPsalmToKjv[chapter] {
                return CanonicalRef(book: "Psalms", chapter: kjvPsalm, verse: verse)
            }
            return CanonicalRef(book: "Psalms", chapter: chapter, verse: verse)
        }

        // Daniel: LXX 3:24-90 is Prayer of Azariah (no KJV equivalent — pass through)
        // Daniel 13 (Susanna) and 14 (Bel) are deuterocanonical — pass through
        if normalizedBook == "Daniel" && (chapter > 12 || (chapter == 3 && verse >= 24 && verse <= 90)) {
            return CanonicalRef(book: normalizedBook, chapter: chapter, verse: verse)
        }

        return CanonicalRef(book: normalizedBook, chapter: chapter, verse: verse)
    }

    private func canonicalToLxx(_ ref: CanonicalRef) -> (book: String, chapter: Int, verse: Int) {
        if ref.book == "Psalms" {
            if let lxxPsalm = Self.kjvPsalmToLxx[ref.chapter] {
                return ("Psalms", lxxPsalm, ref.verse)
            }
            return ("Psalms", ref.chapter, ref.verse)
        }
        return (ref.book, ref.chapter, ref.verse)
    }

    // MARK: - Synodal ↔ Canonical

    private func synodalToCanonical(book: String, chapter: Int, verse: Int) -> CanonicalRef {
        // Psalms: Synodal uses LXX numbering AND counts superscriptions as verse 1
        if book == "Psalms" {
            // First: LXX psalm number → KJV psalm number
            var kjvChapter = chapter
            if let mapped = Self.lxxPsalmToKjv[chapter] {
                kjvChapter = mapped
            }
            // Then: adjust verse for superscription offset
            var kjvVerse = verse
            if Self.psalmsWithSuperscriptionOffset.contains(kjvChapter) && verse > 1 {
                kjvVerse = verse - 1
            }
            return CanonicalRef(book: "Psalms", chapter: kjvChapter, verse: kjvVerse)
        }

        // Joel: Synodal 2:28-32 = KJV 3:1-5; Synodal 3 = KJV 3:6+; Synodal 4 = no KJV equivalent (or KJV 3 continued)
        if book == "Joel" {
            if chapter == 2 && verse >= 28 {
                return CanonicalRef(book: "Joel", chapter: 3, verse: verse - 27)
            }
            if chapter == 3 {
                return CanonicalRef(book: "Joel", chapter: 3, verse: verse + 5)
            }
            if chapter == 4 {
                // Synodal Joel 4 = KJV Joel 3 continued (verse offset depends on Synodal ch3 length)
                return CanonicalRef(book: "Joel", chapter: 3, verse: verse + 16)
            }
        }

        // Malachi: Synodal 3:19-24 = KJV 4:1-6
        if book == "Malachi" && chapter == 3 && verse >= 19 {
            return CanonicalRef(book: "Malachi", chapter: 4, verse: verse - 18)
        }

        return CanonicalRef(book: book, chapter: chapter, verse: verse)
    }

    private func canonicalToSynodal(_ ref: CanonicalRef) -> (book: String, chapter: Int, verse: Int) {
        if ref.book == "Psalms" {
            // KJV psalm → LXX/Synodal psalm
            var synChapter = ref.chapter
            if let lxxPsalm = Self.kjvPsalmToLxx[ref.chapter] {
                synChapter = lxxPsalm
            }
            // Adjust verse for superscription
            var synVerse = ref.verse
            if Self.psalmsWithSuperscriptionOffset.contains(ref.chapter) {
                synVerse = ref.verse + 1
            }
            return ("Psalms", synChapter, synVerse)
        }

        // Joel: KJV 3:1-5 → Synodal 2:28-32
        if ref.book == "Joel" && ref.chapter == 3 {
            if ref.verse <= 5 {
                return ("Joel", 2, ref.verse + 27)
            }
            if ref.verse <= 16 {
                return ("Joel", 3, ref.verse - 5)
            }
            return ("Joel", 4, ref.verse - 16)
        }

        // Malachi: KJV 4:1-6 → Synodal 3:19-24
        if ref.book == "Malachi" && ref.chapter == 4 {
            return ("Malachi", 3, ref.verse + 18)
        }

        return (ref.book, ref.chapter, ref.verse)
    }

    // MARK: - Vulgate ↔ Canonical

    private func vulgateToCanonical(book: String, chapter: Int, verse: Int) -> CanonicalRef {
        // Vulgate Psalms follow LXX numbering
        if book == "Psalms" {
            if let kjvPsalm = Self.lxxPsalmToKjv[chapter] {
                return CanonicalRef(book: "Psalms", chapter: kjvPsalm, verse: verse)
            }
            return CanonicalRef(book: "Psalms", chapter: chapter, verse: verse)
        }
        return CanonicalRef(book: book, chapter: chapter, verse: verse)
    }

    private func canonicalToVulgate(_ ref: CanonicalRef) -> (book: String, chapter: Int, verse: Int) {
        if ref.book == "Psalms" {
            if let lxxPsalm = Self.kjvPsalmToLxx[ref.chapter] {
                return ("Psalms", lxxPsalm, ref.verse)
            }
            return ("Psalms", ref.chapter, ref.verse)
        }
        return (ref.book, ref.chapter, ref.verse)
    }

    // MARK: - LXX Book Name Normalization

    /// Maps LXX-specific book names to canonical (KJV) names.
    private func lxxBookToCanonical(_ book: String) -> String {
        switch book {
        case "1 Kingdoms", "1 Reigns":      return "1 Samuel"
        case "2 Kingdoms", "2 Reigns":      return "2 Samuel"
        case "3 Kingdoms", "3 Reigns":      return "1 Kings"
        case "4 Kingdoms", "4 Reigns":      return "2 Kings"
        case "1 Paralipomenon":             return "1 Chronicles"
        case "2 Paralipomenon":             return "2 Chronicles"
        case "1 Esdras":                    return "Ezra"
        case "2 Esdras":                    return "Nehemiah"
        default:                            return book
        }
    }
}
