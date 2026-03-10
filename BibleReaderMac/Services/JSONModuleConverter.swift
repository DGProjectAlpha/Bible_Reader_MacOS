import Foundation
import SQLite3

// MARK: - JSON Module Converter

/// Converts JSON-format .brbmod files (used by the Windows version) to SQLite format
/// that the macOS app expects. The conversion happens transparently during import.
enum JSONModuleConverter {

    // MARK: - Detection

    /// Check if a file is a JSON-format .brbmod (as opposed to SQLite).
    static func isJSONModule(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { handle.closeFile() }
        guard let header = try? handle.read(upToCount: 16) else { return false }
        // SQLite files start with "SQLite format 3\0"
        // JSON files start with "{" (possibly with leading whitespace/BOM)
        let trimmed = header.drop(while: { $0 == 0xEF || $0 == 0xBB || $0 == 0xBF || $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 })
        return trimmed.first == UInt8(ascii: "{")
    }

    // MARK: - Conversion

    /// Convert a JSON .brbmod file to SQLite format.
    /// Returns the URL of the converted SQLite file (in a temp directory).
    /// Caller is responsible for cleaning up or moving the file.
    static func convertToSQLite(jsonURL: URL) throws -> URL {
        let data = try Data(contentsOf: jsonURL)
        let module = try JSONDecoder().decode(JSONBrbMod.self, from: data)

        // Create temp file for the SQLite database
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent(jsonURL.lastPathComponent)

        // Remove any existing temp file
        try? FileManager.default.removeItem(at: outputURL)

        // Create SQLite database
        var db: OpaquePointer?
        guard sqlite3_open(outputURL.path, &db) == SQLITE_OK, let db else {
            throw ConversionError.cannotCreateDatabase
        }
        defer { sqlite3_close(db) }

        try createTables(db: db, hasWordTags: module.meta.format == "tagged")
        try insertMetadata(db: db, meta: module.meta)
        try insertVerses(db: db, books: module.data, format: module.meta.format)

        return outputURL
    }

    // MARK: - Private

    private static let SQLITE_TRANSIENT_PTR = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func exec(_ db: OpaquePointer, _ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK else {
            let msg = err.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(err)
            throw ConversionError.sqlError(msg)
        }
    }

    private static func createTables(db: OpaquePointer, hasWordTags: Bool) throws {
        try exec(db, """
            CREATE TABLE metadata (
                key TEXT PRIMARY KEY,
                value TEXT
            );
            CREATE TABLE verses (
                book TEXT NOT NULL,
                chapter INTEGER NOT NULL,
                verse INTEGER NOT NULL,
                text TEXT NOT NULL,
                PRIMARY KEY (book, chapter, verse)
            );
        """)

        if hasWordTags {
            try exec(db, """
                CREATE TABLE word_tags (
                    verse_id TEXT NOT NULL,
                    word_index INTEGER NOT NULL,
                    word TEXT NOT NULL,
                    strongs_number TEXT,
                    PRIMARY KEY (verse_id, word_index, IFNULL(strongs_number, ''))
                );
                CREATE INDEX idx_word_tags_verse ON word_tags(verse_id);
            """)
        }
    }

    private static func insertMetadata(db: OpaquePointer, meta: JSONBrbModMeta) throws {
        let pairs: [(String, String)] = [
            ("name", meta.name),
            ("abbreviation", meta.abbreviation),
            ("language", meta.language),
            ("format", meta.format),
            ("version", "\(meta.version)"),
            ("copyright", meta.copyright ?? ""),
            ("notes", meta.notes ?? ""),
        ]

        // Build book_names mapping from Russian to canonical English
        let bookNameMap = buildBookNameMap(books: nil)
        if !bookNameMap.isEmpty {
            let bookNamesJSON = (try? JSONEncoder().encode(bookNameMap))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            try insertKV(db: db, key: "book_names", value: bookNamesJSON)
        }

        for (key, value) in pairs {
            try insertKV(db: db, key: key, value: value)
        }
    }

