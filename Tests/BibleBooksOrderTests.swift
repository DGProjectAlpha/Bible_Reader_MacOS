// BibleBooksOrderTests.swift
// Run on macOS with: swift Tests/BibleBooksOrderTests.swift
//
// Self-contained test: verifies BibleBooks canonical ordering, testament splits,
// chapter counts, and sortIndex behavior.

import Foundation

// MARK: - Inline BibleBooks (mirrors production code)

enum Testament { case old, new }

enum BibleBooks {
    static let all: [String] = [
        "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy",
        "Joshua", "Judges", "Ruth", "1 Samuel", "2 Samuel",
        "1 Kings", "2 Kings", "1 Chronicles", "2 Chronicles",
        "Ezra", "Nehemiah", "Esther", "Job", "Psalms",
        "Proverbs", "Ecclesiastes", "Song of Solomon", "Isaiah", "Jeremiah",
        "Lamentations", "Ezekiel", "Daniel", "Hosea", "Joel",
        "Amos", "Obadiah", "Jonah", "Micah", "Nahum",
        "Habakkuk", "Zephaniah", "Haggai", "Zechariah", "Malachi",
        "Matthew", "Mark", "Luke", "John", "Acts",
        "Romans", "1 Corinthians", "2 Corinthians", "Galatians", "Ephesians",
        "Philippians", "Colossians", "1 Thessalonians", "2 Thessalonians",
        "1 Timothy", "2 Timothy", "Titus", "Philemon", "Hebrews",
        "James", "1 Peter", "2 Peter", "1 John", "2 John",
        "3 John", "Jude", "Revelation"
    ]

    static let oldTestament: [String] = Array(all[0..<39])
    static let newTestament: [String] = Array(all[39..<66])

    static let chapterCounts: [String: Int] = [
        "Genesis": 50, "Exodus": 40, "Leviticus": 27, "Numbers": 36, "Deuteronomy": 34,
        "Joshua": 24, "Judges": 21, "Ruth": 4, "1 Samuel": 31, "2 Samuel": 24,
        "1 Kings": 22, "2 Kings": 25, "1 Chronicles": 29, "2 Chronicles": 36,
        "Ezra": 10, "Nehemiah": 13, "Esther": 10, "Job": 42, "Psalms": 150,
        "Proverbs": 31, "Ecclesiastes": 12, "Song of Solomon": 8, "Isaiah": 66, "Jeremiah": 52,
        "Lamentations": 5, "Ezekiel": 48, "Daniel": 12, "Hosea": 14, "Joel": 3,
        "Amos": 9, "Obadiah": 1, "Jonah": 4, "Micah": 7, "Nahum": 3,
        "Habakkuk": 3, "Zephaniah": 3, "Haggai": 2, "Zechariah": 14, "Malachi": 4,
        "Matthew": 28, "Mark": 16, "Luke": 24, "John": 21, "Acts": 28,
        "Romans": 16, "1 Corinthians": 16, "2 Corinthians": 13, "Galatians": 6, "Ephesians": 6,
        "Philippians": 4, "Colossians": 4, "1 Thessalonians": 5, "2 Thessalonians": 3,
        "1 Timothy": 6, "2 Timothy": 4, "Titus": 3, "Philemon": 1, "Hebrews": 13,
        "James": 5, "1 Peter": 5, "2 Peter": 3, "1 John": 5, "2 John": 1,
        "3 John": 1, "Jude": 1, "Revelation": 22
    ]

    static func sortIndex(for bookName: String) -> Int? {
        all.firstIndex(of: bookName)
    }

