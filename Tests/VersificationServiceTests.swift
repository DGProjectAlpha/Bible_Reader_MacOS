// VersificationServiceTests.swift
// Run on macOS with: swift Tests/VersificationServiceTests.swift
//
// This file is self-contained — it duplicates the minimal types needed
// so it can compile standalone without the full Xcode project.

import Foundation

// MARK: - Minimal type stubs (duplicated for standalone test)

enum VersificationScheme: String { case kjv = "kjv", lxx = "lxx", synodal = "synodal", vulgate = "vulgate" }

struct CanonicalRef: Hashable {
    let book: String; let chapter: Int; let verse: Int
    var id: String { "\(book):\(chapter):\(verse)" }
}

// Inline BibleBooks.chapterCounts for Psalms/Joel/Malachi/Daniel
let chapterCounts: [String: Int] = ["Psalms": 150, "Joel": 3, "Malachi": 4, "Daniel": 12]

// MARK: - Inline VersificationService (mirrors production code)

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
        var map = [Int: Int]()
        map[9] = 9; map[10] = 9
        for kjv in 11...113 { map[kjv] = kjv - 1 }
        map[114] = 113; map[115] = 113; map[116] = 114
        for kjv in 117...146 { map[kjv] = kjv - 1 }
        map[147] = 146
        return map
    }()

    private static let lxxPsalmToKjv: [Int: Int] = {
        var map = [Int: Int]()
        map[9] = 9
        for lxx in 10...112 { map[lxx] = lxx + 1 }
        map[113] = 114; map[114] = 116; map[115] = 116
        for lxx in 116...145 { map[lxx] = lxx + 1 }
        map[146] = 147; map[147] = 147
        return map
    }()

    private static let psalmsWithSuperscriptionOffset: Set<Int> = [
        3,4,5,6,7,8,9,12,13,18,19,20,21,22,30,31,34,36,38,39,
        40,41,42,44,45,46,47,48,49,51,52,53,54,55,56,57,58,59,60,
        61,62,63,64,65,66,67,68,69,70,75,76,77,80,81,83,84,85,88,
        89,92,98,100,101,102,108,109,110,140,142
    ]

    // -- LXX --
    private func lxxToCanonical(book: String, chapter: Int, verse: Int) -> CanonicalRef {
        let nb = lxxBookToCanonical(book)
        if nb == "Psalms", let kjv = Self.lxxPsalmToKjv[chapter] {
            return CanonicalRef(book: "Psalms", chapter: kjv, verse: verse)
        }
        return CanonicalRef(book: nb, chapter: chapter, verse: verse)
    }
    private func canonicalToLxx(_ ref: CanonicalRef) -> (String, Int, Int) {
        if ref.book == "Psalms", let lxx = Self.kjvPsalmToLxx[ref.chapter] {
            return ("Psalms", lxx, ref.verse)
        }
        return (ref.book, ref.chapter, ref.verse)
    }

    // -- Synodal --
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
        if ref.book == "Malachi" && ref.chapter == 4 {
            return ("Malachi", 3, ref.verse + 18)
        }
        return (ref.book, ref.chapter, ref.verse)
    }

    // -- Vulgate --
    private func vulgateToCanonical(book: String, chapter: Int, verse: Int) -> CanonicalRef {
        if book == "Psalms", let kjv = Self.lxxPsalmToKjv[chapter] {
            return CanonicalRef(book: "Psalms", chapter: kjv, verse: verse)
        }
        return CanonicalRef(book: book, chapter: chapter, verse: verse)
    }
    private func canonicalToVulgate(_ ref: CanonicalRef) -> (String, Int, Int) {
        if ref.book == "Psalms", let lxx = Self.kjvPsalmToLxx[ref.chapter] {
            return ("Psalms", lxx, ref.verse)
        }
        return (ref.book, ref.chapter, ref.verse)
    }

    private func lxxBookToCanonical(_ book: String) -> String {
        switch book {
        case "1 Kingdoms", "1 Reigns": return "1 Samuel"
        case "2 Kingdoms", "2 Reigns": return "2 Samuel"
        case "3 Kingdoms", "3 Reigns": return "1 Kings"
        case "4 Kingdoms", "4 Reigns": return "2 Kings"
        case "1 Paralipomenon": return "1 Chronicles"
        case "2 Paralipomenon": return "2 Chronicles"
        case "1 Esdras": return "Ezra"
        case "2 Esdras": return "Nehemiah"
        default: return book
        }
    }
}

