import SwiftUI

struct SidebarView: View {
    @Environment(BibleStore.self) private var bibleStore
    @Environment(UIStateStore.self) private var uiStateStore
    @Environment(UserDataStore.self) private var userDataStore

    // Notes inline editing
    @State private var editingNoteId: UUID? = nil
    @State private var editingNoteText: String = ""

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

    // MARK: - Computed

    private var activeModule: Module? {
        bibleStore.modules.first(where: { $0.id == bibleStore.activeModuleId })
    }

    // MARK: - Body

    var body: some View {
        List {
            bookmarksSection
            highlightsSection
            notesSection
            strongsSection
            crossReferencesSection
            searchSection
            recentHistorySection
        }
        .listStyle(.sidebar)
        .onChange(of: uiStateStore.selectedVerseId) {
            loadStrongsData()
            loadCrossRefData()
        }
    }

    // MARK: - 1. Bookmarks

    private var bookmarksSection: some View {
        DisclosureGroup(
            isExpanded: uiStateStore.bindingForSection(.bookmarks)
        ) {
            if userDataStore.bookmarks.isEmpty {
                Text("No bookmarks yet")
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
                            Label("Remove Bookmark", systemImage: "trash")
                        }
                    }
                }
            }
        } label: {
            Label("Bookmarks", systemImage: "bookmark.fill")
        }
        .padding(.vertical, 2)

    }

    // MARK: - 2. Highlights

    private var highlightsSection: some View {
        DisclosureGroup(
            isExpanded: uiStateStore.bindingForSection(.highlights)
        ) {
            let grouped = Dictionary(grouping: userDataStore.highlights) { $0.color }
            if grouped.isEmpty {
                Text("No highlights yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(BookmarkColor.allCases, id: \.self) { color in
                    if let items = grouped[color], !items.isEmpty {
                        Section {
                            ForEach(items) { highlight in
                                Button {
                                    navigateToVerseId(highlight.verseId)
                                } label: {
                                    Text(highlight.verseId)
                                        .font(.subheadline)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        Task { await userDataStore.removeHighlight(verseId: highlight.verseId) }
                                    } label: {
                                        Label("Remove Highlight", systemImage: "trash")
                                    }
                                }
                            }
                        } header: {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(swiftColor(for: color))
                                    .frame(width: 8, height: 8)
                                Text(color.rawValue.capitalized)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
        } label: {
            Label("Highlights", systemImage: "paintbrush")
        }
        .padding(.vertical, 2)
    }

    // MARK: - 3. Notes

    private var notesSection: some View {
        DisclosureGroup(
            isExpanded: uiStateStore.bindingForSection(.notes)
        ) {
            if userDataStore.notes.isEmpty {
                Text("No notes yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(userDataStore.notes.sorted(by: { $0.updatedAt > $1.updatedAt })) { note in
                    if editingNoteId == note.id {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.verseId)
                                .font(.subheadline.bold())
                            TextEditor(text: $editingNoteText)
                                .font(.caption)
                                .frame(minHeight: 60, maxHeight: 120)
                                .scrollContentBackground(.hidden)
                                .background(Color(.textBackgroundColor).opacity(0.5))
                                .cornerRadius(4)
                            HStack(spacing: 8) {
                                Button("Save") {
                                    commitNoteEdit(noteId: note.id)
                                }
                                .font(.caption)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                Button("Cancel") {
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
                            editingNoteId = note.id
                            editingNoteText = note.text
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.verseId)
                                    .font(.subheadline.bold())
                                Text(note.text)
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
                                Label("Edit Note", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                Task { await userDataStore.deleteNote(id: note.id) }
                            } label: {
                                Label("Delete Note", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        } label: {
            Label("Notes", systemImage: "note.text")
        }
        .padding(.vertical, 2)
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
        DisclosureGroup(
            isExpanded: uiStateStore.bindingForSection(.strongs)
        ) {
            if selectedStrongsEntry != nil {
                strongsDetailContent
            } else if uiStateStore.selectedVerseId != nil {
                if isLoadingStrongs {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } else if wordTags.isEmpty {
                    Text("No Strong's data for this verse")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(wordTags) { tag in
                        sidebarWordTagRow(tag)
                    }
                }
            } else {
                Text("Select a verse to view Strong's numbers")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        } label: {
            Label("Strong's Numbers", systemImage: "textformat.123")
        }
        .padding(.vertical, 2)
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
        Group {
            Button {
                selectedStrongsEntry = nil
                selectedStrongsNumber = nil
                strongsVerses = []
                similarEntries = []
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back to words")
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
                        Text("KJV: \(kjvDef)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if isLoadingDetail {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                } else if !strongsVerses.isEmpty {
                    Section("Verses (\(strongsVerses.count))") {
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
                            Text("+ \(strongsVerses.count - 15) more")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                if !similarEntries.isEmpty {
                    Section("Related") {
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
            }
        }
    }

    // MARK: - 5. Cross References

    private var crossReferencesSection: some View {
        DisclosureGroup(
            isExpanded: uiStateStore.bindingForSection(.crossReferences)
        ) {
            if uiStateStore.selectedVerseId != nil {
                if isLoadingCrossRefs {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } else if crossRefs.isEmpty {
                    Text("No cross-references for this verse")
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
                Text("Select a verse to view cross references")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        } label: {
            Label("Cross References", systemImage: "arrow.triangle.branch")
        }
        .padding(.vertical, 2)
    }

    // MARK: - 6. Search

    private var searchSection: some View {
        DisclosureGroup(
            isExpanded: uiStateStore.bindingForSection(.search)
        ) {
            @Bindable var uiState = uiStateStore

            VStack(spacing: 6) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("Search in \(activeModuleName)…", text: $uiState.searchQuery)
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

            if uiStateStore.searchResults.isEmpty && !uiStateStore.searchQuery.isEmpty {
                Text("No results for \"\(uiStateStore.searchQuery)\"")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
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
        } label: {
            Label("Search", systemImage: "magnifyingglass")
        }
        .padding(.vertical, 2)
    }

    // MARK: - 7. Recent History

    private var recentHistorySection: some View {
        DisclosureGroup(
            isExpanded: uiStateStore.bindingForSection(.recentHistory)
        ) {
            if userDataStore.readingHistory.isEmpty {
                Text("No recent history")
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
                    Button("Clear History") {
                        Task { await userDataStore.clearHistory() }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label("Recent History", systemImage: "clock")
        }
        .padding(.vertical, 2)
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
            if let paneId = bibleStore.activePaneId {
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
        guard uiStateStore.isSectionExpanded(.strongs) || true else { return }

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
        Task {
            let tags = await StrongsService.shared.resolvedWordTags(
                moduleId: moduleId,
                book: book,
                chapter: chapter,
                verse: verse
            )
            await MainActor.run {
                wordTags = tags
                isLoadingStrongs = false
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
        Task {
            let refs = await CrossReferenceService.shared.loadResolvedBidirectional(
                moduleId: moduleId,
                verseId: crossVerseId,
                scheme: scheme
            )
            await MainActor.run {
                crossRefs = refs
                isLoadingCrossRefs = false
            }
        }
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
