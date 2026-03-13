import Foundation

// ============================================================
// CrossReferenceResolutionTests.swift
// Standalone tests verifying cross-references resolve correctly
// through integrated VersificationService + CrossReferenceService logic.
// Run: swift Tests/CrossReferenceResolutionTests.swift
// ============================================================

// MARK: - Minimal type replicas (just enough to test resolution logic)

enum VersificationScheme: String { case kjv, lxx, synodal, vulgate }

struct CanonicalRef: Hashable {
    let book: String; let chapter: Int; let verse: Int
    var id: String { "\(book):\(chapter):\(verse)" }
}

struct CrossReference {
    let fromVerseId: String
    let toVerseId: String
    let referenceType: String
}

// MARK: - VersificationService (production logic copy)

final class VersificationService {
    static let shared = VersificationService()

    func toCanonical(book: String, chapter: Int, verse: Int, scheme: VersificationScheme) -> CanonicalRef {
        switch scheme {
        case .kjv:     return CanonicalRef(book: book, chapter: chapter, verse: verse)
        case .lxx:     return lxxToCanonical(book: book, chapter: chapter, verse: verse)
        case .synodal: return synodalToCanonical(book: book, chapter: chapter, verse: verse)
        case .vulgate: return vulgateToCanonical(book: book, chapter: chapter, verse: verse)
        }
    }

    func fromCanonical(_ ref: CanonicalRef, to scheme: VersificationScheme) -> (book: String, chapter: Int, verse: Int) {
        switch scheme {
        case .kjv:     return (ref.book, ref.chapter, ref.verse)
        case .lxx:     return canonicalToLxx(ref)
        case .synodal: return canonicalToSynodal(ref)
        case .vulgate: return canonicalToVulgate(ref)
        }
    }

    func convert(book: String, chapter: Int, verse: Int,
                 from source: VersificationScheme, to target: VersificationScheme) -> (book: String, chapter: Int, verse: Int) {
        if source == target { return (book, chapter, verse) }
        let canonical = toCanonical(book: book, chapter: chapter, verse: verse, scheme: source)
        return fromCanonical(canonical, to: target)
    }

    // -- Psalm tables --
    private static let kjvPsalmToLxx: [Int: Int] = {
        var m = [Int: Int](); m[9] = 9; m[10] = 9
        for k in 11...113 { m[k] = k - 1 }
        m[114] = 113; m[115] = 113; m[116] = 114
        for k in 117...146 { m[k] = k - 1 }; m[147] = 146; return m
    }()
    private static let lxxPsalmToKjv: [Int: Int] = {
        var m = [Int: Int](); m[9] = 9
        for l in 10...112 { m[l] = l + 1 }
        m[113] = 114; m[114] = 116; m[115] = 116
        for l in 116...145 { m[l] = l + 1 }
        m[146] = 147; m[147] = 147; return m
    }()
    private static let psalmsWithSuperscriptionOffset: Set<Int> = [
        3,4,5,6,7,8,9,12,13,18,19,20,21,22,30,31,34,36,38,39,
        40,41,42,44,45,46,47,48,49,51,52,53,54,55,56,57,58,59,60,
        61,62,63,64,65,66,67,68,69,70,75,76,77,80,81,83,84,85,88,
        89,92,98,100,101,102,108,109,110,140,142
    ]

