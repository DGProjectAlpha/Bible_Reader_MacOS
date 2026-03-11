import SwiftUI

// MARK: - Search View

struct SearchView: View {
    @EnvironmentObject var store: BibleStore
    @EnvironmentObject var windowState: WindowState
    @State private var searchText = ""
    @State private var scope: SearchScope = .bible
    @State private var isSearching = false
    @State private var results: [SearchResult] = []
    @State private var selectedModuleIds: Set<UUID> = []  // empty = all modules
    @State private var showModuleFilter = false
    @State private var hasSearched = false
    @State private var resultsCapped = false
    // Verse lookup
    @State private var showVerseLookup = false
    @State private var lookupText = ""

    private var allModuleIds: Set<UUID> {
        Set(store.loadedTranslations.map(\.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if hasSearched {
                resultsList
            }
        }
        .onAppear {
            selectedModuleIds = allModuleIds
            // If windowState has a pending search query, use it
            if !windowState.searchQuery.isEmpty {
                searchText = windowState.searchQuery
                windowState.searchQuery = ""
                performSearch()
            }
        }
        .onChange(of: windowState.searchQuery) { oldValue, newValue in
            if !newValue.isEmpty {
                searchText = newValue
                windowState.searchQuery = ""
                performSearch()
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search word or phrase...", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit { performSearch() }

                if !searchText.isEmpty {
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            searchText = ""
                            results = []
                            hasSearched = false
                            resultsCapped = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Verse lookup button
                Button(action: { showVerseLookup.toggle() }) {
                    Image(systemName: "number")
                        .font(.callout)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Go to verse reference")
                .popover(isPresented: $showVerseLookup) {
                    verseLookupPopover
                }

                Button("Search") { performSearch() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)

                Divider().frame(height: 16)

                Button(action: { windowState.showSearchPanel = false }) {
                    Image(systemName: "xmark")
                        .font(.callout)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Close search")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            HStack(spacing: 12) {
                // Scope picker
                Picker("Scope", selection: $scope) {
                    ForEach(SearchScope.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                // Module filter button
                Button(action: { showModuleFilter.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text(moduleFilterLabel)
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .popover(isPresented: $showModuleFilter) {
                    moduleFilterPopover
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .glassHeader()
    }

    private var moduleFilterLabel: String {
        if selectedModuleIds.count == store.loadedTranslations.count {
            return "All"
        } else if selectedModuleIds.count == 1, let id = selectedModuleIds.first,
                  let t = store.loadedTranslations.first(where: { $0.id == id }) {
            return t.abbreviation
        } else {
            return "\(selectedModuleIds.count) selected"
        }
    }

    // MARK: - Verse Lookup Popover

    private var verseLookupPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Go to Reference").font(.headline)
            Text("e.g. John 3:16, Gen 1, Rev 21:1")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                TextField("Book Chapter:Verse", text: $lookupText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { performVerseLookup() }

                Button("Go") { performVerseLookup() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(lookupText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .frame(minWidth: 260, maxWidth: 400)
    }

    // MARK: - Module Filter Popover

    private var moduleFilterPopover: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Search in").font(.headline)
                Spacer()
                Button("All") {
                    selectedModuleIds = allModuleIds
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.bottom, 4)

            ForEach(store.loadedTranslations) { t in
                Toggle(isOn: Binding(
                    get: { selectedModuleIds.contains(t.id) },
                    set: { on in
                        if on { selectedModuleIds.insert(t.id) }
                        else { selectedModuleIds.remove(t.id) }
                    }
                )) {
                    HStack(spacing: 6) {
                        Text(t.abbreviation).fontWeight(.medium)
                        Text(t.name).foregroundStyle(.secondary).font(.caption)
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
        .padding(12)
        .frame(minWidth: 220, maxWidth: 360)
    }

    // MARK: - Results

    private var resultsList: some View {
        Group {
            if isSearching {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Searching...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else if results.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.quaternary)
                    Text("No results found — try a different search term or scope")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    // Result count header
                    HStack {
                        Text(resultCountLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if resultsCapped {
                            Text("(capped)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassToolbar()

                    Divider()

                    List(results) { result in
                        SearchResultRow(
                            result: result,
                            searchText: searchText,
                            store: store,
                            onNavigate: { navigateToResult(result) },
                            onSyncAll: { syncAllPanes(to: result) },
                            onOpenParallel: { openInParallel(result) }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            navigateToResult(result)
                        }
                    }
                    .listStyle(.inset)
                }
            }
        }
    }

    private var resultCountLabel: String {
        if resultsCapped {
            return "500+ results"
        }
        return "\(results.count) result\(results.count == 1 ? "" : "s")"
    }

    // MARK: - Actions

    private func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }

        isSearching = true
        hasSearched = true
        results = []
        resultsCapped = false

        let currentBook = windowState.panes.first?.selectedBook
        let currentChapter = windowState.panes.first?.selectedChapter
        let capturedModuleIds = selectedModuleIds
        let capturedScope = scope
        let capturedTranslations = store.loadedTranslations.filter { t in
            capturedModuleIds.contains(t.id)
        }

        Task.detached {
            var collected: [SearchResult] = []

            for translation in capturedTranslations {
                do {
                    let hits = try ModuleService.search(
                        in: translation.filePath,
                        query: query,
                        scope: capturedScope,
                        currentBook: currentBook,
                        currentChapter: currentChapter
                    )
                    let tagged = hits.map { hit in
                        SearchResult(
                            translationAbbreviation: translation.abbreviation,
                            book: hit.book,
                            chapter: hit.chapter,
                            verse: hit.verse,
                            text: hit.text,
                            matchRange: hit.matchRange
                        )
                    }
                    collected.append(contentsOf: tagged)
                } catch {
                    print("Search failed for \(translation.abbreviation): \(error)")
                }
            }

            // Check if any individual translation hit the 500 cap
            let capped = collected.count >= 500
            let finalResults = collected

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    results = finalResults
                    resultsCapped = capped
                    isSearching = false
                }
            }
        }
    }

    private func navigateToResult(_ result: SearchResult) {
        guard let pane = windowState.panes.first else { return }

        if let translation = store.loadedTranslations.first(where: { $0.abbreviation == result.translationAbbreviation }) {
            pane.selectedTranslationId = translation.id
        }
        pane.selectedBook = result.book
        pane.selectedChapter = result.chapter
        store.loadVerses(for: pane)

        // Scroll to the specific verse
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(
                name: .navigateToVerse,
                object: nil,
                userInfo: ["book": result.book, "chapter": result.chapter, "verse": result.verse]
            )
        }
    }

    private func syncAllPanes(to result: SearchResult) {
        for pane in windowState.panes {
            if let translation = store.loadedTranslations.first(where: { $0.abbreviation == result.translationAbbreviation }) {
                pane.selectedTranslationId = translation.id
            }
            pane.selectedBook = result.book
            pane.selectedChapter = result.chapter
            store.loadVerses(for: pane)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(
                name: .navigateToVerse,
                object: nil,
                userInfo: ["book": result.book, "chapter": result.chapter, "verse": result.verse]
            )
        }
    }

    private func openInParallel(_ result: SearchResult) {
        let translation = store.loadedTranslations.first(where: { $0.abbreviation == result.translationAbbreviation })
        windowState.addPane(translationId: translation?.id)

        guard let newPane = windowState.panes.last else { return }
        if let t = translation {
            newPane.selectedTranslationId = t.id
        }
        newPane.selectedBook = result.book
        newPane.selectedChapter = result.chapter
        store.loadVerses(for: newPane)
    }

    // MARK: - Verse Lookup

    private func performVerseLookup() {
        let input = lookupText.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }

        let parsed = parseVerseReference(input)
        guard let book = parsed.book else { return }

        guard let pane = windowState.panes.first else { return }

        // Find matching translation (use current pane's translation)
        pane.selectedBook = book
        pane.selectedChapter = parsed.chapter
        store.loadVerses(for: pane)

        if let verse = parsed.verse {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NotificationCenter.default.post(
                    name: .navigateToVerse,
                    object: nil,
                    userInfo: ["book": book, "chapter": parsed.chapter, "verse": verse]
                )
            }
        }

        showVerseLookup = false
        lookupText = ""
    }

    /// Parse a verse reference string like "John 3:16", "Gen 1", "1 Cor 13:4", "Revelation 21"
    private func parseVerseReference(_ input: String) -> (book: String?, chapter: Int, verse: Int?) {
        let trimmed = input.trimmingCharacters(in: .whitespaces)

        // Try to split off the last numeric portion (chapter:verse or just chapter)
        // Pattern: everything before the last space-separated number group is the book name
        var bookPart = ""
        var numericPart = ""

        // Find where the numeric portion starts (from the end)
        let components = trimmed.components(separatedBy: " ").filter { !$0.isEmpty }
        guard !components.isEmpty else { return (nil, 1, nil) }

        // The numeric part is the last component that starts with a digit
        if let lastComponent = components.last, let firstChar = lastComponent.first, firstChar.isNumber || lastComponent.contains(":") {
            numericPart = lastComponent
            bookPart = components.dropLast().joined(separator: " ")
        } else {
            // No numeric part found, treat entire input as book name
            bookPart = trimmed
        }

        // Parse chapter:verse from numeric part
        var chapter = 1
        var verse: Int? = nil

        if numericPart.contains(":") {
            let parts = numericPart.split(separator: ":")
            chapter = Int(parts[0]) ?? 1
            if parts.count > 1 {
                verse = Int(parts[1])
            }
        } else if let ch = Int(numericPart) {
            chapter = ch
        }

        // Match book name
        let matchedBook = matchBookName(bookPart)
        return (matchedBook, chapter, verse)
    }

    /// Fuzzy match a book name input against canonical book names
    private func matchBookName(_ input: String) -> String? {
        let lower = input.lowercased().trimmingCharacters(in: .whitespaces)
        guard !lower.isEmpty else { return nil }

        // Exact match first
        if let exact = BibleBooks.all.first(where: { $0.lowercased() == lower }) {
            return exact
        }

        // Common abbreviations
        let abbreviations: [String: String] = [
            "gen": "Genesis", "ex": "Exodus", "exo": "Exodus", "lev": "Leviticus",
            "num": "Numbers", "deut": "Deuteronomy", "deu": "Deuteronomy",
            "josh": "Joshua", "jos": "Joshua", "judg": "Judges", "jdg": "Judges",
            "ruth": "Ruth", "1 sam": "1 Samuel", "1sam": "1 Samuel",
            "2 sam": "2 Samuel", "2sam": "2 Samuel",
            "1 kgs": "1 Kings", "1kgs": "1 Kings", "1 ki": "1 Kings", "1ki": "1 Kings",
            "2 kgs": "2 Kings", "2kgs": "2 Kings", "2 ki": "2 Kings", "2ki": "2 Kings",
            "1 chr": "1 Chronicles", "1chr": "1 Chronicles", "1 ch": "1 Chronicles",
            "2 chr": "2 Chronicles", "2chr": "2 Chronicles", "2 ch": "2 Chronicles",
            "ezr": "Ezra", "neh": "Nehemiah", "est": "Esther",
            "job": "Job", "ps": "Psalms", "psa": "Psalms", "psalm": "Psalms",
            "prov": "Proverbs", "pro": "Proverbs", "eccl": "Ecclesiastes", "ecc": "Ecclesiastes",
            "song": "Song of Solomon", "sos": "Song of Solomon", "ss": "Song of Solomon",
            "isa": "Isaiah", "jer": "Jeremiah", "lam": "Lamentations",
            "ezek": "Ezekiel", "eze": "Ezekiel", "dan": "Daniel",
            "hos": "Hosea", "joe": "Joel", "amo": "Amos", "oba": "Obadiah", "obad": "Obadiah",
            "jon": "Jonah", "mic": "Micah", "nah": "Nahum", "hab": "Habakkuk",
            "zeph": "Zephaniah", "zep": "Zephaniah", "hag": "Haggai",
            "zech": "Zechariah", "zec": "Zechariah", "mal": "Malachi",
            "matt": "Matthew", "mat": "Matthew", "mk": "Mark", "mar": "Mark",
            "lk": "Luke", "luk": "Luke", "jn": "John", "joh": "John",
            "acts": "Acts", "act": "Acts",
            "rom": "Romans", "1 cor": "1 Corinthians", "1cor": "1 Corinthians",
            "2 cor": "2 Corinthians", "2cor": "2 Corinthians",
            "gal": "Galatians", "eph": "Ephesians", "phil": "Philippians", "php": "Philippians",
            "col": "Colossians", "1 thess": "1 Thessalonians", "1thess": "1 Thessalonians",
            "1 th": "1 Thessalonians", "1th": "1 Thessalonians",
            "2 thess": "2 Thessalonians", "2thess": "2 Thessalonians",
            "2 th": "2 Thessalonians", "2th": "2 Thessalonians",
            "1 tim": "1 Timothy", "1tim": "1 Timothy", "2 tim": "2 Timothy", "2tim": "2 Timothy",
            "tit": "Titus", "phm": "Philemon", "phlm": "Philemon",
            "heb": "Hebrews", "jas": "James", "jam": "James",
            "1 pet": "1 Peter", "1pet": "1 Peter", "1 pe": "1 Peter",
            "2 pet": "2 Peter", "2pet": "2 Peter", "2 pe": "2 Peter",
            "1 jn": "1 John", "1jn": "1 John", "1 jo": "1 John",
            "2 jn": "2 John", "2jn": "2 John", "2 jo": "2 John",
            "3 jn": "3 John", "3jn": "3 John", "3 jo": "3 John",
            "jude": "Jude", "rev": "Revelation", "apo": "Revelation"
        ]

        if let abbr = abbreviations[lower] {
            return abbr
        }

        // Prefix match
        if let prefix = BibleBooks.all.first(where: { $0.lowercased().hasPrefix(lower) }) {
            return prefix
        }

        return nil
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let result: SearchResult
    let searchText: String
    let store: BibleStore
    let onNavigate: () -> Void
    let onSyncAll: () -> Void
    let onOpenParallel: () -> Void

    @State private var isHovered = false
    @State private var prevVerseText: String?
    @State private var nextVerseText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(result.translationAbbreviation)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(Color.accentColor)

                Text("\(result.book) \(result.chapter):\(result.verse)")
                    .font(.callout.weight(.semibold))

                Spacer()

                // Action buttons on hover
                if isHovered {
                    HStack(spacing: 4) {
                        Button(action: onSyncAll) {
                            Image(systemName: "rectangle.on.rectangle")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help("Sync all panes to this verse")

                        Button(action: onOpenParallel) {
                            Image(systemName: "plus.rectangle.on.rectangle")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help("Open in new parallel pane")
                    }
                }
            }

            // Previous verse context
            if let prev = prevVerseText {
                Text("\(result.verse - 1). \(prev)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .italic()
            }

            // Matched verse with highlighting
            highlightedText
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            // Next verse context
            if let next = nextVerseText {
                Text("\(result.verse + 1). \(next)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .italic()
            }
        }
        .padding(.vertical, 4)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .task {
            loadContextVerses()
        }
    }

    /// Renders the verse text with the search term highlighted.
    private var highlightedText: Text {
        let text = result.text
        let lower = text.lowercased()
        let term = searchText.lowercased()

        guard !term.isEmpty else { return Text(text) }

        // Collect all match ranges first, then build AttributedString in one pass
        var ranges: [Range<String.Index>] = []
        var searchStart = lower.startIndex
        while let range = lower.range(of: term, range: searchStart..<lower.endIndex) {
            ranges.append(range)
            searchStart = range.upperBound
        }

        guard !ranges.isEmpty else { return Text(text) }

        var attributed = AttributedString(text)
        for range in ranges {
            let attrStart = AttributedString.Index(range.lowerBound, within: attributed)!
            let attrEnd = AttributedString.Index(range.upperBound, within: attributed)!
            attributed[attrStart..<attrEnd].foregroundColor = .accentColor
            attributed[attrStart..<attrEnd].font = .body.bold()
        }

        return Text(attributed)
    }

    private func loadContextVerses() {
        // Find the translation file path
        guard let translation = store.loadedTranslations.first(where: { $0.abbreviation == result.translationAbbreviation }) else { return }

        // Load previous verse
        if result.verse > 1 {
            prevVerseText = try? ModuleService.loadSingleVerse(
                from: translation.filePath,
                book: result.book,
                chapter: result.chapter,
                verse: result.verse - 1
            )
        }

        // Load next verse
        nextVerseText = try? ModuleService.loadSingleVerse(
            from: translation.filePath,
            book: result.book,
            chapter: result.chapter,
            verse: result.verse + 1
        )
    }
}