    static func testament(for bookName: String) -> Testament? {
        guard let index = all.firstIndex(of: bookName) else { return nil }
        return index < 39 ? .old : .new
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

// --- 1. Total book count is 66 ---
assert(BibleBooks.all.count == 66,
       "Expected 66 books, got \(BibleBooks.all.count)")

// --- 2. OT has 39 books ---
assert(BibleBooks.oldTestament.count == 39,
       "Expected 39 OT books, got \(BibleBooks.oldTestament.count)")

// --- 3. NT has 27 books ---
assert(BibleBooks.newTestament.count == 27,
       "Expected 27 NT books, got \(BibleBooks.newTestament.count)")

// --- 4. First book is Genesis ---
assert(BibleBooks.all.first == "Genesis",
       "First book should be Genesis, got \(BibleBooks.all.first ?? "nil")")

// --- 5. Last book is Revelation ---
assert(BibleBooks.all.last == "Revelation",
       "Last book should be Revelation, got \(BibleBooks.all.last ?? "nil")")

// --- 6. OT ends with Malachi ---
assert(BibleBooks.oldTestament.last == "Malachi",
       "Last OT book should be Malachi, got \(BibleBooks.oldTestament.last ?? "nil")")

// --- 7. NT starts with Matthew ---
assert(BibleBooks.newTestament.first == "Matthew",
       "First NT book should be Matthew, got \(BibleBooks.newTestament.first ?? "nil")")

// --- 8. sortIndex returns correct indices ---
assert(BibleBooks.sortIndex(for: "Genesis") == 0,
       "Genesis sortIndex should be 0")
assert(BibleBooks.sortIndex(for: "Malachi") == 38,
       "Malachi sortIndex should be 38")
assert(BibleBooks.sortIndex(for: "Matthew") == 39,
       "Matthew sortIndex should be 39")
assert(BibleBooks.sortIndex(for: "Revelation") == 65,
       "Revelation sortIndex should be 65")

// --- 9. sortIndex returns nil for unknown book ---
assert(BibleBooks.sortIndex(for: "Tobit") == nil,
       "Unknown book should return nil sortIndex")

// --- 10. OT books sort before NT books ---
do {
    let genIdx = BibleBooks.sortIndex(for: "Genesis")!
    let revIdx = BibleBooks.sortIndex(for: "Revelation")!
    let mattIdx = BibleBooks.sortIndex(for: "Matthew")!
    let malIdx = BibleBooks.sortIndex(for: "Malachi")!
    assert(genIdx < malIdx && malIdx < mattIdx && mattIdx < revIdx,
           "Canonical order: Gen < Mal < Matt < Rev")
}

// --- 11. Pentateuch order ---
do {
    let pent = ["Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy"]
    let indices = pent.compactMap { BibleBooks.sortIndex(for: $0) }
    assert(indices == [0, 1, 2, 3, 4],
           "Pentateuch should be indices 0-4, got \(indices)")
}

// --- 12. Gospels order ---
do {
    let gospels = ["Matthew", "Mark", "Luke", "John"]
    let indices = gospels.compactMap { BibleBooks.sortIndex(for: $0) }
    assert(indices == [39, 40, 41, 42],
           "Gospels should be indices 39-42, got \(indices)")
}

// --- 13. Sorting a shuffled list by sortIndex produces canonical order ---
do {
    var shuffled = ["Revelation", "Genesis", "Psalms", "Matthew", "Ruth", "Romans", "Malachi"]
    shuffled.sort { (BibleBooks.sortIndex(for: $0) ?? 999) < (BibleBooks.sortIndex(for: $1) ?? 999) }
    let expected = ["Genesis", "Ruth", "Psalms", "Malachi", "Matthew", "Romans", "Revelation"]
    assert(shuffled == expected,
           "Sorted order should be \(expected), got \(shuffled)")
}

// --- 14. Every book has a chapter count ---
do {
    let missing = BibleBooks.all.filter { BibleBooks.chapterCounts[$0] == nil }
    assert(missing.isEmpty,
           "Books missing chapter counts: \(missing)")
}

// --- 15. All chapter counts are positive ---
do {
    let nonPositive = BibleBooks.chapterCounts.filter { $0.value <= 0 }
    assert(nonPositive.isEmpty,
           "Books with non-positive chapter counts: \(nonPositive)")
}

// --- 16. Testament assignment ---
do {
    assert(BibleBooks.testament(for: "Genesis") == .old, "Genesis should be OT")
    assert(BibleBooks.testament(for: "Malachi") == .old, "Malachi should be OT")
    assert(BibleBooks.testament(for: "Matthew") == .new, "Matthew should be NT")
    assert(BibleBooks.testament(for: "Revelation") == .new, "Revelation should be NT")
    assert(BibleBooks.testament(for: "FakeBook") == nil, "Unknown book testament should be nil")
}

// --- 17. No duplicate book names ---
do {
    let unique = Set(BibleBooks.all)
    assert(unique.count == BibleBooks.all.count,
           "Duplicate book names found: \(BibleBooks.all.count - unique.count) dupes")
}

// --- 18. Spot-check well-known chapter counts ---
do {
    assert(BibleBooks.chapterCounts["Genesis"] == 50, "Genesis should have 50 chapters")
    assert(BibleBooks.chapterCounts["Psalms"] == 150, "Psalms should have 150 chapters")
    assert(BibleBooks.chapterCounts["Obadiah"] == 1, "Obadiah should have 1 chapter")
    assert(BibleBooks.chapterCounts["Revelation"] == 22, "Revelation should have 22 chapters")
}

// --- Summary ---
print("\n===== Bible Books Order Tests =====")
print("Passed: \(passed)  Failed: \(failed)")
if failed > 0 {
    print("SOME TESTS FAILED")
    exit(1)
} else {
    print("ALL TESTS PASSED")
}
