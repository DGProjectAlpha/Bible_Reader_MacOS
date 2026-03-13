import Foundation

struct Chapter: Identifiable {
    let id: String          // "GEN.1"
    let book: String
    let number: Int
    var verses: [Verse]
}
