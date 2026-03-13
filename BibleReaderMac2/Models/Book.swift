import Foundation

struct Book: Identifiable {
    let id: String              // "GEN"
    let name: String
    let shortName: String
    let testament: Testament    // .old / .new
    let chapterCount: Int
}
