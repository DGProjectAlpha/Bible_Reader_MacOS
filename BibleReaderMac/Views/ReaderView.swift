import SwiftUI
import Combine

// MARK: - Reader View (top-level split container)

struct ReaderView: View {
    @EnvironmentObject var store: BibleStore
    @State private var syncScrolling = true
    @StateObject private var syncCoordinator = ScrollSyncCoordinator()
    @State private var showStrongsSidebar = false
    @State private var selectedVerseForStrongs: SelectedVerseInfo?

    var body: some View {
        HSplitView {
            // Main reader area
            Group {
                if store.loadedTranslations.isEmpty {
                    emptyState
                } else if store.panes.count == 1, let pane = store.panes.first {
                    ReaderPaneView(
                        pane: pane,
                        isSolo: true,
                        syncScrolling: $syncScrolling,
                        coordinator: syncCoordinator,
                        onVerseTap: { verse, translation in
                            selectVerseForStrongs(verse, translation: translation, pane: pane)
                        }
                    )
                } else {
                    HSplitView {
                        ForEach(store.panes) { pane in
                            ReaderPaneView(
                                pane: pane,
                                isSolo: false,
                                syncScrolling: $syncScrolling,
                                coordinator: syncCoordinator,
                                onVerseTap: { verse, translation in
                                    selectVerseForStrongs(verse, translation: translation, pane: pane)
                                }
                            )
                            .frame(minWidth: 280)
                        }
                    }
                }
            }

            // Strong's concordance sidebar
            if showStrongsSidebar, let info = selectedVerseForStrongs {
                StrongsSidebarView(
                    verseRef: info.displayRef,
                    verseId: info.verseId,
                    translationFilePath: info.filePath,
                    isVisible: $showStrongsSidebar
                )
                .transition(.move(edge: .trailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Toggle(isOn: $syncScrolling) {
                    Label("Sync Scroll", systemImage: syncScrolling ? "link" : "link.badge.plus")
                }
                .help(syncScrolling ? "Scroll syncing enabled" : "Scroll syncing disabled")

                if store.panes.count < 4 {
                    Button(action: { store.addPane() }) {
                        Label("Add Pane", systemImage: "plus.rectangle.on.rectangle")
                    }
                    .help("Add parallel translation pane")
                }

                Button(action: {
                    NotificationCenter.default.post(name: .manageTranslations, object: nil)
                }) {
                    Label("Translations", systemImage: "books.vertical")
                }
                .help("Manage translations")
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Divider()

                Toggle(isOn: $showStrongsSidebar) {
                    Label("Strong's", systemImage: "character.book.closed")
                }
                .help(showStrongsSidebar ? "Hide Strong's sidebar" : "Show Strong's sidebar")
            }
        }
        // Handle cross-reference navigation: jump reader to a specific verse
        .onReceive(NotificationCenter.default.publisher(for: .navigateToVerse)) { notification in
            guard let userInfo = notification.userInfo,
                  let book = userInfo["book"] as? String,
                  let chapter = userInfo["chapter"] as? Int,
                  let verse = userInfo["verse"] as? Int,
                  let pane = store.panes.first else { return }

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
        .onChange(of: syncScrolling) { enabled in
            if enabled {
                // When re-enabling sync, align all panes to the first pane's position
                guard let leader = store.panes.first else { return }
                for pane in store.panes.dropFirst() {
                    pane.selectedBook = leader.selectedBook
                    pane.selectedChapter = leader.selectedChapter
                    store.loadVerses(for: pane)
                }
            }
        }
    }

    // MARK: - Strong's Verse Selection

    private func selectVerseForStrongs(_ verse: Verse, translation: Translation?, pane: ReaderPane) {
        guard let translation else { return }
        let info = SelectedVerseInfo(
            verseId: verse.id,
            displayRef: "\(pane.selectedBook) \(pane.selectedChapter):\(verse.number)",
            filePath: translation.filePath
        )
        selectedVerseForStrongs = info
        if !showStrongsSidebar {
            withAnimation(.easeInOut(duration: 0.25)) {
                showStrongsSidebar = true
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
    private var suppressionTimers: [UUID: DispatchWorkItem] = []

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
    @ObservedObject var pane: ReaderPane
    let isSolo: Bool
    @Binding var syncScrolling: Bool
    @ObservedObject var coordinator: ScrollSyncCoordinator
    var onVerseTap: ((Verse, Translation?) -> Void)?

    @State private var scrollProxy: ScrollViewProxy?
    @State private var fontSize: CGFloat = 15
    @State private var showBookPicker = false
    @State private var hoveredVerse: Int?
    @State private var selectedVerse: Int?
    @State private var visibleVerseNumbers: Set<Int> = []

    var body: some View {
        VStack(spacing: 0) {
            paneHeader
            Divider()
            verseContent
        }
        .vibrancyBackground(material: .contentBackground, blendingMode: .withinWindow)
        .onAppear { loadCurrentChapter() }
        .onChange(of: pane.selectedTranslationId) { _ in loadCurrentChapter() }
        .onChange(of: pane.selectedBook) { _ in
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
        .onChange(of: pane.selectedChapter) { _ in
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
        .onChange(of: coordinator.visibleVerse) { verse in
            guard syncScrolling,
                  let source = coordinator.sourcePane,
                  source != pane.id else { return }
            coordinator.suppressPane(pane.id)
            withAnimation(.easeOut(duration: 0.2)) {
                scrollProxy?.scrollTo(verseAnchor(verse), anchor: .top)
            }
        }
        // Respond to navigation sync from other panes
        .onChange(of: coordinator.navigationEvent) { event in
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

                    Button(action: { fontSize = min(28, fontSize + 1) }) {
                        Image(systemName: "textformat.size.larger")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help("Increase font size")
                }

                // Close pane button
                if !isSolo {
                    Divider().frame(height: 20)
                    Button(action: { store.removePane(pane.id) }) {
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
                                fontSize: fontSize,
                                isHovered: hoveredVerse == verse.number,
                                isSelected: selectedVerse == verse.number
                            )
                            .id(verseAnchor(verse.number))
                            .onHover { isHovered in
                                hoveredVerse = isHovered ? verse.number : nil
                            }
                            .onTapGesture {
                                selectedVerse = (selectedVerse == verse.number) ? nil : verse.number
                                onVerseTap?(verse, currentTranslation)
                            }
                            .contextMenu {
                                Button("View Cross-References") {
                                    NotificationCenter.default.post(
                                        name: .showCrossReferences,
                                        object: nil,
                                        userInfo: ["verseId": verse.id]
                                    )
                                }
                                Button("Copy Verse") {
                                    let ref = "\(pane.selectedBook) \(pane.selectedChapter):\(verse.number)"
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString("\(ref) — \(verse.text)", forType: .string)
                                }
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
                pane.selectedChapter = BibleBooks.chapterCounts[prevBook] ?? 1
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
    var isHovered: Bool = false
    var isSelected: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(verse.number)")
                .font(.system(size: fontSize * 0.7).monospacedDigit())
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(width: 30, alignment: .trailing)

            Text(verse.text)
                .font(.system(size: fontSize, design: .serif))
                .lineSpacing(fontSize * 0.3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
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
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        } else if isHovered {
            return Color.primary.opacity(0.04)
        }
        return Color.clear
    }
}

// MARK: - Selected Verse Info (for Strong's sidebar)

struct SelectedVerseInfo: Equatable {
    let verseId: String       // "Genesis:1:1"
    let displayRef: String    // "Genesis 1:1"
    let filePath: String      // path to the .brbmod file

    static func == (lhs: SelectedVerseInfo, rhs: SelectedVerseInfo) -> Bool {
        lhs.verseId == rhs.verseId && lhs.filePath == rhs.filePath
    }
}

// MARK: - Keyboard Navigation

extension ReaderView {
    /// Keyboard shortcut handler — wire to .onKeyPress or Commands
    static func handleKeyNav(store: BibleStore, event: KeyEquivalent) {
        guard let pane = store.panes.first else { return }
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