    private func lxxToCanonical(book: String, chapter: Int, verse: Int) -> CanonicalRef {
        let nb = lxxBookToCanonical(book)
        if nb == "Psalms", let kjv = Self.lxxPsalmToKjv[chapter] {
            return CanonicalRef(book: "Psalms", chapter: kjv, verse: verse)
        }
        return CanonicalRef(book: nb, chapter: chapter, verse: verse)
    }
    private func canonicalToLxx(_ ref: CanonicalRef) -> (String, Int, Int) {
        if ref.book == "Psalms", let lxx = Self.kjvPsalmToLxx[ref.chapter] { return ("Psalms", lxx, ref.verse) }
        return (ref.book, ref.chapter, ref.verse)
    }
    private func synodalToCanonical(book: String, chapter: Int, verse: Int) -> CanonicalRef {
        if book == "Psalms" {
            var kjvCh = chapter
            if let mapped = Self.lxxPsalmToKjv[chapter] { kjvCh = mapped }
            var kjvV = verse
            if Self.psalmsWithSuperscriptionOffset.contains(kjvCh) && verse > 1 { kjvV = verse - 1 }
            return CanonicalRef(book: "Psalms", chapter: kjvCh, verse: kjvV)
        }
        if book == "Joel" {
            if chapter == 2 && verse >= 28 { return CanonicalRef(book: "Joel", chapter: 3, verse: verse - 27) }
            if chapter == 3 { return CanonicalRef(book: "Joel", chapter: 3, verse: verse + 5) }
            if chapter == 4 { return CanonicalRef(book: "Joel", chapter: 3, verse: verse + 16) }
        }
        if book == "Malachi" && chapter == 3 && verse >= 19 {
            return CanonicalRef(book: "Malachi", chapter: 4, verse: verse - 18)
        }
        return CanonicalRef(book: book, chapter: chapter, verse: verse)
    }
    private func canonicalToSynodal(_ ref: CanonicalRef) -> (String, Int, Int) {
        if ref.book == "Psalms" {
            var synCh = ref.chapter
            if let lxx = Self.kjvPsalmToLxx[ref.chapter] { synCh = lxx }
            var synV = ref.verse
            if Self.psalmsWithSuperscriptionOffset.contains(ref.chapter) { synV = ref.verse + 1 }
            return ("Psalms", synCh, synV)
        }
        if ref.book == "Joel" && ref.chapter == 3 {
            if ref.verse <= 5 { return ("Joel", 2, ref.verse + 27) }
            if ref.verse <= 16 { return ("Joel", 3, ref.verse - 5) }
            return ("Joel", 4, ref.verse - 16)
        }
        if ref.book == "Malachi" && ref.chapter == 4 { return ("Malachi", 3, ref.verse + 18) }
        return (ref.book, ref.chapter, ref.verse)
    }
    private func vulgateToCanonical(book: String, chapter: Int, verse: Int) -> CanonicalRef {
        if book == "Psalms", let kjv = Self.lxxPsalmToKjv[chapter] {
            return CanonicalRef(book: "Psalms", chapter: kjv, verse: verse)
        }
        return CanonicalRef(book: book, chapter: chapter, verse: verse)
    }
    private func canonicalToVulgate(_ ref: CanonicalRef) -> (String, Int, Int) {
        if ref.book == "Psalms", let lxx = Self.kjvPsalmToLxx[ref.chapter] { return ("Psalms", lxx, ref.verse) }
        return (ref.book, ref.chapter, ref.verse)
    }
    private func lxxBookToCanonical(_ book: String) -> String {
        switch book {
        case "1 Kingdoms","1 Reigns": return "1 Samuel"
        case "2 Kingdoms","2 Reigns": return "2 Samuel"
        case "3 Kingdoms","3 Reigns": return "1 Kings"
        case "4 Kingdoms","4 Reigns": return "2 Kings"
        case "1 Paralipomenon": return "1 Chronicles"
        case "2 Paralipomenon": return "2 Chronicles"
        case "1 Esdras": return "Ezra"
        case "2 Esdras": return "Nehemiah"
        default: return book
        }
    }
}

// MARK: - Cross-reference resolution logic (mirrors CrossReferenceService)

func parseVerseId(_ verseId: String) -> (book: String, chapter: Int, verse: Int)? {
    let parts = verseId.components(separatedBy: ":")
    guard parts.count >= 3,
          let chapter = Int(parts[parts.count - 2]),
          let verse = Int(parts[parts.count - 1]) else { return nil }
    let book = parts.dropLast(2).joined(separator: ":")
    guard !book.isEmpty else { return nil }
    return (book, chapter, verse)
}

func toCanonicalVerseId(_ verseId: String, scheme: VersificationScheme) -> String {
    guard scheme != .kjv, let p = parseVerseId(verseId) else { return verseId }
    return VersificationService.shared.toCanonical(book: p.book, chapter: p.chapter, verse: p.verse, scheme: scheme).id
}

/// Simulates loadResolved: given a verse in a module's scheme, convert to canonical for DB lookup,
/// then convert each cross-ref target back to the module's scheme.
func resolveRefs(queryVerseId: String, scheme: VersificationScheme,
                 dbRefs: [CrossReference]) -> [(book: String, chapter: Int, verse: Int)] {
    let vs = VersificationService.shared
    // Step 1: Convert query to canonical (for DB lookup)
    let canonicalQuery = toCanonicalVerseId(queryVerseId, scheme: scheme)
    _ = canonicalQuery // used for DB fetch in production

    // Step 2: For each ref target (stored in KJV canonical), convert back to module's scheme
    var results: [(book: String, chapter: Int, verse: Int)] = []
    for ref in dbRefs {
        guard let parsed = parseVerseId(ref.toVerseId) else { continue }
        let mapped = vs.convert(book: parsed.book, chapter: parsed.chapter, verse: parsed.verse,
                                from: .kjv, to: scheme)
        results.append(mapped)
    }
    return results
}

