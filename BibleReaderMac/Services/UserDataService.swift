import Foundation

/// Persists user data (bookmarks, reading history) to JSON files in Application Support.
class UserDataService {
    static let shared = UserDataService()

    private let fileManager = FileManager.default

    private var dataDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("BibleReaderMac", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var bookmarksURL: URL { dataDirectory.appendingPathComponent("bookmarks.json") }
    private var historyURL: URL { dataDirectory.appendingPathComponent("reading_history.json") }

    // MARK: - Bookmarks

    func loadBookmarks() -> [Bookmark] {
        guard let data = try? Data(contentsOf: bookmarksURL) else { return [] }
        return (try? JSONDecoder().decode([Bookmark].self, from: data)) ?? []
    }

    func saveBookmarks(_ bookmarks: [Bookmark]) {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        try? data.write(to: bookmarksURL, options: .atomic)
    }

    // MARK: - Reading History

    func loadHistory() -> [ReadingHistoryEntry] {
        guard let data = try? Data(contentsOf: historyURL) else { return [] }
        return (try? JSONDecoder().decode([ReadingHistoryEntry].self, from: data)) ?? []
    }

    func saveHistory(_ history: [ReadingHistoryEntry]) {
        // Keep last 500 entries
        let trimmed = history.suffix(500)
        guard let data = try? JSONEncoder().encode(Array(trimmed)) else { return }
        try? data.write(to: historyURL, options: .atomic)
    }
}
