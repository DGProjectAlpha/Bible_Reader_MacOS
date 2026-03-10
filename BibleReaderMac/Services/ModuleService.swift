import Foundation
import SQLite3

// MARK: - Errors

enum ModuleServiceError: LocalizedError {
    case cannotOpenDatabase(String)
    case metadataNotFound
    case queryFailed(String)
    case tableNotFound(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpenDatabase(let path): return "Cannot open module at \(path)"
        case .metadataNotFound: return "Module metadata not found in file"
        case .queryFailed(let msg): return "Database query failed: \(msg)"
        case .tableNotFound(let name): return "Table '\(name)' not found in module"
        }
    }
}

// MARK: - SQLite Helpers (SQLITE_TRANSIENT for safe string binding)

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - ModuleConnection (cached, per-file database handle)

/// Wraps a single read-only SQLite connection to a .brbmod file.
/// Reuse via `ModuleConnectionPool` instead of opening/closing per query.
final class ModuleConnection {
    let filePath: String
    private let db: OpaquePointer

    init(filePath: String) throws {
        self.filePath = filePath
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(filePath, &handle, flags, nil) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw ModuleServiceError.cannotOpenDatabase(filePath)
        }
        self.db = handle
        // Enable WAL mode read performance + 5s busy timeout
        sqlite3_busy_timeout(db, 5000)
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Low-level query helpers