// MARK: - Test runner

var passed = 0
var failed = 0

func assert(_ condition: Bool, _ msg: String, file: String = #file, line: Int = #line) {
    if condition {
        passed += 1
        print("  ✅ \(msg)")
    } else {
        failed += 1
        print("  ❌ FAIL: \(msg) (line \(line))")
    }
}

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String, file: String = #file, line: Int = #line) {
    if a == b {
        passed += 1
        print("  ✅ \(msg)")
    } else {
        failed += 1
        print("  ❌ FAIL: \(msg) — got \(a), expected \(b) (line \(line))")
    }
}

print("=== Cross-Reference Resolution Tests ===\n")

// ---------------------------------------------------------------
// 1. parseVerseId basics
// ---------------------------------------------------------------
print("-- parseVerseId --")

let p1 = parseVerseId("Genesis:1:1")!
assertEqual(p1.book, "Genesis", "Parse Genesis:1:1 book")
assertEqual(p1.chapter, 1, "Parse Genesis:1:1 chapter")
assertEqual(p1.verse, 1, "Parse Genesis:1:1 verse")

let p2 = parseVerseId("1 Samuel:3:10")!
assertEqual(p2.book, "1 Samuel", "Parse book with space")
assertEqual(p2.chapter, 3, "1 Samuel chapter")

let p3 = parseVerseId("Song of Solomon:2:4")!
assertEqual(p3.book, "Song of Solomon", "Parse multi-word book")

assert(parseVerseId("bad") == nil, "Reject invalid verseId 'bad'")
assert(parseVerseId("X:Y:Z") == nil, "Reject non-numeric chapter/verse")
assert(parseVerseId("") == nil, "Reject empty string")

// ---------------------------------------------------------------
// 2. toCanonicalVerseId — KJV passthrough
// ---------------------------------------------------------------
print("\n-- toCanonicalVerseId --")

assertEqual(toCanonicalVerseId("John:3:16", scheme: .kjv), "John:3:16",
            "KJV passthrough")

// LXX Psalm 10 → KJV Psalm 11
assertEqual(toCanonicalVerseId("Psalms:10:1", scheme: .lxx), "Psalms:11:1",
            "LXX Ps 10:1 → KJV Ps 11:1")

// Synodal Joel 2:28 → KJV Joel 3:1
assertEqual(toCanonicalVerseId("Joel:2:28", scheme: .synodal), "Joel:3:1",
            "Synodal Joel 2:28 → KJV Joel 3:1")

// Synodal Malachi 3:19 → KJV Malachi 4:1
assertEqual(toCanonicalVerseId("Malachi:3:19", scheme: .synodal), "Malachi:4:1",
            "Synodal Mal 3:19 → KJV Mal 4:1")

// ---------------------------------------------------------------
// 3. KJV cross-refs resolve as-is (identity)
// ---------------------------------------------------------------
print("\n-- KJV module: identity resolution --")

let kjvRefs = [
    CrossReference(fromVerseId: "John:3:16", toVerseId: "Romans:5:8", referenceType: "parallel"),
    CrossReference(fromVerseId: "John:3:16", toVerseId: "1 John:4:9", referenceType: "related"),
]
let kjvResolved = resolveRefs(queryVerseId: "John:3:16", scheme: .kjv, dbRefs: kjvRefs)
assertEqual(kjvResolved.count, 2, "KJV: 2 refs resolved")
assertEqual(kjvResolved[0].book, "Romans", "KJV ref 1 → Romans")
assertEqual(kjvResolved[0].chapter, 5, "KJV ref 1 → ch 5")
assertEqual(kjvResolved[0].verse, 8, "KJV ref 1 → v 8")
assertEqual(kjvResolved[1].book, "1 John", "KJV ref 2 → 1 John")

// ---------------------------------------------------------------
// 4. LXX module: Psalm numbering shift in cross-refs
// ---------------------------------------------------------------
print("\n-- LXX module: Psalm cross-ref remapping --")

// DB stores KJV Psalm 23:1 as a cross-ref target. LXX module should see it as Psalm 22:1.
let lxxPsalmRefs = [
    CrossReference(fromVerseId: "Psalms:22:1", toVerseId: "Psalms:23:1", referenceType: "parallel"),
]
let lxxResolved = resolveRefs(queryVerseId: "Psalms:21:1", scheme: .lxx, dbRefs: lxxPsalmRefs)
assertEqual(lxxResolved.count, 1, "LXX: 1 ref resolved")
assertEqual(lxxResolved[0].book, "Psalms", "LXX target book")
assertEqual(lxxResolved[0].chapter, 22, "LXX: KJV Ps 23 → LXX Ps 22")
assertEqual(lxxResolved[0].verse, 1, "LXX target verse")