// MARK: - Test Harness

var passed = 0
var failed = 0

func assert(_ condition: Bool, _ msg: String, file: String = #file, line: Int = #line) {
    if condition {
        passed += 1
    } else {
        failed += 1
        print("FAIL [\(line)]: \(msg)")
    }
}

let svc = VersificationService.shared

// --- 1. Identity: KJV → KJV is no-op ---
do {
    let r = svc.convert(book: "Genesis", chapter: 1, verse: 1, from: .kjv, to: .kjv)
    assert(r.book == "Genesis" && r.chapter == 1 && r.verse == 1,
           "KJV→KJV identity failed: got \(r)")
}

// --- 2. Psalm numbering: KJV→LXX ---
do {
    // KJV Psalm 11 → LXX Psalm 10
    let r = svc.convert(book: "Psalms", chapter: 11, verse: 3, from: .kjv, to: .lxx)
    assert(r.0 == "Psalms" && r.1 == 10 && r.2 == 3,
           "KJV Ps 11:3 → LXX expected Ps 10:3, got \(r)")
}

// --- 3. Psalm numbering: LXX→KJV ---
do {
    // LXX Psalm 10 → KJV Psalm 11
    let r = svc.convert(book: "Psalms", chapter: 10, verse: 5, from: .lxx, to: .kjv)
    assert(r.0 == "Psalms" && r.1 == 11 && r.2 == 5,
           "LXX Ps 10:5 → KJV expected Ps 11:5, got \(r)")
}

// --- 4. Psalm 9: KJV→LXX stays 9 (merge point) ---
do {
    let r = svc.convert(book: "Psalms", chapter: 9, verse: 1, from: .kjv, to: .lxx)
    assert(r.0 == "Psalms" && r.1 == 9 && r.2 == 1,
           "KJV Ps 9:1 → LXX expected Ps 9:1, got \(r)")
}

// --- 5. Psalm numbering roundtrip: KJV→LXX→KJV ---
do {
    let mid = svc.convert(book: "Psalms", chapter: 50, verse: 10, from: .kjv, to: .lxx)
    let back = svc.convert(book: mid.0, chapter: mid.1, verse: mid.2, from: .lxx, to: .kjv)
    assert(back.0 == "Psalms" && back.1 == 50 && back.2 == 10,
           "KJV Ps50:10 roundtrip failed: mid=\(mid) back=\(back)")
}

// --- 6. Synodal Joel: Joel 2:28 (Syn) → Joel 3:1 (KJV) ---
do {
    let r = svc.convert(book: "Joel", chapter: 2, verse: 28, from: .synodal, to: .kjv)
    assert(r.0 == "Joel" && r.1 == 3 && r.2 == 1,
           "Synodal Joel 2:28 → KJV expected Joel 3:1, got \(r)")
}

// --- 7. KJV Joel 3:1 → Synodal Joel 2:28 ---
do {
    let r = svc.convert(book: "Joel", chapter: 3, verse: 1, from: .kjv, to: .synodal)
    assert(r.0 == "Joel" && r.1 == 2 && r.2 == 28,
           "KJV Joel 3:1 → Synodal expected Joel 2:28, got \(r)")
}

// --- 8. Synodal Malachi: Mal 3:19 (Syn) → Mal 4:1 (KJV) ---
do {
    let r = svc.convert(book: "Malachi", chapter: 3, verse: 19, from: .synodal, to: .kjv)
    assert(r.0 == "Malachi" && r.1 == 4 && r.2 == 1,
           "Synodal Mal 3:19 → KJV expected Mal 4:1, got \(r)")
}

