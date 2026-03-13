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