    func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw ModuleServiceError.queryFailed(errorMessage)
        }
        return stmt
    }

    var errorMessage: String {
        String(cString: sqlite3_errmsg(db))
    }

    /// Execute a query, bind parameters, and iterate rows with a closure.
    func query<T>(_ sql: String, bindings: [Any] = [], mapper: (OpaquePointer) -> T) throws -> [T] {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        for (i, value) in bindings.enumerated() {
            let idx = Int32(i + 1)
            switch value {
            case let s as String:
                sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
            case let n as Int:
                sqlite3_bind_int64(stmt, idx, Int64(n))
            case let n as Int32:
                sqlite3_bind_int(stmt, idx, n)
            case let d as Double:
                sqlite3_bind_double(stmt, idx, d)
            default:
                sqlite3_bind_null(stmt, idx)
            }
        }

        var results: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(mapper(stmt))
        }
        return results
    }

    /// Convenience: read a single text column from `stmt` at `col`, returning "" on NULL.
    static func text(_ stmt: OpaquePointer, _ col: Int32) -> String {
        sqlite3_column_text(stmt, col).map { String(cString: $0) } ?? ""
    }

    static func int(_ stmt: OpaquePointer, _ col: Int32) -> Int {
        Int(sqlite3_column_int(stmt, col))
    }

    /// Check if a table exists in this database.
    func tableExists(_ name: String) throws -> Bool {
        let rows = try query(
            "SELECT count(*) FROM sqlite_master WHERE type='table' AND name=?1",
            bindings: [name]
        ) { stmt in
            Self.int(stmt, 0)
        }
        return (rows.first ?? 0) > 0
    }

    // MARK: - Module Metadata

    func readMetadata() throws -> ModuleMetadata {
        guard try tableExists("metadata") else {
            throw ModuleServiceError.tableNotFound("metadata")
        }

        let pairs = try query("SELECT key, value FROM metadata") { stmt in
            (Self.text(stmt, 0), Self.text(stmt, 1))
        }

        var dict: [String: String] = [:]
        for (k, v) in pairs { dict[k] = v }

        guard let name = dict["name"] else {
            throw ModuleServiceError.metadataNotFound
        }

        let formatStr = dict["format"] ?? "plain"
        let moduleFormat: ModuleFormat = (formatStr == "tagged") ? .tagged : .plain

        var bookNames: [String: String]?
        if let raw = dict["book_names"], let data = raw.data(using: .utf8) {
            bookNames = try? JSONDecoder().decode([String: String].self, from: data)
        }

        return ModuleMetadata(
            name: name,
            abbreviation: dict["abbreviation"] ?? String(name.prefix(3).uppercased()),
            language: dict["language"] ?? "Unknown",
            format: moduleFormat,
            version: Int(dict["version"] ?? "1") ?? 1,
            versificationScheme: dict["versification_scheme"] ?? "kjv",
            copyright: dict["copyright"],
            notes: dict["notes"],
            bookNames: bookNames
        )
    }

    // MARK: - Books & Chapters

    /// Returns the distinct book names in verse order, with chapter counts.
    func listBooks() throws -> [(book: String, chapterCount: Int)] {
        try query(
            "SELECT book, MAX(chapter) FROM verses GROUP BY book ORDER BY MIN(rowid)",
            bindings: []
        ) { stmt in
            (book: Self.text(stmt, 0), chapterCount: Self.int(stmt, 1))
        }
    }

    /// Returns the number of verses in a given chapter.
    func verseCount(book: String, chapter: Int) throws -> Int {
        let rows = try query(
            "SELECT COUNT(*) FROM verses WHERE book = ?1 AND chapter = ?2",
            bindings: [book, chapter]
        ) { stmt in Self.int(stmt, 0) }
        return rows.first ?? 0
    }

    // MARK: - Verses

    func loadVerses(book: String, chapter: Int) throws -> [Verse] {
        try query(
            "SELECT verse, text FROM verses WHERE book = ?1 AND chapter = ?2 ORDER BY verse",
            bindings: [book, chapter]
        ) { stmt in
            Verse(
                book: book,
                chapter: chapter,
                number: Self.int(stmt, 0),
                text: Self.text(stmt, 1)
            )
        }
    }

    /// Batch-load all verses for multiple chapters (used for scrolling preload).
    func loadVerseRange(book: String, chapters: ClosedRange<Int>) throws -> [Verse] {
        try query(
            "SELECT chapter, verse, text FROM verses WHERE book = ?1 AND chapter BETWEEN ?2 AND ?3 ORDER BY chapter, verse",
            bindings: [book, chapters.lowerBound, chapters.upperBound]
        ) { stmt in
            Verse(
                book: book,
                chapter: Self.int(stmt, 0),
                number: Self.int(stmt, 1),
                text: Self.text(stmt, 2)
            )
        }
    }

    // MARK: - Word Tags (Strong's)

    func loadWordTags(verseId: String) throws -> [WordTag] {
        guard try tableExists("word_tags") else { return [] }

        return try query(
            "SELECT word_index, word, strongs_number FROM word_tags WHERE verse_id = ?1 AND strongs_number IS NOT NULL ORDER BY word_index",
            bindings: [verseId]
        ) { stmt in
            WordTag(
                wordIndex: Self.int(stmt, 0),
                word: Self.text(stmt, 1),
                strongsNumbers: [Self.text(stmt, 2)]
            )
        }
    }

    /// Batch word tags for all verses in a chapter.
    func loadWordTagsForChapter(book: String, chapter: Int) throws -> [String: [WordTag]] {
        guard try tableExists("word_tags") else { return [:] }

        let rows = try query(
            "SELECT verse_id, word_index, word, strongs_number FROM word_tags WHERE verse_id LIKE ?1 AND strongs_number IS NOT NULL ORDER BY verse_id, word_index",
            bindings: ["\(book):\(chapter):%"]
        ) { stmt in
            (
                verseId: Self.text(stmt, 0),
                tag: WordTag(
                    wordIndex: Self.int(stmt, 1),
                    word: Self.text(stmt, 2),
                    strongsNumbers: [Self.text(stmt, 3)]
                )
            )
        }

        var grouped: [String: [WordTag]] = [:]
        for row in rows {
            grouped[row.verseId, default: []].append(row.tag)
        }
        return grouped
    }

    // MARK: - Cross-References

    func loadCrossReferences(verseId: String) throws -> [CrossReference] {
        guard try tableExists("cross_references") else { return [] }

        return try query(
            "SELECT from_verse_id, to_verse_id, ref_type FROM cross_references WHERE from_verse_id = ?1",
            bindings: [verseId]
        ) { stmt in
            CrossReference(
                fromVerseId: Self.text(stmt, 0),
                toVerseId: Self.text(stmt, 1),
                referenceType: CrossReferenceType(rawValue: Self.text(stmt, 2)) ?? .related
            )
        }
    }

    // MARK: - Search

    func search(query searchText: String, scope: SearchScope = .bible, currentBook: String? = nil, currentChapter: Int? = nil) throws -> [SearchResult] {
        var sql = "SELECT book, chapter, verse, text FROM verses WHERE text LIKE ?1"
        var bindings: [Any] = ["%\(searchText)%"]

        switch scope {
        case .bible:
            break
        case .ot:
            let otBooks = BibleBooks.oldTestament.map { "'\($0)'" }.joined(separator: ",")
            sql += " AND book IN (\(otBooks))"
        case .nt:
            let ntBooks = BibleBooks.newTestament.map { "'\($0)'" }.joined(separator: ",")
            sql += " AND book IN (\(ntBooks))"
        case .book:
            if let book = currentBook {
                sql += " AND book = ?2"
                bindings.append(book)
            }
        case .chapter:
            if let book = currentBook, let chapter = currentChapter {
                sql += " AND book = ?2 AND chapter = ?3"
                bindings.append(book)
                bindings.append(chapter)
            }
        }

        sql += " ORDER BY rowid LIMIT 500"

        let lowerQuery = searchText.lowercased()
        return try self.query(sql, bindings: bindings) { stmt in
            let text = Self.text(stmt, 3)
            let matchRange = text.lowercased().range(of: lowerQuery)
            return SearchResult(
                book: Self.text(stmt, 0),
                chapter: Self.int(stmt, 1),
                verse: Self.int(stmt, 2),
                text: text,
                matchRange: matchRange
            )
        }
    }
}

