import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Wizard Step

enum ExportWizardStep: Int, CaseIterable {
    case contentSelection = 0
    case ordering = 1
    case formatting = 2
    case export = 3

    var title: String {
        switch self {
        case .contentSelection: "Select Content"
        case .ordering: "Order & Grouping"
        case .formatting: "Bible Version & Formatting"
        case .export: "Export"
        }
    }

    var canGoBack: Bool { self != .contentSelection }
    var canGoNext: Bool { self != .export }
}

// MARK: - Export Ordering

enum ExportOrdering: String, CaseIterable, Identifiable {
    case byBookOrder
    case byDateNewest
    case byDateOldest
    case byColor

    var id: String { rawValue }

    var label: String {
        switch self {
        case .byBookOrder: "By Book Order"
        case .byDateNewest: "By Date Added (Newest First)"
        case .byDateOldest: "By Date Added (Oldest First)"
        case .byColor: "By Color"
        }
    }
}

// MARK: - Export Format

enum ExportFormat: String, CaseIterable, Identifiable {
    case pdf
    case plainText
    case markdown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pdf: "PDF"
        case .plainText: "Plain Text (.txt)"
        case .markdown: "Markdown (.md)"
        }
    }

    var fileExtension: String {
        switch self {
        case .pdf: "pdf"
        case .plainText: "txt"
        case .markdown: "md"
        }
    }

    var utType: UTType {
        switch self {
        case .pdf: .pdf
        case .plainText: .plainText
        case .markdown: UTType(filenameExtension: "md") ?? .plainText
        }
    }
}

// MARK: - Export Item (unified wrapper)

enum ExportItemType: String, Hashable {
    case bookmark, highlight, note
}

struct ExportItem: Identifiable, Hashable {
    let id: UUID
    let type: ExportItemType
    let verseId: String
    let previewText: String
    let color: BookmarkColor?
    let createdAt: Date?

    init(bookmark: Bookmark) {
        self.id = bookmark.id
        self.type = .bookmark
        self.verseId = bookmark.verseId
        self.previewText = bookmark.note.isEmpty ? "Bookmark" : String(bookmark.note.prefix(50))
        self.color = bookmark.color
        self.createdAt = bookmark.createdAt
    }

    init(highlight: HighlightedVerse) {
        self.id = highlight.id
        self.type = .highlight
        self.verseId = highlight.verseId
        self.previewText = "Highlight"
        self.color = highlight.color
        self.createdAt = nil
    }

    init(note: Note) {
        self.id = note.id
        self.type = .note
        self.verseId = note.verseId
        self.previewText = String(note.text.prefix(50))
        self.color = nil
        self.createdAt = note.createdAt
    }

    var verseReference: String {
        // Convert "GEN.1.1" → "Genesis 1:1" style display
        let parts = verseId.split(separator: ".")
        guard parts.count >= 3 else { return verseId }
        let bookAbbrev = String(parts[0])
        let chapter = String(parts[1])
        let verse = String(parts[2])
        let bookName = ExportItem.bookName(from: bookAbbrev)
        return "\(bookName) \(chapter):\(verse)"
    }

    /// Canonical book order index for sorting
    var bookOrderIndex: Int {
        let parts = verseId.split(separator: ".")
        guard let first = parts.first else { return 999 }
        return ExportItem.canonicalBookIndex(String(first))
    }

    var chapterNumber: Int {
        let parts = verseId.split(separator: ".")
        guard parts.count >= 2, let ch = Int(parts[1]) else { return 0 }
        return ch
    }

    var verseNumber: Int {
        let parts = verseId.split(separator: ".")
        guard parts.count >= 3, let v = Int(parts[2]) else { return 0 }
        return v
    }

