import Foundation

enum Testament {
    case old, new
}

enum BookmarkColor: String, Codable, CaseIterable {
    case yellow, blue, green, orange, purple
}

enum LoadingState {
    case idle, loading, loaded, error(String)
}

enum InspectorTab {
    case strongs, crossRef, notes, bookmarks
}

enum SidebarSection: String, CaseIterable {
    case bookmarks = "bookmarks"
    case highlights = "highlights"
    case notes = "notes"
    case strongs = "strongs"
    case crossReferences = "crossReferences"
    case search = "search"
    case recentHistory = "recentHistory"
}
