import Foundation
import SwiftUI

// MARK: - Module Metadata

/// Metadata stored in the `metadata` key-value table of a .brbmod SQLite file,
/// or in the `meta` JSON block of a JSON-format .brbmod file.
struct ModuleMetadata: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String              // "King James Version"
    var abbreviation: String      // "KJV"
    var language: String          // BCP-47: "en", "ru", "he", "el"
    var format: ModuleFormat      // .plain or .tagged
    var version: Int              // schema version (currently 1)
    var versificationScheme: String // "kjv", "lxx", "synodal"
    var copyright: String?
    var notes: String?
    /// Localized book names keyed by canonical English name.
    /// e.g. { "Genesis": "Бытие", "Exodus": "Исход" }
    var bookNames: [String: String]?

    init(
        id: UUID = UUID(),
        name: String,
        abbreviation: String,
        language: String,
        format: ModuleFormat = .plain,
        version: Int = 1,
        versificationScheme: String = "kjv",
        copyright: String? = nil,
        notes: String? = nil,
        bookNames: [String: String]? = nil
    ) {
        self.id = id
        self.name = name
        self.abbreviation = abbreviation
        self.language = language
        self.format = format
        self.version = version
        self.versificationScheme = versificationScheme
        self.copyright = copyright
        self.notes = notes
        self.bookNames = bookNames
    }
}

enum ModuleFormat: String, Codable, Hashable {
    case plain   // flat string verses, no Strong's tagging
    case tagged  // per-word tokens with Strong's number arrays
}

// MARK: - Translation (loaded module reference)

/// A loaded Bible translation — points to its .brbmod file on disk.
struct Translation: Identifiable, Codable, Hashable {
    let id: UUID
    let metadata: ModuleMetadata
    let filePath: String

    init(id: UUID = UUID(), metadata: ModuleMetadata, filePath: String) {
        self.id = id
        self.metadata = metadata
        self.filePath = filePath
    }

    /// Derive a stable, deterministic UUID from a file path so the same module
    /// always has the same ID regardless of cache state or app restarts.
    static func stableId(for filePath: String) -> UUID {
        // Use the last path component (filename) as the seed — stable across container moves
        let seed = URL(fileURLWithPath: filePath).lastPathComponent
        var hash = seed.utf8.reduce(UInt64(14695981039346656037)) { acc, byte in
            (acc ^ UInt64(byte)) &* 1099511628211
        }
        // Map the 64-bit hash into a UUID (version 4 layout with fixed variant/version bits)
        var bytes = (0..<16).map { i -> UInt8 in
            defer { hash = hash &* 6364136223846793005 &+ 1442695040888963407 }
            return UInt8(hash >> 56)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40  // version 4
        bytes[8] = (bytes[8] & 0x3F) | 0x80  // variant bits
        return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],
                           bytes[4],bytes[5],bytes[6],bytes[7],
                           bytes[8],bytes[9],bytes[10],bytes[11],
                           bytes[12],bytes[13],bytes[14],bytes[15]))
    }

    var name: String { metadata.name }
    var abbreviation: String { metadata.abbreviation }
    var language: String { metadata.language }
    var versificationScheme: String { metadata.versificationScheme }
}

// MARK: - Book

/// Represents a single Bible book with its canonical position.
struct Book: Identifiable, Hashable {
    var id: String { name }
    let name: String             // canonical English name: "Genesis", "Matthew"
    let localizedName: String?   // from module metadata bookNames
    let chapterCount: Int
    let testament: Testament

    /// Display name: localized if available, otherwise canonical.
    var displayName: String { localizedName ?? name }
}

enum Testament: String, Codable, Hashable {
    case old
    case new
}

// MARK: - Verse

/// A single verse of Bible text.
struct Verse: Identifiable, Hashable {
    /// Composite key: "Book:Chapter:Verse" — e.g. "Genesis:1:1"
    let id: String
    let book: String
    let chapter: Int
    let number: Int      // 1-indexed verse number
    let text: String

    /// Strong's word tags for this verse (empty for plain-format modules).
    let wordTags: [WordTag]

    init(book: String, chapter: Int, number: Int, text: String, wordTags: [WordTag] = []) {
        self.id = "\(book):\(chapter):\(number)"
        self.book = book
        self.chapter = chapter
        self.number = number
        self.text = text
        self.wordTags = wordTags
    }
}

// MARK: - Word-Level Strong's Tagging

/// A single word in a verse with its Strong's concordance tag.
/// Maps to the `word_tags` table in the SQLite schema.
struct WordTag: Hashable {
    let wordIndex: Int          // 0-based position within the verse text
    let word: String            // the display word (may include punctuation)
    let strongsNumbers: [String] // e.g. ["H7225"], ["G2316"], ["H3068", "H430"] for compounds
}

/// A verse broken into individually-tagged word tokens (tagged format).
struct TaggedVerse: Hashable {
    let book: String
    let chapter: Int
    let number: Int
    let tokens: [WordToken]
}

/// A single word token with zero or more Strong's concordance numbers.
struct WordToken: Hashable, Codable {
    let word: String             // display word (may include punctuation)
    let strongs: [String]        // H### (Hebrew/OT) or G### (Greek/NT), empty if untagged
}