// ---------------------------------------------------------------
// 5. Synodal module: Joel chapter split + superscription offset
// ---------------------------------------------------------------
print("\n-- Synodal module: Joel + Psalm superscription --")

// Cross-ref target in DB: Joel 3:2 (KJV). Synodal should see Joel 2:29.
let synJoelRefs = [
    CrossReference(fromVerseId: "Acts:2:17", toVerseId: "Joel:3:2", referenceType: "quotation"),
]
let synJoelResolved = resolveRefs(queryVerseId: "Acts:2:17", scheme: .synodal, dbRefs: synJoelRefs)
assertEqual(synJoelResolved.count, 1, "Synodal Joel: 1 ref")
assertEqual(synJoelResolved[0].book, "Joel", "Synodal target: Joel")
assertEqual(synJoelResolved[0].chapter, 2, "Synodal: KJV Joel 3:2 → Syn Joel 2")
assertEqual(synJoelResolved[0].verse, 29, "Synodal: KJV Joel 3:2 → Syn v29")

// Cross-ref target in DB: Psalms 51:1 (KJV). Synodal has superscription offset → v2.
let synPsalmRefs = [
    CrossReference(fromVerseId: "2 Samuel:12:13", toVerseId: "Psalms:51:1", referenceType: "allusion"),
]
let synPsalmResolved = resolveRefs(queryVerseId: "2 Samuel:12:13", scheme: .synodal, dbRefs: synPsalmRefs)
assertEqual(synPsalmResolved[0].book, "Psalms", "Synodal Psalm target book")
assertEqual(synPsalmResolved[0].chapter, 50, "Synodal: KJV Ps 51 → Syn Ps 50")
assertEqual(synPsalmResolved[0].verse, 2, "Synodal: KJV v1 → Syn v2 (superscription)")

// ---------------------------------------------------------------
// 6. Synodal Malachi remapping
// ---------------------------------------------------------------
print("\n-- Synodal module: Malachi 4 → 3 --")

let synMalRefs = [
    CrossReference(fromVerseId: "Matthew:11:10", toVerseId: "Malachi:4:5", referenceType: "quotation"),
]
let synMalResolved = resolveRefs(queryVerseId: "Matthew:11:10", scheme: .synodal, dbRefs: synMalRefs)
assertEqual(synMalResolved[0].book, "Malachi", "Synodal Mal book")
assertEqual(synMalResolved[0].chapter, 3, "Synodal: KJV Mal 4 → Syn Mal 3")
assertEqual(synMalResolved[0].verse, 23, "Synodal: KJV Mal 4:5 → Syn Mal 3:23")

// ---------------------------------------------------------------
// 7. Vulgate: Psalm shift (same as LXX for Psalms)
// ---------------------------------------------------------------
print("\n-- Vulgate module: Psalm shift --")

let vulgRefs = [
    CrossReference(fromVerseId: "Hebrews:3:7", toVerseId: "Psalms:95:7", referenceType: "quotation"),
]
let vulgResolved = resolveRefs(queryVerseId: "Hebrews:3:7", scheme: .vulgate, dbRefs: vulgRefs)
assertEqual(vulgResolved[0].book, "Psalms", "Vulgate target book")
assertEqual(vulgResolved[0].chapter, 94, "Vulgate: KJV Ps 95 → Vulg Ps 94")

// ---------------------------------------------------------------
// 8. Non-Psalm, non-special books — all schemes agree
// ---------------------------------------------------------------
print("\n-- Non-Psalm cross-refs identical across schemes --")

let ntRef = CrossReference(fromVerseId: "Matthew:5:1", toVerseId: "Luke:6:20", referenceType: "parallel")
for scheme in [VersificationScheme.kjv, .lxx, .synodal, .vulgate] {
    let r = resolveRefs(queryVerseId: "Matthew:5:1", scheme: scheme, dbRefs: [ntRef])
    assertEqual(r[0].book, "Luke", "\(scheme.rawValue): NT ref book unchanged")
    assertEqual(r[0].chapter, 6, "\(scheme.rawValue): NT ref chapter unchanged")
    assertEqual(r[0].verse, 20, "\(scheme.rawValue): NT ref verse unchanged")
}

