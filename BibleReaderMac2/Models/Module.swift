import Foundation

struct Module: Identifiable {
    let id: String              // filename without extension
    let name: String
    let abbreviation: String    // "KJV", "ASV", etc.
    let language: String
    let books: [Book]
    let versificationScheme: VersificationScheme
}
