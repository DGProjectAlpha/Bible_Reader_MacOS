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
        ).first ?? FileManager.default.temporaryDirectory
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
        let bURL = bookmarksURL, nURL = notesURL, hURL = highlightsURL, rURL = historyURL
        let loaded: ([Bookmark], [Note], [HighlightedVerse], [BibleLocation]) = await Task.detached {
            let b: [Bookmark] = (try? Self.loadJSONFromDisk(from: bURL)) ?? []
            let n: [Note] = (try? Self.loadJSONFromDisk(from: nURL)) ?? []
            let h: [HighlightedVerse] = (try? Self.loadJSONFromDisk(from: hURL)) ?? []
            let r: [BibleLocation] = (try? Self.loadJSONFromDisk(from: rURL)) ?? []
            return (b, n, h, r)
        }.value
        bookmarks = loaded.0
        notes = loaded.1
        highlights = loaded.2
        readingHistory = loaded.3
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
        let b = bookmarks, n = notes, h = highlights, r = readingHistory
        let bURL = bookmarksURL, nURL = notesURL, hURL = highlightsURL, rURL = historyURL
        Task.detached {
            try? Self.saveJSONToDisk(b, to: bURL)
            try? Self.saveJSONToDisk(n, to: nURL)
            try? Self.saveJSONToDisk(h, to: hURL)
            try? Self.saveJSONToDisk(r, to: rURL)
        }
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

    nonisolated private static func loadJSONFromDisk<T: Decodable>(from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    nonisolated private static func saveJSONToDisk<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: .atomic)
    }
}
