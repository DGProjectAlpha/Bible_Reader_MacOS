import Foundation

// MARK: - Versification Schemes

enum VersificationScheme: String, Codable, Hashable, CaseIterable {
    case kjv      = "kjv"
    case lxx      = "lxx"
    case synodal  = "synodal"
    case vulgate  = "vulgate"

    static func from(_ string: String) -> VersificationScheme {
        VersificationScheme(rawValue: string.lowercased()) ?? .kjv
    }
}

/// A canonical verse reference using KJV numbering as the internal interchange format.
struct CanonicalRef: Hashable {
    let book: String
    let chapter: Int
    let verse: Int

    var id: String { "\(book):\(chapter):\(verse)" }
}

// MARK: - Versification Service

final class VersificationService {

    static let shared = VersificationService()
    private init() {}

    // MARK: - Public API

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

    func convert(book: String, chapter: Int, verse: Int,
                 from source: VersificationScheme, to target: VersificationScheme) -> (book: String, chapter: Int, verse: Int) {
        if source == target { return (book, chapter, verse) }
        let canonical = toCanonical(book: book, chapter: chapter, verse: verse, scheme: source)
        return fromCanonical(canonical, to: target)
    }

    func chapterCount(book: String, scheme: VersificationScheme) -> Int {
        if let override = schemeChapterOverrides[scheme]?[book] {
            return override
        }
        return BibleBooks.chapterCounts[book] ?? 0
    }

    // MARK: - Psalm Numbering Tables

    private static let kjvPsalmToLxx: [Int: Int] = {
        var map = [Int: Int]()
        map[9] = 9
        map[10] = 9
        for kjv in 11...113 {
            map[kjv] = kjv - 1
        }
        map[114] = 113
        map[115] = 113
        map[116] = 114
        for kjv in 117...146 {
            map[kjv] = kjv - 1
        }
        map[147] = 146
        return map
    }()

    private static let lxxPsalmToKjv: [Int: Int] = {
        var map = [Int: Int]()
        map[9] = 9
        for lxx in 10...112 {
            map[lxx] = lxx + 1
        }
        map[113] = 114
        map[114] = 116
        map[115] = 116
        for lxx in 116...145 {
            map[lxx] = lxx + 1
        }
        map[146] = 147
        map[147] = 147
        return map
    }()

    // MARK: - Synodal Psalm Superscription Offsets

    private static let psalmsWithSuperscriptionOffset: Set<Int> = [
        3, 4, 5, 6, 7, 8, 9, 12, 13, 18, 19, 20, 21, 22, 30, 31, 34, 36, 38, 39,
        40, 41, 42, 44, 45, 46, 47, 48, 49, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60,
        61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 75, 76, 77, 80, 81, 83, 84, 85, 88,
        89, 92, 98, 100, 101, 102, 108, 109, 110, 140, 142
    ]

    // MARK: - Chapter Count Overrides per Scheme

    private let schemeChapterOverrides: [VersificationScheme: [String: Int]] = [
        .lxx: [
            "Daniel": 14,
        ],
        .synodal: [
            "Joel": 4,
            "Malachi": 3,
        ],
        .vulgate: [
            "Daniel": 14,
        ],
    ]

    // MARK: - LXX ↔ Canonical

    private func lxxToCanonical(book: String, chapter: Int, verse: Int) -> CanonicalRef {
        let normalizedBook = lxxBookToCanonical(book)

        if normalizedBook == "Psalms" {
            if let kjvPsalm = Self.lxxPsalmToKjv[chapter] {
                return CanonicalRef(book: "Psalms", chapter: kjvPsalm, verse: verse)
            }
            return CanonicalRef(book: "Psalms", chapter: chapter, verse: verse)
        }

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
        if book == "Psalms" {
            var kjvChapter = chapter
            if let mapped = Self.lxxPsalmToKjv[chapter] {
                kjvChapter = mapped
            }
            var kjvVerse = verse
            if Self.psalmsWithSuperscriptionOffset.contains(kjvChapter) && verse > 1 {
                kjvVerse = verse - 1
            }
            return CanonicalRef(book: "Psalms", chapter: kjvChapter, verse: kjvVerse)
        }

        if book == "Joel" {
            if chapter == 2 && verse >= 28 {
                return CanonicalRef(book: "Joel", chapter: 3, verse: verse - 27)
            }
            if chapter == 3 {
                return CanonicalRef(book: "Joel", chapter: 3, verse: verse + 5)
            }
            if chapter == 4 {
                return CanonicalRef(book: "Joel", chapter: 3, verse: verse + 16)
            }
        }

        if book == "Malachi" && chapter == 3 && verse >= 19 {
            return CanonicalRef(book: "Malachi", chapter: 4, verse: verse - 18)
        }

        return CanonicalRef(book: book, chapter: chapter, verse: verse)
    }

    private func canonicalToSynodal(_ ref: CanonicalRef) -> (book: String, chapter: Int, verse: Int) {
        if ref.book == "Psalms" {
            var synChapter = ref.chapter
            if let lxxPsalm = Self.kjvPsalmToLxx[ref.chapter] {
                synChapter = lxxPsalm
            }
            var synVerse = ref.verse
            if Self.psalmsWithSuperscriptionOffset.contains(ref.chapter) {
                synVerse = ref.verse + 1
            }
            return ("Psalms", synChapter, synVerse)
        }

        if ref.book == "Joel" && ref.chapter == 3 {
            if ref.verse <= 5 {
                return ("Joel", 2, ref.verse + 27)
            }
            if ref.verse <= 16 {
                return ("Joel", 3, ref.verse - 5)
            }
            return ("Joel", 4, ref.verse - 16)
        }

        if ref.book == "Malachi" && ref.chapter == 4 {
            return ("Malachi", 3, ref.verse + 18)
        }

        return (ref.book, ref.chapter, ref.verse)
    }

    // MARK: - Vulgate ↔ Canonical

    private func vulgateToCanonical(book: String, chapter: Int, verse: Int) -> CanonicalRef {
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
