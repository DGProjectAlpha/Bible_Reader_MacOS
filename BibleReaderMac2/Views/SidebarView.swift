import SwiftUI

struct SidebarView: View {
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
    @State private var viewingVersesForEntry: StrongsEntry? = nil
    @State private var isLoadingStrongs = false
    @State private var isLoadingCrossRefs = false
    @State private var isLoadingDetail = false
    @State private var isLoadingVerses = false
    @State private var strongsTask: Task<Void, Never>?
    @State private var crossRefTask: Task<Void, Never>?

    // MARK: - Computed

    private var activeModule: Module? {
        bibleStore.modules.first(where: { $0.id == bibleStore.activeModuleId })
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            let availableHeight = geometry.size.height
            VStack(spacing: 0) {
                // Pinned search bar at top
                searchSection
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        bookmarksSection(availableHeight: availableHeight)
                        highlightsSection(availableHeight: availableHeight)
                        notesSection(availableHeight: availableHeight)
                        strongsSection(availableHeight: availableHeight)
                        crossReferencesSection(availableHeight: availableHeight)
                        recentHistorySection(availableHeight: availableHeight)
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                }
            }
        }
        .glassEffect(.regular.tint(uiStateStore.sidebarTintColor.opacity(0.15)))
        .symbolRenderingMode(.hierarchical)
        .onChange(of: uiStateStore.selectedVerseId) {
            loadStrongsData()
            loadCrossRefData()
        }
        .onChange(of: uiStateStore.selectedStrongsId) {
            if wordTags.isEmpty {
                loadStrongsData()
            } else {
                autoSelectStrongsEntry()
            }
        }
        .onChange(of: uiStateStore.selectedStrongsWord) {
            if wordTags.isEmpty {
                loadStrongsData()
            } else {
                autoSelectStrongsEntryByWord()
            }
        }
    }

    // MARK: - 1. Bookmarks

    private func bookmarksSection(availableHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (always visible)
            Button {
                uiStateStore.toggleSection(.bookmarks)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bookmark.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                    Text("sidebar.bookmarks")
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                uiStateStore.isSectionExpanded(.bookmarks)
                    ? Color.primary.opacity(0.08)
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
                .frame(maxHeight: availableHeight * 0.4)
            }
        }
    }

    // MARK: - 2. Highlights

    private func highlightsSection(availableHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (always visible)
            Button {
                uiStateStore.toggleSection(.highlights)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "highlighter")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                    Text("sidebar.highlights")
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                uiStateStore.isSectionExpanded(.highlights)
                    ? Color.primary.opacity(0.08)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .animation(.spring(duration: 0.25, bounce: 0.1), value: uiStateStore.isSectionExpanded(.highlights))

            // Content (expandable)
            if uiStateStore.isSectionExpanded(.highlights) {
                // Sort picker
                Picker(selection: $highlightSortMode) {
                    ForEach(HighlightSortMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                } label: {
                    EmptyView()
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)
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
                .frame(maxHeight: availableHeight * 0.4)
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
                        Text(color.displayName)
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

    private func notesSection(availableHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (always visible)
            Button {
                uiStateStore.toggleSection(.notes)
            } label: {
                HStack {
                    Image(systemName: "note.text")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                    Text("sidebar.notes")
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                uiStateStore.isSectionExpanded(.notes)
                    ? Color.primary.opacity(0.08)
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
                .frame(maxHeight: availableHeight * 0.4)
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

    private func strongsSection(availableHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (always visible)
            Button {
                uiStateStore.toggleSection(.strongs)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "character.book.closed")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                    Text("sidebar.strongsNumbers")
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                uiStateStore.isSectionExpanded(.strongs)
                    ? Color.primary.opacity(0.08)
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
                .frame(maxHeight: availableHeight * 0.4)
            }
        }
    }

    @State private var hoveredWordTag: Int? = nil

    private func sidebarWordTagRow(_ tag: ResolvedWordTag) -> some View {
        let isHovered = hoveredWordTag == tag.id
        return Button {
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
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if #available(macOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.clear)
                        .glassEffect(.regular.tint(Color.accentColor.opacity(isHovered ? 0.12 : 0)), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHovered ? Color.accentColor.opacity(0.08) : Color.clear)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredWordTag = hovering ? tag.id : nil
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    @State private var hoveredVerseRef: UUID? = nil
    @State private var hoveredSimilar: String? = nil
    @State private var hoveredStrongsEntry: String? = nil

    private var strongsDetailContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let versesEntry = viewingVersesForEntry {
                // VERSES VIEW — showing verses for a specific Strong's entry
                strongsVersesView(for: versesEntry)
            } else if let entry = selectedStrongsEntry {
                // DETAIL VIEW — exact entry + similar entries
                strongsEntryCard(entry)

                // Similar / synonym entries
                if isLoadingDetail {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                } else if !similarEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("sidebar.related")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                        ForEach(similarEntries.prefix(10)) { similar in
                            strongsEntryRow(similar)
                        }
                    }
                }
            }
        }
    }

    // Card showing a Strong's entry (number, lemma, definition) — clickable to see verses
    private func strongsEntryCard(_ entry: StrongsEntry) -> some View {
        let isHovered = hoveredStrongsEntry == entry.number
        return Button {
            loadVersesForEntry(entry)
        } label: {
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
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if #available(macOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.clear)
                        .glassEffect(.regular.tint(Color.accentColor.opacity(isHovered ? 0.10 : 0.06)), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(isHovered ? 0.08 : 0.05))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in hoveredStrongsEntry = hovering ? entry.number : nil }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    // Row for a similar/synonym entry — clickable to see its verses
    private func strongsEntryRow(_ entry: StrongsEntry) -> some View {
        let isHovered = hoveredSimilar == entry.number
        return Button {
            loadVersesForEntry(entry)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.number)
                        .font(.caption.monospaced())
                        .foregroundStyle(Color.accentColor)
                    if !entry.lemma.isEmpty {
                        Text(entry.lemma)
                            .font(.caption)
                    }
                }
                if let def = entry.kjvDefinition ?? entry.strongsDefinition {
                    Text(def)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if #available(macOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.clear)
                        .glassEffect(.regular.tint(Color.accentColor.opacity(isHovered ? 0.10 : 0)), in: RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.accentColor.opacity(0.06) : Color.clear)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in hoveredSimilar = hovering ? entry.number : nil }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    // Verses view — shows list of verses using a specific Strong's number
    private func strongsVersesView(for entry: StrongsEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Back button
            Button {
                viewingVersesForEntry = nil
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .symbolRenderingMode(.hierarchical)
                        .imageScale(.small)
                    Text("sidebar.back")
                }
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)

            // Entry summary
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.number)
                    .font(.subheadline.monospaced().bold())
                    .foregroundStyle(Color.accentColor)
                if !entry.lemma.isEmpty {
                    Text(entry.lemma)
                        .font(.caption)
                }
            }

            if isLoadingVerses {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else if strongsVerses.isEmpty {
                Text("sidebar.noVersesFound")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("\(strongsVerses.count) verses")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                ForEach(strongsVerses.prefix(100)) { ref in
                    Button {
                        navigateToStrongsVerse(ref)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
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
            }
        }
    }

    private func loadVersesForEntry(_ entry: StrongsEntry) {
        viewingVersesForEntry = entry
        isLoadingVerses = true
        strongsVerses = []
        let moduleId = bibleStore.activeModuleId
        let number = entry.number
        Task {
            let verses = await StrongsService.shared.findVersesByStrongs(number, moduleId: moduleId)
            await MainActor.run {
                strongsVerses = verses
                isLoadingVerses = false
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

    // MARK: - 5. Cross References

    private func crossReferencesSection(availableHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (always visible)
            Button {
                uiStateStore.toggleSection(.crossReferences)
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.branch")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                    Text("sidebar.crossReferences")
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                uiStateStore.isSectionExpanded(.crossReferences)
                    ? Color.primary.opacity(0.08)
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
                .frame(maxHeight: availableHeight * 0.4)
            }
        }
    }

    // MARK: - 6. Search

    private var searchSection: some View {
        @Bindable var uiState = uiStateStore

        return VStack(alignment: .leading, spacing: 6) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField(String(localized: "sidebar.search"), text: $uiState.searchQuery)
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
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(Color(.textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

            if uiStateStore.searchResults.isEmpty && !uiStateStore.searchQuery.isEmpty {
                Text("sidebar.noResultsFor \(uiStateStore.searchQuery)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else if !uiStateStore.searchResults.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(uiStateStore.searchResults) { result in
                            Button {
                                navigateToSearchResult(result)
                            } label: {
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
                                        .font(.caption)
                                        .lineLimit(2)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .padding(.bottom, 6)
    }

    // MARK: - 7. Recent History

    private func recentHistorySection(availableHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (always visible)
            Button {
                uiStateStore.toggleSection(.recentHistory)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                    Text("sidebar.recentHistory")
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                uiStateStore.isSectionExpanded(.recentHistory)
                    ? Color.primary.opacity(0.08)
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
                                            .symbolRenderingMode(.hierarchical)
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
                .frame(maxHeight: availableHeight * 0.4)
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

    private func navigateToSearchResult(_ result: SearchResult) {
        guard let paneId = bibleStore.activePaneId else { return }
        let location = BibleLocation(
            moduleId: result.moduleId,
            book: result.verse.book,
            chapter: result.verse.chapter,
            verseNumber: result.verse.verseNumber
        )
        Task {
            // Switch active module if needed
            if bibleStore.activeModuleId != result.moduleId {
                bibleStore.activeModuleId = result.moduleId
            }
            await bibleStore.navigate(paneId: paneId, to: location)
            await MainActor.run {
                uiStateStore.selectedVerseId = result.verse.id
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

    private func searchVerseReference(_ result: SearchResult) -> String {
        let bookName = bibleStore.modules
            .first(where: { $0.id == result.moduleId })?
            .books.first(where: { $0.id == result.verse.book })?.name ?? result.verse.book
        return "\(bookName) \(result.verse.chapter):\(result.verse.verseNumber)"
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
        // Always load if strongs section is expanded OR if a word/strongs was just tapped
        let hasPendingLookup = uiStateStore.selectedStrongsId != nil || uiStateStore.selectedStrongsWord != nil
        guard uiStateStore.isSectionExpanded(.strongs) || hasPendingLookup else { return }

        selectedStrongsEntry = nil
        selectedStrongsNumber = nil
        strongsVerses = []
        similarEntries = []
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
                autoSelectStrongsEntryByWord()
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

    private func autoSelectStrongsEntryByWord() {
        guard let word = uiStateStore.selectedStrongsWord else { return }
        let lowered = word.lowercased()

        // Try matching the clicked word against loaded word tags first
        if let tag = wordTags.first(where: { $0.word.lowercased() == lowered }),
           let entry = tag.entry {
            selectedStrongsNumber = tag.strongsNumber
            selectedStrongsEntry = entry
            loadStrongsDetail(entry: entry)
            uiStateStore.selectedStrongsWord = nil
        } else if !wordTags.isEmpty {
            // Word tags loaded but no match — do a reverse-index search by word text
            // so we never fall back to showing the full verse word list
            uiStateStore.selectedStrongsWord = nil
            let moduleId = bibleStore.activeModuleId
            isLoadingDetail = true
            Task {
                let result = await StrongsService.shared.searchSimilar(word: word, preferredModule: moduleId)
                await MainActor.run {
                    if let exact = result.exact {
                        selectedStrongsNumber = exact.number
                        selectedStrongsEntry = exact
                        similarEntries = result.similar
                        isLoadingDetail = false
                    } else {
                        isLoadingDetail = false
                    }
                }
            }
        }
        // If word tags aren't loaded yet, loadStrongsData will call us after loading
    }

    private func loadStrongsDetail(entry: StrongsEntry) {
        let moduleId = bibleStore.activeModuleId
        let number = entry.number
        isLoadingDetail = true
        similarEntries = []
        viewingVersesForEntry = nil

        Task {
            let similar = await StrongsService.shared.findSimilarByDefinition(number: number, preferredModule: moduleId)

            await MainActor.run {
                similarEntries = similar
                isLoadingDetail = false
            }
        }
    }
}