    private static let bookAbbreviations: [(abbrev: String, name: String)] = [
        ("GEN", "Genesis"), ("EXO", "Exodus"), ("LEV", "Leviticus"), ("NUM", "Numbers"),
        ("DEU", "Deuteronomy"), ("JOS", "Joshua"), ("JDG", "Judges"), ("RUT", "Ruth"),
        ("1SA", "1 Samuel"), ("2SA", "2 Samuel"), ("1KI", "1 Kings"), ("2KI", "2 Kings"),
        ("1CH", "1 Chronicles"), ("2CH", "2 Chronicles"), ("EZR", "Ezra"), ("NEH", "Nehemiah"),
        ("EST", "Esther"), ("JOB", "Job"), ("PSA", "Psalms"), ("PRO", "Proverbs"),
        ("ECC", "Ecclesiastes"), ("SNG", "Song of Solomon"), ("ISA", "Isaiah"), ("JER", "Jeremiah"),
        ("LAM", "Lamentations"), ("EZK", "Ezekiel"), ("DAN", "Daniel"), ("HOS", "Hosea"),
        ("JOL", "Joel"), ("AMO", "Amos"), ("OBA", "Obadiah"), ("JON", "Jonah"),
        ("MIC", "Micah"), ("NAM", "Nahum"), ("HAB", "Habakkuk"), ("ZEP", "Zephaniah"),
        ("HAG", "Haggai"), ("ZEC", "Zechariah"), ("MAL", "Malachi"),
        ("MAT", "Matthew"), ("MRK", "Mark"), ("LUK", "Luke"), ("JHN", "John"),
        ("ACT", "Acts"), ("ROM", "Romans"), ("1CO", "1 Corinthians"), ("2CO", "2 Corinthians"),
        ("GAL", "Galatians"), ("EPH", "Ephesians"), ("PHP", "Philippians"), ("COL", "Colossians"),
        ("1TH", "1 Thessalonians"), ("2TH", "2 Thessalonians"), ("1TI", "1 Timothy"),
        ("2TI", "2 Timothy"), ("TIT", "Titus"), ("PHM", "Philemon"), ("HEB", "Hebrews"),
        ("JAS", "James"), ("1PE", "1 Peter"), ("2PE", "2 Peter"), ("1JN", "1 John"),
        ("2JN", "2 John"), ("3JN", "3 John"), ("JUD", "Jude"), ("REV", "Revelation")
    ]

    static func bookName(from abbreviation: String) -> String {
        let upper = abbreviation.uppercased()
        return bookAbbreviations.first(where: { $0.abbrev == upper })?.name ?? abbreviation
    }

    static func canonicalBookIndex(_ abbreviation: String) -> Int {
        let upper = abbreviation.uppercased()
        return bookAbbreviations.firstIndex(where: { $0.abbrev == upper }) ?? 999
    }
}

// MARK: - Font Configuration

struct ExportFontConfig: Equatable {
    var family: String
    var size: CGFloat
    var isBold: Bool
    var isItalic: Bool

