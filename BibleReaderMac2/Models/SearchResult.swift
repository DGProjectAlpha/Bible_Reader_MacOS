import Foundation

struct SearchResult: Identifiable {
    let id: String          // "moduleId:book.chapter.verse"
    let moduleId: String
    let moduleName: String
    let verse: Verse
}
