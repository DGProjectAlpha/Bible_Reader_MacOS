import SwiftUI

// MARK: - Tool Categories

enum FloatingToolCategory: String, CaseIterable, Identifiable {
    case search = "Search"
    case bookmarks = "Bookmarks"
    case highlights = "Highlights"
    case notes = "Notes"
    case strongs = "Strong's"
    case crossReferences = "Cross References"
    case history = "History"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .search: "magnifyingglass"
        case .bookmarks: "bookmark.fill"
        case .highlights: "highlighter"
        case .notes: "note.text"
        case .strongs: "character.book.closed"
        case .crossReferences: "arrow.triangle.branch"
        case .history: "clock"
        case .settings: "gearshape"
        }
    }
}

// MARK: - Root View

struct FloatingToolsView: View {
    @Environment(BibleStore.self) private var bibleStore
    @Environment(UIStateStore.self) private var uiStateStore
    @Environment(UserDataStore.self) private var userDataStore

    @State private var selectedTool: FloatingToolCategory? = .bookmarks

    var body: some View {
        NavigationSplitView {
            List(FloatingToolCategory.allCases, selection: $selectedTool) { tool in
                Label(tool.rawValue, systemImage: tool.icon)
                    .symbolRenderingMode(.hierarchical)
                    .tag(tool)
            }
            .navigationSplitViewColumnWidth(min: 140, ideal: 160, max: 200)
            .navigationTitle("Tools")
        } detail: {
            Group {
                switch selectedTool {
                case .search:
                    FloatingSearchDetail()
                case .bookmarks:
                    FloatingBookmarksDetail()
                case .highlights:
                    FloatingHighlightsDetail()
                case .notes:
                    FloatingNotesDetail()
                case .strongs:
                    FloatingStrongsDetail()
                case .crossReferences:
                    FloatingCrossRefsDetail()
                case .history:
                    FloatingHistoryDetail()
                case .settings:
                    SettingsView()
                case .none:
                    Text("Select a tool")
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  window.title == "Bible Reader — Tools" else { return }
            uiStateStore.isToolsWindowDetached = false
            withAnimation(.easeInOut(duration: 0.25)) {
                uiStateStore.sidebarVisibility = .all
            }
        }
    }
}

// MARK: - Search Detail

private struct FloatingSearchDetail: View {
    @Environment(BibleStore.self) private var bibleStore
    @Environment(UIStateStore.self) private var uiStateStore

    var body: some View {
        @Bindable var uiState = uiStateStore

        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    String(localized: "search.searchIn \(activeModuleName)"),
                    text: $uiState.searchQuery
                )
                .textFieldStyle(.plain)
                .onSubmit {
                    Task { await uiStateStore.performSearch(using: bibleStore) }
                }
                if !uiStateStore.searchQuery.isEmpty {
                    Button {
                        uiStateStore.searchQuery = ""
                        uiStateStore.searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(.textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .padding()

            if uiStateStore.searchResults.isEmpty && !uiStateStore.searchQuery.isEmpty {
                Spacer()
                Text("sidebar.noResultsFor \(uiStateStore.searchQuery)")
                    .foregroundStyle(.tertiary)
                Spacer()
            } else if !uiStateStore.searchResults.isEmpty {
                List(uiStateStore.searchResults) { result in
                    Button { navigateToSearchResult(result) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(result.moduleName)
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.accentColor.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                Text(searchVerseReference(result))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                            }
                            Text(result.verse.text)
                                .font(.callout)
                                .lineLimit(3)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Spacer()
                Text("Enter a search term")
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .navigationTitle("Search")
    }

    private var activeModuleName: String {
        bibleStore.modules.first(where: { $0.id == bibleStore.activeModuleId })?.abbreviation ?? "Bible"
    }

    private func searchVerseReference(_ result: SearchResult) -> String {
        let bookName = bibleStore.modules
            .first(where: { $0.id == result.moduleId })?
            .books.first(where: { $0.id == result.verse.book })?.name ?? result.verse.book
        return "\(bookName) \(result.verse.chapter):\(result.verse.verseNumber)"
    }

    private func navigateToSearchResult(_ result: SearchResult) {
        guard let paneId = bibleStore.activePaneId else { return }
        let location = BibleLocation(
            moduleId: result.moduleId,
            book: result.verse.book,
            chapter: result.verse.chapter,
            verseNumber: result.verse.verseNumber
        )
        Task {
            if bibleStore.activeModuleId != result.moduleId {
                bibleStore.activeModuleId = result.moduleId
            }
            await bibleStore.navigate(paneId: paneId, to: location)
            await MainActor.run {
                uiStateStore.selectedVerseId = result.verse.id
            }
        }
    }
}

// MARK: - Bookmarks Detail

private struct FloatingBookmarksDetail: View {
    @Environment(BibleStore.self) private var bibleStore
    @Environment(UIStateStore.self) private var uiStateStore
    @Environment(UserDataStore.self) private var userDataStore

    var body: some View {
        Group {
            if userDataStore.bookmarks.isEmpty {
                ContentUnavailableView("No Bookmarks", systemImage: "bookmark", description: Text("sidebar.noBookmarksYet"))
            } else {
                List(userDataStore.bookmarks.sorted(by: { $0.createdAt > $1.createdAt })) { bookmark in
                    Button { navigateToVerse(bookmark.verseId) } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(bookmark.color.swiftUIColor)
                                .frame(width: 12, height: 12)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayReference(for: bookmark.verseId))
                                    .font(.body)
                                if !bookmark.note.isEmpty {
                                    Text(bookmark.note)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await userDataStore.deleteBookmark(id: bookmark.id) }
                        } label: {
                            Label("sidebar.removeBookmark", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Bookmarks")
    }

    private func displayReference(for verseId: String) -> String {
        let parts = verseId.split(separator: ".")
        guard parts.count == 3,
              let chapter = Int(parts[1]),
              let verse = Int(parts[2]) else { return verseId }
        let book = String(parts[0])
        let activeModule = bibleStore.modules.first(where: { $0.id == bibleStore.activeModuleId })
        let bookName = activeModule?.books.first(where: { $0.id == book })?.shortName ?? book
        return "\(bookName) \(chapter):\(verse)"
    }

    private func navigateToVerse(_ verseId: String) {
        let parts = verseId.split(separator: ".")
        guard parts.count == 3,
              let chapter = Int(parts[1]),
              let verse = Int(parts[2]) else { return }
        let book = String(parts[0])
        let location = BibleLocation(moduleId: bibleStore.activeModuleId, book: book, chapter: chapter, verseNumber: verse)
        Task {
            if let paneId = bibleStore.activePaneId {
                await bibleStore.navigate(paneId: paneId, to: location)
            }
            await MainActor.run {
                uiStateStore.selectedVerseId = verseId
            }
        }
    }
}

// MARK: - Highlights Detail

private struct FloatingHighlightsDetail: View {
    @Environment(BibleStore.self) private var bibleStore
    @Environment(UIStateStore.self) private var uiStateStore
    @Environment(UserDataStore.self) private var userDataStore
    @State private var sortMode: HighlightSortMode = .byColor

    var body: some View {
        VStack(spacing: 0) {
            if userDataStore.highlights.isEmpty {
                ContentUnavailableView("No Highlights", systemImage: "highlighter", description: Text("sidebar.noHighlightsYet"))
            } else {
                Picker("Sort", selection: $sortMode) {
                    ForEach(HighlightSortMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                List {
                    switch sortMode {
                    case .byColor:
                        let grouped = Dictionary(grouping: userDataStore.highlights) { $0.color }
                        ForEach(BookmarkColor.allCases, id: \.self) { color in
                            if let items = grouped[color], !items.isEmpty {
                                Section {
                                    ForEach(items) { highlight in
                                        highlightRow(highlight)
                                    }
                                } header: {
                                    HStack(spacing: 4) {
                                        Circle().fill(color.swiftUIColor).frame(width: 8, height: 8)
                                        Text(color.displayName)
                                    }
                                }
                            }
                        }
                    case .newestFirst:
                        ForEach(userDataStore.highlights.reversed()) { highlight in
                            highlightRow(highlight)
                        }
                    case .oldestFirst:
                        ForEach(Array(userDataStore.highlights)) { highlight in
                            highlightRow(highlight)
                        }
                    }
                }
            }
        }
        .navigationTitle("Highlights")
    }

    private func highlightRow(_ highlight: HighlightedVerse) -> some View {
        Button { navigateToVerse(highlight.verseId) } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(highlight.color.swiftUIColor)
                    .frame(width: 12, height: 12)
                Text(displayReference(for: highlight.verseId))
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                Task { await userDataStore.removeHighlight(verseId: highlight.verseId) }
            } label: {
                Label("sidebar.removeHighlight", systemImage: "trash")
            }
        }
    }

    private func displayReference(for verseId: String) -> String {
        let parts = verseId.split(separator: ".")
        guard parts.count == 3,
              let chapter = Int(parts[1]),
              let verse = Int(parts[2]) else { return verseId }
        let book = String(parts[0])
        let activeModule = bibleStore.modules.first(where: { $0.id == bibleStore.activeModuleId })
        let bookName = activeModule?.books.first(where: { $0.id == book })?.shortName ?? book
        return "\(bookName) \(chapter):\(verse)"
    }

    private func navigateToVerse(_ verseId: String) {
        let parts = verseId.split(separator: ".")
        guard parts.count == 3,
              let chapter = Int(parts[1]),
              let verse = Int(parts[2]) else { return }
        let book = String(parts[0])
        let location = BibleLocation(moduleId: bibleStore.activeModuleId, book: book, chapter: chapter, verseNumber: verse)
        Task {
            if let paneId = bibleStore.activePaneId {
                await bibleStore.navigate(paneId: paneId, to: location)
            }
            await MainActor.run { uiStateStore.selectedVerseId = verseId }
        }
    }
}

// MARK: - Notes Detail

private struct FloatingNotesDetail: View {
    @Environment(BibleStore.self) private var bibleStore
    @Environment(UIStateStore.self) private var uiStateStore
    @Environment(UserDataStore.self) private var userDataStore
    @State private var editingNoteId: UUID? = nil
    @State private var editingNoteText: String = ""

    var body: some View {
        Group {
            if userDataStore.notes.isEmpty {
                ContentUnavailableView("No Notes", systemImage: "note.text", description: Text("sidebar.noNotesYet"))
            } else {
                List(userDataStore.notes.sorted(by: { $0.createdAt < $1.createdAt })) { note in
                    if editingNoteId == note.id {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(displayReference(for: note.verseId))
                                .font(.headline)
                            TextEditor(text: $editingNoteText)
                                .frame(minHeight: 80, maxHeight: 200)
                                .scrollContentBackground(.hidden)
                                .background(Color(.textBackgroundColor).opacity(0.5))
                                .cornerRadius(6)
                            HStack(spacing: 8) {
                                Button("sidebar.save") { commitNoteEdit(noteId: note.id) }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                Button("sidebar.cancel") {
                                    editingNoteId = nil
                                    editingNoteText = ""
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        Button { navigateToVerse(note.verseId) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(displayReference(for: note.verseId))
                                    .font(.body.bold())
                                Text(note.text)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                editingNoteId = note.id
                                editingNoteText = note.text
                            } label: {
                                Label("sidebar.editNote", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                Task { await userDataStore.deleteNote(id: note.id) }
                            } label: {
                                Label("sidebar.deleteNote", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Notes")
    }

    private func commitNoteEdit(noteId: UUID) {
        let text = editingNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            Task { await userDataStore.deleteNote(id: noteId) }
        } else {
            Task { await userDataStore.updateNote(id: noteId, text: text) }
        }
        editingNoteId = nil
        editingNoteText = ""
    }

    private func displayReference(for verseId: String) -> String {
        let parts = verseId.split(separator: ".")
        guard parts.count == 3,
              let chapter = Int(parts[1]),
              let verse = Int(parts[2]) else { return verseId }
        let book = String(parts[0])
        let activeModule = bibleStore.modules.first(where: { $0.id == bibleStore.activeModuleId })
        let bookName = activeModule?.books.first(where: { $0.id == book })?.shortName ?? book
        return "\(bookName) \(chapter):\(verse)"
    }

    private func navigateToVerse(_ verseId: String) {
        let parts = verseId.split(separator: ".")
        guard parts.count == 3,
              let chapter = Int(parts[1]),
              let verse = Int(parts[2]) else { return }
        let book = String(parts[0])
        let location = BibleLocation(moduleId: bibleStore.activeModuleId, book: book, chapter: chapter, verseNumber: verse)
        Task {
            if let paneId = bibleStore.activePaneId {
                await bibleStore.navigate(paneId: paneId, to: location)
            }
            await MainActor.run { uiStateStore.selectedVerseId = verseId }
        }
    }
}

// MARK: - Strong's Detail

private struct FloatingStrongsDetail: View {
    @Environment(BibleStore.self) private var bibleStore
    @Environment(UIStateStore.self) private var uiStateStore

    @State private var wordTags: [ResolvedWordTag] = []
    @State private var selectedEntry: StrongsEntry? = nil
    @State private var similarEntries: [StrongsEntry] = []
    @State private var strongsVerses: [StrongsVerseReference] = []
    @State private var viewingVersesForEntry: StrongsEntry? = nil
    @State private var isLoadingTags = false
    @State private var isLoadingDetail = false
    @State private var isLoadingVerses = false
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let versesEntry = viewingVersesForEntry {
                versesView(for: versesEntry)
            } else if let entry = selectedEntry {
                entryDetailView(entry)
            } else if uiStateStore.selectedVerseId != nil {
                if isLoadingTags {
                    ProgressView("Loading Strong's data...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if wordTags.isEmpty {
                    ContentUnavailableView("No Strong's Data", systemImage: "character.book.closed", description: Text("sidebar.noStrongsData"))
                } else {
                    wordTagsList
                }
            } else {
                ContentUnavailableView("Select a Verse", systemImage: "character.book.closed", description: Text("sidebar.selectVerseStrongs"))
            }
        }
        .navigationTitle("Strong's Numbers")
        .onChange(of: uiStateStore.selectedVerseId) { loadData() }
        .onAppear { loadData() }
    }

    private var wordTagsList: some View {
        List(wordTags) { tag in
            Button {
                guard let entry = tag.entry else { return }
                selectedEntry = entry
                loadDetail(entry: entry)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(tag.word)
                            .font(.body.bold())
                        if let num = tag.strongsNumber {
                            Text(num)
                                .font(.callout.monospaced())
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    if let entry = tag.entry {
                        if !entry.lemma.isEmpty {
                            Text(entry.lemma)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        if let def = entry.kjvDefinition ?? entry.strongsDefinition {
                            Text(def)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func entryDetailView(_ entry: StrongsEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Back button
            Button {
                selectedEntry = nil
                similarEntries = []
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .imageScale(.small)
                    Text("Word Tags")
                }
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .padding()

            List {
                Section("Entry") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(entry.number)
                                .font(.title2.monospaced())
                                .foregroundStyle(Color.accentColor)
                            if !entry.lemma.isEmpty {
                                Text(entry.lemma)
                                    .font(.title3)
                            }
                        }
                        if !entry.transliteration.isEmpty {
                            Text(entry.transliteration)
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                        if let def = entry.strongsDefinition, !def.isEmpty {
                            Text(def)
                        }
                        if let kjv = entry.kjvDefinition, !kjv.isEmpty {
                            Text("common.kjvPrefix \(kjv)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    Button { loadVerses(entry) } label: {
                        Label("Show Verses", systemImage: "list.bullet")
                    }
                }

                if isLoadingDetail {
                    Section("Related") {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                } else if !similarEntries.isEmpty {
                    Section("Related") {
                        ForEach(similarEntries.prefix(10)) { similar in
                            Button {
                                selectedEntry = similar
                                loadDetail(entry: similar)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(similar.number)
                                            .font(.callout.monospaced())
                                            .foregroundStyle(Color.accentColor)
                                        if !similar.lemma.isEmpty {
                                            Text(similar.lemma)
                                                .font(.callout)
                                        }
                                    }
                                    if let def = similar.kjvDefinition ?? similar.strongsDefinition {
                                        Text(def)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func versesView(for entry: StrongsEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                viewingVersesForEntry = nil
                strongsVerses = []
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .imageScale(.small)
                    Text("Back to \(entry.number)")
                }
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .padding()

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.number)
                    .font(.headline.monospaced())
                    .foregroundStyle(Color.accentColor)
                if !entry.lemma.isEmpty {
                    Text(entry.lemma)
                }
            }
            .padding(.horizontal)

            if isLoadingVerses {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if strongsVerses.isEmpty {
                Text("sidebar.noVersesFound")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("\(strongsVerses.count) verses")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal)

                List(strongsVerses.prefix(100)) { ref in
                    Button { navigateToStrongsVerse(ref) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ref.displayRef)
                                .font(.callout.bold())
                                .foregroundStyle(Color.accentColor)
                            Text(ref.text)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func loadData() {
        selectedEntry = nil
        similarEntries = []
        strongsVerses = []
        viewingVersesForEntry = nil

        guard let verseId = uiStateStore.selectedVerseId else {
            wordTags = []
            return
        }

        let parts = verseId.split(separator: ".")
        guard parts.count == 3,
              let chapter = Int(parts[1]),
              let verse = Int(parts[2]) else { return }
        let book = String(parts[0])
        let moduleId = bibleStore.activeModuleId

        isLoadingTags = true
        loadTask?.cancel()
        loadTask = Task {
            let tags = await StrongsService.shared.resolvedWordTags(
                moduleId: moduleId, book: book, chapter: chapter, verse: verse
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                wordTags = tags
                isLoadingTags = false
            }
        }
    }

    private func loadDetail(entry: StrongsEntry) {
        isLoadingDetail = true
        similarEntries = []
        viewingVersesForEntry = nil
        let moduleId = bibleStore.activeModuleId
        Task {
            let similar = await StrongsService.shared.findSimilarByDefinition(number: entry.number, preferredModule: moduleId)
            await MainActor.run {
                similarEntries = similar
                isLoadingDetail = false
            }
        }
    }

    private func loadVerses(_ entry: StrongsEntry) {
        viewingVersesForEntry = entry
        isLoadingVerses = true
        strongsVerses = []
        let moduleId = bibleStore.activeModuleId
        Task {
            let verses = await StrongsService.shared.findVersesByStrongs(entry.number, moduleId: moduleId)
            await MainActor.run {
                strongsVerses = verses
                isLoadingVerses = false
            }
        }
    }

    private func navigateToStrongsVerse(_ ref: StrongsVerseReference) {
        let location = BibleLocation(moduleId: bibleStore.activeModuleId, book: ref.book, chapter: ref.chapter, verseNumber: ref.verse)
        Task {
            if let paneId = bibleStore.activePaneId {
                await bibleStore.navigate(paneId: paneId, to: location)
            }
            await MainActor.run {
                uiStateStore.selectedVerseId = "\(ref.book).\(ref.chapter).\(ref.verse)"
            }
        }
    }
}

// MARK: - Cross References Detail

private struct FloatingCrossRefsDetail: View {
    @Environment(BibleStore.self) private var bibleStore
    @Environment(UIStateStore.self) private var uiStateStore

    @State private var crossRefs: [ResolvedCrossReference] = []
    @State private var isLoading = false
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        Group {
            if uiStateStore.selectedVerseId != nil {
                if isLoading {
                    ProgressView("Loading cross references...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if crossRefs.isEmpty {
                    ContentUnavailableView("No Cross References", systemImage: "arrow.triangle.branch", description: Text("sidebar.noCrossReferences"))
                } else {
                    List(crossRefs) { ref in
                        Button { navigateToCrossRef(ref) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ref.displayRef)
                                    .font(.callout.bold())
                                    .foregroundStyle(Color.accentColor)
                                Text(ref.targetText)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                ContentUnavailableView("Select a Verse", systemImage: "arrow.triangle.branch", description: Text("sidebar.selectVerseCrossRefs"))
            }
        }
        .navigationTitle("Cross References")
        .onChange(of: uiStateStore.selectedVerseId) { loadData() }
        .onAppear { loadData() }
    }

    private func loadData() {
        guard let verseId = uiStateStore.selectedVerseId else {
            crossRefs = []
            return
        }

        let parts = verseId.split(separator: ".")
        guard parts.count == 3,
              let chapter = Int(parts[1]),
              let verse = Int(parts[2]) else { return }
        let book = String(parts[0])
        let moduleId = bibleStore.activeModuleId
        let crossVerseId = "\(book):\(chapter):\(verse)"
        let scheme = bibleStore.modules.first(where: { $0.id == moduleId })?.versificationScheme ?? .kjv

        isLoading = true
        loadTask?.cancel()
        loadTask = Task {
            async let moduleRefs = CrossReferenceService.shared.loadResolvedBidirectional(
                moduleId: moduleId, verseId: crossVerseId, scheme: scheme
            )
            async let tskRefs = CrossReferenceService.shared.loadTSKResolved(
                moduleId: moduleId, book: book, chapter: chapter, verse: verse
            )

            let modResults = await moduleRefs
            let tskResults = await tskRefs
            guard !Task.isCancelled else { return }

            let existingTargets = Set(modResults.map { "\($0.targetBook):\($0.targetChapter):\($0.targetVerse)" })
            let uniqueTsk = tskResults.filter { !existingTargets.contains("\($0.targetBook):\($0.targetChapter):\($0.targetVerse)") }

            await MainActor.run {
                crossRefs = modResults + uniqueTsk
                isLoading = false
            }
        }
    }

    private func navigateToCrossRef(_ ref: ResolvedCrossReference) {
        let location = BibleLocation(
            moduleId: bibleStore.activeModuleId,
            book: ref.targetBook,
            chapter: ref.targetChapter,
            verseNumber: ref.targetVerse
        )
        Task {
            let paneId = bibleStore.activePaneId ?? bibleStore.panes.first?.id
            if let paneId {
                await bibleStore.navigate(paneId: paneId, to: location)
            }
            await MainActor.run {
                uiStateStore.selectedVerseId = "\(ref.targetBook).\(ref.targetChapter).\(ref.targetVerse)"
            }
        }
    }
}

// MARK: - History Detail

private struct FloatingHistoryDetail: View {
    @Environment(BibleStore.self) private var bibleStore
    @Environment(UIStateStore.self) private var uiStateStore
    @Environment(UserDataStore.self) private var userDataStore

    var body: some View {
        Group {
            if userDataStore.readingHistory.isEmpty {
                ContentUnavailableView("No History", systemImage: "clock", description: Text("sidebar.noRecentHistory"))
            } else {
                List {
                    ForEach(Array(userDataStore.readingHistory.prefix(15).enumerated()), id: \.offset) { _, location in
                        Button { navigateToHistory(location) } label: {
                            Label {
                                Text(historyLabel(for: location))
                            } icon: {
                                Image(systemName: "clock")
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Section {
                        Button("sidebar.clearHistory") {
                            Task { await userDataStore.clearHistory() }
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("History")
    }

    private var activeModule: Module? {
        bibleStore.modules.first(where: { $0.id == bibleStore.activeModuleId })
    }

    private func historyLabel(for location: BibleLocation) -> String {
        let bookName = activeModule?.books.first(where: { $0.id == location.book })?.shortName ?? location.book
        if let verse = location.verseNumber {
            return "\(bookName) \(location.chapter):\(verse)"
        }
        return "\(bookName) \(location.chapter)"
    }

    private func navigateToHistory(_ location: BibleLocation) {
        guard let paneId = bibleStore.activePaneId else { return }
        Task {
            await bibleStore.navigate(paneId: paneId, to: location)
            if let verse = location.verseNumber {
                await MainActor.run {
                    uiStateStore.selectedVerseId = "\(location.book).\(location.chapter).\(verse)"
                }
            }
        }
    }
}