    var nsFont: NSFont {
        var font: NSFont
        if family == ".AppleSystemUIFont" || family == "System" || family == "" {
            font = NSFont.systemFont(ofSize: size, weight: isBold ? .bold : .regular)
        } else {
            font = NSFont(name: family, size: size) ?? NSFont.systemFont(ofSize: size)
            if isBold {
                font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
        }
        if isItalic {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        return font
    }

    static let defaultReference = ExportFontConfig(family: "System", size: 14, isBold: true, isItalic: false)
    static let defaultNote = ExportFontConfig(family: "System", size: 12, isBold: false, isItalic: true)

    @MainActor
    static func defaultVerseText(from uiState: UIStateStore) -> ExportFontConfig {
        ExportFontConfig(family: uiState.fontFamily, size: uiState.fontSize, isBold: false, isItalic: false)
    }
}

// MARK: - Export Progress

enum ExportState: Equatable {
    case idle
    case exporting(progress: Double)
    case completed(url: URL)
    case failed(message: String)
}

// MARK: - ExportWizardStore

@MainActor @Observable
final class ExportWizardStore {

    // MARK: Step Navigation

    var currentStep: ExportWizardStep = .contentSelection

    func goNext() {
        guard let next = ExportWizardStep(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = next
    }

    func goBack() {
        guard let prev = ExportWizardStep(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = prev
    }

    // MARK: Step 1 — Content Selection

    var bookmarkItems: [ExportItem] = []
    var highlightItems: [ExportItem] = []
    var noteItems: [ExportItem] = []

    var selectedItemIds: Set<UUID> = []

    var selectedItems: [ExportItem] {
        (bookmarkItems + highlightItems + noteItems).filter { selectedItemIds.contains($0.id) }
    }

    var hasSelection: Bool { !selectedItemIds.isEmpty }

    func selectAll(for type: ExportItemType) {
        let items: [ExportItem]
        switch type {
        case .bookmark: items = bookmarkItems
        case .highlight: items = highlightItems
        case .note: items = noteItems
        }
        for item in items { selectedItemIds.insert(item.id) }
    }

    func deselectAll(for type: ExportItemType) {
        let items: [ExportItem]
        switch type {
        case .bookmark: items = bookmarkItems
        case .highlight: items = highlightItems
        case .note: items = noteItems
        }
        for item in items { selectedItemIds.remove(item.id) }
    }

    func toggleItem(_ id: UUID) {
        if selectedItemIds.contains(id) {
            selectedItemIds.remove(id)
        } else {
            selectedItemIds.insert(id)
        }
    }

    func isSelected(_ id: UUID) -> Bool {
        selectedItemIds.contains(id)
    }

    func allSelected(for type: ExportItemType) -> Bool {
        let items: [ExportItem]
        switch type {
        case .bookmark: items = bookmarkItems
        case .highlight: items = highlightItems
        case .note: items = noteItems
        }
        return !items.isEmpty && items.allSatisfy { selectedItemIds.contains($0.id) }
    }

    // MARK: Step 2 — Ordering & Grouping

    var ordering: ExportOrdering = .byBookOrder
    var groupByBook: Bool = true

    // MARK: Step 3 — Bible Version & Formatting

    var selectedModuleIds: Set<String> = []
    var referenceFontConfig: ExportFontConfig = .defaultReference
    var verseTextFontConfig: ExportFontConfig = ExportFontConfig(family: "System", size: 14, isBold: false, isItalic: false)
    var noteFontConfig: ExportFontConfig = .defaultNote

    // MARK: Step 4 — Export

    var exportFormat: ExportFormat = .pdf
    var exportState: ExportState = .idle
    var exportTask: Task<Void, Never>?

    func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
        exportState = .idle
    }

    // MARK: - Initialization

    /// Populate items from UserDataStore data
    func loadItems(from userDataStore: UserDataStore) {
        bookmarkItems = userDataStore.bookmarks.map { ExportItem(bookmark: $0) }
        highlightItems = userDataStore.highlights.map { ExportItem(highlight: $0) }
        noteItems = userDataStore.notes.map { ExportItem(note: $0) }
    }

    /// Initialize verse text font from user's settings
    func initializeFonts(from uiState: UIStateStore) {
        verseTextFontConfig = .defaultVerseText(from: uiState)
    }

    /// Set default selected module from active module
    func initializeModules(activeModuleId: String) {
        selectedModuleIds = [activeModuleId]
    }

    // MARK: - Sorted Items

    func sortedSelectedItems() -> [ExportItem] {
        let items = selectedItems
        switch ordering {
        case .byBookOrder:
            return items.sorted {
                if $0.bookOrderIndex != $1.bookOrderIndex { return $0.bookOrderIndex < $1.bookOrderIndex }
                if $0.chapterNumber != $1.chapterNumber { return $0.chapterNumber < $1.chapterNumber }
                return $0.verseNumber < $1.verseNumber
            }
        case .byDateNewest:
            return items.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        case .byDateOldest:
            return items.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        case .byColor:
            return items.sorted {
                let c0 = $0.color?.rawValue ?? "zzz"
                let c1 = $1.color?.rawValue ?? "zzz"
                if c0 != c1 { return c0 < c1 }
                return $0.bookOrderIndex < $1.bookOrderIndex
            }
        }
    }

    func groupedSelectedItems() -> [(bookName: String, items: [ExportItem])] {
        let sorted = sortedSelectedItems()
        guard groupByBook else { return [("", sorted)] }

        var groups: [(bookName: String, items: [ExportItem])] = []
        var currentBook = ""
        var currentItems: [ExportItem] = []

        for item in sorted {
            let parts = item.verseId.split(separator: ".")
            let book = parts.first.map { ExportItem.bookName(from: String($0)) } ?? "Unknown"
            if book != currentBook {
                if !currentItems.isEmpty {
                    groups.append((currentBook, currentItems))
                }
                currentBook = book
                currentItems = [item]
            } else {
                currentItems.append(item)
            }
        }
        if !currentItems.isEmpty {
            groups.append((currentBook, currentItems))
        }
        return groups
    }

    // MARK: - Validation

    var canProceedFromStep1: Bool { hasSelection }
    var canProceedFromStep3: Bool { !selectedModuleIds.isEmpty }

    var canProceedFromCurrentStep: Bool {
        switch currentStep {
        case .contentSelection: return canProceedFromStep1
        case .ordering: return true
        case .formatting: return canProceedFromStep3
        case .export: return true
        }
    }
}
