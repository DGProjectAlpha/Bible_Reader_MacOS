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

struct HoverHighlight: ViewModifier {
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
    func hoverHighlight() -> some View {
        modifier(HoverHighlight())
    }
}

struct InspectorView: View {
    @Environment(BibleStore.self) private var bibleStore
    @Environment(UserDataStore.self) private var userDataStore
    @Environment(UIStateStore.self) private var uiStateStore

    private var inspectorTab: InspectorTab {
        get { uiStateStore.inspectorTab }
        nonmutating set { uiStateStore.inspectorTab = newValue }
    }
    @State private var wordTags: [ResolvedWordTag] = []
    @State private var crossRefs: [ResolvedCrossReference] = []
    @State private var selectedStrongsEntry: StrongsEntry? = nil
    @State private var selectedStrongsNumber: String? = nil
    @State private var strongsVerses: [StrongsVerseReference] = []
    @State private var similarEntries: [StrongsEntry] = []
    @State private var wordSynonyms: [StrongsEntry] = []
    @State private var synonymsExpanded = true
    @State private var isLoadingStrongs = false
    @State private var isLoadingCrossRefs = false
    @State private var isLoadingDetail = false
    @State private var versesExpanded = false
    @State private var showAllStrongsVerses = false
    @State private var clickedWord: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("Inspector", selection: Binding(
                get: { uiStateStore.inspectorTab },
                set: { uiStateStore.inspectorTab = $0 }
            )) {
                Text(String(localized: "inspector.strongs")).tag(InspectorTab.strongs)
                Text(String(localized: "inspector.crossRefs")).tag(InspectorTab.crossRef)
                Text(String(localized: "inspector.notes")).tag(InspectorTab.notes)
                Text(String(localized: "inspector.bookmarks")).tag(InspectorTab.bookmarks)
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            // Content
            Group {
                switch inspectorTab {
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: uiStateStore.selectedVerseId) {
            loadDataForSelectedVerse()
        }
        .onChange(of: inspectorTab) {
            loadDataForSelectedVerse()
        }
        .onChange(of: uiStateStore.selectedStrongsId) {
            autoSelectStrongsEntry()
        }
        .onChange(of: uiStateStore.selectedStrongsWord) {
            autoSelectStrongsEntryByWord()
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
                        Text(String(localized: "inspector.noStrongsData"))
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
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
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
                    wordSynonyms = []
                    versesExpanded = false
                    clickedWord = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(String(localized: "inspector.backToWords"))
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                if let entry = selectedStrongsEntry {
                    // Exact match header card
                    VStack(alignment: .leading, spacing: 8) {
                        // Clicked word display
                        if let word = clickedWord {
                            Text(word)
                                .font(.title3.bold())
                                .foregroundStyle(.primary)
                        }

                        // Language badge + Strong's number
                        HStack(spacing: 8) {
                            // Greek/Hebrew language badge
                            Text(entry.number.hasPrefix("G") ? "Greek" : "Hebrew")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    entry.number.hasPrefix("G")
                                        ? Color.blue
                                        : Color.orange,
                                    in: Capsule()
                                )

                            Text(entry.number)
                                .font(.title2.bold().monospaced())
                                .foregroundStyle(Color.accentColor)
                        }

                        // Lemma (original language word)
                        if !entry.lemma.isEmpty {
                            Text(entry.lemma)
                                .font(.title3)
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
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.accentColor.opacity(0.06))
                    )

                    // Derivation
                    if let derivation = entry.derivation, !derivation.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "inspector.derivation"))
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
                            Text(String(localized: "inspector.strongsDefinition"))
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                            Text(strongsDef)
                                .font(.callout)
                        }
                    }

                    // KJV usage
                    if let kjvDef = entry.kjvDefinition, !kjvDef.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "inspector.kjvUsage"))
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                            Text(kjvDef)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // Expandable verses section
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
                                versesExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: versesExpanded ? "chevron.down" : "chevron.right")
                                    .font(.caption2)
                                Text(String(localized: "inspector.versesWith \(entry.number)"))
                                    .font(.subheadline.bold())
                                if !isLoadingDetail {
                                    Text("(\(strongsVerses.count))")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if versesExpanded {
                            if isLoadingDetail {
                                detailSkeletonView
                            } else if strongsVerses.isEmpty {
                                Text(String(localized: "inspector.noVersesFound"))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            } else {
                                let displayLimit = showAllStrongsVerses ? strongsVerses.count : min(20, strongsVerses.count)
                                ForEach(strongsVerses.prefix(displayLimit)) { ref in
                                    Button {
                                        navigateToStrongsVerse(ref)
                                    } label: {
                                        HStack(spacing: 4) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(ref.displayRef)
                                                    .font(.caption.bold())
                                                    .foregroundStyle(Color.accentColor)
                                                Text(ref.text)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                                    .multilineTextAlignment(.leading)
                                            }
                                            Spacer()
                                            Image(systemName: "arrow.right.circle")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                        .padding(.vertical, 2)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .hoverHighlight()
                                }

                                if strongsVerses.count > 20 {
                                    Button {
                                        withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
                                            showAllStrongsVerses.toggle()
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: showAllStrongsVerses ? "chevron.up" : "ellipsis.circle")
                                                .font(.caption)
                                            Text(showAllStrongsVerses
                                                ? "Show Less"
                                                : "Show All \(strongsVerses.count) Verses")
                                                .font(.caption.bold())
                                        }
                                        .foregroundStyle(Color.accentColor)
                                        .padding(.top, 4)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // Synonyms & Related Words section
                    if !wordSynonyms.isEmpty || !similarEntries.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            Button {
                                withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
                                    synonymsExpanded.toggle()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: synonymsExpanded ? "chevron.down" : "chevron.right")
                                        .font(.caption2)
                                    Text("Synonyms & Related Words")
                                        .font(.subheadline.bold())
                                    Text("(\(mergedSynonyms.count))")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if synonymsExpanded {
                                ForEach(mergedSynonyms.prefix(15)) { similar in
                                    synonymRow(similar)
                                }
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
        wordSynonyms = []
        showAllStrongsVerses = false

        Task {
            async let versesResult = StrongsService.shared.findVersesByStrongs(number, moduleId: moduleId)
            async let similarResult = StrongsService.shared.findSimilarByDefinition(number: number, preferredModule: moduleId)

            // Also search by clicked word for direct word-based synonyms
            let wordSearch: (exact: StrongsEntry?, similar: [StrongsEntry])
            if let word = clickedWord, !word.isEmpty {
                wordSearch = await StrongsService.shared.searchSimilar(word: word, preferredModule: moduleId, limit: 15)
            } else {
                wordSearch = (nil, [])
            }

            let verses = await versesResult
            let similar = await similarResult
            // Word synonyms: exclude the current entry
            let wordSyns = wordSearch.similar.filter { $0.number != number }

            await MainActor.run {
                strongsVerses = verses
                similarEntries = similar
                wordSynonyms = wordSyns
                isLoadingDetail = false
            }
        }
    }

    // MARK: - Synonym Helpers

    /// Merge word-based synonyms and definition-based similar entries, deduplicating by number.
    private var mergedSynonyms: [StrongsEntry] {
        var seen = Set<String>()
        if let current = selectedStrongsNumber { seen.insert(current) }
        var result: [StrongsEntry] = []
        // Word-based synonyms first (more directly relevant)
        for entry in wordSynonyms {
            if seen.insert(entry.number).inserted {
                result.append(entry)
            }
        }
        // Then definition-based similar entries
        for entry in similarEntries {
            if seen.insert(entry.number).inserted {
                result.append(entry)
            }
        }
        return result
    }

    /// Extract the primary usage word from a KJV definition string.
    private func primaryUsageWord(_ entry: StrongsEntry) -> String? {
        guard let kjv = entry.kjvDefinition, !kjv.isEmpty else { return nil }
        // KJV definitions are comma-separated; first word is the primary usage
        let first = kjv.split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespaces)
        return first
    }

    private func synonymRow(_ similar: StrongsEntry) -> some View {
        Button {
            clickedWord = nil
            selectedStrongsEntry = similar
            selectedStrongsNumber = similar.number
            versesExpanded = false
            synonymsExpanded = true
            loadStrongsDetail(entry: similar)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        // Primary usage word
                        if let usage = primaryUsageWord(similar) {
                            Text(usage)
                                .font(.callout.bold())
                                .foregroundStyle(.primary)
                        }

                        Spacer()

                        // Strong's number badge
                        Text(similar.number)
                            .font(.caption2.monospaced().bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                similar.number.hasPrefix("G")
                                    ? Color.blue.opacity(0.7)
                                    : Color.orange.opacity(0.7),
                                in: Capsule()
                            )
                    }

                    HStack(spacing: 6) {
                        if !similar.lemma.isEmpty {
                            Text(similar.lemma)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !similar.transliteration.isEmpty {
                            Text(similar.transliteration)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .italic()
                        }
                    }

                    if let def = similar.kjvDefinition ?? similar.strongsDefinition {
                        Text(def)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
        .hoverHighlight()
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
                        Text(String(localized: "inspector.noCrossReferences"))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "inspector.noLinkedReferences"))
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
                        .foregroundStyle(Color.accentColor)
                    Text(crossRefs.count == 1
                        ? String(localized: "inspector.crossRefCount \(crossRefs.count)")
                        : String(localized: "inspector.crossRefCountPlural \(crossRefs.count)"))
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
                    .foregroundStyle(Color.accentColor)

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

    private func navigateToStrongsVerse(_ ref: StrongsVerseReference) {
        let moduleId = bibleStore.activeModuleId
        let location = BibleLocation(
            moduleId: moduleId,
            book: ref.book,
            chapter: ref.chapter,
            verseNumber: ref.verse
        )

        Task {
            let paneId = bibleStore.activePaneId ?? bibleStore.panes.first?.id
            if let paneId {
                await bibleStore.navigate(paneId: paneId, to: location)
            }
            await MainActor.run {
                uiStateStore.selectedVerseId = "\(ref.book).\(ref.chapter).\(ref.verse)"
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

    // MARK: - Cross-Ref Type Helpers

    private func labelForRefType(_ type: String) -> String {
        switch type {
        case "parallel":  return String(localized: "inspector.parallelPassages")
        case "quotation": return String(localized: "inspector.quotations")
        case "allusion":  return String(localized: "inspector.allusions")
        default:          return String(localized: "inspector.related")
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
                    .foregroundStyle(Color.accentColor)
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
                    .help(String(localized: "inspector.deleteNote"))
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
                    Text(String(localized: "inspector.noNotesYet"))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "inspector.selectVerseStartTyping"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            Image(systemName: "note.text")
                                .foregroundStyle(Color.accentColor)
                            Text(userDataStore.notes.count == 1
                                ? String(localized: "inspector.noteCount \(userDataStore.notes.count)")
                                : String(localized: "inspector.noteCountPlural \(userDataStore.notes.count)"))
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
                    .foregroundStyle(Color.accentColor)
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

    // MARK: - Bookmarks Tab (extracted to BookmarksTabView.swift)

    private var bookmarksTab: some View {
        BookmarksTabView()
    }

    // MARK: - Placeholders

    private var noSelectionPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.tap")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(String(localized: "inspector.selectVerse"))
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(String(localized: "inspector.tapVerseDetails"))
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
            wordSynonyms = []
            return
        }

        // Reset detail view when verse changes
        selectedStrongsEntry = nil
        selectedStrongsNumber = nil
        strongsVerses = []
        similarEntries = []
        wordSynonyms = []
        versesExpanded = false
        clickedWord = nil

        let parts = verseId.split(separator: ".")
        guard parts.count == 3,
              let chapter = Int(parts[1]),
              let verse = Int(parts[2]) else { return }
        let book = String(parts[0])
        let moduleId = bibleStore.activeModuleId

        switch inspectorTab {
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
                    autoSelectStrongsEntry()
                    autoSelectStrongsEntryByWord()
                }
            }
        case .crossRef:
            isLoadingCrossRefs = true
            let crossVerseId = "\(book):\(chapter):\(verse)"
            let scheme = bibleStore.modules.first(where: { $0.id == moduleId })?.versificationScheme ?? .kjv
            Task {
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

                // Merge, deduplicating by target verse
                let existingTargets = Set(modResults.map { "\($0.targetBook):\($0.targetChapter):\($0.targetVerse)" })
                let uniqueTsk = tskResults.filter { !existingTargets.contains("\($0.targetBook):\($0.targetChapter):\($0.targetVerse)") }

                await MainActor.run {
                    crossRefs = modResults + uniqueTsk
                    isLoadingCrossRefs = false
                }
            }
        case .notes, .bookmarks:
            break
        }
    }

    // MARK: - Auto-Select Strong's Entry

    private func autoSelectStrongsEntry() {
        guard let strongsId = uiStateStore.selectedStrongsId else { return }
        if let tag = wordTags.first(where: { $0.strongsNumber == strongsId }),
           let entry = tag.entry {
            clickedWord = tag.word
            selectedStrongsNumber = strongsId
            selectedStrongsEntry = entry
            versesExpanded = false
            loadStrongsDetail(entry: entry)
            uiStateStore.selectedStrongsId = nil
        }
    }

    private func autoSelectStrongsEntryByWord() {
        guard let word = uiStateStore.selectedStrongsWord else { return }
        let lowered = word.lowercased()
        if let tag = wordTags.first(where: { $0.word.lowercased() == lowered }),
           let entry = tag.entry {
            clickedWord = tag.word
            selectedStrongsNumber = tag.strongsNumber
            selectedStrongsEntry = entry
            versesExpanded = false
            loadStrongsDetail(entry: entry)
            uiStateStore.selectedStrongsWord = nil
        } else if !wordTags.isEmpty {
            uiStateStore.selectedStrongsWord = nil
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
                Text(isSaved ? String(localized: "inspector.saved") : String(localized: "inspector.typing"))
                    .font(.caption2)
                    .foregroundStyle(isSaved ? .green.opacity(0.7) : .orange.opacity(0.7))
                    .padding(.trailing, 12)
                    .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - Bookmark Row View

struct BookmarkRowView: View {
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
                .help(String(localized: "bookmarks.deleteBookmark"))
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)

            // Note section
            if isEditingNote {
                TextField(String(localized: "bookmarks.addNote"), text: $noteText, axis: .vertical)
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
                        Text(bookmark.note.isEmpty ? String(localized: "bookmarks.addNote") : bookmark.note)
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
                        Text(String(localized: "inspector.writeNoteHint"))
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
                    Text(String(localized: "inspector.willAutoSave"))
                        .font(.caption2)
                        .foregroundStyle(.orange.opacity(0.7))
                } else if created {
                    Text(String(localized: "inspector.saved"))
                        .font(.caption2)
                        .foregroundStyle(.green.opacity(0.7))
                }
            }
            .padding(.trailing, 12)
            .padding(.vertical, 4)
        }
    }
}
