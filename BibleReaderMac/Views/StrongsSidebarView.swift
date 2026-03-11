import SwiftUI

// MARK: - Strong's Concordance Sidebar

/// Displays Strong's concordance data for the clicked word, matching the Windows version layout:
/// 1. The specific word's concordance entry shown prominently at top
/// 2. Greek/Hebrew text, transliteration, pronunciation, definition, derivation, KJV usage
/// 3. Collapsible "Verses using this word" section
/// 4. "Similar numbers" section below a divider
/// 5. Other words in the verse as a secondary expandable list
struct StrongsSidebarView: View {
    @EnvironmentObject var store: BibleStore
    let verseRef: String          // e.g. "Genesis 1:1"
    let verseId: String           // e.g. "Genesis:1:1"
    let translationFilePath: String
    @Binding var isVisible: Bool
    var initialWordIndex: Int?    // auto-expand this word when loaded

    @State private var resolvedTags: [ResolvedWordTag] = []
    @State private var isLoading = false
    @State private var focusedEntry: StrongsEntry?        // the clicked word's primary Strong's entry
    @State private var focusedWord: String = ""           // the clicked word text
    @State private var focusedNumber: String = ""         // the clicked Strong's number

    // Verses using this number
    @State private var versesOpen = false
    @State private var verseRefs: [StrongsService.VerseReference]?
    @State private var isLoadingVerses = false

    // Similar entries
    @State private var similarExact: StrongsEntry?
    @State private var similarEntries: [StrongsEntry] = []
    @State private var isLoadingSimilar = false
    @State private var expandedSimilarNum: String?

