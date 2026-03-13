import Foundation

struct Verse: Identifiable, Hashable {
    let id: String              // "GEN.1.1" — book.chapter.verse
    let book: String            // "GEN"
    let chapter: Int
    let verseNumber: Int
    let text: String
    let strongsNumbers: [String] // ["G0001", "H0002"] — empty if none
}
