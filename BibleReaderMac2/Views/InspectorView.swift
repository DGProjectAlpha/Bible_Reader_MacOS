import SwiftUI

// MARK: - Shimmer Effect Modifier

struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.3), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 300
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerEffect())
    }
}

// MARK: - Hover Highlight Modifier

private struct HoverHighlight: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovering ? Color.primary.opacity(0.06) : .clear)
            )
            .scaleEffect(isHovering ? 1.03 : 1.0)
            .animation(.spring(duration: 0.2, bounce: 0.3), value: isHovering)
            .onHover { hovering in isHovering = hovering }
    }
}

extension View {
    fileprivate func hoverHighlight() -> some View {
        modifier(HoverHighlight())
    }
}

struct InspectorView: View {
    @Environment(BibleStore.self) private var bibleStore
    @Environment(UserDataStore.self) private var userDataStore
    @Environment(UIStateStore.self) private var uiStateStore

    @State private var wordTags: [ResolvedWordTag] = []
    @State private var crossRefs: [ResolvedCrossReference] = []
    @State private var selectedStrongsEntry: StrongsEntry? = nil
    @State private var selectedStrongsNumber: String? = nil
    @State private var strongsVerses: [StrongsVerseReference] = []
    @State private var similarEntries: [StrongsEntry] = []
    @State private var isLoadingStrongs = false
    @State private var isLoadingCrossRefs = false
    @State private var isLoadingDetail = false