    private static func insertKV(db: OpaquePointer, key: String, value: String) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO metadata (key, value) VALUES (?1, ?2)", -1, &stmt, nil) == SQLITE_OK,
              let stmt else {
            throw ConversionError.sqlError("Failed to prepare metadata insert")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT_PTR)
        sqlite3_bind_text(stmt, 2, value, -1, SQLITE_TRANSIENT_PTR)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw ConversionError.sqlError("Failed to insert metadata key: \(key)")
        }
    }

    private static func insertVerses(db: OpaquePointer, books: [JSONBrbModBook], format: String) throws {
        try exec(db, "BEGIN TRANSACTION")

        // Prepare verse insert
        var verseStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO verses (book, chapter, verse, text) VALUES (?1, ?2, ?3, ?4)", -1, &verseStmt, nil) == SQLITE_OK,
              let verseStmt else {
            throw ConversionError.sqlError("Failed to prepare verse insert")
        }
        defer { sqlite3_finalize(verseStmt) }

        // Prepare word_tags insert (only for tagged format)
        var tagStmt: OpaquePointer?
        if format == "tagged" {
            guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO word_tags (verse_id, word_index, word, strongs_number) VALUES (?1, ?2, ?3, ?4)", -1, &tagStmt, nil) == SQLITE_OK,
                  let tagStmt else {
                throw ConversionError.sqlError("Failed to prepare word_tags insert")
            }
            // tagStmt cleanup handled below
            _ = tagStmt
        }
        defer { if let s = tagStmt { sqlite3_finalize(s) } }

        // Map from Russian book names to canonical English
        let nameMap = russianToEnglishMap()

        // Also build a reverse map for book_names metadata
        var bookNamesMap: [String: String] = [:]

        for (bookIndex, book) in books.enumerated() {
            let canonicalName = nameMap[book.name] ?? BibleBooks.all[safe: bookIndex] ?? book.name
            if canonicalName != book.name {
                bookNamesMap[canonicalName] = book.name
            }

            for (chapterIndex, chapter) in book.chapters.enumerated() {
                let chapterNum = chapterIndex + 1
                for (verseIndex, verse) in chapter.enumerated() {
                    let verseNum = verseIndex + 1

                    // Build plain text from tokens
                    let text: String
                    if format == "tagged" {
                        text = verse.map { $0.word }.joined(separator: " ")
                    } else {
                        // For plain format, verse is an array with a single token whose word is the full text
                        text = verse.first?.word ?? ""
                    }

                    sqlite3_reset(verseStmt)
                    sqlite3_bind_text(verseStmt, 1, canonicalName, -1, SQLITE_TRANSIENT_PTR)
                    sqlite3_bind_int(verseStmt, 2, Int32(chapterNum))
                    sqlite3_bind_int(verseStmt, 3, Int32(verseNum))
                    sqlite3_bind_text(verseStmt, 4, text, -1, SQLITE_TRANSIENT_PTR)

                    guard sqlite3_step(verseStmt) == SQLITE_DONE else {
                        throw ConversionError.sqlError("Failed to insert verse \(canonicalName) \(chapterNum):\(verseNum)")
                    }

                    // Insert word tags for tagged format
                    if format == "tagged", let tagStmt {
                        let verseId = "\(canonicalName):\(chapterNum):\(verseNum)"

                        for (wordIndex, token) in verse.enumerated() {
                            if token.strongs.isEmpty {
                                // Insert word with NULL strongs
                                sqlite3_reset(tagStmt)
                                sqlite3_bind_text(tagStmt, 1, verseId, -1, SQLITE_TRANSIENT_PTR)
                                sqlite3_bind_int(tagStmt, 2, Int32(wordIndex))
                                sqlite3_bind_text(tagStmt, 3, token.word, -1, SQLITE_TRANSIENT_PTR)
                                sqlite3_bind_null(tagStmt, 4)
                                _ = sqlite3_step(tagStmt)
                            } else {
                                for strongsNum in token.strongs {
                                    sqlite3_reset(tagStmt)
                                    sqlite3_bind_text(tagStmt, 1, verseId, -1, SQLITE_TRANSIENT_PTR)
                                    sqlite3_bind_int(tagStmt, 2, Int32(wordIndex))
                                    sqlite3_bind_text(tagStmt, 3, token.word, -1, SQLITE_TRANSIENT_PTR)
                                    sqlite3_bind_text(tagStmt, 4, strongsNum, -1, SQLITE_TRANSIENT_PTR)
                                    _ = sqlite3_step(tagStmt)
                                }
                            }
                        }
                    }
                }
            }
        }

        // Update book_names in metadata
        if !bookNamesMap.isEmpty {
            if let jsonData = try? JSONEncoder().encode(bookNamesMap),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                // Update the book_names key
                var updateStmt: OpaquePointer?
                if sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO metadata (key, value) VALUES ('book_names', ?1)", -1, &updateStmt, nil) == SQLITE_OK,
                   let updateStmt {
                    sqlite3_bind_text(updateStmt, 1, jsonStr, -1, SQLITE_TRANSIENT_PTR)
                    _ = sqlite3_step(updateStmt)
                    sqlite3_finalize(updateStmt)
                }
            }
        }

        try exec(db, "COMMIT")
    }

    // MARK: - Russian Book Name Mapping

    private static func buildBookNameMap(books: [JSONBrbModBook]?) -> [String: String] {
        // Canonical English -> Russian display name
        var map: [String: String] = [:]
        let russianNames = [
            "Бытие", "Исход", "Левит", "Числа", "Второзаконие",
            "Иисус Навин", "Судьи", "Руфь", "1-я Царств", "2-я Царств",
            "3-я Царств", "4-я Царств", "1-я Паралипоменон", "2-я Паралипоменон",
            "Ездра", "Неемия", "Есфирь", "Иов", "Псалтирь",
            "Притчи", "Екклесиаст", "Песня Песней", "Исаия", "Иеремия",
            "Плач Иеремии", "Иезекииль", "Даниил", "Осия", "Иоиль",
            "Амос", "Авдий", "Иона", "Михей", "Наум",
            "Аввакум", "Софония", "Аггей", "Захария", "Малахия",
            "От Матфея", "От Марка", "От Луки", "От Иоанна", "Деяния",
            "К Римлянам", "1-е Коринфянам", "2-е Коринфянам", "К Галатам", "К Ефесянам",
            "К Филиппийцам", "К Колоссянам", "1-е Фессалоникийцам", "2-е Фессалоникийцам",
            "1-е Тимофею", "2-е Тимофею", "К Титу", "К Филимону", "К Евреям",
            "Иакова", "1-е Петра", "2-е Петра", "1-е Иоанна", "2-е Иоанна",
            "3-е Иоанна", "Иуды", "Откровение"
        ]

        for (i, eng) in BibleBooks.all.enumerated() {
            if i < russianNames.count {
                map[eng] = russianNames[i]
            }
        }
        return map
    }

    /// Map from Russian Synodal book names to canonical English names.
    static func russianToEnglishMap() -> [String: String] {
        var map: [String: String] = [:]
        let russianNames = [
            "Бытие", "Исход", "Левит", "Числа", "Второзаконие",
            "Иисус Навин", "Судьи", "Руфь", "1-я Царств", "2-я Царств",
            "3-я Царств", "4-я Царств", "1-я Паралипоменон", "2-я Паралипоменон",
            "Ездра", "Неемия", "Есфирь", "Иов", "Псалтирь",
            "Притчи", "Екклесиаст", "Песня Песней", "Исаия", "Иеремия",
            "Плач Иеремии", "Иезекииль", "Даниил", "Осия", "Иоиль",
            "Амос", "Авдий", "Иона", "Михей", "Наум",
            "Аввакум", "Софония", "Аггей", "Захария", "Малахия",
            "От Матфея", "От Марка", "От Луки", "От Иоанна", "Деяния",
            "К Римлянам", "1-е Коринфянам", "2-е Коринфянам", "К Галатам", "К Ефесянам",
            "К Филиппийцам", "К Колоссянам", "1-е Фессалоникийцам", "2-е Фессалоникийцам",
            "1-е Тимофею", "2-е Тимофею", "К Титу", "К Филимону", "К Евреям",
            "Иакова", "1-е Петра", "2-е Петра", "1-е Иоанна", "2-е Иоанна",
            "3-е Иоанна", "Иуды", "Откровение"
        ]

        for (i, eng) in BibleBooks.all.enumerated() {
            if i < russianNames.count {
                map[russianNames[i]] = eng
            }
        }
        return map
    }

    // MARK: - Errors

    enum ConversionError: LocalizedError {
        case cannotCreateDatabase
        case sqlError(String)
        case invalidJSON(String)

        var errorDescription: String? {
            switch self {
            case .cannotCreateDatabase: return "Cannot create SQLite database for module conversion"
            case .sqlError(let msg): return "SQL error during conversion: \(msg)"
            case .invalidJSON(let msg): return "Invalid JSON module format: \(msg)"
            }
        }
    }
}

// MARK: - JSON .brbmod Data Structures

struct JSONBrbMod: Codable {
    let meta: JSONBrbModMeta
    let data: [JSONBrbModBook]
}

struct JSONBrbModMeta: Codable {
    let name: String
    let abbreviation: String
    let language: String
    let format: String
    let version: Int
    let copyright: String?
    let notes: String?
}

struct JSONBrbModBook: Codable {
    let name: String
    let chapters: [[[JSONWordToken]]]
}

struct JSONWordToken: Codable {
    let word: String
    let strongs: [String]

    init(from decoder: Decoder) throws {
        // Handle both tagged format (object with word+strongs) and plain format (just a string)
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            word = try container.decode(String.self, forKey: .word)
            strongs = (try? container.decode([String].self, forKey: .strongs)) ?? []
        } else {
            // Plain string verse
            let container = try decoder.singleValueContainer()
            word = try container.decode(String.self)
            strongs = []
        }
    }

    private enum CodingKeys: String, CodingKey {
        case word, strongs
    }
}

// MARK: - Safe Array Index

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
