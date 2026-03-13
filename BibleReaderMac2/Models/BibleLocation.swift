import Foundation

struct BibleLocation: Equatable, Hashable, Codable {
    let moduleId: String
    let book: String
    let chapter: Int
    var verseNumber: Int?       // nil = top of chapter
}
