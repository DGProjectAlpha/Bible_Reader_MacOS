import SwiftUI
import Combine

// MARK: - Reader View (top-level split container)

struct ReaderView: View {
    @EnvironmentObject var store: BibleStore
    @EnvironmentObject var windowState: WindowState
    @AppStorage("syncScrolling") private var syncScrolling = true
    @StateObject private var syncCoordinator = ScrollSyncCoordinator()

    var body: some View {
        Group {
            if store.loadedTranslations.isEmpty {
                emptyState
            } else if windowState.panes.count == 1, let pane = windowState.panes.first {
                ReaderPaneView(
                    pane: pane,
                    isSolo: true,
                    syncScrolling: $syncScrolling,
                    coordinator: syncCoordinator
                )
            } else {
                HSplitView {
                    ForEach(windowState.panes) { pane in
                        ReaderPaneView(
                            pane: pane,
                            isSolo: false,
                            syncScrolling: $syncScrolling,
                            coordinator: syncCoordinator
                        )
                        .frame(minWidth: 280)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Toggle(isOn: $syncScrolling) {
                    Label("Sync Scroll", systemImage: syncScrolling ? "link" : "link.badge.plus")
                }
                .help(syncScrolling ? "Scroll syncing enabled" : "Scroll syncing disabled")

                if windowState.panes.count < 8 {
                    Button(action: {
                        windowState.addPane(translationId: store.loadedTranslations.first?.id)
                    }) {
                        Label("Add Pane", systemImage: "plus.rectangle.on.rectangle")
                    }
                    .help("Add parallel translation pane")
                }
            }
        }
        // Handle cross-reference navigation: jump reader to a specific verse
        .onReceive(NotificationCenter.default.publisher(for: .navigateToVerse)) { notification in
            guard let userInfo = notification.userInfo,
                  let book = userInfo["book"] as? String,
                  let chapter = userInfo["chapter"] as? Int,
                  let verse = userInfo["verse"] as? Int,
                  let pane = windowState.panes.first else { return }

            pane.selectedBook = book
            pane.selectedChapter = chapter
            store.loadVerses(for: pane)

            // Scroll to the specific verse after a short delay for layout
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if let proxy = syncCoordinator.scrollProxies[pane.id] {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("verse-\(pane.id)-\(verse)", anchor: .top)
                    }
                }
            }
        }
        .onChange(of: syncScrolling) {
            if syncScrolling {
                // When re-enabling sync, align all panes to the first pane's position
                guard let leader = windowState.panes.first else { return }
                for pane in windowState.panes.dropFirst() {
                    pane.selectedBook = leader.selectedBook
                    pane.selectedChapter = leader.selectedChapter
                    store.loadVerses(for: pane)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text("No Translations Loaded")
                .font(.title2.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Import a .brbmod module to start reading.")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Button("Import Module...") {
                NotificationCenter.default.post(name: .importModule, object: nil)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Scroll Sync Coordinator

/// Central coordinator that manages scroll and navigation sync between panes.
/// Prevents feedback loops via source tracking and debouncing.
@MainActor
class ScrollSyncCoordinator: ObservableObject {
    /// The verse number currently visible at the top of the source pane.
    @Published var visibleVerse: Int = 1
    /// The pane that initiated the current sync event.
    @Published var sourcePane: UUID?
    /// Navigation sync: the book/chapter that was just navigated to.
    @Published var navigationEvent: NavigationEvent?

    /// Tracks which panes are currently suppressed from emitting scroll events
    /// (because they are responding to a sync, not user-initiated scroll).
    private var suppressedPanes: Set<UUID> = []
    private var suppressionTimers: [UUID: DispatchWorkItem] = [:]

    struct NavigationEvent: Equatable {
        let book: String
        let chapter: Int
        let sourcePane: UUID
        let timestamp: Date

        static func == (lhs: NavigationEvent, rhs: NavigationEvent) -> Bool {
            lhs.book == rhs.book && lhs.chapter == rhs.chapter && lhs.sourcePane == rhs.sourcePane
        }
    }

    /// Called by a pane when the user scrolls, reporting the topmost visible verse.
    func reportVisibleVerse(_ verse: Int, from paneId: UUID) {
        guard !suppressedPanes.contains(paneId) else { return }
        guard verse != visibleVerse || sourcePane != paneId else { return }
        sourcePane = paneId
        visibleVerse = verse
    }

    /// Called by a pane when the user navigates to a different book/chapter.
    func reportNavigation(book: String, chapter: Int, from paneId: UUID) {
        navigationEvent = NavigationEvent(
            book: book,
            chapter: chapter,
            sourcePane: paneId,
            timestamp: Date()
        )
    }

    /// Registered scroll proxies from each pane, keyed by pane ID.
    var scrollProxies: [UUID: ScrollViewProxy] = [:]

    func registerScrollProxy(_ proxy: ScrollViewProxy, for paneId: UUID) {
        scrollProxies[paneId] = proxy
    }

    /// Suppress a pane from emitting scroll events temporarily (while it scrolls in response to sync).
    func suppressPane(_ paneId: UUID, for duration: TimeInterval = 0.5) {
        suppressedPanes.insert(paneId)
        suppressionTimers[paneId]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.suppressedPanes.remove(paneId)
            self?.suppressionTimers.removeValue(forKey: paneId)
        }
        suppressionTimers[paneId] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}

// MARK: - Single Reader Pane

struct ReaderPaneView: View {
    @EnvironmentObject var store: BibleStore
    @EnvironmentObject var windowState: WindowState
    @ObservedObject var pane: ReaderPane
    let isSolo: Bool
    @Binding var syncScrolling: Bool
    @ObservedObject var coordinator: ScrollSyncCoordinator

    @AppStorage("fontSize") private var fontSize: Double = 15
    @AppStorage("fontFamily") private var fontFamily: String = "System"
    @AppStorage("lineSpacing") private var lineSpacing: Double = 1.3
    @AppStorage("wordSpacing") private var wordSpacing: Double = 0.0
    @AppStorage("verseNumberStyle") private var verseNumberStyle: String = "superscript"
    @AppStorage("paragraphMode") private var paragraphMode: Bool = false
    @AppStorage("verseHighlightOpacity") private var verseHighlightOpacity: Double = 0.12
    @AppStorage("showChapterTitles") private var showChapterTitles: Bool = true
    @AppStorage("readerTheme") private var readerTheme: String = "auto"
    @AppStorage("textColorHex") private var textColorHex: String = ""
    @AppStorage("backgroundColorHex") private var backgroundColorHex: String = ""

    @State private var scrollProxy: ScrollViewProxy?
    @State private var showBookPicker = false
    @State private var previousTranslationId: UUID?
    @State private var hoveredVerse: Int?
    @State private var selectedVerse: Int?
    @State private var visibleVerseNumbers: Set<Int> = []
    @State private var noteEditingVerse: Verse?
    @State private var noteEditText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            paneHeader
            Divider()
            verseContent
        }
        .vibrancyBackground(material: .contentBackground, blendingMode: .withinWindow)
        .onAppear {
            previousTranslationId = pane.selectedTranslationId
            loadCurrentChapter()
        }
        .onChange(of: pane.selectedTranslationId) { _, newId in
            // Convert verse position between versification schemes when switching translations
            if let oldId = previousTranslationId, oldId != newId {
                let topVerse = visibleVerseNumbers.min() ?? 1
                store.convertPanePosition(for: pane, from: oldId, to: newId, currentVerse: topVerse)
            }
            previousTranslationId = newId
            loadCurrentChapter()
        }
        .onChange(of: pane.selectedBook) {
            pane.selectedChapter = 1
            loadCurrentChapter()
            if syncScrolling {
                coordinator.reportNavigation(
                    book: pane.selectedBook,
                    chapter: 1,
                    from: pane.id
                )
            }
        }
        .onChange(of: pane.selectedChapter) {
            loadCurrentChapter()
            if syncScrolling {
                coordinator.reportNavigation(
                    book: pane.selectedBook,
                    chapter: pane.selectedChapter,
                    from: pane.id
                )
            }
        }
        // Respond to scroll sync from other panes
        .onChange(of: coordinator.visibleVerse) { _, verse in
            guard syncScrolling,
                  let source = coordinator.sourcePane,
                  source != pane.id else { return }
            coordinator.suppressPane(pane.id)
            withAnimation(.easeOut(duration: 0.2)) {
                scrollProxy?.scrollTo(verseAnchor(verse), anchor: .top)
            }
        }
        // Respond to navigation sync from other panes
        .onChange(of: coordinator.navigationEvent) { _, event in
            guard syncScrolling,
                  let event,
                  event.sourcePane != pane.id else { return }
            if pane.selectedBook != event.book {
                pane.selectedBook = event.book
            }
            if pane.selectedChapter != event.chapter {
                pane.selectedChapter = event.chapter
            }
            loadCurrentChapter()
        }
        // Note editor sheet
        .sheet(item: $noteEditingVerse) { verse in
            NoteEditorSheet(
                verseId: verse.id,
                verseRef: "\(pane.selectedBook) \(pane.selectedChapter):\(verse.number)",
                translationId: pane.selectedTranslationId,
                initialText: store.noteFor(verseId: verse.id, translationId: pane.selectedTranslationId)?.content ?? "",
                onSave: { content in
                    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // Delete note if empty
                        if let note = store.noteFor(verseId: verse.id, translationId: pane.selectedTranslationId) {
                            store.removeNote(note.id)
                        }
                    } else {
                        store.addNote(verseId: verse.id, translationId: pane.selectedTranslationId, content: content)
                    }
                }
            )
        }
    }

    // MARK: - Header Bar

    private var paneHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Translation picker
                Picker("", selection: $pane.selectedTranslationId) {
                    ForEach(store.loadedTranslations) { t in
                        Text(t.abbreviation).tag(t.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 100)
                .help("Select translation")

                Divider().frame(height: 20)

                // Book picker
                Picker("", selection: $pane.selectedBook) {
                    ForEach(BibleBooks.all, id: \.self) { book in
                        Text(book).tag(book)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 160)
                .help("Select book")

                // Chapter nav
                HStack(spacing: 2) {
                    Button(action: prevChapter) {
                        Image(systemName: "chevron.left")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .disabled(pane.selectedChapter <= 1)
                    .help("Previous chapter")

                    Picker("", selection: $pane.selectedChapter) {
                        ForEach(1...max(1, pane.chapterCount), id: \.self) { ch in
                            Text("\(ch)").tag(ch)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 60)
                    .help("Select chapter")

                    Button(action: nextChapter) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .disabled(pane.selectedChapter >= pane.chapterCount)
                    .help("Next chapter")
                }

                Spacer()

                // Font size controls
                HStack(spacing: 2) {
                    Button(action: { fontSize = max(10, fontSize - 1) }) {
                        Image(systemName: "textformat.size.smaller")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help("Decrease font size")

                    Text("\(Int(fontSize))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .center)

                    Button(action: { fontSize = min(36, fontSize + 1) }) {
                        Image(systemName: "textformat.size.larger")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help("Increase font size")
                }

                // Close pane button
                if !isSolo {
                    Divider().frame(height: 20)
                    Button(action: { windowState.removePane(pane.id) }) {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Close pane")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            // Chapter title
            if showChapterTitles {
                HStack {
                    Text("\(displayBookName) \(pane.selectedChapter)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    if let translation = currentTranslation {
                        Text(translation.name)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
        .glassHeader()
    }

    // MARK: - Verse Content

    private var verseContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if pane.verses.isEmpty {
                        noVersesView
                    } else {
                        ForEach(pane.verses) { verse in
                            VerseRow(
                                verse: verse,
                                fontSize: CGFloat(fontSize),
                                fontFamily: fontFamily,
                                lineSpacingMultiplier: CGFloat(lineSpacing),
                                wordSpacing: CGFloat(wordSpacing),
                                verseNumberStyle: verseNumberStyle,
                                highlightOpacity: verseHighlightOpacity,
                                isHovered: hoveredVerse == verse.number,
                                isSelected: selectedVerse == verse.number,
                                isBookmarked: store.isBookmarked(verseId: verse.id, translationId: pane.selectedTranslationId),
                                highlightColor: store.highlightFor(verseId: verse.id, translationId: pane.selectedTranslationId)?.color,
                                hasNote: store.noteFor(verseId: verse.id, translationId: pane.selectedTranslationId) != nil,
                                customTextColor: resolvedTextColor,
                                customBackgroundColor: resolvedBackgroundColor,
                                onToggleBookmark: {
                                    toggleBookmark(for: verse)
                                },
                                onHighlightColor: { color in
                                    if let color {
                                        store.setHighlight(verseId: verse.id, translationId: pane.selectedTranslationId, color: color)
                                    } else {
                                        store.removeHighlight(verseId: verse.id, translationId: pane.selectedTranslationId)
                                    }
                                },
                                onNoteEdit: {
                                    noteEditingVerse = verse
                                },
                                onVerseNumberTap: {
                                    // Verse number click → show cross-refs in inspector
                                    windowState.showCrossRefsInspector(verseId: verse.id)
                                },
                                onWordTap: { wordTag in
                                    // Word click → show Strong's in inspector
                                    guard let translation = currentTranslation else { return }
                                    let displayRef = "\(pane.selectedBook) \(pane.selectedChapter):\(verse.number)"
                                    windowState.showStrongsInspector(
                                        verseId: verse.id,
                                        displayRef: displayRef,
                                        filePath: translation.filePath
                                    )
                                }
                            )
                            .id(verseAnchor(verse.number))
                            .onHover { isHovered in
                                hoveredVerse = isHovered ? verse.number : nil
                            }
                            .onTapGesture {
                                selectedVerse = (selectedVerse == verse.number) ? nil : verse.number
                            }
                            .contextMenu {
                                verseContextMenu(for: verse)
                            }
                            .onAppear {
                                visibleVerseNumbers.insert(verse.number)
                                reportTopVisibleVerse()
                            }
                            .onDisappear {
                                visibleVerseNumbers.remove(verse.number)
                            }
                        }

                        // Chapter navigation footer
                        chapterNavFooter
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onAppear {
                scrollProxy = proxy
                coordinator.registerScrollProxy(proxy, for: pane.id)
            }
        }
        .background(sepiaBackground)
    }

    private var sepiaBackground: some View {
        Group {
            if readerTheme == "sepia" && backgroundColorHex.isEmpty {
                Color(red: 0.98, green: 0.95, blue: 0.88) // Warm parchment
            } else {
                Color.clear
            }
        }
    }

    private var resolvedTextColor: Color? {
        if let custom = Color.fromHex(textColorHex) { return custom }
        if readerTheme == "sepia" { return Color(red: 0.30, green: 0.22, blue: 0.12) }
        return nil
    }

    private var resolvedBackgroundColor: Color? {
        if let custom = Color.fromHex(backgroundColorHex) { return custom }
        return nil // sepia bg handled by sepiaBackground on scroll view
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func verseContextMenu(for verse: Verse) -> some View {
        if store.isBookmarked(verseId: verse.id, translationId: pane.selectedTranslationId) {
            Button("Remove Bookmark") {
                if let bm = store.bookmarks.first(where: { $0.verseId == verse.id && $0.translationId == pane.selectedTranslationId }) {
                    store.removeBookmark(bm.id)
                }
            }
        } else {
            Button("Bookmark Verse") {
                store.addBookmark(verseId: verse.id, translationId: pane.selectedTranslationId)
            }
        }

        Divider()

        Menu("Highlight") {
            ForEach(HighlightColor.allCases, id: \.self) { color in
                Button(color.label) {
                    store.setHighlight(verseId: verse.id, translationId: pane.selectedTranslationId, color: color)
                }
            }
            if store.highlightFor(verseId: verse.id, translationId: pane.selectedTranslationId) != nil {
                Divider()
                Button("Remove Highlight") {
                    store.removeHighlight(verseId: verse.id, translationId: pane.selectedTranslationId)
                }
            }
        }

        Button("Add Note...") {
            noteEditingVerse = verse
        }

        Divider()

        Button("View Cross-References") {
            windowState.showCrossRefsInspector(verseId: verse.id)
        }

        if let translation = currentTranslation {
            Button("View Strong's") {
                let displayRef = "\(pane.selectedBook) \(pane.selectedChapter):\(verse.number)"
                windowState.showStrongsInspector(
                    verseId: verse.id,
                    displayRef: displayRef,
                    filePath: translation.filePath
                )
            }
        }

        Divider()

        Button("Copy Verse") {
            let ref = "\(pane.selectedBook) \(pane.selectedChapter):\(verse.number)"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("\(ref) — \(verse.text)", forType: .string)
        }

        Button("Copy Reference") {
            let ref = "\(pane.selectedBook) \(pane.selectedChapter):\(verse.number)"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(ref, forType: .string)
        }
    }

    private func toggleBookmark(for verse: Verse) {
        if store.isBookmarked(verseId: verse.id, translationId: pane.selectedTranslationId) {
            if let bm = store.bookmarks.first(where: { $0.verseId == verse.id && $0.translationId == pane.selectedTranslationId }) {
                store.removeBookmark(bm.id)
            }
        } else {
            store.addBookmark(verseId: verse.id, translationId: pane.selectedTranslationId)
        }
    }

    private var noVersesView: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.page")
                .font(.title)
                .foregroundStyle(.quaternary)
            Text("No verses found")
                .font(.callout)
                .foregroundStyle(.tertiary)
            if currentTranslation == nil {
                Text("Select a translation above")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Chapter Nav Footer

    private var chapterNavFooter: some View {
        HStack {
            if pane.selectedChapter > 1 {
                Button(action: prevChapter) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("\(displayBookName) \(pane.selectedChapter - 1)")
                    }
                    .font(.callout)
                }
                .buttonStyle(.borderless)
            }

            Spacer()

            if pane.selectedChapter < pane.chapterCount {
                Button(action: nextChapter) {
                    HStack(spacing: 4) {
                        Text("\(displayBookName) \(pane.selectedChapter + 1)")
                        Image(systemName: "chevron.right")
                    }
                    .font(.callout)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 4)
    }

    // MARK: - Helpers

    private var currentTranslation: Translation? {
        store.loadedTranslations.first { $0.id == pane.selectedTranslationId }
    }

    private var displayBookName: String {
        if let translation = currentTranslation,
           let localized = translation.metadata.bookNames?[pane.selectedBook] {
            return localized
        }
        return pane.selectedBook
    }

    private func verseAnchor(_ number: Int) -> String {
        "verse-\(pane.id)-\(number)"
    }

    private func loadCurrentChapter() {
        store.loadVerses(for: pane)
        visibleVerseNumbers.removeAll()
    }

    /// Report the lowest visible verse number to the coordinator for scroll sync.
    private func reportTopVisibleVerse() {
        guard syncScrolling, !visibleVerseNumbers.isEmpty else { return }
        let topVerse = visibleVerseNumbers.min() ?? 1
        coordinator.reportVisibleVerse(topVerse, from: pane.id)
    }

    private func prevChapter() {
        if pane.selectedChapter > 1 {
            pane.selectedChapter -= 1
        } else {
            // Go to previous book's last chapter
            if let idx = BibleBooks.all.firstIndex(of: pane.selectedBook), idx > 0 {
                let prevBook = BibleBooks.all[idx - 1]
                pane.selectedBook = prevBook
                pane.selectedChapter = pane.chapterCount
                loadCurrentChapter()
            }
        }
    }

    private func nextChapter() {
        if pane.selectedChapter < pane.chapterCount {
            pane.selectedChapter += 1
        } else {
            // Go to next book's first chapter
            if let idx = BibleBooks.all.firstIndex(of: pane.selectedBook),
               idx < BibleBooks.all.count - 1 {
                pane.selectedBook = BibleBooks.all[idx + 1]
                pane.selectedChapter = 1
                loadCurrentChapter()
            }
        }
    }
}

// MARK: - Verse Row

struct VerseRow: View {
    let verse: Verse
    var fontSize: CGFloat = 15
    var fontFamily: String = "System"
    var lineSpacingMultiplier: CGFloat = 1.3
    var wordSpacing: CGFloat = 0.0
    var verseNumberStyle: String = "superscript"
    var highlightOpacity: Double = 0.12
    var isHovered: Bool = false
    var isSelected: Bool = false
    var isBookmarked: Bool = false
    var highlightColor: HighlightColor? = nil
    var hasNote: Bool = false
    var customTextColor: Color? = nil
    var customBackgroundColor: Color? = nil
    var onToggleBookmark: (() -> Void)? = nil
    var onHighlightColor: ((HighlightColor?) -> Void)? = nil
    var onNoteEdit: (() -> Void)? = nil
    var onVerseNumberTap: (() -> Void)? = nil
    var onWordTap: ((WordTag?) -> Void)? = nil

    @State private var showHighlightPicker = false

    private var showActionButtons: Bool {
        isHovered || isSelected
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            // Left action column — visible on hover/select or when active
            actionButtons
                .frame(width: 44, alignment: .trailing)

            // Verse number
            if verseNumberStyle == "margin" {
                verseNumberButton
                    .frame(width: 30, alignment: .trailing)
            }

            // Verse text
            if verseNumberStyle == "superscript" || verseNumberStyle == "inline" {
                if verse.wordTags.isEmpty {
                    // Plain text with inline verse number
                    HStack(spacing: 0) {
                        verseNumberButton
                        Text(" ")
                        verseBodyTextView
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // Tagged text — clickable words
                    HStack(spacing: 0) {
                        verseNumberButton
                        Text(" ")
                    }
                    taggedVerseText
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                // Margin style — text separate from number
                if verse.wordTags.isEmpty {
                    verseBodyTextView
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    taggedVerseText
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: showActionButtons)
        .animation(.easeInOut(duration: 0.15), value: highlightColor)
    }

    // MARK: - Action Buttons Column

    private var actionButtons: some View {
        HStack(spacing: 2) {
            // Bookmark button
            if showActionButtons || isBookmarked {
                Button(action: { onToggleBookmark?() }) {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 11))
                        .foregroundColor(isBookmarked ? .accentColor : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help(isBookmarked ? "Remove bookmark" : "Bookmark this verse")
                .transition(.opacity)
            }

            // Highlight button
            if showActionButtons || highlightColor != nil {
                Button(action: { showHighlightPicker.toggle() }) {
                    Image(systemName: highlightColor != nil ? "paintbrush.fill" : "paintbrush")
                        .font(.system(size: 11))
                        .foregroundColor(highlightColor?.displayColor ?? .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Highlight verse")
                .transition(.opacity)
                .popover(isPresented: $showHighlightPicker, arrowEdge: .trailing) {
                    HighlightColorPicker(
                        currentColor: highlightColor,
                        onSelect: { color in
                            onHighlightColor?(color)
                            showHighlightPicker = false
                        }
                    )
                }
            }

            // Note button
            if showActionButtons || hasNote {
                Button(action: { onNoteEdit?() }) {
                    Image(systemName: hasNote ? "note.text" : "note.text.badge.plus")
                        .font(.system(size: 11))
                        .foregroundColor(hasNote ? .orange : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help(hasNote ? "Edit note" : "Add note")
                .transition(.opacity)
            }
        }
        .opacity(showActionButtons || isBookmarked || highlightColor != nil || hasNote ? 1 : 0)
    }

    // MARK: - Verse Number Button

    private var verseNumberButton: some View {
        Button(action: { onVerseNumberTap?() }) {
            if verseNumberStyle == "superscript" {
                Text("\(verse.number)")
                    .font(.system(size: fontSize * 0.6).monospacedDigit())
                    .foregroundColor(verseNumberColor)
                    .baselineOffset(fontSize * 0.3)
            } else {
                Text("\(verse.number)")
                    .font(.system(size: fontSize * 0.7).monospacedDigit())
                    .foregroundColor(verseNumberColor)
            }
        }
        .buttonStyle(.plain)
        .help("View cross-references")
    }

    // MARK: - Verse Text (Plain)

    private var verseBodyTextView: some View {
        Text(verse.text)
            .font(resolvedFont)
            .foregroundColor(customTextColor)
            .lineSpacing(fontSize * (lineSpacingMultiplier - 1.0))
            .tracking(wordSpacing)
            .textSelection(.enabled)
    }

    // MARK: - Verse Text (Tagged — clickable words)

    private var taggedVerseText: some View {
        // Build a flow layout of clickable words
        WrappingHStack(alignment: .leading, spacing: 3) {
            ForEach(Array(verse.wordTags.enumerated()), id: \.offset) { _, tag in
                TaggedWordView(
                    tag: tag,
                    fontSize: fontSize,
                    fontFamily: fontFamily,
                    customTextColor: customTextColor,
                    onTap: { onWordTap?(tag) }
                )
            }
        }
        .lineSpacing(fontSize * (lineSpacingMultiplier - 1.0))
    }

    // MARK: - Styling

    private var verseNumberColor: Color {
        Color.accentColor.opacity(isSelected ? 1.0 : 0.8)
    }

    private var resolvedFont: Font {
        if fontFamily == "System" {
            return .system(size: fontSize, design: .serif)
        }
        return .custom(fontFamily, size: fontSize)
    }

    private var backgroundColor: Color {
        if let hl = highlightColor {
            return hl.displayColor.opacity(highlightOpacity)
        }
        if isSelected {
            return Color.accentColor.opacity(highlightOpacity)
        } else if isHovered {
            return Color.primary.opacity(0.04)
        }
        return customBackgroundColor ?? Color.clear
    }
}

// MARK: - Tagged Word View

struct TaggedWordView: View {
    let tag: WordTag
    let fontSize: CGFloat
    let fontFamily: String
    let customTextColor: Color?
    let onTap: () -> Void

    @State private var isWordHovered = false

    private var hasStrongs: Bool {
        !tag.strongsNumbers.isEmpty
    }

    var body: some View {
        Text(tag.word)
            .font(resolvedFont)
            .foregroundColor(textColor)
            .underline(isWordHovered && hasStrongs, color: .accentColor.opacity(0.4))
            .onHover { hovering in
                if hasStrongs {
                    isWordHovered = hovering
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
            .onTapGesture {
                if hasStrongs {
                    onTap()
                }
            }
            .help(hasStrongs ? tag.strongsNumbers.joined(separator: ", ") : "")
    }

    private var textColor: Color {
        if isWordHovered && hasStrongs {
            return .accentColor
        }
        return customTextColor ?? .primary
    }

    private var resolvedFont: Font {
        if fontFamily == "System" {
            return .system(size: fontSize, design: .serif)
        }
        return .custom(fontFamily, size: fontSize)
    }
}

// MARK: - Highlight Color Picker Popover

struct HighlightColorPicker: View {
    let currentColor: HighlightColor?
    let onSelect: (HighlightColor?) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(HighlightColor.allCases, id: \.self) { color in
                Button(action: { onSelect(color) }) {
                    Circle()
                        .fill(color.displayColor)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(currentColor == color ? 0.6 : 0.2), lineWidth: currentColor == color ? 2 : 0.5)
                        )
                        .scaleEffect(currentColor == color ? 1.15 : 1.0)
                }
                .buttonStyle(.plain)
                .help(color.label)
            }

            if currentColor != nil {
                Divider().frame(height: 22)
                Button(action: { onSelect(nil) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove highlight")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Note Editor Sheet

struct NoteEditorSheet: View {
    let verseId: String
    let verseRef: String
    let translationId: UUID
    let initialText: String
    let onSave: (String) -> Void

    @State private var noteText: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Note")
                        .font(.headline)
                    Text(verseRef)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Save") {
                    onSave(noteText)
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Text editor
            TextEditor(text: $noteText)
                .font(.body)
                .padding(8)
                .frame(minHeight: 150)

            // Delete button if note exists
            if !initialText.isEmpty {
                Divider()
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        onSave("")
                        dismiss()
                    } label: {
                        Label("Delete Note", systemImage: "trash")
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 400, maxWidth: 400, minHeight: 280)
        .onAppear {
            noteText = initialText
        }
    }
}

// MARK: - Wrapping HStack (Flow Layout)

/// A simple flow layout for word-level display
struct WrappingHStack: Layout {
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            guard index < subviews.count else { break }
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct LayoutResult {
        var positions: [CGPoint]
        var size: CGSize
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing * 0.5
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxX = max(maxX, currentX)
        }

        return LayoutResult(
            positions: positions,
            size: CGSize(width: maxX, height: currentY + lineHeight)
        )
    }
}

// MARK: - Keyboard Navigation

extension ReaderView {
    /// Keyboard shortcut handler — wire to .onKeyPress or Commands
    static func handleKeyNav(windowState: WindowState, store: BibleStore, event: KeyEquivalent) {
        guard let pane = windowState.panes.first else { return }
        switch event {
        case .leftArrow:
            if pane.selectedChapter > 1 {
                pane.selectedChapter -= 1
                store.loadVerses(for: pane)
            }
        case .rightArrow:
            if pane.selectedChapter < pane.chapterCount {
                pane.selectedChapter += 1
                store.loadVerses(for: pane)
            }
        default:
            break
        }
    }
}