    var body: some View {
        @Bindable var uiState = uiStateStore

        VStack(spacing: 0) {
            // Tab picker
            Picker("Inspector", selection: $uiState.inspectorTab) {
                Text("Strong's").tag(InspectorTab.strongs)
                Text("Cross-Refs").tag(InspectorTab.crossRef)
                Text("Notes").tag(InspectorTab.notes)
                Text("Bookmarks").tag(InspectorTab.bookmarks)
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            // Content
            Group {
                switch uiStateStore.inspectorTab {
                case .strongs:
                    strongsTab
                case .crossRef:
                    crossRefTab
                case .notes:
                    notesTab
                case .bookmarks:
                    bookmarksTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: uiStateStore.selectedVerseId) {
            loadDataForSelectedVerse()
        }
        .onChange(of: uiStateStore.inspectorTab) {
            loadDataForSelectedVerse()
        }
    }

    // MARK: - Strong's Tab

    private var strongsTab: some View {
        Group {
            if selectedStrongsEntry != nil {
                strongsDetailView
            } else if let verseId = uiStateStore.selectedVerseId {
                if isLoadingStrongs {
                    strongsSkeletonView
                } else if wordTags.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "textformat.abc")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No Strong's data")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(verseId)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    strongsWordList
                }
            } else {
                noSelectionPlaceholder
            }
        }
    }

    private var strongsWordList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(wordTags) { tag in
                    wordTagRow(tag)
                }
            }
            .padding(8)
        }
    }

    private func wordTagRow(_ tag: ResolvedWordTag) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(tag.word)
                            .font(.body.bold())

                        if let num = tag.strongsNumber {
                            Text(num)
                                .font(.caption.monospaced())
                                .foregroundStyle(.accentColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }

                    if let entry = tag.entry {
                        HStack(spacing: 6) {
                            if !entry.lemma.isEmpty {
                                Text(entry.lemma)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if !entry.transliteration.isEmpty {
                                Text(entry.transliteration)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .italic()
                            }
                        }
                        if let def = entry.kjvDefinition ?? entry.strongsDefinition {
                            Text(def)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }

                Spacer()

                if tag.entry != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(tag.strongsNumber != nil ? Color.accentColor.opacity(0.03) : .clear)
            )
            .onTapGesture {
                guard let entry = tag.entry else { return }
                selectedStrongsNumber = tag.strongsNumber
                selectedStrongsEntry = entry
                loadStrongsDetail(entry: entry)
            }
            .hoverHighlight()

            Divider()
        }
    }

    // MARK: - Strong's Detail View

    private var strongsDetailView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Back button
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
                .foregroundStyle(.accentColor)

                if let entry = selectedStrongsEntry {
                    // Header: number + lemma
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.number)
                            .font(.title2.bold().monospaced())
                            .foregroundStyle(.accentColor)

                        if !entry.lemma.isEmpty {
                            Text(entry.lemma)
                                .font(.title3)
                        }
                    }

                    // Transliteration + pronunciation
                    if !entry.transliteration.isEmpty || entry.pronunciation != nil {
                        HStack(spacing: 12) {
                            if !entry.transliteration.isEmpty {
                                Label(entry.transliteration, systemImage: "character.textbox")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if let pron = entry.pronunciation {
                                Label(pron, systemImage: "speaker.wave.2")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Derivation
                    if let derivation = entry.derivation, !derivation.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Derivation")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                            Text(derivation)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Strong's definition
                    if let strongsDef = entry.strongsDefinition, !strongsDef.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Strong's Definition")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                            Text(strongsDef)
                                .font(.callout)
                        }
                    }

                    // KJV usage
                    if let kjvDef = entry.kjvDefinition, !kjvDef.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("KJV Usage")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                            Text(kjvDef)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // Verses using this Strong's number
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Verses with \(entry.number)")
                            .font(.subheadline.bold())

                        if isLoadingDetail {
                            detailSkeletonView
                        } else if strongsVerses.isEmpty {
                            Text("No verses found")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(strongsVerses.prefix(20)) { ref in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ref.displayRef)
                                        .font(.caption.bold())
                                        .foregroundStyle(.accentColor)
                                    Text(ref.text)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .padding(.vertical, 2)
                            }

                            if strongsVerses.count > 20 {
                                Text("+ \(strongsVerses.count - 20) more verses")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 2)
                            }
                        }
                    }

                    // Similar entries
                    if !similarEntries.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Related Entries")
                                .font(.subheadline.bold())

                            ForEach(similarEntries.prefix(8)) { similar in
                                Button {
                                    selectedStrongsEntry = similar
                                    selectedStrongsNumber = similar.number
                                    loadStrongsDetail(entry: similar)
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(similar.number)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.accentColor)
                                        if !similar.lemma.isEmpty {
                                            Text(similar.lemma)
                                                .font(.caption)
                                        }
                                        Spacer()
                                        if let def = similar.kjvDefinition {
                                            Text(def)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(1)
                                                .frame(maxWidth: 120, alignment: .trailing)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .hoverHighlight()
                            }
                        }
                    }
                }
            }
            .padding(10)
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

    // MARK: - Cross-References Tab

    private var crossRefTab: some View {
        Group {
            if uiStateStore.selectedVerseId != nil {
                if isLoadingCrossRefs {
                    crossRefSkeletonView
                } else if crossRefs.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No cross-references")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("This verse has no linked references")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    crossRefList
                }
            } else {
                noSelectionPlaceholder
            }
        }
    }

    /// Groups cross-refs by type and displays them in sections
    private var crossRefList: some View {
        let grouped = Dictionary(grouping: crossRefs) { $0.reference.referenceType }
        let typeOrder = ["parallel", "quotation", "allusion", "related"]
        let sortedKeys = grouped.keys.sorted { a, b in
            (typeOrder.firstIndex(of: a) ?? 99) < (typeOrder.firstIndex(of: b) ?? 99)
        }

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Summary header
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(.accentColor)
                    Text("\(crossRefs.count) cross-reference\(crossRefs.count == 1 ? "" : "s")")
                        .font(.subheadline.bold())
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                Divider()

                ForEach(sortedKeys, id: \.self) { type in
                    if let refs = grouped[type] {
                        crossRefSection(type: type, refs: refs)
                    }
                }
            }
        }
    }

    private func crossRefSection(type: String, refs: [ResolvedCrossReference]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: iconForRefType(type))
                    .font(.caption)
                    .foregroundStyle(colorForRefType(type))
                Text(labelForRefType(type))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text("(\(refs.count))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.04))

            ForEach(refs) { ref in
                crossRefRow(ref)
            }
        }
    }

    private func crossRefRow(_ ref: ResolvedCrossReference) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(ref.displayRef)
                    .font(.subheadline.bold())
                    .foregroundStyle(.accentColor)

                Spacer()

                Image(systemName: "arrow.right.circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text(ref.targetText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Divider()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            navigateToCrossRef(ref)
        }
        .hoverHighlight()
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

    // MARK: - Cross-Ref Type Helpers

    private func labelForRefType(_ type: String) -> String {
        switch type {
        case "parallel":  return "Parallel Passages"
        case "quotation": return "Quotations"
        case "allusion":  return "Allusions"
        default:          return "Related"
        }
    }

    private func iconForRefType(_ type: String) -> String {
        switch type {
        case "parallel":  return "equal.circle"
        case "quotation": return "quote.opening"
        case "allusion":  return "link"
        default:          return "arrow.triangle.branch"
        }
    }

    private func colorForRefType(_ type: String) -> Color {
        switch type {
        case "parallel":  return .blue
        case "quotation": return .orange
        case "allusion":  return .purple
        default:          return .secondary
        }
    }

    // MARK: - Notes Tab

    private var notesTab: some View {
        Group {
            if let verseId = uiStateStore.selectedVerseId {
                notesEditor(verseId: verseId)
            } else {
                allNotesList
            }
        }
    }

    private func notesEditor(verseId: String) -> some View {
        let existingNote = userDataStore.notes.first(where: { $0.verseId == verseId })

        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                    .foregroundStyle(.accentColor)
                Text(verseId)
                    .font(.subheadline.bold())
                Spacer()
                if let note = existingNote {
                    Text(note.updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Button {
                        Task { await userDataStore.deleteNote(id: note.id) }
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Delete note")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            if let note = existingNote {
                NoteEditorField(noteId: note.id, initialText: note.text)
                    .environment(userDataStore)
            } else {
                NoteCreatorField(verseId: verseId)
                    .environment(userDataStore)
            }
        }
    }

    /// Shows all notes when no verse is selected
    private var allNotesList: some View {
        Group {
            if userDataStore.notes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "note.text")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No notes yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Select a verse and start typing")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            Image(systemName: "note.text")
                                .foregroundStyle(.accentColor)
                            Text("\(userDataStore.notes.count) note\(userDataStore.notes.count == 1 ? "" : "s")")
                                .font(.subheadline.bold())
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)

                        Divider()

                        ForEach(userDataStore.notes.sorted(by: { $0.updatedAt > $1.updatedAt })) { note in
                            noteListRow(note)
                        }
                    }
                }
            }
        }
    }

    private func noteListRow(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(note.verseId)
                    .font(.subheadline.bold())
                    .foregroundStyle(.accentColor)
                Spacer()
                Text(note.updatedAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(note.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Divider()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            uiStateStore.selectedVerseId = note.verseId
        }
        .hoverHighlight()
    }

    // MARK: - Bookmarks Tab

    private var bookmarksTab: some View {
        Group {
            if let verseId = uiStateStore.selectedVerseId {
                verseBookmarksView(verseId: verseId)
            } else {
                allBookmarksList
            }
        }
    }

    private func verseBookmarksView(verseId: String) -> some View {
        let verseBookmarks = userDataStore.bookmarks.filter { $0.verseId == verseId }

        return VStack(alignment: .leading, spacing: 0) {
            // Header with add button
            HStack(spacing: 6) {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(.accentColor)
                Text(verseId)
                    .font(.subheadline.bold())
                Spacer()
                Button {
                    Task {
                        let bookmark = Bookmark(
                            id: UUID(),
                            verseId: verseId,
                            color: .yellow,
                            note: "",
                            createdAt: Date()
                        )
                        await userDataStore.addBookmark(bookmark)
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Add bookmark")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            if verseBookmarks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bookmark")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No bookmarks for this verse")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Tap + to add one")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(verseBookmarks) { bookmark in
                            BookmarkRowView(bookmark: bookmark)
                                .environment(userDataStore)
                        }
                    }
                }
            }
        }
    }

    private var allBookmarksList: some View {
        Group {
            if userDataStore.bookmarks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bookmark")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No bookmarks yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Select a verse to add a bookmark")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let sorted = userDataStore.bookmarks.sorted { $0.createdAt > $1.createdAt }
                let grouped = Dictionary(grouping: sorted) { colorForBookmark($0.color).description }
                _ = grouped // suppress warning, we group by color visually below

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Summary header
                        HStack(spacing: 8) {
                            Image(systemName: "bookmark.fill")
                                .foregroundStyle(.accentColor)
                            Text("\(userDataStore.bookmarks.count) bookmark\(userDataStore.bookmarks.count == 1 ? "" : "s")")
                                .font(.subheadline.bold())
                            Spacer()

                            // Color summary dots
                            ForEach(BookmarkColor.allCases, id: \.self) { color in
                                let count = userDataStore.bookmarks.filter { $0.color == color }.count
                                if count > 0 {
                                    HStack(spacing: 2) {
                                        Circle()
                                            .fill(colorForBookmark(color))
                                            .frame(width: 8, height: 8)
                                        Text("\(count)")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)

                        Divider()

                        ForEach(sorted) { bookmark in
                            bookmarkListRow(bookmark)
                        }
                    }
                }
            }
        }
    }

    private func bookmarkListRow(_ bookmark: Bookmark) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(colorForBookmark(bookmark.color))
                    .frame(width: 10, height: 10)
                Text(bookmark.verseId)
                    .font(.subheadline.bold())
                    .foregroundStyle(.accentColor)
                Spacer()
                Text(bookmark.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if !bookmark.note.isEmpty {
                Text(bookmark.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Divider()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            navigateToBookmark(bookmark)
        }
        .hoverHighlight()
    }

    // MARK: - Placeholders

    private var noSelectionPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.tap")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Select a verse")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Tap a verse to see details")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Skeleton Views

    private var strongsSkeletonView: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .frame(width: 50, height: 16)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .frame(height: 16)
                }
            }
        }
        .padding()
        .redacted(reason: .placeholder)
        .shimmer()
    }

    private var detailSkeletonView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(height: 14)
            }
        }
        .padding(.vertical, 8)
        .redacted(reason: .placeholder)
        .shimmer()
    }

    private var crossRefSkeletonView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<5, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .frame(width: 80, height: 14)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .frame(height: 12)
                }
            }
        }
        .padding()
        .redacted(reason: .placeholder)
        .shimmer()
    }

    // MARK: - Data Loading

    private func loadDataForSelectedVerse() {
        guard let verseId = uiStateStore.selectedVerseId else {
            wordTags = []
            crossRefs = []
            selectedStrongsEntry = nil
            selectedStrongsNumber = nil
            strongsVerses = []
            similarEntries = []
            return
        }

        // Reset detail view when verse changes
        selectedStrongsEntry = nil
        selectedStrongsNumber = nil
        strongsVerses = []
        similarEntries = []

        let parts = verseId.split(separator: ".")
        guard parts.count == 3,
              let chapter = Int(parts[1]),
              let verse = Int(parts[2]) else { return }
        let book = String(parts[0])
        let moduleId = bibleStore.activeModuleId

        switch uiStateStore.inspectorTab {
        case .strongs:
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
        case .crossRef:
            isLoadingCrossRefs = true
            let crossVerseId = "\(book):\(chapter):\(verse)"
            let scheme = bibleStore.modules.first(where: { $0.id == moduleId })?.versificationScheme ?? .kjv
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
        case .notes, .bookmarks:
            break
        }
    }

    // MARK: - Bookmark Navigation

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

    // MARK: - Helpers

    private func colorForBookmark(_ color: BookmarkColor) -> Color {
        switch color {
        case .yellow: return .yellow
        case .blue:   return .blue
        case .green:  return .green
        case .orange: return .orange
        case .purple: return .purple
        }
    }
}

