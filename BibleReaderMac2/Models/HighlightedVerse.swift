import Foundation

struct HighlightedVerse: Identifiable, Codable {
    let id: UUID
    let verseId: String
    let color: BookmarkColor
}
