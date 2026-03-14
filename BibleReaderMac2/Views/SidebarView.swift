import SwiftUI

struct SidebarView: View {
    let sidebarHeight: CGFloat

    @Environment(BibleStore.self) private var bibleStore
    @Environment(UIStateStore.self) private var uiStateStore
    @Environment(UserDataStore.self) private var userDataStore

    // Notes inline editing
    @State private var editingNoteId: UUID? = nil
    @State private var editingNoteText: String = ""

    // Highlights sort
    @State private var highlightSortMode: HighlightSortMode = .byColor

    // Strong's & cross-ref state
    @State private var wordTags: [ResolvedWordTag] = []
    @State private var crossRefs: [ResolvedCrossReference] = []
    @State private var selectedStrongsEntry: StrongsEntry? = nil
    @State private var selectedStrongsNumber: String? = nil
    @State private var strongsVerses: [StrongsVerseReference] = []
    @State private var similarEntries: [StrongsEntry] = []
    @State private var isLoadingStrongs = false
    @State private var isLoadingCrossRefs = false
    @State private var isLoadingDetail = false
    @State private var strongsTask: Task<Void, Never>?
    @State private var crossRefTask: Task<Void, Never>?

    // MARK: - Computed

    private var activeModule: Module? {
        bibleStore.modules.first(where: { $0.id == bibleStore.activeModuleId })
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                bookmarksSection
                highlightsSection
                notesSection
                strongsSection
                crossReferencesSection
                searchSection
                recentHistorySection
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(maxHeight: sidebarHeight - 8)
        .symbolRenderingMode(.hierarchical)
        .onChange(of: uiStateStore.selectedVerseId) {
            loadStrongsData()
            loadCrossRefData()
        }
        .onChange(of: uiStateStore.selectedStrongsId) {
            autoSelectStrongsEntry()
        }
    }

    // MARK: - 1. Bookmarks