// MARK: - Note Editor Field

private struct NoteEditorField: View {
    @Environment(UserDataStore.self) private var userDataStore
    let noteId: UUID
    @State private var text: String
    @State private var saveTask: Task<Void, Never>?
    @State private var isSaved = true

    init(noteId: UUID, initialText: String) {
        self.noteId = noteId
        self._text = State(initialValue: initialText)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $text)
                .font(.body)
                .padding(6)
                .scrollContentBackground(.hidden)
                .background(Color(.textBackgroundColor).opacity(0.5))
                .cornerRadius(6)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .onChange(of: text) {
                    isSaved = false
                    saveTask?.cancel()
                    saveTask = Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        guard !Task.isCancelled else { return }
                        await userDataStore.updateNote(id: noteId, text: text)
                        await MainActor.run { isSaved = true }
                    }
                }

            HStack {
                Spacer()
                Text(isSaved ? "Saved" : "Typing...")
                    .font(.caption2)
                    .foregroundStyle(isSaved ? .green.opacity(0.7) : .orange.opacity(0.7))
                    .padding(.trailing, 12)
                    .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - Bookmark Row View

private struct BookmarkRowView: View {
    @Environment(UserDataStore.self) private var userDataStore
    let bookmark: Bookmark
    @State private var noteText: String
    @State private var isEditingNote = false
    @State private var saveTask: Task<Void, Never>?

    init(bookmark: Bookmark) {
        self.bookmark = bookmark
        self._noteText = State(initialValue: bookmark.note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Color + date + delete row
            HStack(spacing: 8) {
                // Color picker circles
                ForEach(BookmarkColor.allCases, id: \.self) { color in
                    Circle()
                        .fill(swiftColor(for: color))
                        .frame(width: bookmark.color == color ? 16 : 12, height: bookmark.color == color ? 16 : 12)
                        .overlay {
                            if bookmark.color == color {
                                Circle().stroke(.primary.opacity(0.3), lineWidth: 1.5)
                            }
                        }
                        .onTapGesture {
                            Task { await userDataStore.updateBookmark(id: bookmark.id, color: color) }
                        }
                }

                Spacer()

                Text(bookmark.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Button {
                    Task { await userDataStore.deleteBookmark(id: bookmark.id) }
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Delete bookmark")
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)

            // Note section
            if isEditingNote {
                TextField("Add a note...", text: $noteText, axis: .vertical)
                    .font(.caption)
                    .textFieldStyle(.plain)
                    .padding(6)
                    .background(Color(.textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                    .onChange(of: noteText) {
                        saveTask?.cancel()
                        saveTask = Task {
                            try? await Task.sleep(for: .milliseconds(500))
                            guard !Task.isCancelled else { return }
                            await userDataStore.updateBookmark(id: bookmark.id, note: noteText)
                        }
                    }
                    .onSubmit {
                        isEditingNote = false
                    }
            } else {
                Button {
                    isEditingNote = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil.line")
                            .font(.caption2)
                        Text(bookmark.note.isEmpty ? "Add a note..." : bookmark.note)
                            .font(.caption)
                            .foregroundStyle(bookmark.note.isEmpty ? .tertiary : .secondary)
                            .lineLimit(2)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }

            Divider()
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(swiftColor(for: bookmark.color).opacity(0.05))
                .padding(.horizontal, 4)
        )
    }

    private func swiftColor(for color: BookmarkColor) -> Color {
        switch color {
        case .yellow: return .yellow
        case .blue:   return .blue
        case .green:  return .green
        case .orange: return .orange
        case .purple: return .purple
        }
    }
}

// MARK: - Note Creator Field

private struct NoteCreatorField: View {
    @Environment(UserDataStore.self) private var userDataStore
    let verseId: String
    @State private var text = ""
    @State private var created = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $text)
                .font(.body)
                .padding(6)
                .scrollContentBackground(.hidden)
                .background(Color(.textBackgroundColor).opacity(0.5))
                .cornerRadius(6)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Write a note about this verse...")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 14)
                            .padding(.top, 16)
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: text) {
                    guard !text.isEmpty, !created else { return }
                    saveTask?.cancel()
                    saveTask = Task {
                        try? await Task.sleep(for: .milliseconds(800))
                        guard !Task.isCancelled, !text.isEmpty else { return }
                        let note = Note(
                            id: UUID(),
                            verseId: verseId,
                            text: text,
                            createdAt: Date(),
                            updatedAt: Date()
                        )
                        await userDataStore.addNote(note)
                        await MainActor.run { created = true }
                    }
                }

            HStack {
                Spacer()
                if !text.isEmpty && !created {
                    Text("Will auto-save...")
                        .font(.caption2)
                        .foregroundStyle(.orange.opacity(0.7))
                } else if created {
                    Text("Saved")
                        .font(.caption2)
                        .foregroundStyle(.green.opacity(0.7))
                }
            }
            .padding(.trailing, 12)
            .padding(.vertical, 4)
        }
    }
}