// --- 9. KJV Malachi 4:1 → Synodal Mal 3:19 ---
do {
    let r = svc.convert(book: "Malachi", chapter: 4, verse: 1, from: .kjv, to: .synodal)
    assert(r.0 == "Malachi" && r.1 == 3 && r.2 == 19,
           "KJV Mal 4:1 → Synodal expected Mal 3:19, got \(r)")
}

// --- 10. Synodal Psalms superscription offset: KJV Ps 3:1 → Synodal Ps 3:2 ---
do {
    let r = svc.convert(book: "Psalms", chapter: 3, verse: 1, from: .kjv, to: .synodal)
    // Ps 3 has no LXX psalm renumber (< 9), and is in superscription set → verse +1
    assert(r.2 == 2,
           "KJV Ps 3:1 → Synodal expected verse 2, got verse \(r.2)")
}

// --- 11. Synodal Psalms superscription reverse: Syn Ps 3:2 → KJV Ps 3:1 ---
do {
    let r = svc.convert(book: "Psalms", chapter: 3, verse: 2, from: .synodal, to: .kjv)
    assert(r.2 == 1,
           "Synodal Ps 3:2 → KJV expected verse 1, got verse \(r.2)")
}

// --- 12. Vulgate Psalms: same as LXX psalm numbering ---
do {
    let r = svc.convert(book: "Psalms", chapter: 23, verse: 1, from: .kjv, to: .vulgate)
    // KJV 23 → LXX/Vulgate 22
    assert(r.0 == "Psalms" && r.1 == 22 && r.2 == 1,
           "KJV Ps 23:1 → Vulgate expected Ps 22:1, got \(r)")
}

// --- 13. LXX book name normalization ---
do {
    let r = svc.convert(book: "1 Kingdoms", chapter: 5, verse: 3, from: .lxx, to: .kjv)
    assert(r.0 == "1 Samuel" && r.1 == 5 && r.2 == 3,
           "LXX '1 Kingdoms' → KJV expected '1 Samuel', got \(r)")
}

// --- 14. Non-psalm, non-Joel, non-Malachi books pass through unchanged ---
do {
    let r = svc.convert(book: "Romans", chapter: 8, verse: 28, from: .synodal, to: .kjv)
    assert(r.0 == "Romans" && r.1 == 8 && r.2 == 28,
           "NT passthrough failed: got \(r)")
}

// --- 15. Cross-scheme: Synodal → LXX for Psalm 51 ---
do {
    // KJV Ps 51 → LXX Ps 50 (via kjvPsalmToLxx), and synodal adds +1 verse offset
    // Synodal Ps 50:3 → canonical (KJV Ps 51, verse 3-1=2) → LXX Ps 50:2
    let r = svc.convert(book: "Psalms", chapter: 50, verse: 3, from: .synodal, to: .lxx)
    // synodal ch 50 → lxxPsalmToKjv[50] = 51, superscription offset: v3-1=2
    // canonical: Ps 51:2 → kjvPsalmToLxx[51] = 50
    assert(r.0 == "Psalms" && r.1 == 50 && r.2 == 2,
           "Synodal Ps 50:3 → LXX expected Ps 50:2, got \(r)")
}

// --- 16. Joel roundtrip: KJV→Synodal→KJV ---
do {
    let mid = svc.convert(book: "Joel", chapter: 3, verse: 5, from: .kjv, to: .synodal)
    let back = svc.convert(book: mid.0, chapter: mid.1, verse: mid.2, from: .synodal, to: .kjv)
    assert(back.0 == "Joel" && back.1 == 3 && back.2 == 5,
           "Joel 3:5 KJV roundtrip failed: mid=\(mid) back=\(back)")
}

// --- Summary ---
print("\n===== Versification Tests =====")
print("Passed: \(passed)  Failed: \(failed)")
if failed > 0 {
    print("SOME TESTS FAILED")
    exit(1)
} else {
    print("ALL TESTS PASSED")
}
