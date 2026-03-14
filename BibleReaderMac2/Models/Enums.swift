import Foundation
import SwiftUI

enum Testament {
    case old, new
}

enum BookmarkColor: String, Codable, CaseIterable {
    case yellow, blue, green, orange, purple

    var swiftUIColor: Color {
        switch self {
        case .yellow: return .yellow
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        }
    }

    var displayName: String {
        rawValue.capitalized
    }
}

enum LoadingState {
    case idle, loading, loaded, error(String)
}

enum InspectorTab {
    case strongs, crossRef, notes, bookmarks
}

enum HighlightSortMode: String, CaseIterable, Identifiable {
    case byColor, newestFirst, oldestFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .byColor: "Color"
        case .newestFirst: "Newest"
        case .oldestFirst: "Oldest"
        }
    }
}

enum SidebarSection: String, CaseIterable {
    case bookmarks = "bookmarks"
    case highlights = "highlights"
    case notes = "notes"
    case strongs = "strongs"
    case crossReferences = "crossReferences"
    case recentHistory = "recentHistory"
}