// MARK: - Strong's Concordance Entry

/// A single entry from the Strong's Exhaustive Concordance.
/// Loaded from strongs-hebrew.json / strongs-greek.json.
struct StrongsEntry: Identifiable, Hashable {
    /// The Strong's number itself, e.g. "H1", "G3056"
    var id: String { number }
    let number: String
    let lemma: String            // original Hebrew/Greek word
    let transliteration: String  // xlit (Hebrew) or translit (Greek)
    let pronunciation: String?
    let derivation: String?
    let strongsDefinition: String?
    let kjvDefinition: String?

    /// Which testament this entry belongs to.
    var testament: Testament {
        number.hasPrefix("H") ? .old : .new
    }
}

// MARK: - Cross-References

/// A cross-reference link between two verses.
/// Maps to the `cross_references` table in the SQLite schema.
struct CrossReference: Hashable {
    let fromVerseId: String     // "Book:Chapter:Verse"
    let toVerseId: String       // "Book:Chapter:Verse"
    let referenceType: CrossReferenceType
}

enum CrossReferenceType: String, Codable, Hashable {
    case parallel              // same event described elsewhere
    case quotation             // direct OT quote in NT
    case allusion              // indirect reference
    case related               // topically related
}

// MARK: - User Data Models

/// A user bookmark on a specific verse.
struct Bookmark: Identifiable, Codable, Hashable {
    let id: UUID
    let verseId: String         // "Book:Chapter:Verse"
    let translationId: UUID
    let label: String?
    var note: String?           // user-written note attached to this bookmark
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), verseId: String, translationId: UUID, label: String? = nil, note: String? = nil, createdAt: Date = Date(), updatedAt: Date? = nil) {
        self.id = id
        self.verseId = verseId
        self.translationId = translationId
        self.label = label
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

/// A user note attached to a specific verse.
struct Note: Identifiable, Codable, Hashable {
    let id: UUID
    let verseId: String         // "Book:Chapter:Verse"
    let translationId: UUID
    var content: String
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), verseId: String, translationId: UUID, content: String, createdAt: Date = Date(), updatedAt: Date? = nil) {
        self.id = id
        self.verseId = verseId
        self.translationId = translationId
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

/// A verse highlight with a named color.
struct Highlight: Identifiable, Codable, Hashable {
    let id: UUID
    let verseId: String         // "Book:Chapter:Verse"
    let translationId: UUID
    let color: HighlightColor
    let createdAt: Date

    init(id: UUID = UUID(), verseId: String, translationId: UUID, color: HighlightColor, createdAt: Date = Date()) {
        self.id = id
        self.verseId = verseId
        self.translationId = translationId
        self.color = color
        self.createdAt = createdAt
    }
}

enum HighlightColor: String, Codable, Hashable, CaseIterable {
    case yellow, green, blue, pink, purple

    var displayColor: Color {
        switch self {
        case .yellow: return Color.yellow
        case .green: return Color.green
        case .blue: return Color.blue
        case .pink: return Color.pink
        case .purple: return Color.purple
        }
    }

    var label: String {
        rawValue.capitalized
    }
}



// MARK: - Search

/// A single search hit across loaded translations.
struct SearchResult: Identifiable, Hashable {
    let id: UUID
    let translationAbbreviation: String
    let book: String
    let chapter: Int
    let verse: Int
    let text: String
    let matchRange: Range<String.Index>?

    init(translationAbbreviation: String = "", book: String, chapter: Int, verse: Int, text: String, matchRange: Range<String.Index>? = nil) {
        self.id = UUID()
        self.translationAbbreviation = translationAbbreviation
        self.book = book
        self.chapter = chapter
        self.verse = verse
        self.text = text
        self.matchRange = matchRange
    }

    // Hashable — exclude matchRange (Range<String.Index> isn't Hashable)
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
        lhs.id == rhs.id
    }
}

/// Search scope options matching the Windows version.
enum SearchScope: String, Codable, Hashable, CaseIterable {
    case bible   = "Entire Bible"
    case ot      = "Old Testament"
    case nt      = "New Testament"
    case book    = "Current Book"
    case chapter = "Current Chapter"
}

// MARK: - Reading History

/// A single entry in the user's reading history, recorded when navigating chapters.
struct ReadingHistoryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let book: String
    let chapter: Int
    let verse: Int?             // 1-indexed, nil = chapter-level navigation
    let translationAbbreviation: String
    let timestamp: Date

    init(id: UUID = UUID(), book: String, chapter: Int, verse: Int? = nil, translationAbbreviation: String, timestamp: Date = Date()) {
        self.id = id
        self.book = book
        self.chapter = chapter
        self.verse = verse
        self.translationAbbreviation = translationAbbreviation
        self.timestamp = timestamp
    }

    var displayRef: String {
        if let v = verse {
            return "\(book) \(chapter):\(v)"
        }
        return "\(book) \(chapter)"
    }
}

// MARK: - Verse Key (lightweight reference)

/// Lightweight value identifying a specific verse without carrying its text.
struct VerseKey: Hashable, Codable {
    let book: String
    let chapter: Int
    let verse: Int  // 1-indexed

    var id: String { "\(book):\(chapter):\(verse)" }
}