// ---------------------------------------------------------------
// 9. Roundtrip: query in LXX, canonicalize, resolve target back to LXX
// ---------------------------------------------------------------
print("\n-- Roundtrip: LXX query → canonical lookup → LXX target --")

// User is in LXX module viewing Psalm 22:1 (= KJV 23:1).
// DB has cross-ref from KJV Ps 23:1 → KJV Ps 100:3
let roundtripRef = CrossReference(fromVerseId: "Psalms:23:1", toVerseId: "Psalms:100:3", referenceType: "related")
let canonQuery = toCanonicalVerseId("Psalms:22:1", scheme: .lxx)
assertEqual(canonQuery, "Psalms:23:1", "LXX Ps 22:1 canonicalizes to KJV Ps 23:1")

let roundtripResolved = resolveRefs(queryVerseId: "Psalms:22:1", scheme: .lxx, dbRefs: [roundtripRef])
assertEqual(roundtripResolved[0].chapter, 99, "KJV Ps 100 → LXX Ps 99")
assertEqual(roundtripResolved[0].verse, 3, "Verse preserved in roundtrip")

// ---------------------------------------------------------------
// 10. Roundtrip: Synodal query → canonical → Synodal target
// ---------------------------------------------------------------
print("\n-- Roundtrip: Synodal Joel query → canonical → Synodal target --")

// Synodal user at Joel 2:30 (= KJV Joel 3:3). DB ref: Joel 3:3 → Revelation 6:12
let synRoundtrip = CrossReference(fromVerseId: "Joel:3:3", toVerseId: "Revelation:6:12", referenceType: "parallel")
let synCanon = toCanonicalVerseId("Joel:2:30", scheme: .synodal)
assertEqual(synCanon, "Joel:3:3", "Synodal Joel 2:30 → KJV Joel 3:3")
let synRtResolved = resolveRefs(queryVerseId: "Joel:2:30", scheme: .synodal, dbRefs: [synRoundtrip])
assertEqual(synRtResolved[0].book, "Revelation", "Synodal roundtrip: book")
assertEqual(synRtResolved[0].chapter, 6, "Synodal roundtrip: chapter")
assertEqual(synRtResolved[0].verse, 12, "Synodal roundtrip: verse (NT unchanged)")

// ---------------------------------------------------------------
// 11. Multiple cross-refs with mixed targets
// ---------------------------------------------------------------
print("\n-- Multiple mixed cross-refs in Synodal --")

let mixedRefs = [
    CrossReference(fromVerseId: "Psalms:51:1", toVerseId: "2 Samuel:12:13", referenceType: "parallel"),
    CrossReference(fromVerseId: "Psalms:51:1", toVerseId: "Psalms:32:5", referenceType: "related"),
    CrossReference(fromVerseId: "Psalms:51:1", toVerseId: "Isaiah:1:18", referenceType: "related"),
]
let mixedResolved = resolveRefs(queryVerseId: "Psalms:50:2", scheme: .synodal, dbRefs: mixedRefs)
assertEqual(mixedResolved.count, 3, "All 3 refs resolved")
assertEqual(mixedResolved[0].book, "2 Samuel", "Mixed ref 1: 2 Samuel (unchanged)")
assertEqual(mixedResolved[1].book, "Psalms", "Mixed ref 2: Psalms")
assertEqual(mixedResolved[1].chapter, 31, "Mixed ref 2: KJV Ps 32 → Syn Ps 31")
assertEqual(mixedResolved[1].verse, 6, "Mixed ref 2: KJV v5 → Syn v6 (superscription)")
assertEqual(mixedResolved[2].book, "Isaiah", "Mixed ref 3: Isaiah (unchanged)")
assertEqual(mixedResolved[2].chapter, 1, "Mixed ref 3: chapter unchanged")

// ---------------------------------------------------------------
// 12. Edge: empty refs list
// ---------------------------------------------------------------
print("\n-- Edge cases --")

let emptyResolved = resolveRefs(queryVerseId: "Genesis:1:1", scheme: .kjv, dbRefs: [])
assertEqual(emptyResolved.count, 0, "Empty refs → empty results")

// Malformed toVerseId in a ref
let badRef = CrossReference(fromVerseId: "Genesis:1:1", toVerseId: "invalid", referenceType: "related")
let badResolved = resolveRefs(queryVerseId: "Genesis:1:1", scheme: .kjv, dbRefs: [badRef])
assertEqual(badResolved.count, 0, "Malformed ref toVerseId skipped")

// ---------------------------------------------------------------
// Summary
// ---------------------------------------------------------------
print("\n=== Results: \(passed) passed, \(failed) failed ===")
if failed > 0 { exit(1) }
