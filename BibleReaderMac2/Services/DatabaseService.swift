import Foundation
import SQLite3

// MARK: - Errors

enum DatabaseServiceError: LocalizedError {
    case cannotOpenDatabase(String)
    case queryFailed(String)
    case moduleNotOpen(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpenDatabase(let path): return "Cannot open module at \(path)"
        case .queryFailed(let msg): return "Database query failed: \(msg)"
        case .moduleNotOpen(let id): return "Module '\(id)' is not open"
        }
    }
}

// MARK: - SQLITE_TRANSIENT

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - WordTag

struct WordTag: Identifiable, Hashable {
    var id: Int { wordIndex }
    let wordIndex: Int
    let word: String
    let strongsNumber: String?
}

// MARK: - StrongsEntry

struct StrongsEntry: Identifiable, Hashable {
    var id: String { number }
    let number: String          // "H7225", "G3056"
    let lemma: String
    let transliteration: String
    let pronunciation: String?
    let derivation: String?
    let strongsDefinition: String?
    let kjvDefinition: String?
}

// MARK: - CrossReference

struct CrossReference: Identifiable, Hashable {
    let id = UUID()
    let fromVerseId: String
    let toVerseId: String
    let referenceType: String   // "parallel", "quotation", "allusion", "related"

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: CrossReference, rhs: CrossReference) -> Bool { lhs.id == rhs.id }
}

// MARK: - DatabaseService

