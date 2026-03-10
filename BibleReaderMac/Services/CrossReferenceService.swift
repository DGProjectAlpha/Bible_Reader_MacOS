import Foundation

// MARK: - Resolved Cross-Reference (display-ready)

/// A cross-reference with its target verse text resolved for preview.
struct ResolvedCrossReference: Identifiable, Hashable {
    let id = UUID()
    let reference: CrossReference
    let targetBook: String
    let targetChapter: Int
    let targetVerse: Int
    let targetText: String
    let translationAbbreviation: String

    /// Human-readable reference string: "Genesis 1:1"
    var displayRef: String {
        "\(targetBook) \(targetChapter):\(targetVerse)"
    }

    /// Short badge for the reference type
    var typeBadge: String {
        switch reference.referenceType {
        case .parallel:  return "Parallel"
        case .quotation: return "Quotation"
        case .allusion:  return "Allusion"
        case .related:   return "Related"
        }
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: ResolvedCrossReference, rhs: ResolvedCrossReference) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Cross-Reference Service

/// Loads cross-references from module SQLite databases and resolves target verse text.
enum CrossReferenceService {

    /// Load and resolve all cross-references for a given verse across all provided translation files.
    /// Returns resolved refs with target verse text loaded from the same module.
    static func loadResolved(
        verseId: String,
        translations: [(filePath: String, abbreviation: String)]
    ) -> [ResolvedCrossReference] {
        var results: [ResolvedCrossReference] = []

        for (filePath, abbreviation) in translations {
            guard let conn = try? ModuleConnectionPool.shared.connection(for: filePath) else { continue }
            guard let refs = try? conn.loadCrossReferences(verseId: verseId), !refs.isEmpty else { continue }

            for ref in refs {
                let parts = parseVerseId(ref.toVerseId)
                guard let parts else { continue }

                // Load the target verse text for preview
                let targetText: String
                if let verses = try? conn.loadVerses(book: parts.book, chapter: parts.chapter),
                   let verse = verses.first(where: { $0.number == parts.verse }) {
                    targetText = verse.text
                } else {
                    targetText = "(verse not found in this module)"
                }

                results.append(ResolvedCrossReference(
                    reference: ref,
                    targetBook: parts.book,
                    targetChapter: parts.chapter,
                    targetVerse: parts.verse,
                    targetText: targetText,
                    translationAbbreviation: abbreviation
                ))
            }
        }

        return results
    }

    /// Also search for reverse cross-references (other verses that reference this one).
    static func loadReverse(
        verseId: String,
        translations: [(filePath: String, abbreviation: String)]
    ) -> [ResolvedCrossReference] {
        var results: [ResolvedCrossReference] = []

        for (filePath, abbreviation) in translations {
            guard let conn = try? ModuleConnectionPool.shared.connection(for: filePath) else { continue }
            guard (try? conn.tableExists("cross_references")) == true else { continue }

            let reverseRefResult = try? conn.query(
                "SELECT from_verse_id, to_verse_id, ref_type FROM cross_references WHERE to_verse_id = ?1",
                bindings: [verseId]
            ) { stmt in
                CrossReference(
                    fromVerseId: ModuleConnection.text(stmt, 0),
                    toVerseId: ModuleConnection.text(stmt, 1),
                    referenceType: CrossReferenceType(rawValue: ModuleConnection.text(stmt, 2)) ?? .related
                )
            }
            guard let reverseRefs = reverseRefResult else { continue }

            for ref in reverseRefs {
                let parts = parseVerseId(ref.fromVerseId)
                guard let parts else { continue }

                let targetText: String
                if let verses = try? conn.loadVerses(book: parts.book, chapter: parts.chapter),
                   let verse = verses.first(where: { $0.number == parts.verse }) {
                    targetText = verse.text
                } else {
                    targetText = "(verse not found)"
                }

                results.append(ResolvedCrossReference(
                    reference: CrossReference(
                        fromVerseId: ref.fromVerseId,
                        toVerseId: verseId,
                        referenceType: ref.referenceType
                    ),
                    targetBook: parts.book,
                    targetChapter: parts.chapter,
                    targetVerse: parts.verse,
                    targetText: targetText,
                    translationAbbreviation: abbreviation
                ))
            }
        }

        return results
    }

    // MARK: - Helpers

    /// Parse "Book:Chapter:Verse" into components.
    private static func parseVerseId(_ verseId: String) -> (book: String, chapter: Int, verse: Int)? {
        let parts = verseId.components(separatedBy: ":")
        guard parts.count >= 3,
              let chapter = Int(parts[parts.count - 2]),
              let verse = Int(parts[parts.count - 1]) else {
            return nil
        }
        // Book name may contain colons (unlikely but safe): rejoin everything before last two parts
        let book = parts.dropLast(2).joined(separator: ":")
        guard !book.isEmpty else { return nil }
        return (book: book, chapter: chapter, verse: verse)
    }
}
