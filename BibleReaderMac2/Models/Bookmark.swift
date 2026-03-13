import Foundation

struct Bookmark: Identifiable, Codable {
    let id: UUID
    let verseId: String         // "GEN.1.1"
    let color: BookmarkColor
    let note: String
    let createdAt: Date
}
