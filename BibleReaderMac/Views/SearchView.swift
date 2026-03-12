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
    @State private var selectedModuleIds: Set<UUID> = []
    @State private var showModuleFilter = false
    @State private var debounceTask: Task<Void, Never>?
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
                    Image(systemName: windowState.searchIsSearching ? "clock" : "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.45))
                        .animation(.easeInOut(duration: 0.15), value: windowState.searchIsSearching)
                        .frame(width: 16)

                    TextField(L("search.placeholder"), text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .focused($isFieldFocused)
                        .frame(width: 220)
                        .onSubmit { performSearch() }
                        .onAppear { isFieldFocused = true }

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
                            Button(action: { scope = s; if windowState.searchHasSearched { performSearch() } }) {
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
                windowState.searchResults = []
                windowState.searchHasSearched = false
                windowState.searchResultsCapped = false
                return
            }
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 280_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { performSearch() }
            }
        }
        .onChange(of: scope) { _, _ in
            if windowState.searchHasSearched { performSearch() }
        }
    }

    // MARK: - Results Popover

    private var resultCountLabel: String {
        if windowState.searchResultsCapped { return L("search.many_results") }
        let c = windowState.searchResults.count
        return "\(c) result\(c == 1 ? "" : "s")"
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
        // Focus is set via .onAppear on the TextField when it enters the hierarchy
    }

    private func collapse() {
        isFieldFocused = false
        // Don't clear searchText so re-opening shows last query
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            windowState.showSearchPanel = false
        }
    }

    private func clearSearch() {
        searchText = ""
        windowState.searchResults = []
        windowState.searchHasSearched = false
        windowState.searchResultsCapped = false
        windowState.searchIsSearching = false
    }

    // MARK: - Actions

    private func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }

        windowState.searchIsSearching = true
        windowState.searchHasSearched = true
        windowState.searchResults = []
        windowState.searchResultsCapped = false
        NotificationCenter.default.post(name: .init("SearchPanelQueryChanged"), object: query)

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
            let finalResults = collected
            let capped = finalResults.count >= 500
            await MainActor.run {
                windowState.searchResults = finalResults
                windowState.searchResultsCapped = capped
                windowState.searchIsSearching = false
            }
        }
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
// MARK: - Search Results Panel (window-level overlay, rendered in ContentView)

struct SearchResultsPanel: View {
    @EnvironmentObject var store: BibleStore
    @EnvironmentObject var windowState: WindowState

    @State private var searchText: String = ""
    @State private var showVerseLookup = false
    @State private var lookupText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 8) {
                if windowState.searchIsSearching {
                    ProgressView().controlSize(.mini)
                    Text(L("search.searching"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(resultCountLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    if windowState.searchResultsCapped {
                        Text(L("search.capped"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()

                Button(action: { showVerseLookup.toggle() }) {
                    Image(systemName: "number")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.45))
                }
                .buttonStyle(.plain)
                .help(L("search.go_to_verse_help"))
                .popover(isPresented: $showVerseLookup) { verseLookupPopover }

                Button(action: {
                    windowState.showSearchPanel = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L("search.close_help"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            if windowState.searchIsSearching {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("search.searching"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else if windowState.searchResults.isEmpty {
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
                        ForEach(windowState.searchResults) { result in
                            SearchResultRow(
                                result: result,
                                searchText: searchText,
                                store: store,
                                onNavigate: { navigateToResult(result) },
                                onSyncAll: { syncAllPanes(to: result) },
                                onOpenParallel: { openInParallel(result) }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { navigateToResult(result) }
                            if result.id != windowState.searchResults.last?.id {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: min(460, (NSScreen.main?.frame.height ?? 900) * 0.5))
            }
        }
        .frame(width: 440)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 8)
        .onReceive(NotificationCenter.default.publisher(for: .init("SearchPanelQueryChanged"))) { notif in
            if let q = notif.object as? String { searchText = q }
        }
    }

    private var resultCountLabel: String {
        if windowState.searchResultsCapped { return L("search.many_results") }
        let c = windowState.searchResults.count
        return "\(c) result\(c == 1 ? "" : "s")"
    }

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

    private func performVerseLookup() {
        let input = lookupText.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }
        guard let pane = windowState.panes.first else { return }
        // Simple parse: "Book Chapter:Verse"
        let parts = input.split(separator: " ")
        guard let last = parts.last else { return }
        var book: String
        var chapter = 1
        var verse: Int? = nil
        if last.contains(":") {
            let cv = last.split(separator: ":")
            chapter = Int(cv[0]) ?? 1
            if cv.count > 1 { verse = Int(cv[1]) }
            book = parts.dropLast().joined(separator: " ")
        } else if let ch = Int(last) {
            chapter = ch
            book = parts.dropLast().joined(separator: " ")
        } else {
            book = input
        }
        guard let matchedBook = BibleBooks.all.first(where: { $0.lowercased() == book.lowercased() })
            ?? BibleBooks.all.first(where: { $0.lowercased().hasPrefix(book.lowercased()) }) else { return }
        windowState.navigate(paneId: pane.id, book: matchedBook, chapter: chapter)
        guard let updated = windowState.panes.first else { return }
        let verses = store.loadVerses(translationId: updated.translationId, book: updated.book, chapter: updated.chapter)
        let scheme = store.versificationScheme(for: updated.translationId)
        windowState.setVerses(paneId: pane.id, verses: verses, versificationScheme: scheme)
        if let v = verse {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NotificationCenter.default.post(name: .navigateToVerse, object: nil,
                    userInfo: ["book": matchedBook, "chapter": chapter, "verse": v])
            }
        }
        showVerseLookup = false
        lookupText = ""
        windowState.showSearchPanel = false
    }
}

