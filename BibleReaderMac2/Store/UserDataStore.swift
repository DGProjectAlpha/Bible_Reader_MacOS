import Foundation

@MainActor @Observable
final class UserDataStore {
    var bookmarks: [Bookmark] = []
    var notes: [Note] = []
    var highlights: [HighlightedVerse] = []
    var readingHistory: [BibleLocation] = []

    private let dataDirectory: URL

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        dataDirectory = appSupport
            .appendingPathComponent("BibleReaderMac2", isDirectory: true)
        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Persistence Paths

    private var bookmarksURL: URL { dataDirectory.appendingPathComponent("bookmarks.json") }
    private var notesURL: URL { dataDirectory.appendingPathComponent("notes.json") }
    private var highlightsURL: URL { dataDirectory.appendingPathComponent("highlights.json") }
    private var historyURL: URL { dataDirectory.appendingPathComponent("reading_history.json") }

    // MARK: - Load

    func load() async {
        bookmarks = (try? loadJSON(from: bookmarksURL)) ?? []
        notes = (try? loadJSON(from: notesURL)) ?? []
        highlights = (try? loadJSON(from: highlightsURL)) ?? []
        readingHistory = (try? loadJSON(from: historyURL)) ?? []
    }

    // MARK: - Bookmarks

    func addBookmark(_ bookmark: Bookmark) async {
        bookmarks.append(bookmark)
        await save()
    }

    func updateBookmark(id: UUID, color: BookmarkColor? = nil, note: String? = nil) async {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        let old = bookmarks[index]
        bookmarks[index] = Bookmark(
            id: old.id,
            verseId: old.verseId,
            color: color ?? old.color,
            note: note ?? old.note,
            createdAt: old.createdAt
        )
        await save()
    }

    func deleteBookmark(id: UUID) async {
        bookmarks.removeAll { $0.id == id }
        await save()
    }

    // MARK: - Notes

    func addNote(_ note: Note) async {
        notes.append(note)
        await save()
    }

    func updateNote(id: UUID, text: String) async {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].text = text
        notes[index].updatedAt = Date()
        await save()
    }

    func deleteNote(id: UUID) async {
        notes.removeAll { $0.id == id }
        await save()
    }

    // MARK: - Highlights

    func addHighlight(_ highlight: HighlightedVerse) async {
        highlights.append(highlight)
        await save()
    }

    func removeHighlight(verseId: String) async {
        highlights.removeAll { $0.verseId == verseId }
        await save()
    }

    // MARK: - Reading History

    func addToHistory(_ location: BibleLocation) async {
        readingHistory.removeAll { $0 == location }
        readingHistory.insert(location, at: 0)
        if readingHistory.count > 50 {
            readingHistory = Array(readingHistory.prefix(50))
        }
        await save()
    }

    func clearHistory() async {
        readingHistory.removeAll()
        await save()
    }

    // MARK: - Save

    func save() async {
        try? saveJSON(bookmarks, to: bookmarksURL)
        try? saveJSON(notes, to: notesURL)
        try? saveJSON(highlights, to: highlightsURL)
        try? saveJSON(readingHistory, to: historyURL)
    }

    // MARK: - JSON Helpers

    private func loadJSON<T: Decodable>(from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func saveJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: .atomic)
    }
}
