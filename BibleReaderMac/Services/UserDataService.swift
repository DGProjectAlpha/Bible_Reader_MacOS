import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Persists user data (bookmarks, reading history) using SQLite + JSON files in Application Support.
class UserDataService {
    static let shared = UserDataService()

    private let fileManager = FileManager.default
    private var db: OpaquePointer?

    /// The active profile name — all reads/writes are scoped to this.
    private(set) var activeProfile: String = "Default"

    private var dataDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("BibleReaderMac", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var bookmarksURL: URL { dataDirectory.appendingPathComponent("bookmarks.json") }
    private var dbURL: URL { dataDirectory.appendingPathComponent("userdata.sqlite") }

    init() {
        // Restore active profile from UserDefaults
        activeProfile = UserDefaults.standard.string(forKey: "activeProfile") ?? "Default"
        openDatabase()
        createTables()
        migrateProfileColumn()
        migrateJsonHistoryIfNeeded()
        migrateJsonBookmarksIfNeeded()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Database Setup

    private func openDatabase() {
        let path = dbURL.path
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        var handle: OpaquePointer?
        if sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK {
            db = handle
            sqlite3_busy_timeout(db, 5000)
            // Enable WAL for better concurrent read performance
            sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
        } else {
            print("UserDataService: failed to open database at \(path)")
            if let handle { sqlite3_close(handle) }
        }
    }

    private func createTables() {
        guard let db else { return }
        let sql = """
        CREATE TABLE IF NOT EXISTS reading_history (
            id TEXT PRIMARY KEY,
            book TEXT NOT NULL,
            chapter INTEGER NOT NULL,
            verse INTEGER,
            translation_abbreviation TEXT NOT NULL,
            timestamp REAL NOT NULL,
            profile TEXT NOT NULL DEFAULT 'Default'
        );
        CREATE INDEX IF NOT EXISTS idx_history_timestamp ON reading_history(timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_history_book_chapter ON reading_history(book, chapter);
        CREATE TABLE IF NOT EXISTS bookmarks (
            id TEXT PRIMARY KEY,
            verse_id TEXT NOT NULL,
            translation_id TEXT NOT NULL,
            label TEXT,
            note TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            profile TEXT NOT NULL DEFAULT 'Default'
        );
        CREATE INDEX IF NOT EXISTS idx_bookmarks_verse ON bookmarks(verse_id, translation_id);
        CREATE INDEX IF NOT EXISTS idx_bookmarks_created ON bookmarks(created_at DESC);
        CREATE TABLE IF NOT EXISTS highlights (
            id TEXT PRIMARY KEY,
            verse_id TEXT NOT NULL,
            translation_id TEXT NOT NULL,
            color TEXT NOT NULL,
            created_at REAL NOT NULL,
            profile TEXT NOT NULL DEFAULT 'Default'
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_highlights_verse ON highlights(verse_id, translation_id, profile);
        CREATE TABLE IF NOT EXISTS notes (
            id TEXT PRIMARY KEY,
            verse_id TEXT NOT NULL,
            translation_id TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            profile TEXT NOT NULL DEFAULT 'Default'
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_notes_verse ON notes(verse_id, translation_id, profile);
        CREATE INDEX IF NOT EXISTS idx_notes_updated ON notes(updated_at DESC);
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    /// One-time migration: import existing JSON reading_history.json into SQLite, then delete it.
    private func migrateJsonHistoryIfNeeded() {
        let jsonURL = dataDirectory.appendingPathComponent("reading_history.json")
        guard fileManager.fileExists(atPath: jsonURL.path),
              let data = try? Data(contentsOf: jsonURL),
              let entries = try? JSONDecoder().decode([ReadingHistoryEntry].self, from: data),
              !entries.isEmpty else { return }

        for entry in entries {
            insertHistoryEntry(entry)
        }
        try? fileManager.removeItem(at: jsonURL)
    }

    // MARK: - Bookmarks (SQLite)

    /// One-time migration: import existing bookmarks.json into SQLite, then delete the file.
    private func migrateJsonBookmarksIfNeeded() {
        guard fileManager.fileExists(atPath: bookmarksURL.path),
              let data = try? Data(contentsOf: bookmarksURL),
              let bookmarks = try? JSONDecoder().decode([Bookmark].self, from: data),
              !bookmarks.isEmpty else { return }

        for bm in bookmarks {
            insertBookmark(bm)
        }
        try? fileManager.removeItem(at: bookmarksURL)
    }

    func insertBookmark(_ bookmark: Bookmark) {
        guard let db else { return }
        let sql = "INSERT OR REPLACE INTO bookmarks (id, verse_id, translation_id, label, note, created_at, updated_at, profile) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, bookmark.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, bookmark.verseId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, bookmark.translationId.uuidString, -1, SQLITE_TRANSIENT)
        if let label = bookmark.label {
            sqlite3_bind_text(stmt, 4, label, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        if let note = bookmark.note {
            sqlite3_bind_text(stmt, 5, note, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        sqlite3_bind_double(stmt, 6, bookmark.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 7, bookmark.updatedAt.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 8, activeProfile, -1, SQLITE_TRANSIENT)

        sqlite3_step(stmt)
    }

    func loadBookmarks() -> [Bookmark] {
        guard let db else { return [] }
        let sql = "SELECT id, verse_id, translation_id, label, note, created_at, updated_at FROM bookmarks WHERE profile = ?1 ORDER BY created_at DESC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, activeProfile, -1, SQLITE_TRANSIENT)

        var results: [Bookmark] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let idStr = String(cString: sqlite3_column_text(stmt, 0))
            let verseId = String(cString: sqlite3_column_text(stmt, 1))
            let transIdStr = String(cString: sqlite3_column_text(stmt, 2))
            let label: String? = sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 3))
            let note: String? = sqlite3_column_type(stmt, 4) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 4))
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
            let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))

            results.append(Bookmark(
                id: UUID(uuidString: idStr) ?? UUID(),
                verseId: verseId,
                translationId: UUID(uuidString: transIdStr) ?? UUID(),
                label: label,
                note: note,
                createdAt: createdAt,
                updatedAt: updatedAt
            ))
        }
        return results
    }

    func deleteBookmark(_ id: UUID) {
        guard let db else { return }
        let sql = "DELETE FROM bookmarks WHERE id = ?1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    func updateBookmarkNote(_ id: UUID, note: String?) {
        guard let db else { return }
        let sql = "UPDATE bookmarks SET note = ?1, updated_at = ?2 WHERE id = ?3"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        if let note {
            sqlite3_bind_text(stmt, 1, note, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 1)
        }
        sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    func updateBookmarkLabel(_ id: UUID, label: String?) {
        guard let db else { return }
        let sql = "UPDATE bookmarks SET label = ?1, updated_at = ?2 WHERE id = ?3"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        if let label {
            sqlite3_bind_text(stmt, 1, label, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 1)
        }
        sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    func clearBookmarks() {
        guard let db else { return }
        let sql = "DELETE FROM bookmarks WHERE profile = ?1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, activeProfile, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    // MARK: - Highlights (SQLite)

    func insertHighlight(_ highlight: Highlight) {
        guard let db else { return }
        let sql = "INSERT OR REPLACE INTO highlights (id, verse_id, translation_id, color, created_at, profile) VALUES (?1, ?2, ?3, ?4, ?5, ?6)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, highlight.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, highlight.verseId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, highlight.translationId.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, highlight.color.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 5, highlight.createdAt.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 6, activeProfile, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    func deleteHighlight(verseId: String, translationId: UUID) {
        guard let db else { return }
        let sql = "DELETE FROM highlights WHERE verse_id = ?1 AND translation_id = ?2 AND profile = ?3"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, verseId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, translationId.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, activeProfile, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    func loadHighlights() -> [Highlight] {
        guard let db else { return [] }
        let sql = "SELECT id, verse_id, translation_id, color, created_at FROM highlights WHERE profile = ?1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, activeProfile, -1, SQLITE_TRANSIENT)
        var results: [Highlight] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let idStr = String(cString: sqlite3_column_text(stmt, 0))
            let verseId = String(cString: sqlite3_column_text(stmt, 1))
            let transIdStr = String(cString: sqlite3_column_text(stmt, 2))
            let colorStr = String(cString: sqlite3_column_text(stmt, 3))
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
            guard let color = HighlightColor(rawValue: colorStr) else { continue }
            results.append(Highlight(
                id: UUID(uuidString: idStr) ?? UUID(),
                verseId: verseId,
                translationId: UUID(uuidString: transIdStr) ?? UUID(),
                color: color,
                createdAt: createdAt
            ))
        }
        return results
    }

    // MARK: - Notes (SQLite)

    func insertNote(_ note: Note) {
        guard let db else { return }
        let sql = "INSERT OR REPLACE INTO notes (id, verse_id, translation_id, content, created_at, updated_at, profile) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, note.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, note.verseId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, note.translationId.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, note.content, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 5, note.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 6, note.updatedAt.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 7, activeProfile, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    func updateNote(id: UUID, content: String) {
        guard let db else { return }
        let sql = "UPDATE notes SET content = ?1, updated_at = ?2 WHERE id = ?3"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, content, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    func deleteNote(_ id: UUID) {
        guard let db else { return }
        let sql = "DELETE FROM notes WHERE id = ?1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    func loadNotes() -> [Note] {
        guard let db else { return [] }
        let sql = "SELECT id, verse_id, translation_id, content, created_at, updated_at FROM notes WHERE profile = ?1 ORDER BY updated_at DESC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, activeProfile, -1, SQLITE_TRANSIENT)
        var results: [Note] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let idStr = String(cString: sqlite3_column_text(stmt, 0))
            let verseId = String(cString: sqlite3_column_text(stmt, 1))
            let transIdStr = String(cString: sqlite3_column_text(stmt, 2))
            let content = String(cString: sqlite3_column_text(stmt, 3))
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
            let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
            results.append(Note(
                id: UUID(uuidString: idStr) ?? UUID(),
                verseId: verseId,
                translationId: UUID(uuidString: transIdStr) ?? UUID(),
                content: content,
                createdAt: createdAt
            ))
            // Fix updatedAt after init
            if var last = results.last {
                last.updatedAt = updatedAt
                results[results.count - 1] = last
            }
        }
        return results
    }

    // MARK: - Reading History (SQLite)

    func insertHistoryEntry(_ entry: ReadingHistoryEntry) {
        guard let db else { return }
        let sql = "INSERT OR REPLACE INTO reading_history (id, book, chapter, verse, translation_abbreviation, timestamp, profile) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        let idStr = entry.id.uuidString
        sqlite3_bind_text(stmt, 1, idStr, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, entry.book, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 3, Int32(entry.chapter))
        if let v = entry.verse {
            sqlite3_bind_int(stmt, 4, Int32(v))
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        sqlite3_bind_text(stmt, 5, entry.translationAbbreviation, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 6, entry.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 7, activeProfile, -1, SQLITE_TRANSIENT)

        sqlite3_step(stmt)
    }

    func loadHistory(limit: Int = 500) -> [ReadingHistoryEntry] {
        guard let db else { return [] }
        let sql = "SELECT id, book, chapter, verse, translation_abbreviation, timestamp FROM reading_history WHERE profile = ?1 ORDER BY timestamp DESC LIMIT ?2"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, activeProfile, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var results: [ReadingHistoryEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let idStr = String(cString: sqlite3_column_text(stmt, 0))
            let book = String(cString: sqlite3_column_text(stmt, 1))
            let chapter = Int(sqlite3_column_int(stmt, 2))
            let verse: Int? = sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 3))
            let abbrev = String(cString: sqlite3_column_text(stmt, 4))
            let ts = sqlite3_column_double(stmt, 5)

            results.append(ReadingHistoryEntry(
                id: UUID(uuidString: idStr) ?? UUID(),
                book: book,
                chapter: chapter,
                verse: verse,
                translationAbbreviation: abbrev,
                timestamp: Date(timeIntervalSince1970: ts)
            ))
        }
        return results
    }

    /// Get the most recent history entry (last viewed position).
    func lastViewedPosition() -> ReadingHistoryEntry? {
        return loadHistory(limit: 1).first
    }

    func clearHistory() {
        guard let db else { return }
        let sql = "DELETE FROM reading_history WHERE profile = ?1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, activeProfile, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    /// Trim history to keep only the most recent N entries for the active profile.
    func trimHistory(keepLast count: Int = 500) {
        guard let db else { return }
        let sql = "DELETE FROM reading_history WHERE profile = ?1 AND id NOT IN (SELECT id FROM reading_history WHERE profile = ?2 ORDER BY timestamp DESC LIMIT ?3)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, activeProfile, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, activeProfile, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 3, Int32(count))
        sqlite3_step(stmt)
    }

    /// Check if the most recent entry matches the given position (dedup check).
    func lastEntryMatches(book: String, chapter: Int, verse: Int?, translationAbbreviation: String) -> Bool {
        guard let last = lastViewedPosition() else { return false }
        return last.book == book && last.chapter == chapter && last.verse == verse &&
               last.translationAbbreviation == translationAbbreviation
    }

    // MARK: - Profile Management

    /// Switch active profile. All subsequent reads/writes will use this profile.
    func setActiveProfile(_ name: String) {
        activeProfile = name
        UserDefaults.standard.set(name, forKey: "activeProfile")
    }

    /// Delete all data for a specific profile.
    func deleteProfileData(_ profileName: String) {
        guard let db else { return }
        let tables = ["bookmarks", "highlights", "notes", "reading_history"]
        for table in tables {
            let sql = "DELETE FROM \(table) WHERE profile = ?1"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, profileName, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
    }

    /// Clear all highlights for the active profile.
    func clearHighlights() {
        guard let db else { return }
        let sql = "DELETE FROM highlights WHERE profile = ?1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, activeProfile, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    /// Clear all notes for the active profile.
    func clearNotes() {
        guard let db else { return }
        let sql = "DELETE FROM notes WHERE profile = ?1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, activeProfile, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    // MARK: - Profile Column Migration

    /// Add `profile` column to all tables if missing, default existing rows to "Default".
    /// Also updates unique indexes to include the profile column.
    private func migrateProfileColumn() {
        guard let db else { return }
        let tables = ["bookmarks", "highlights", "notes", "reading_history"]
        for table in tables {
            // Check if column exists
            var tableInfo: OpaquePointer?
            let pragma = "PRAGMA table_info(\(table))"
            guard sqlite3_prepare_v2(db, pragma, -1, &tableInfo, nil) == SQLITE_OK else { continue }
            var hasProfile = false
            while sqlite3_step(tableInfo) == SQLITE_ROW {
                if let name = sqlite3_column_text(tableInfo, 1) {
                    if String(cString: name) == "profile" {
                        hasProfile = true
                        break
                    }
                }
            }
            sqlite3_finalize(tableInfo)

            if !hasProfile {
                let alter = "ALTER TABLE \(table) ADD COLUMN profile TEXT NOT NULL DEFAULT 'Default'"
                sqlite3_exec(db, alter, nil, nil, nil)

                // Recreate unique indexes to include profile
                if table == "highlights" {
                    sqlite3_exec(db, "DROP INDEX IF EXISTS idx_highlights_verse", nil, nil, nil)
                    sqlite3_exec(db, "CREATE UNIQUE INDEX IF NOT EXISTS idx_highlights_verse ON highlights(verse_id, translation_id, profile)", nil, nil, nil)
                } else if table == "notes" {
                    sqlite3_exec(db, "DROP INDEX IF EXISTS idx_notes_verse", nil, nil, nil)
                    sqlite3_exec(db, "CREATE UNIQUE INDEX IF NOT EXISTS idx_notes_verse ON notes(verse_id, translation_id, profile)", nil, nil, nil)
                }
            }
        }
    }
}
