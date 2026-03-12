import SwiftUI

// MARK: - Search Toolbar Item
//
// A compact search field that lives entirely in the window toolbar.
// - When collapsed: shows a magnifying glass button that can be tapped to expand
// - When expanded: the field grows to the left; results drop down as a popover
// - In full-screen mode the popover is naturally bounded by the screen edge

struct SearchToolbarItem: View {
    @EnvironmentObject var store: BibleStore
    @EnvironmentObject var windowState: WindowState

    @State private var searchText = ""
    @State private var scope: SearchScope = .bible
    @State private var isSearching = false
    @State private var results: [SearchResult] = []
    @State private var selectedModuleIds: Set<UUID> = []
    @State private var showModuleFilter = false
    @State private var hasSearched = false
    @State private var resultsCapped = false
    @State private var showVerseLookup = false
    @State private var lookupText = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var showResults = false
    @FocusState private var isFieldFocused: Bool

    private var isExpanded: Bool { windowState.showSearchPanel }

    private var allModuleIds: Set<UUID> {
        Set(store.loadedTranslations.map(\.id))
    }

    var body: some View {
        HStack(spacing: 0) {
            if isExpanded {
                // Expanded search field
                HStack(spacing: 8) {
                    Image(systemName: isSearching ? "clock" : "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.45))
                        .animation(.easeInOut(duration: 0.15), value: isSearching)
                        .frame(width: 16)

                    TextField(L("search.placeholder"), text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .focused($isFieldFocused)
                        .frame(width: 220)
                        .onSubmit { performSearch() }

                    if !searchText.isEmpty {
                        Button(action: clearSearch) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.primary.opacity(0.3))
                        }
                        .buttonStyle(.plain)
                    }

                    Divider().frame(height: 16).opacity(0.5)

                    // Scope indicator
                    Menu {
                        ForEach(SearchScope.allCases, id: \.self) { s in
                            Button(action: { scope = s; if hasSearched { performSearch() } }) {
                                HStack {
                                    Text(s.rawValue)
                                    if scope == s {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: scopeIcon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(scope == .bible ? .primary.opacity(0.45) : Color.accentColor)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help(L("search.scope"))

                    Button(action: { showModuleFilter.toggle() }) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(selectedModuleIds.count < store.loadedTranslations.count ? Color.accentColor : .primary.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                    .help(L("search.filter_help"))
                    .popover(isPresented: $showModuleFilter) { moduleFilterPopover }

                    Divider().frame(height: 16).opacity(0.5)

                    Button(action: collapse) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.primary.opacity(0.45))
                            .frame(width: 18, height: 18)
                            .background(.primary.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(L("search.close_help"))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.primary.opacity(0.06))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(.primary.opacity(0.12), lineWidth: 0.75)
                        }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
                .popover(isPresented: $showResults, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                    resultsPopover
                }
            } else {
                // Collapsed: just a magnifying glass button
                Button(action: expand) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                }
                .help(L("toolbar.search_help"))
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .opacity
                ))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isExpanded)
        .onAppear {
            selectedModuleIds = allModuleIds
            if !windowState.searchQuery.isEmpty {
                searchText = windowState.searchQuery
                windowState.searchQuery = ""
                expand()
                performSearch()
            }
        }
        .onChange(of: windowState.searchQuery) { _, newValue in
            if !newValue.isEmpty {
                searchText = newValue
                windowState.searchQuery = ""
                if !isExpanded { expand() }
                performSearch()
            }
        }
        .onChange(of: windowState.showSearchPanel) { _, shown in
            if !shown { collapse() }
        }
        .onChange(of: searchText) { _, newValue in
            debounceTask?.cancel()
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                withAnimation(.easeOut(duration: 0.18)) {
                    results = []
                    hasSearched = false
                    resultsCapped = false
                    showResults = false
                }
                return
            }
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 280_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { performSearch() }
            }
        }
        .onChange(of: scope) { _, _ in
            if hasSearched { performSearch() }
        }
    }

    // MARK: - Results Popover

    private var resultsPopover: some View {
        VStack(spacing: 0) {
            // Count row
            HStack(spacing: 8) {
                if isSearching {
                    ProgressView().controlSize(.mini)
                    Text(L("search.searching"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(resultCountLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    if resultsCapped {
                        Text(L("search.capped"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()

                // Go-to-verse button
                Button(action: { showVerseLookup.toggle() }) {
                    Image(systemName: "number")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.45))
                }
                .buttonStyle(.plain)
                .help(L("search.go_to_verse_help"))
                .popover(isPresented: $showVerseLookup) { verseLookupPopover }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            if !isSearching && results.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.quaternary)
                    Text(L("search.no_results"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { result in
                            SearchResultRow(
                                result: result,
                                searchText: searchText,
                                store: store,
                                onNavigate: { navigateToResult(result) },
                                onSyncAll: { syncAllPanes(to: result) },
                                onOpenParallel: { openInParallel(result) }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { navigateAndClose(result) }
                            if result.id != results.last?.id {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 460)
            }
        }
        .frame(width: 420)
    }

    private var resultCountLabel: String {
        if resultsCapped { return L("search.many_results") }
        return "\(results.count) result\(results.count == 1 ? "" : "s")"
    }

    private var scopeIcon: String {
        switch scope {
        case .bible: return "book"
        case .ot: return "o.circle"
        case .nt: return "n.circle"
        case .book: return "bookmark"
        case .chapter: return "number"
        }
    }

    // MARK: - Verse Lookup Popover

    private var verseLookupPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("search.go_to_ref_title")).font(.headline)
            Text(L("search.ref_placeholder"))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField(L("search.ref_format"), text: $lookupText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { performVerseLookup() }
                Button(L("go")) { performVerseLookup() }
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
                Text(L("search.scope")).font(.headline)
                Spacer()
                Button(L("search.scope_all")) { selectedModuleIds = allModuleIds }
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

    // MARK: - Expand / Collapse

    private func expand() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            windowState.showSearchPanel = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isFieldFocused = true
        }
    }

    private func collapse() {
        isFieldFocused = false
        showResults = false
        // Don't clear searchText so re-opening shows last query
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            windowState.showSearchPanel = false
        }
    }

    private func clearSearch() {
        withAnimation(.easeOut(duration: 0.18)) {
            searchText = ""
            results = []
            hasSearched = false
            resultsCapped = false
            showResults = false
        }
    }

    // MARK: - Actions

    private func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }

        isSearching = true
        hasSearched = true
        results = []
        resultsCapped = false
        showResults = true

        let currentBook = windowState.panes.first?.book
        let currentChapter = windowState.panes.first?.chapter
        let capturedModuleIds = selectedModuleIds
        let capturedScope = scope
        let capturedTranslations = store.loadedTranslations.filter { capturedModuleIds.contains($0.id) }

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
            let capped = collected.count >= 500
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    results = collected
                    resultsCapped = capped
                    isSearching = false
                }
            }
        }
    }

    private func navigateToResult(_ result: SearchResult) {
        guard let pane = windowState.panes.first else { return }
        let translationId = store.loadedTranslations.first(where: { $0.abbreviation == result.translationAbbreviation })?.id ?? pane.translationId
        windowState.navigate(paneId: pane.id, book: result.book, chapter: result.chapter, translationId: translationId)
        guard let updated = windowState.panes.first else { return }
        let verses = store.loadVerses(translationId: updated.translationId, book: updated.book, chapter: updated.chapter)
        let scheme = store.versificationScheme(for: updated.translationId)
        windowState.setVerses(paneId: pane.id, verses: verses, versificationScheme: scheme)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .navigateToVerse, object: nil,
                userInfo: ["book": result.book, "chapter": result.chapter, "verse": result.verse])
        }
    }

    private func navigateAndClose(_ result: SearchResult) {
        navigateToResult(result)
        collapse()
    }

    private func syncAllPanes(to result: SearchResult) {
        for pane in windowState.panes {
            let translationId = store.loadedTranslations.first(where: { $0.abbreviation == result.translationAbbreviation })?.id ?? pane.translationId
            windowState.navigate(paneId: pane.id, book: result.book, chapter: result.chapter, translationId: translationId)
            guard let updated = windowState.panes.first(where: { $0.id == pane.id }) else { continue }
            let verses = store.loadVerses(translationId: updated.translationId, book: updated.book, chapter: updated.chapter)
            let scheme = store.versificationScheme(for: updated.translationId)
            windowState.setVerses(paneId: pane.id, verses: verses, versificationScheme: scheme)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .navigateToVerse, object: nil,
                userInfo: ["book": result.book, "chapter": result.chapter, "verse": result.verse])
        }
        collapse()
    }

    private func openInParallel(_ result: SearchResult) {
        let translationId = store.loadedTranslations.first(where: { $0.abbreviation == result.translationAbbreviation })?.id
            ?? store.firstTranslationId() ?? UUID()
        windowState.addPane(translationId: translationId, book: result.book, chapter: result.chapter)
        guard let newPane = windowState.panes.last else { return }
        let verses = store.loadVerses(translationId: newPane.translationId, book: newPane.book, chapter: newPane.chapter)
        let scheme = store.versificationScheme(for: newPane.translationId)
        windowState.setVerses(paneId: newPane.id, verses: verses, versificationScheme: scheme)
    }

    // MARK: - Verse Lookup

    private func performVerseLookup() {
        let input = lookupText.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }
        let parsed = parseVerseReference(input)
        guard let book = parsed.book else { return }
        guard let pane = windowState.panes.first else { return }
        windowState.navigate(paneId: pane.id, book: book, chapter: parsed.chapter)
        guard let updated = windowState.panes.first else { return }
        let verses = store.loadVerses(translationId: updated.translationId, book: updated.book, chapter: updated.chapter)
        let scheme = store.versificationScheme(for: updated.translationId)
        windowState.setVerses(paneId: pane.id, verses: verses, versificationScheme: scheme)
        if let verse = parsed.verse {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NotificationCenter.default.post(name: .navigateToVerse, object: nil,
                    userInfo: ["book": book, "chapter": parsed.chapter, "verse": verse])
            }
        }
        showVerseLookup = false
        lookupText = ""
        collapse()
    }

    private func parseVerseReference(_ input: String) -> (book: String?, chapter: Int, verse: Int?) {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        var bookPart = ""
        var numericPart = ""
        let components = trimmed.components(separatedBy: " ").filter { !$0.isEmpty }
        guard !components.isEmpty else { return (nil, 1, nil) }
        if let lastComponent = components.last,
           let firstChar = lastComponent.first,
           firstChar.isNumber || lastComponent.contains(":") {
            numericPart = lastComponent
            bookPart = components.dropLast().joined(separator: " ")
        } else {
            bookPart = trimmed
        }
        var chapter = 1
        var verse: Int? = nil
        if numericPart.contains(":") {
            let parts = numericPart.split(separator: ":")
            chapter = Int(parts[0]) ?? 1
            if parts.count > 1 { verse = Int(parts[1]) }
        } else if let ch = Int(numericPart) {
            chapter = ch
        }
        return (matchBookName(bookPart), chapter, verse)
    }

    private func matchBookName(_ input: String) -> String? {
        let lower = input.lowercased().trimmingCharacters(in: .whitespaces)
        guard !lower.isEmpty else { return nil }
        if let exact = BibleBooks.all.first(where: { $0.lowercased() == lower }) { return exact }
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
        if let abbr = abbreviations[lower] { return abbr }
        if let prefix = BibleBooks.all.first(where: { $0.lowercased().hasPrefix(lower) }) { return prefix }
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

                if isHovered {
                    HStack(spacing: 4) {
                        Button(action: onSyncAll) {
                            Image(systemName: "rectangle.on.rectangle")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help(L("search.sync_panes"))

                        Button(action: onOpenParallel) {
                            Image(systemName: "plus.rectangle.on.rectangle")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help(L("search.open_parallel"))
                    }
                }
            }

            if let prev = prevVerseText {
                Text("\(result.verse - 1). \(prev)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .italic()
            }

            highlightedText
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let next = nextVerseText {
                Text("\(result.verse + 1). \(next)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .italic()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isHovered ? Color.primary.opacity(0.05) : .clear)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .task { loadContextVerses() }
    }

    private var highlightedText: Text {
        let text = result.text
        let lower = text.lowercased()
        let term = searchText.lowercased()
        guard !term.isEmpty else { return Text(text) }
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
        guard let translation = store.loadedTranslations.first(where: { $0.abbreviation == result.translationAbbreviation }) else { return }
        if result.verse > 1 {
            prevVerseText = try? ModuleService.loadSingleVerse(
                from: translation.filePath, book: result.book, chapter: result.chapter, verse: result.verse - 1)
        }
        nextVerseText = try? ModuleService.loadSingleVerse(
            from: translation.filePath, book: result.book, chapter: result.chapter, verse: result.verse + 1)
    }
}
