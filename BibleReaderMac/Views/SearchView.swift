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

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if hasSearched {
                resultsList
            } else {
                emptyState
            }
        }
        .navigationTitle("Search")
        .onAppear {
            // Default: search all modules
            selectedModuleIds = Set(store.loadedTranslations.map(\.id))
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
                        searchText = ""
                        results = []
                        hasSearched = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button("Search") { performSearch() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
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

    // MARK: - Module Filter Popover

    private var moduleFilterPopover: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Search in").font(.headline)
                Spacer()
                Button("All") {
                    selectedModuleIds = Set(store.loadedTranslations.map(\.id))
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
        .frame(minWidth: 240)
    }

    // MARK: - Results

    private var resultsList: some View {
        Group {
            if isSearching {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Searching...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(.quaternary)
                    Text("No results found")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Try a different search term or scope")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    // Result count header
                    HStack {
                        Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassToolbar()

                    Divider()

                    List(results) { result in
                        SearchResultRow(result: result, searchText: searchText)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                navigateToResult(result)
                            }
                    }
                    .listStyle(.plain)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("Search the Bible")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("Enter a word or phrase to search across all loaded translations")
                .font(.caption)
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }

        isSearching = true
        hasSearched = true
        results = []

        // Get current book/chapter from the first pane for scope filtering
        let currentBook = windowState.panes.first?.selectedBook
        let currentChapter = windowState.panes.first?.selectedChapter

        Task.detached {
            var allResults: [SearchResult] = []

            let translations = await store.loadedTranslations.filter { t in
                await selectedModuleIds.contains(t.id)
            }

            for translation in translations {
                do {
                    let hits = try ModuleService.search(
                        in: translation.filePath,
                        query: query,
                        scope: scope,
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
                    allResults.append(contentsOf: tagged)
                } catch {
                    print("Search failed for \(translation.abbreviation): \(error)")
                }
            }

            await MainActor.run {
                results = allResults
                isSearching = false
            }
        }
    }

    private func navigateToResult(_ result: SearchResult) {
        // Navigate the first pane to the result's location
        guard let pane = windowState.panes.first else { return }

        // Find the translation matching the abbreviation
        if let translation = store.loadedTranslations.first(where: { $0.abbreviation == result.translationAbbreviation }) {
            pane.selectedTranslationId = translation.id
        }
        pane.selectedBook = result.book
        pane.selectedChapter = result.chapter
        store.loadVerses(for: pane)

        // Switch to reader view
        NotificationCenter.default.post(name: .navigateToReader, object: nil)
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let result: SearchResult
    let searchText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(result.translationAbbreviation)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(.blue)

                Text("\(result.book) \(result.chapter):\(result.verse)")
                    .font(.callout.weight(.semibold))

                Spacer()
            }

            highlightedText
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
    }

    /// Renders the verse text with the search term highlighted.
    private var highlightedText: Text {
        let text = result.text
        let lower = text.lowercased()
        let term = searchText.lowercased()

        guard !term.isEmpty else { return Text(text) }

        var built = Text("")
        var searchStart = lower.startIndex

        while let range = lower.range(of: term, range: searchStart..<lower.endIndex) {
            // Text before match
            if range.lowerBound > searchStart {
                built = built + Text(text[searchStart..<range.lowerBound])
            }
            // The matched portion — highlighted
            built = built + Text(text[range])
                .foregroundColor(.white)
                .bold()
                .background(Color.orange.opacity(0.7))

            searchStart = range.upperBound
        }

        // Remainder after last match
        if searchStart < lower.endIndex {
            built = built + Text(text[searchStart..<text.endIndex])
        }

        return built
    }
}

// MARK: - Notification for navigation

extension Notification.Name {
    static let navigateToReader = Notification.Name("navigateToReader")
}