// MARK: - ModuleConnectionPool (thread-safe connection cache)

/// Caches open read-only connections to .brbmod files.
/// Connections are opened once and reused until explicitly closed.
final class ModuleConnectionPool {
    static let shared = ModuleConnectionPool()

    private var connections: [String: ModuleConnection] = [:]
    private let lock = NSLock()

    private init() {}

    /// Get or create a read-only connection for the given module file.
    func connection(for filePath: String) throws -> ModuleConnection {
        lock.lock()
        defer { lock.unlock() }

        if let existing = connections[filePath] {
            return existing
        }

        let conn = try ModuleConnection(filePath: filePath)
        connections[filePath] = conn
        return conn
    }

    /// Close and remove a cached connection.
    func close(filePath: String) {
        lock.lock()
        defer { lock.unlock() }
        connections.removeValue(forKey: filePath)
    }

    /// Close all cached connections.
    func closeAll() {
        lock.lock()
        defer { lock.unlock() }
        connections.removeAll()
    }
}

// MARK: - ModuleService (static convenience API)

/// High-level static API matching the original interface.
/// All calls go through the connection pool for performance.
enum ModuleService {

    static func readMetadata(from url: URL) throws -> ModuleMetadata {
        let conn = try ModuleConnectionPool.shared.connection(for: url.path)
        return try conn.readMetadata()
    }

    static func loadVerses(from filePath: String, book: String, chapter: Int) throws -> [Verse] {
        let conn = try ModuleConnectionPool.shared.connection(for: filePath)
        return try conn.loadVerses(book: book, chapter: chapter)
    }

    static func loadWordTags(from filePath: String, verseId: String) throws -> [WordTag] {
        let conn = try ModuleConnectionPool.shared.connection(for: filePath)
        return try conn.loadWordTags(verseId: verseId)
    }

    static func loadCrossReferences(from filePath: String, verseId: String) throws -> [CrossReference] {
        let conn = try ModuleConnectionPool.shared.connection(for: filePath)
        return try conn.loadCrossReferences(verseId: verseId)
    }

    static func search(in filePath: String, query: String, scope: SearchScope = .bible, currentBook: String? = nil, currentChapter: Int? = nil) throws -> [SearchResult] {
        let conn = try ModuleConnectionPool.shared.connection(for: filePath)
        return try conn.search(query: query, scope: scope, currentBook: currentBook, currentChapter: currentChapter)
    }

    static func listBooks(from filePath: String) throws -> [(book: String, chapterCount: Int)] {
        let conn = try ModuleConnectionPool.shared.connection(for: filePath)
        return try conn.listBooks()
    }

    static func verseCount(from filePath: String, book: String, chapter: Int) throws -> Int {
        let conn = try ModuleConnectionPool.shared.connection(for: filePath)
        return try conn.verseCount(book: book, chapter: chapter)
    }

    static func loadVerseRange(from filePath: String, book: String, chapters: ClosedRange<Int>) throws -> [Verse] {
        let conn = try ModuleConnectionPool.shared.connection(for: filePath)
        return try conn.loadVerseRange(book: book, chapters: chapters)
    }

    static func loadWordTagsForChapter(from filePath: String, book: String, chapter: Int) throws -> [String: [WordTag]] {
        let conn = try ModuleConnectionPool.shared.connection(for: filePath)
        return try conn.loadWordTagsForChapter(book: book, chapter: chapter)
    }
}