    // Per-similar-entry verse data
    @State private var similarVersesOpen: Set<String> = []
    @State private var similarVerseRefs: [String: [StrongsService.VerseReference]] = [:]
    @State private var similarVersesLoading: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if isLoading {
                ProgressView("Loading concordance...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if focusedEntry != nil {
                focusedEntryView
            } else if resolvedTags.isEmpty {
                emptyState
            } else {
                // Fallback: no specific word focused, show word list
                wordListFallback
            }
        }
        .frame(minWidth: 260, idealWidth: 320, maxWidth: 420)
        .vibrancyBackground(material: .sidebar)
        .onAppear { loadStrongsData() }
        .onChange(of: verseId) { loadStrongsData() }
        .onChange(of: initialWordIndex) {
            if let idx = initialWordIndex {
                focusOnWord(atIndex: idx)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Strong's Concordance")
                    .font(.headline)
                Text(verseRef)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isVisible = false } }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.borderless)
            .help("Close concordance sidebar")
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .glassHeader()
    }

    // MARK: - Focused Entry View (main concordance display)

    private var focusedEntryView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let entry = focusedEntry {
                    // Primary entry detail
                    entryDetailSection(entry)

                    // Verses using this word
                    versesSection

                    // Similar numbers
                    similarSection
                }
            }
        }
    }

    // MARK: - Entry Detail Section

    private func entryDetailSection(_ entry: StrongsEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Strong's number prominently at top
            HStack(alignment: .center, spacing: 10) {
                Text(entry.number)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(strongsBadgeColor(entry.number))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    if !focusedWord.isEmpty {
                        Text(focusedWord)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    Text(entry.testament == .old ? "Hebrew" : "Greek")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Lemma (original Hebrew/Greek word)
            if !entry.lemma.isEmpty {
                Text(entry.lemma)
                    .font(.system(size: 32, design: .serif))
                    .foregroundStyle(.primary)
                    .environment(\.layoutDirection, entry.testament == .old ? .rightToLeft : .leftToRight)
            }

            // Transliteration + pronunciation
            HStack(spacing: 8) {
                if !entry.transliteration.isEmpty {
                    Text(entry.transliteration)
                        .font(.system(size: 14).italic())
                        .foregroundStyle(.primary)
                }
                if let pron = entry.pronunciation, !pron.isEmpty {
                    Text("(\(pron))")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            // Definition
            if let def = entry.strongsDefinition, !def.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    sectionLabel("Definition")
                    Text(cleanDefinition(def))
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Derivation
            if let deriv = entry.derivation, !deriv.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    sectionLabel("Derivation")
                    Text(cleanDefinition(deriv))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // KJV Usage with parsed pills
            if let kjv = entry.kjvDefinition, !kjv.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        sectionLabel("KJV Usage")
                        let total = totalUsageCount(kjv)
                        if let total {
                            Text("(\(total) occurrences)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    let items = parseKjvUsage(kjv)
                    if !items.isEmpty {
                        FlowLayoutCompact {
                            ForEach(items.indices, id: \.self) { i in
                                HStack(spacing: 2) {
                                    Text(items[i].word)
                                        .font(.caption2)
                                    if let count = items[i].count {
                                        Text("×\(count)")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(Capsule())
                            }
                        }
                    } else {
                        Text(kjv)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(12)
    }

    // MARK: - Verses Using This Word

    private var versesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()

            Button(action: toggleVerses) {
                HStack {
                    sectionLabel("Verses Using This Word")
                    Spacer()
                    if isLoadingVerses {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                    Image(systemName: versesOpen ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if versesOpen, let refs = verseRefs {
                VStack(alignment: .leading, spacing: 0) {
                    if refs.isEmpty {
                        Text("No verses found")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                    } else {
                        if refs.count >= 300 {
                            Text("Showing first 300 results")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 4)
                        }
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(refs) { ref in
                                VerseRefButton(ref: ref) {
                                    navigateToVerse(book: ref.book, chapter: ref.chapter, verse: ref.verse)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Similar Numbers

    private var similarSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoadingSimilar {
                HStack {
                    Divider()
                    ProgressView("Finding similar entries...")
                        .font(.caption)
                    Spacer()
                }
                .padding(12)
            } else if !similarEntries.isEmpty || similarExact != nil {
                Divider()

                HStack(spacing: 6) {
                    sectionLabel("Similar Numbers")
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(.quaternary)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

                LazyVStack(spacing: 1) {
                    // Show the "exact" similar match first if different from focused
                    if let exact = similarExact, exact.number != focusedNumber {
                        similarEntryRow(exact, isExact: true)
                    }

                    ForEach(similarEntries, id: \.number) { entry in
                        if entry.number != focusedNumber {
                            similarEntryRow(entry, isExact: false)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private func similarEntryRow(_ entry: StrongsEntry, isExact: Bool) -> some View {
        let isExpanded = expandedSimilarNum == entry.number
        return VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedSimilarNum = isExpanded ? nil : entry.number
                }
            }) {
                HStack(spacing: 6) {
                    Text(entry.number)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(isExact ? Color.blue.opacity(0.2) : Color.orange.opacity(0.15))
                        .foregroundStyle(isExact ? .blue : .orange)
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    if isExact {
                        Text("Best Match")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.blue)
                            .textCase(.uppercase)
                    }

                    Text(entry.lemma)
                        .font(.system(size: 14, design: .serif))
                        .lineLimit(1)

                    if !entry.transliteration.isEmpty {
                        Text(entry.transliteration)
                            .font(.caption.italic())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                compactEntryDetail(entry)
            }
        }
        .background(isExpanded ? Color.accentColor.opacity(0.06) : Color.clear)
    }

    private func compactEntryDetail(_ entry: StrongsEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Lemma
            Text(entry.lemma)
                .font(.system(size: 22, design: .serif))
                .foregroundStyle(.primary)
                .environment(\.layoutDirection, entry.testament == .old ? .rightToLeft : .leftToRight)

            // Transliteration + pronunciation
            HStack(spacing: 6) {
                if !entry.transliteration.isEmpty {
                    Text(entry.transliteration)
                        .font(.caption.italic())
                        .foregroundStyle(.primary)
                }
                if let pron = entry.pronunciation, !pron.isEmpty {
                    Text("(\(pron))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let def = entry.strongsDefinition, !def.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    sectionLabel("Definition")
                    Text(cleanDefinition(def))
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let deriv = entry.derivation, !deriv.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    sectionLabel("Derivation")
                    Text(cleanDefinition(deriv))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let kjv = entry.kjvDefinition, !kjv.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        sectionLabel("KJV Usage")
                        let total = totalUsageCount(kjv)
                        if let total {
                            Text("(\(total) occurrences)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    let items = parseKjvUsage(kjv)
                    if !items.isEmpty {
                        FlowLayoutCompact {
                            ForEach(items.indices, id: \.self) { i in
                                HStack(spacing: 2) {
                                    Text(items[i].word)
                                        .font(.caption2)
                                    if let count = items[i].count {
                                        Text("×\(count)")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(Capsule())
                            }
                        }
                    } else {
                        Text(kjv)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // Expandable verses for this similar entry
            similarVersesButton(for: entry)

            // Button to switch focus to this entry
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    switchFocus(to: entry)
                }
            }) {
                Text("View full detail")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func similarVersesButton(for entry: StrongsEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { toggleSimilarVerses(for: entry.number) }) {
                HStack(spacing: 4) {
                    Text("Verses Using This Word")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                    if similarVersesLoading.contains(entry.number) {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
                    Image(systemName: similarVersesOpen.contains(entry.number) ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if similarVersesOpen.contains(entry.number), let refs = similarVerseRefs[entry.number] {
                if refs.isEmpty {
                    Text("No verses found")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 4)
                } else {
                    if refs.count >= 300 {
                        Text("Showing first 300 results")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.bottom, 2)
                    }
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(refs) { ref in
                            VerseRefButton(ref: ref) {
                                navigateToVerse(book: ref.book, chapter: ref.chapter, verse: ref.verse)
                            }
                        }
                    }
                }
            }
        }
    }

    private func toggleSimilarVerses(for number: String) {
        if !similarVersesOpen.contains(number) && similarVerseRefs[number] == nil {
            similarVersesLoading.insert(number)
            let fp = translationFilePath
            DispatchQueue.global(qos: .userInitiated).async {
                let refs = StrongsService.findVersesByStrongs(number, filePath: fp)
                DispatchQueue.main.async {
                    similarVerseRefs[number] = refs
                    similarVersesLoading.remove(number)
                    similarVersesOpen.insert(number)
                }
            }
        } else {
            if similarVersesOpen.contains(number) {
                similarVersesOpen.remove(number)
            } else {
                similarVersesOpen.insert(number)
            }
        }
    }

    // MARK: - Click a Word Prompt (no word focused yet)

    private var wordListFallback: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.tap")
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)
            Text("Tap a Word")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Click any word in the verse to see its Strong's concordance entry.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)
            Text("No Strong's Data")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Text("This verse has no Strong's concordance tags. Try a tagged translation like KJV.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    private func loadStrongsData() {
        isLoading = true
        focusedEntry = nil
        versesOpen = false
        verseRefs = nil
        similarEntries = []
        similarExact = nil
        expandedSimilarNum = nil
        similarVersesOpen = []
        similarVerseRefs = [:]
        similarVersesLoading = []
        let targetWordIndex = initialWordIndex

        DispatchQueue.global(qos: .userInitiated).async {
            let tags = StrongsService.entriesForVerse(
                verseId: verseId,
                filePath: translationFilePath
            )
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.2)) {
                    resolvedTags = tags
                    isLoading = false
                    // Auto-focus the tapped word
                    if let idx = targetWordIndex {
                        focusOnWord(atIndex: idx)
                    }
                }
            }
        }
    }

    private func focusOnWord(atIndex idx: Int) {
        guard let match = resolvedTags.first(where: { $0.wordTag.wordIndex == idx }),
              let num = match.strongsNumbers.first else { return }

        // Use resolved entry if available, otherwise create a minimal placeholder
        let entry = match.primaryEntry ?? StrongsEntry(
            number: num,
            lemma: "",
            transliteration: "",
            pronunciation: nil,
            derivation: nil,
            strongsDefinition: nil,
            kjvDefinition: nil
        )

        focusedEntry = entry
        focusedWord = match.word
        focusedNumber = num
        versesOpen = false
        verseRefs = nil
        expandedSimilarNum = nil

        // If we only have a placeholder, try a direct lookup in background
        if match.primaryEntry == nil {
            let fp = translationFilePath
            DispatchQueue.global(qos: .userInitiated).async {
                if let resolved = StrongsService.lookup(num, in: fp) {
                    DispatchQueue.main.async {
                        if focusedNumber == num {
                            focusedEntry = resolved
                        }
                    }
                }
            }
        }

        // Load similar entries in background
        loadSimilarEntries(word: match.word)
    }

    private func switchFocus(to entry: StrongsEntry, word: String? = nil) {
        focusedEntry = entry
        focusedNumber = entry.number
        focusedWord = word ?? ""
        versesOpen = false
        verseRefs = nil
        expandedSimilarNum = nil
        similarEntries = []
        similarExact = nil
        similarVersesOpen = []
        similarVerseRefs = [:]
        similarVersesLoading = []

        // Always reload similar entries for the new focused entry.
        // Definition-based matching doesn't require a word; word-based
        // search is only used as a fallback.
        loadSimilarEntries(word: word ?? "")
    }

    private func loadSimilarEntries(word: String) {
        isLoadingSimilar = true
        let fp = translationFilePath
        let num = focusedNumber
        DispatchQueue.global(qos: .userInitiated).async {
            // Use Windows-style definition matching: find entries whose kjv_def
            // shares words with the selected entry's kjv_def
            let definitionMatches = StrongsService.findSimilarByDefinition(
                number: num, filePath: fp, limit: 15
            )
            // Fall back to word-based search if definition matching yields nothing
            if definitionMatches.isEmpty {
                let result = StrongsService.searchSimilar(word: word, filePath: fp)
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        similarExact = result.exact
                        similarEntries = result.similar
                        isLoadingSimilar = false
                    }
                }
            } else {
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        similarExact = nil
                        similarEntries = definitionMatches
                        isLoadingSimilar = false
                    }
                }
            }
        }
    }

    private func toggleVerses() {
        if !versesOpen && verseRefs == nil {
            isLoadingVerses = true
            let num = focusedNumber
            let fp = translationFilePath
            DispatchQueue.global(qos: .userInitiated).async {
                let refs = StrongsService.findVersesByStrongs(num, filePath: fp)
                DispatchQueue.main.async {
                    verseRefs = refs
                    isLoadingVerses = false
                    versesOpen = true
                }
            }
        } else {
            versesOpen.toggle()
        }
    }

    private func navigateToVerse(book: String, chapter: Int, verse: Int) {
        NotificationCenter.default.post(
            name: .navigateToVerse,
            object: nil,
            userInfo: [
                "book": book,
                "chapter": chapter,
                "verse": verse
            ]
        )
        NotificationCenter.default.post(name: .navigateToReader, object: nil)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func strongsBadgeColor(_ number: String) -> Color {
        number.hasPrefix("H") ? .indigo : .teal
    }

    private static let htmlTagRegex = try! NSRegularExpression(pattern: "<[^>]+>")

    private func cleanDefinition(_ raw: String) -> String {
        let range = NSRange(raw.startIndex..., in: raw)
        let stripped = Self.htmlTagRegex.stringByReplacingMatches(in: raw, range: range, withTemplate: "")
        return stripped
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parse KJV usage string into word/count pairs (e.g. "word(3), phrase(1)").
    private func parseKjvUsage(_ kjvDef: String) -> [(word: String, count: Int?)] {
        var results: [(word: String, count: Int?)] = []
        let pattern = try! NSRegularExpression(pattern: "([a-zA-Z][a-zA-Z\\s'-]*)(?:\\((\\d+)\\))?")
        let nsRange = NSRange(kjvDef.startIndex..., in: kjvDef)
        pattern.enumerateMatches(in: kjvDef, range: nsRange) { match, _, _ in
            guard let match, let wordRange = Range(match.range(at: 1), in: kjvDef) else { return }
            let word = kjvDef[wordRange].trimmingCharacters(in: .whitespaces)
            guard word.count >= 2, word.lowercased() != "times" else { return }
            var count: Int? = nil
            if let countRange = Range(match.range(at: 2), in: kjvDef) {
                count = Int(kjvDef[countRange])
            }
            results.append((word: word, count: count))
        }
        return results
    }

    /// Sum all explicit counts from kjv_def for total usage.
    private func totalUsageCount(_ kjvDef: String) -> Int? {
        // Check for ×number or xnumber pattern
        if let crossMatch = kjvDef.range(of: "[×x](\\d+)", options: .regularExpression) {
            let numStr = kjvDef[crossMatch].dropFirst()
            if let n = Int(numStr) { return n }
        }
        let pattern = try! NSRegularExpression(pattern: "\\((\\d+)\\)")
        let nsRange = NSRange(kjvDef.startIndex..., in: kjvDef)
        var total = 0
        var found = false
        pattern.enumerateMatches(in: kjvDef, range: nsRange) { match, _, _ in
            guard let match, let range = Range(match.range(at: 1), in: kjvDef),
                  let n = Int(kjvDef[range]) else { return }
            total += n
            found = true
        }
        return found ? total : nil
    }
}

// MARK: - Verse Reference Button with Hover

private struct VerseRefButton: View {
    let ref: StrongsService.VerseReference
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ref.displayRef)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                if !ref.text.isEmpty {
                    Text(ref.text)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.blue.opacity(isHovered ? 0.08 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Compact Flow Layout for KJV Usage Pills

/// A simple flow layout that wraps children to the next line.
private struct FlowLayoutCompact: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