actor DatabaseService {
    static let shared = DatabaseService()

    private var connections: [String: OpaquePointer] = [:]  // moduleId → db handle

    private init() {}

    // MARK: - Connection Management

    func openModule(id: String, path: URL) throws {
        if connections[id] != nil { return } // already open

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw DatabaseServiceError.cannotOpenDatabase(path.path)
        }
        sqlite3_busy_timeout(handle, 5000)
        connections[id] = handle
    }

    func closeModule(id: String) {
        guard let db = connections.removeValue(forKey: id) else { return }
        sqlite3_close(db)
    }

    func closeAll() {
        for (_, db) in connections {
            sqlite3_close(db)
        }
        connections.removeAll()
    }

    // MARK: - Queries

    func fetchVerses(moduleId: String, book: String, chapter: Int) throws -> [Verse] {
        let db = try db(for: moduleId)
        return try query(
            db: db,
            sql: "SELECT verse, text FROM verses WHERE book = ?1 AND chapter = ?2 ORDER BY verse",
            bindings: [.text(book), .int(chapter)]
        ) { stmt in
            let verseNum = Int(sqlite3_column_int(stmt, 0))
            let text = columnText(stmt, 1)
            return Verse(
                id: "\(book).\(chapter).\(verseNum)",
                book: book,
                chapter: chapter,
                verseNumber: verseNum,
                text: text,
                strongsNumbers: []
            )
        }
    }

    func fetchBooks(moduleId: String) throws -> [Book] {
        let db = try db(for: moduleId)
        let rows = try query(
            db: db,
            sql: "SELECT book, MAX(chapter) FROM verses GROUP BY book ORDER BY MIN(rowid)",
            bindings: []
        ) { stmt in
            (book: columnText(stmt, 0), chapterCount: Int(sqlite3_column_int(stmt, 1)))
        }

        // Read book_names from metadata if available
        let bookNames = (try? fetchMetadata(moduleId: moduleId))
            .flatMap { meta -> [String: String]? in
                guard let raw = meta["book_names"],
                      let data = raw.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode([String: String].self, from: data)
            } ?? [:]

        return rows.map { row in
            let displayName = bookNames[row.book] ?? row.book
            let testament: Testament = oldTestamentBooks.contains(row.book) ? .old : .new
            return Book(
                id: row.book,
                name: displayName,
                shortName: row.book,
                testament: testament,
                chapterCount: row.chapterCount
            )
        }
    }

    func searchVerses(moduleId: String, query searchText: String) throws -> [Verse] {
        let db = try db(for: moduleId)
        return try self.query(
            db: db,
            sql: "SELECT book, chapter, verse, text FROM verses WHERE text LIKE ?1 ORDER BY rowid LIMIT 500",
            bindings: [.text("%\(searchText)%")]
        ) { stmt in
            let book = columnText(stmt, 0)
            let chapter = Int(sqlite3_column_int(stmt, 1))
            let verseNum = Int(sqlite3_column_int(stmt, 2))
            let text = columnText(stmt, 3)
            return Verse(
                id: "\(book).\(chapter).\(verseNum)",
                book: book,
                chapter: chapter,
                verseNumber: verseNum,
                text: text,
                strongsNumbers: []
            )
        }
    }

    // MARK: - Word Tags (on-demand Strong's data)

    func fetchWordTags(moduleId: String, book: String, chapter: Int, verse: Int) throws -> [WordTag] {
        let db = try db(for: moduleId)

        // Check if word_tags table exists
        guard try tableExists(db: db, name: "word_tags") else { return [] }

        let verseId = "\(book):\(chapter):\(verse)"
        return try query(
            db: db,
            sql: "SELECT word_index, word, strongs_number FROM word_tags WHERE verse_id = ?1 ORDER BY word_index",
            bindings: [.text(verseId)]
        ) { stmt in
            let wordIndex = Int(sqlite3_column_int(stmt, 0))
            let word = columnText(stmt, 1)
            let strongsRaw = columnText(stmt, 2)
            return WordTag(
                wordIndex: wordIndex,
                word: word,
                strongsNumber: strongsRaw.isEmpty ? nil : strongsRaw
            )
        }
    }

    // MARK: - Strong's Definitions

    func fetchStrongsEntry(moduleId: String, number: String) throws -> StrongsEntry? {
        let db = try db(for: moduleId)

        guard try tableExists(db: db, name: "strongs") else { return nil }

        let rows = try query(
            db: db,
            sql: "SELECT number, lemma, transliteration, pronunciation, derivation, strongs_def, kjv_def FROM strongs WHERE number = ?1 LIMIT 1",
            bindings: [.text(number)]
        ) { stmt in
            StrongsEntry(
                number: columnText(stmt, 0),
                lemma: columnText(stmt, 1),
                transliteration: columnText(stmt, 2),
                pronunciation: columnText(stmt, 3).isEmpty ? nil : columnText(stmt, 3),
                derivation: columnText(stmt, 4).isEmpty ? nil : columnText(stmt, 4),
                strongsDefinition: columnText(stmt, 5).isEmpty ? nil : columnText(stmt, 5),
                kjvDefinition: columnText(stmt, 6).isEmpty ? nil : columnText(stmt, 6)
            )
        }

        return rows.first
    }

    func fetchStrongsEntries(moduleId: String, numbers: [String]) throws -> [String: StrongsEntry] {
        let db = try db(for: moduleId)

        guard try tableExists(db: db, name: "strongs"), !numbers.isEmpty else { return [:] }

        // Build parameterized IN clause
        let placeholders = numbers.enumerated().map { "?\($0.offset + 1)" }.joined(separator: ",")
        let sql = "SELECT number, lemma, transliteration, pronunciation, derivation, strongs_def, kjv_def FROM strongs WHERE number IN (\(placeholders))"

        let rows = try query(
            db: db,
            sql: sql,
            bindings: numbers.map { .text($0) }
        ) { stmt in
            StrongsEntry(
                number: columnText(stmt, 0),
                lemma: columnText(stmt, 1),
                transliteration: columnText(stmt, 2),
                pronunciation: columnText(stmt, 3).isEmpty ? nil : columnText(stmt, 3),
                derivation: columnText(stmt, 4).isEmpty ? nil : columnText(stmt, 4),
                strongsDefinition: columnText(stmt, 5).isEmpty ? nil : columnText(stmt, 5),
                kjvDefinition: columnText(stmt, 6).isEmpty ? nil : columnText(stmt, 6)
            )
        }

        var result: [String: StrongsEntry] = [:]
        for entry in rows { result[entry.number] = entry }
        return result
    }

    // MARK: - Cross-References

    func fetchCrossReferences(moduleId: String, verseId: String) throws -> [CrossReference] {
        let db = try db(for: moduleId)

        guard try tableExists(db: db, name: "cross_references") else { return [] }

        return try query(
            db: db,
            sql: "SELECT from_verse_id, to_verse_id, ref_type FROM cross_references WHERE from_verse_id = ?1",
            bindings: [.text(verseId)]
        ) { stmt in
            CrossReference(
                fromVerseId: columnText(stmt, 0),
                toVerseId: columnText(stmt, 1),
                referenceType: columnText(stmt, 2)
            )
        }
    }

    func fetchReverseCrossReferences(moduleId: String, verseId: String) throws -> [CrossReference] {
        let db = try db(for: moduleId)

        guard try tableExists(db: db, name: "cross_references") else { return [] }

        return try query(
            db: db,
            sql: "SELECT from_verse_id, to_verse_id, ref_type FROM cross_references WHERE to_verse_id = ?1",
            bindings: [.text(verseId)]
        ) { stmt in
            CrossReference(
                fromVerseId: columnText(stmt, 0),
                toVerseId: columnText(stmt, 1),
                referenceType: columnText(stmt, 2)
            )
        }
    }

    func findVersesByStrongs(moduleId: String, number: String, limit: Int = 300) throws -> [(book: String, chapter: Int, verse: Int, text: String)] {
        let db = try db(for: moduleId)
        guard try tableExists(db: db, name: "word_tags") else { return [] }

        // Get distinct verse_ids containing this Strong's number
        let verseIds = try query(
            db: db,
            sql: "SELECT DISTINCT verse_id FROM word_tags WHERE strongs_number = ?1 ORDER BY rowid LIMIT ?2",
            bindings: [.text(number), .int(limit)]
        ) { stmt in columnText(stmt, 0) }

        guard !verseIds.isEmpty else { return [] }

        // Parse verse_ids and batch-fetch text
        struct Ref { let verseId: String; let book: String; let chapter: Int; let verse: Int }
        var refs: [Ref] = []
        for vid in verseIds {
            let parts = vid.split(separator: ":")
            guard parts.count >= 3,
                  let ch = Int(parts[parts.count - 2]),
                  let vs = Int(parts[parts.count - 1]) else { continue }
            let bk = parts.dropLast(2).joined(separator: ":")
            refs.append(Ref(verseId: vid, book: bk, chapter: ch, verse: vs))
        }

        // Fetch verse texts
        var textByVid: [String: String] = [:]
        for ref in refs {
            let rows = try query(
                db: db,
                sql: "SELECT text FROM verses WHERE book = ?1 AND chapter = ?2 AND verse = ?3 LIMIT 1",
                bindings: [.text(ref.book), .int(ref.chapter), .int(ref.verse)]
            ) { stmt in columnText(stmt, 0) }
            textByVid[ref.verseId] = rows.first ?? ""
        }

        return refs.map { ref in
            (book: ref.book, chapter: ref.chapter, verse: ref.verse, text: textByVid[ref.verseId] ?? "")
        }
    }

    func fetchVerseText(moduleId: String, book: String, chapter: Int, verse: Int) throws -> String? {
        let db = try db(for: moduleId)
        let rows = try query(
            db: db,
            sql: "SELECT text FROM verses WHERE book = ?1 AND chapter = ?2 AND verse = ?3 LIMIT 1",
            bindings: [.text(book), .int(chapter), .int(verse)]
        ) { stmt in
            columnText(stmt, 0)
        }
        return rows.first
    }

    func fetchMetadata(moduleId: String) throws -> [String: String] {
        let db = try db(for: moduleId)

        // Check if metadata table exists
        guard try tableExists(db: db, name: "metadata") else { return [:] }

        let pairs = try query(
            db: db,
            sql: "SELECT key, value FROM metadata",
            bindings: []
        ) { stmt in
            (columnText(stmt, 0), columnText(stmt, 1))
        }

        var dict: [String: String] = [:]
        for (k, v) in pairs { dict[k] = v }
        return dict
    }

    // MARK: - Table Existence Check

    func hasTable(moduleId: String, name: String) throws -> Bool {
        let db = try db(for: moduleId)
        return try tableExists(db: db, name: name)
    }

    // MARK: - Private Helpers

    private func db(for moduleId: String) throws -> OpaquePointer {
        guard let db = connections[moduleId] else {
            throw DatabaseServiceError.moduleNotOpen(moduleId)
        }
        return db
    }

    private enum Binding {
        case text(String)
        case int(Int)
    }

    private func tableExists(db: OpaquePointer, name: String) throws -> Bool {
        let rows = try query(
            db: db,
            sql: "SELECT count(*) FROM sqlite_master WHERE type='table' AND name=?1",
            bindings: [.text(name)]
        ) { stmt in Int(sqlite3_column_int(stmt, 0)) }
        return (rows.first ?? 0) > 0
    }

    private func query<T>(
        db: OpaquePointer,
        sql: String,
        bindings: [Binding],
        mapper: (OpaquePointer) -> T
    ) throws -> [T] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseServiceError.queryFailed(msg)
        }
        defer { sqlite3_finalize(stmt) }

        for (i, binding) in bindings.enumerated() {
            let idx = Int32(i + 1)
            switch binding {
            case .text(let s):
                sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
            case .int(let n):
                sqlite3_bind_int(stmt, idx, Int32(n))
            }
        }

        var results: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(mapper(stmt))
        }
        return results
    }
}

// MARK: - Column Helpers

private func columnText(_ stmt: OpaquePointer, _ col: Int32) -> String {
    sqlite3_column_text(stmt, col).map { String(cString: $0) } ?? ""
}

// MARK: - Old Testament Book Codes

private let oldTestamentBooks: Set<String> = [
    "GEN", "EXO", "LEV", "NUM", "DEU", "JOS", "JDG", "RUT",
    "1SA", "2SA", "1KI", "2KI", "1CH", "2CH", "EZR", "NEH",
    "EST", "JOB", "PSA", "PRO", "ECC", "SNG", "ISA", "JER",
    "LAM", "EZK", "DAN", "HOS", "JOL", "AMO", "OBA", "JON",
    "MIC", "NAH", "HAB", "ZEP", "HAG", "ZEC", "MAL"
]