    private var bookmarksSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (always visible)
            Button {
                uiStateStore.toggleSection(.bookmarks)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bookmark.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                    Text("sidebar.bookmarks")
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                uiStateStore.isSectionExpanded(.bookmarks)
                    ? Color.accentColor.opacity(0.15)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .animation(.spring(duration: 0.25, bounce: 0.1), value: uiStateStore.isSectionExpanded(.bookmarks))

            // Content (expandable)
            if uiStateStore.isSectionExpanded(.bookmarks) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if userDataStore.bookmarks.isEmpty {
                            Text("sidebar.noBookmarksYet")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(userDataStore.bookmarks.sorted(by: { $0.createdAt > $1.createdAt })) { bookmark in
                                Button {
                                    navigateToBookmark(bookmark)
                                } label: {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(swiftColor(for: bookmark.color))
                                            .frame(width: 10, height: 10)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(bookmark.verseId)
                                                .font(.subheadline)
                                            if !bookmark.note.isEmpty {
                                                Text(bookmark.note)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
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
                    .padding(.leading, 6)
                }
                .frame(maxHeight: sidebarHeight * 0.4)
            }
        }
    }

    // MARK: - 2. Highlights

    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (always visible)
            Button {
                uiStateStore.toggleSection(.highlights)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "highlighter")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                    Text("sidebar.highlights")
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                uiStateStore.isSectionExpanded(.highlights)
                    ? Color.accentColor.opacity(0.15)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .animation(.spring(duration: 0.25, bounce: 0.1), value: uiStateStore.isSectionExpanded(.highlights))

            // Content (expandable)
            if uiStateStore.isSectionExpanded(.highlights) {
                // Sort picker
                Picker("Sort", selection: $highlightSortMode) {
                    ForEach(HighlightSortMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 6)
                .padding(.top, 4)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if userDataStore.highlights.isEmpty {
                            Text("sidebar.noHighlightsYet")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            switch highlightSortMode {
                            case .byColor:
                                highlightsByColorContent
                            case .newestFirst:
                                highlightsListContent(highlights: userDataStore.highlights.reversed())
                            case .oldestFirst:
                                highlightsListContent(highlights: Array(userDataStore.highlights))
                            }
                        }
                    }
                    .padding(.leading, 6)
                }
                .frame(maxHeight: sidebarHeight * 0.4)
            }
        }
    }

    private var highlightsByColorContent: some View {
        let grouped = Dictionary(grouping: userDataStore.highlights) { $0.color }
        return ForEach(BookmarkColor.allCases, id: \.self) { color in
            if let items = grouped[color], !items.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(swiftColor(for: color))
                            .frame(width: 8, height: 8)
                        Text(String(localized: String.LocalizationValue("color.\(color.rawValue)")))
                            .font(.caption)
                    }
                    .padding(.top, 4)
                    ForEach(items) { highlight in
                        highlightRow(highlight)
                    }
                }
            }
        }
    }

    private func highlightsListContent(highlights: [HighlightedVerse]) -> some View {
        ForEach(highlights) { highlight in
            highlightRow(highlight)
        }
    }

    private func highlightRow(_ highlight: HighlightedVerse) -> some View {
        Button {
            navigateToVerseId(highlight.verseId)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(swiftColor(for: highlight.color))
                    .frame(width: 10, height: 10)
                Text(displayReference(for: highlight.verseId))
                    .font(.subheadline)
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
        let bookName = activeModule?.books.first(where: { $0.id == book })?.shortName ?? book
        return "\(bookName) \(chapter):\(verse)"
    }

    // MARK: - 3. Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (always visible)
            Button {
                uiStateStore.toggleSection(.notes)
            } label: {
                HStack {
                    Image(systemName: "note.text")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                    Text("sidebar.notes")
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                uiStateStore.isSectionExpanded(.notes)
                    ? Color.accentColor.opacity(0.15)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .animation(.spring(duration: 0.25, bounce: 0.1), value: uiStateStore.isSectionExpanded(.notes))

            // Content (expandable)
            if uiStateStore.isSectionExpanded(.notes) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if userDataStore.notes.isEmpty {
                            Text("sidebar.noNotesYet")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(userDataStore.notes.sorted(by: { $0.createdAt < $1.createdAt })) { note in
                                if editingNoteId == note.id {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(displayReference(for: note.verseId))
                                            .font(.subheadline.bold())
                                        TextEditor(text: $editingNoteText)
                                            .font(.caption)
                                            .frame(minHeight: 60, maxHeight: 120)
                                            .scrollContentBackground(.hidden)
                                            .background(Color(.textBackgroundColor).opacity(0.5))
                                            .cornerRadius(4)
                                        HStack(spacing: 8) {
                                            Button("sidebar.save") {
                                                commitNoteEdit(noteId: note.id)
                                            }
                                            .font(.caption)
                                            .buttonStyle(.borderedProminent)
                                            .controlSize(.small)
                                            Button("sidebar.cancel") {
                                                editingNoteId = nil
                                                editingNoteText = ""
                                            }
                                            .font(.caption)
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                } else {
                                    Button {
                                        navigateToVerseId(note.verseId)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(displayReference(for: note.verseId))
                                                .font(.subheadline.bold())
                                            Text(truncateNoteText(note.text))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
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
                    .padding(.leading, 6)
                }
                .frame(maxHeight: sidebarHeight * 0.4)
            }
        }
    }

    private func truncateNoteText(_ text: String) -> String {
        if text.count <= 60 { return text }
        return String(text.prefix(60)) + "..."
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

    // MARK: - 4. Strong's Numbers

    private var strongsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (always visible)
            Button {
                uiStateStore.toggleSection(.strongs)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "character.book.closed")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                    Text("sidebar.strongsNumbers")
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                uiStateStore.isSectionExpanded(.strongs)
                    ? Color.accentColor.opacity(0.15)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .animation(.spring(duration: 0.25, bounce: 0.1), value: uiStateStore.isSectionExpanded(.strongs))

            // Content (expandable)
            if uiStateStore.isSectionExpanded(.strongs) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if selectedStrongsEntry != nil {
                            strongsDetailContent
                        } else if uiStateStore.selectedVerseId != nil {
                            if isLoadingStrongs {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            } else if wordTags.isEmpty {
                                Text("sidebar.noStrongsData")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            } else {
                                ForEach(wordTags) { tag in
                                    sidebarWordTagRow(tag)
                                }
                            }
                        } else {
                            Text("sidebar.selectVerseStrongs")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.leading, 6)
                }
                .frame(maxHeight: sidebarHeight * 0.4)
            }
        }
    }

    private func sidebarWordTagRow(_ tag: ResolvedWordTag) -> some View {
        Button {
            guard let entry = tag.entry else { return }
            selectedStrongsNumber = tag.strongsNumber
            selectedStrongsEntry = entry
            loadStrongsDetail(entry: entry)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tag.word)
                        .font(.subheadline.bold())
                    if let num = tag.strongsNumber {
                        Text(num)
                            .font(.caption.monospaced())
                            .foregroundStyle(Color.accentColor)
                    }
                }
                if let entry = tag.entry {
                    if !entry.lemma.isEmpty {
                        Text(entry.lemma)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let def = entry.kjvDefinition ?? entry.strongsDefinition {
                        Text(def)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var strongsDetailContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                selectedStrongsEntry = nil
                selectedStrongsNumber = nil
                strongsVerses = []
                similarEntries = []
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("sidebar.backToWords")
                }
                .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)

            if let entry = selectedStrongsEntry {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(entry.number)
                            .font(.headline.monospaced())
                            .foregroundStyle(Color.accentColor)
                        if !entry.lemma.isEmpty {
                            Text(entry.lemma)
                                .font(.subheadline)
                        }
                    }

                    if !entry.transliteration.isEmpty {
                        Text(entry.transliteration)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                    }

                    if let strongsDef = entry.strongsDefinition, !strongsDef.isEmpty {
                        Text(strongsDef)
                            .font(.caption)
                    }

                    if let kjvDef = entry.kjvDefinition, !kjvDef.isEmpty {
                        Text("common.kjvPrefix \(kjvDef)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if isLoadingDetail {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                } else if !strongsVerses.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("sidebar.versesCount \(strongsVerses.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        ForEach(strongsVerses.prefix(15)) { ref in
                            Button {
                                navigateToStrongsVerse(ref)
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(ref.displayRef)
                                        .font(.caption.bold())
                                        .foregroundStyle(Color.accentColor)
                                    Text(ref.text)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        if strongsVerses.count > 15 {
                            Text("sidebar.moreCount \(strongsVerses.count - 15)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                if !similarEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("sidebar.related")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        ForEach(similarEntries.prefix(6)) { similar in
                            Button {
                                selectedStrongsEntry = similar
                                selectedStrongsNumber = similar.number
                                loadStrongsDetail(entry: similar)
                            } label: {
                                HStack(spacing: 4) {
                                    Text(similar.number)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(Color.accentColor)
                                    if !similar.lemma.isEmpty {
                                        Text(similar.lemma)
                                            .font(.caption)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // "See all verses" button — triggers search filtered by Strong's number
                Button {
                    uiStateStore.searchQuery = entry.number
                    uiStateStore.expandedSidebarSections.insert(SidebarSection.search.rawValue)
                    Task {
                        await uiStateStore.performSearch(using: bibleStore)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                        Text("sidebar.seeAllVerses")
                    }
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - 5. Cross References

    private var crossReferencesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (always visible)
            Button {
                uiStateStore.toggleSection(.crossReferences)
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.branch")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                    Text("sidebar.crossReferences")
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                uiStateStore.isSectionExpanded(.crossReferences)
                    ? Color.accentColor.opacity(0.15)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .animation(.spring(duration: 0.25, bounce: 0.1), value: uiStateStore.isSectionExpanded(.crossReferences))

            // Content (expandable)
            if uiStateStore.isSectionExpanded(.crossReferences) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if uiStateStore.selectedVerseId != nil {
                            if isLoadingCrossRefs {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            } else if crossRefs.isEmpty {
                                Text("sidebar.noCrossReferences")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            } else {
                                ForEach(crossRefs) { ref in
                                    Button {
                                        navigateToCrossRef(ref)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(ref.displayRef)
                                                .font(.subheadline.bold())
                                                .foregroundStyle(Color.accentColor)
                                            Text(ref.targetText)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } else {
                            Text("sidebar.selectVerseCrossRefs")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.leading, 6)
                }
                .frame(maxHeight: sidebarHeight * 0.4)
            }
        }
    }

    // MARK: - 6. Search

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (always visible)
            Button {
                uiStateStore.toggleSection(.search)
            } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                    Text("sidebar.search")
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                uiStateStore.isSectionExpanded(.search)
                    ? Color.accentColor.opacity(0.15)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .animation(.spring(duration: 0.25, bounce: 0.1), value: uiStateStore.isSectionExpanded(.search))

            // Content (expandable)
            if uiStateStore.isSectionExpanded(.search) {
                @Bindable var uiState = uiStateStore

                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        TextField("sidebar.searchIn \(activeModuleName)", text: $uiState.searchQuery)
                            .textFieldStyle(.plain)
                            .font(.subheadline)
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
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                    .background(Color(.textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                }
                .padding(.leading, 6)

                if uiStateStore.searchResults.isEmpty && !uiStateStore.searchQuery.isEmpty {
                    Text("sidebar.noResultsFor \(uiStateStore.searchQuery)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 6)
                } else if !uiStateStore.searchResults.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(uiStateStore.searchResults) { verse in
                                Button {
                                    navigateToSearchResult(verse)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(verseReference(verse))
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.secondary)
                                        Text(verse.text)
                                            .font(.caption)
                                            .lineLimit(2)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.leading, 6)
                    }
                    .frame(maxHeight: sidebarHeight * 0.4)
                }
            }
        }
    }

    // MARK: - 7. Recent History

    private var recentHistorySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (always visible)
            Button {
                uiStateStore.toggleSection(.recentHistory)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                    Text("sidebar.recentHistory")
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                uiStateStore.isSectionExpanded(.recentHistory)
                    ? Color.accentColor.opacity(0.15)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .animation(.spring(duration: 0.25, bounce: 0.1), value: uiStateStore.isSectionExpanded(.recentHistory))

            // Content (expandable)
            if uiStateStore.isSectionExpanded(.recentHistory) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if userDataStore.readingHistory.isEmpty {
                            Text("sidebar.noRecentHistory")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(Array(userDataStore.readingHistory.prefix(15).enumerated()), id: \.offset) { _, location in
                                Button {
                                    navigateToHistory(location)
                                } label: {
                                    Label {
                                        Text(historyLabel(for: location))
                                            .font(.subheadline)
                                    } icon: {
                                        Image(systemName: "clock")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }

                            if !userDataStore.readingHistory.isEmpty {
                                Button("sidebar.clearHistory") {
                                    Task { await userDataStore.clearHistory() }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.leading, 6)
                }
                .frame(maxHeight: sidebarHeight * 0.4)
            }
        }
    }

    // MARK: - Navigation Helpers

    private func navigateToBookmark(_ bookmark: Bookmark) {
        let parts = bookmark.verseId.split(separator: ".")
        guard parts.count == 3,
              let chapter = Int(parts[1]),
              let verse = Int(parts[2]) else { return }
        let book = String(parts[0])
        let moduleId = bibleStore.activeModuleId
        let location = BibleLocation(moduleId: moduleId, book: book, chapter: chapter, verseNumber: verse)

        Task {
            if let paneId = bibleStore.activePaneId {
                await bibleStore.navigate(paneId: paneId, to: location)
            }
            await MainActor.run {
                uiStateStore.selectedVerseId = bookmark.verseId
            }
        }
    }

    private func navigateToVerseId(_ verseId: String) {
        let parts = verseId.split(separator: ".")
        guard parts.count == 3,
              let chapter = Int(parts[1]),
              let verse = Int(parts[2]) else { return }
        let book = String(parts[0])
        let moduleId = bibleStore.activeModuleId
        let location = BibleLocation(moduleId: moduleId, book: book, chapter: chapter, verseNumber: verse)

        Task {
            if let paneId = bibleStore.activePaneId {
                await bibleStore.navigate(paneId: paneId, to: location)
            }
            await MainActor.run {
                uiStateStore.selectedVerseId = verseId
            }
        }
    }

    private func navigateToCrossRef(_ ref: ResolvedCrossReference) {
        let moduleId = bibleStore.activeModuleId
        let location = BibleLocation(
            moduleId: moduleId,
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

    private func navigateToStrongsVerse(_ ref: StrongsVerseReference) {
        let moduleId = bibleStore.activeModuleId
        let location = BibleLocation(moduleId: moduleId, book: ref.book, chapter: ref.chapter, verseNumber: ref.verse)
        Task {
            if let paneId = bibleStore.activePaneId {
                await bibleStore.navigate(paneId: paneId, to: location)
            }
            await MainActor.run {
                uiStateStore.selectedVerseId = "\(ref.book).\(ref.chapter).\(ref.verse)"
            }
        }
    }

    private func navigateToSearchResult(_ verse: Verse) {
        guard let paneId = bibleStore.activePaneId else { return }
        let location = BibleLocation(
            moduleId: bibleStore.activeModuleId,
            book: verse.book,
            chapter: verse.chapter,
            verseNumber: verse.verseNumber
        )
        Task {
            await bibleStore.navigate(paneId: paneId, to: location)
            await MainActor.run {
                uiStateStore.selectedVerseId = verse.id
            }
        }
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

    // MARK: - Display Helpers

    private func historyLabel(for location: BibleLocation) -> String {
        let bookName = activeModule?.books.first(where: { $0.id == location.book })?.shortName ?? location.book
        if let verse = location.verseNumber {
            return "\(bookName) \(location.chapter):\(verse)"
        }
        return "\(bookName) \(location.chapter)"
    }

    private var activeModuleName: String {
        bibleStore.modules.first(where: { $0.id == bibleStore.activeModuleId })?.abbreviation ?? "Bible"
    }

    private func verseReference(_ verse: Verse) -> String {
        let bookName = bibleStore.modules
            .first(where: { $0.id == bibleStore.activeModuleId })?
            .books.first(where: { $0.id == verse.book })?.name ?? verse.book
        return "\(bookName) \(verse.chapter):\(verse.verseNumber)"
    }

    private func swiftColor(for color: BookmarkColor) -> Color {
        switch color {
        case .yellow: .yellow
        case .blue: .blue
        case .green: .green
        case .orange: .orange
        case .purple: .purple
        }
    }

    // MARK: - Data Loading

    private func loadStrongsData() {
        guard uiStateStore.isSectionExpanded(.strongs) else { return }

        selectedStrongsEntry = nil
        selectedStrongsNumber = nil
        strongsVerses = []
        similarEntries = []

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

        isLoadingStrongs = true
        strongsTask?.cancel()
        strongsTask = Task {
            let tags = await StrongsService.shared.resolvedWordTags(
                moduleId: moduleId,
                book: book,
                chapter: chapter,
                verse: verse
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                wordTags = tags
                isLoadingStrongs = false
                autoSelectStrongsEntry()
            }
        }
    }

    private func loadCrossRefData() {
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

        isLoadingCrossRefs = true
        crossRefTask?.cancel()
        crossRefTask = Task {
            async let moduleRefs = CrossReferenceService.shared.loadResolvedBidirectional(
                moduleId: moduleId,
                verseId: crossVerseId,
                scheme: scheme
            )
            async let tskRefs = CrossReferenceService.shared.loadTSKResolved(
                moduleId: moduleId,
                book: book,
                chapter: chapter,
                verse: verse
            )

            let modResults = await moduleRefs
            let tskResults = await tskRefs

            guard !Task.isCancelled else { return }

            // Merge, deduplicating by target verse
            let existingTargets = Set(modResults.map { "\($0.targetBook):\($0.targetChapter):\($0.targetVerse)" })
            let uniqueTsk = tskResults.filter { !existingTargets.contains("\($0.targetBook):\($0.targetChapter):\($0.targetVerse)") }

            await MainActor.run {
                crossRefs = modResults + uniqueTsk
                isLoadingCrossRefs = false
            }
        }
    }

    private func autoSelectStrongsEntry() {
        guard let strongsId = uiStateStore.selectedStrongsId else { return }
        // Try to find the matching entry in already-loaded word tags
        if let tag = wordTags.first(where: { $0.strongsNumber == strongsId }),
           let entry = tag.entry {
            selectedStrongsNumber = strongsId
            selectedStrongsEntry = entry
            loadStrongsDetail(entry: entry)
            uiStateStore.selectedStrongsId = nil
        }
        // If word tags aren't loaded yet, loadStrongsData will call us after loading
    }

    private func loadStrongsDetail(entry: StrongsEntry) {
        let moduleId = bibleStore.activeModuleId
        let number = entry.number
        isLoadingDetail = true
        strongsVerses = []
        similarEntries = []

        Task {
            async let versesResult = StrongsService.shared.findVersesByStrongs(number, moduleId: moduleId)
            async let similarResult = StrongsService.shared.findSimilarByDefinition(number: number, preferredModule: moduleId)

            let verses = await versesResult
            let similar = await similarResult

            await MainActor.run {
                strongsVerses = verses
                similarEntries = similar
                isLoadingDetail = false
            }
        }
    }
}
