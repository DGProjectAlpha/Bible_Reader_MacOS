import Foundation

struct Note: Identifiable, Codable {
    let id: UUID
    let verseId: String
    var text: String
    let createdAt: Date
    var updatedAt: Date
}
