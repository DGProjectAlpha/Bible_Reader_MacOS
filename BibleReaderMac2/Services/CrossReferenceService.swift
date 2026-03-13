import Foundation

// MARK: - ResolvedCrossReference

struct ResolvedCrossReference: Identifiable, Hashable {
    let id = UUID()
    let reference: CrossReference
    let targetBook: String
    let targetChapter: Int
    let targetVerse: Int
    let targetText: String

    var displayRef: String { "\(targetBook) \(targetChapter):\(targetVerse)" }

    var typeBadge: String {
        switch reference.referenceType {
        case "parallel":  return "Parallel"
        case "quotation": return "Quotation"
        case "allusion":  return "Allusion"
        default:          return "Related"
        }
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: ResolvedCrossReference, rhs: ResolvedCrossReference) -> Bool { lhs.id == rhs.id }
}

// MARK: - CrossReferenceService

actor CrossReferenceService {
    static let shared = CrossReferenceService()

    private let databaseService = DatabaseService.shared
    private let versificationService = VersificationService.shared

    private init() {}

    /// Load and resolve cross-references for a verse.
    /// verseId format: "BookName:chapter:verse" in the module's native numbering.
    /// Cross-references in the DB use KJV canonical numbering, so we convert as needed.
    func loadResolved(moduleId: String, verseId: String, scheme: VersificationScheme = .kjv) async -> [ResolvedCrossReference] {
        // Convert the query verse to canonical (KJV) numbering for the DB lookup
        let canonicalVerseId = toCanonicalVerseId(verseId, scheme: scheme)

        let refs: [CrossReference]
        do {
            refs = try await databaseService.fetchCrossReferences(moduleId: moduleId, verseId: canonicalVerseId)
        } catch {
            return []
        }

        guard !refs.isEmpty else { return [] }

        var results: [ResolvedCrossReference] = []
        for ref in refs {
            guard let parsed = parseVerseId(ref.toVerseId) else { continue }

            // Convert canonical target back to the module's scheme for verse lookup
            let mapped = versificationService.convert(
                book: parsed.book, chapter: parsed.chapter, verse: parsed.verse,
                from: .kjv, to: scheme
            )

            let text = (try? await databaseService.fetchVerseText(
                moduleId: moduleId,
                book: mapped.book,
                chapter: mapped.chapter,
                verse: mapped.verse
            )) ?? "(verse not found)"

            results.append(ResolvedCrossReference(
                reference: ref,
                targetBook: mapped.book,
                targetChapter: mapped.chapter,
                targetVerse: mapped.verse,
                targetText: text
            ))
        }

        return results
    }

    /// Load cross-references in both directions (from this verse AND to this verse).
    func loadResolvedBidirectional(moduleId: String, verseId: String, scheme: VersificationScheme = .kjv) async -> [ResolvedCrossReference] {
        let canonicalVerseId = toCanonicalVerseId(verseId, scheme: scheme)

        let forwardRefs = await loadResolved(moduleId: moduleId, verseId: verseId, scheme: scheme)

        // Also find refs that point TO this verse (using canonical ID)
        let reverseRefs: [CrossReference]
        do {
            reverseRefs = try await databaseService.fetchReverseCrossReferences(moduleId: moduleId, verseId: canonicalVerseId)
        } catch {
            return forwardRefs
        }

        guard !reverseRefs.isEmpty else { return forwardRefs }

        // Resolve reverse refs (the "from" side is the target we want to show)
        var results = forwardRefs
        let existingTargets = Set(forwardRefs.map { "\($0.targetBook):\($0.targetChapter):\($0.targetVerse)" })

        for ref in reverseRefs {
            guard let parsed = parseVerseId(ref.fromVerseId) else { continue }

            // Convert canonical source back to the module's scheme
            let mapped = versificationService.convert(
                book: parsed.book, chapter: parsed.chapter, verse: parsed.verse,
                from: .kjv, to: scheme
            )

            let mappedId = "\(mapped.book):\(mapped.chapter):\(mapped.verse)"
            guard !existingTargets.contains(mappedId) else { continue }

            let text = (try? await databaseService.fetchVerseText(
                moduleId: moduleId,
                book: mapped.book,
                chapter: mapped.chapter,
                verse: mapped.verse
            )) ?? "(verse not found)"

            results.append(ResolvedCrossReference(
                reference: ref,
                targetBook: mapped.book,
                targetChapter: mapped.chapter,
                targetVerse: mapped.verse,
                targetText: text
            ))
        }

        return results
    }

    // MARK: - Helpers

    /// Parse "Book:Chapter:Verse" into components.
    private func parseVerseId(_ verseId: String) -> (book: String, chapter: Int, verse: Int)? {
        let parts = verseId.components(separatedBy: ":")
        guard parts.count >= 3,
              let chapter = Int(parts[parts.count - 2]),
              let verse = Int(parts[parts.count - 1]) else { return nil }
        let book = parts.dropLast(2).joined(separator: ":")
        guard !book.isEmpty else { return nil }
        return (book: book, chapter: chapter, verse: verse)
    }

    /// Convert a verseId from the given scheme to KJV canonical numbering.
    private func toCanonicalVerseId(_ verseId: String, scheme: VersificationScheme) -> String {
        guard scheme != .kjv, let parsed = parseVerseId(verseId) else { return verseId }
        let canonical = versificationService.toCanonical(
            book: parsed.book, chapter: parsed.chapter, verse: parsed.verse, scheme: scheme
        )
        return canonical.id
    }
}
