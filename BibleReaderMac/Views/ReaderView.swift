import SwiftUI
import Combine

// MARK: - Reader View (top-level container)

struct ReaderView: View {
    @EnvironmentObject var store: BibleStore
    @EnvironmentObject var windowState: WindowState
    @AppStorage("syncScrolling") private var syncScrolling = true
    @StateObject private var syncCoordinator = ScrollSyncCoordinator()

    var body: some View {
        Group {
            if store.loadedTranslations.isEmpty {
                emptyState
            } else if windowState.panes.count == 1 {
                ReaderPaneView(paneId: windowState.panes[0].id,
                               syncScrolling: $syncScrolling,
                               coordinator: syncCoordinator)
            } else {
                splitPaneGrid()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Toggle(isOn: $syncScrolling) {
                    Label(L("reader.sync_scroll"), systemImage: syncScrolling ? "link" : "link.badge.plus")
                }
                .help(syncScrolling ? L("reader.sync_enabled") : L("reader.sync_disabled"))
            }
        }
        // Cross-ref navigation: jump reader to a specific verse
        .onReceive(NotificationCenter.default.publisher(for: .navigateToVerse)) { notification in
            guard let userInfo = notification.userInfo,
                  let book = userInfo["book"] as? String,
                  let chapter = userInfo["chapter"] as? Int,
                  let verse = userInfo["verse"] as? Int else { return }

            let targetId: UUID
            if let activeId = windowState.lastActivePaneId,
               windowState.panes.contains(where: { $0.id == activeId }) {
                targetId = activeId
            } else if let first = windowState.panes.first {
                targetId = first.id
            } else { return }

            navigateTo(paneId: targetId, book: book, chapter: chapter)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                syncCoordinator.scrollProxies[targetId]?.scrollTo(
                    "verse-\(targetId)-\(verse)", anchor: .top
                )
            }
        }
        .onChange(of: syncScrolling) {
            guard syncScrolling, let leader = windowState.panes.first else { return }
            for pane in windowState.panes.dropFirst() {
                navigateTo(paneId: pane.id, book: leader.book, chapter: leader.chapter)
            }
        }
    }

    // MARK: - Navigate helper

    private func navigateTo(paneId: UUID, book: String, chapter: Int) {
        windowState.navigate(paneId: paneId, book: book, chapter: chapter)
        guard let pane = windowState.panes.first(where: { $0.id == paneId }) else { return }
        let verses = store.loadVerses(translationId: pane.translationId, book: book, chapter: chapter)
        let scheme = store.versificationScheme(for: pane.translationId)
        windowState.setVerses(paneId: paneId, verses: verses, versificationScheme: scheme)
    }

    // MARK: - Split Pane Grid

    private struct PaneColumn: Identifiable {
        let id = UUID()
        let top: UUID
        let bottom: UUID?
    }

    private func buildColumns() -> [PaneColumn] {
        var verticalChildren: [UUID: UUID] = [:]
        var consumed = Set<UUID>()
        for pane in windowState.panes {
            if let buddyId = pane.verticalBuddyId {
                verticalChildren[buddyId] = pane.id
                consumed.insert(pane.id)
            }
        }
        var columns: [PaneColumn] = []
        for pane in windowState.panes {
            if consumed.contains(pane.id) { continue }
            columns.append(PaneColumn(top: pane.id, bottom: verticalChildren[pane.id]))
        }
        return columns
    }

    @ViewBuilder
    private func columnView(_ col: PaneColumn) -> some View {
        if let bottomId = col.bottom {
            VSplitView {
                ReaderPaneView(paneId: col.top, syncScrolling: $syncScrolling, coordinator: syncCoordinator)
                    .frame(minHeight: 100, idealHeight: .infinity, maxHeight: .infinity)
                ReaderPaneView(paneId: bottomId, syncScrolling: $syncScrolling, coordinator: syncCoordinator)
                    .frame(minHeight: 100, idealHeight: .infinity, maxHeight: .infinity)
            }
        } else {
            ReaderPaneView(paneId: col.top, syncScrolling: $syncScrolling, coordinator: syncCoordinator)
        }
    }

    @ViewBuilder
    private func splitPaneGrid() -> some View {
        let cols = buildColumns()
        switch cols.count {
        case 2:
            HSplitView { columnView(cols[0]); columnView(cols[1]) }
        case 3:
            HSplitView { columnView(cols[0]); columnView(cols[1]); columnView(cols[2]) }
        case 4:
            HSplitView { columnView(cols[0]); columnView(cols[1]); columnView(cols[2]); columnView(cols[3]) }
        case 5:
            HSplitView { columnView(cols[0]); columnView(cols[1]); columnView(cols[2]); columnView(cols[3]); columnView(cols[4]) }
        case 6:
            HSplitView { columnView(cols[0]); columnView(cols[1]); columnView(cols[2]); columnView(cols[3]); columnView(cols[4]); columnView(cols[5]) }
        case 7:
            HSplitView { columnView(cols[0]); columnView(cols[1]); columnView(cols[2]); columnView(cols[3]); columnView(cols[4]); columnView(cols[5]); columnView(cols[6]) }
        case 8:
            HSplitView { columnView(cols[0]); columnView(cols[1]); columnView(cols[2]); columnView(cols[3]); columnView(cols[4]); columnView(cols[5]); columnView(cols[6]); columnView(cols[7]) }
        default:
            columnView(cols[0])
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text(L("reader.no_translations_title"))
                .font(.title2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(L("reader.no_translations_hint"))
                .font(.callout)
                .foregroundStyle(.tertiary)
            Button(L("reader.open_settings")) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Scroll Sync Coordinator

@MainActor
class ScrollSyncCoordinator: ObservableObject {
    var scrollProxies: [UUID: ScrollViewProxy] = [:]
    private var lastSyncedVerse: Int = 1
    private var lastSourcePane: UUID?
    private var suppressedPanes: Set<UUID> = []
    private var suppressionTimers: [UUID: DispatchWorkItem] = [:]

    func registerScrollProxy(_ proxy: ScrollViewProxy, for paneId: UUID) {
        scrollProxies[paneId] = proxy
    }

    func reportVisibleVerse(_ verse: Int, from paneId: UUID) {
        guard !suppressedPanes.contains(paneId) else { return }
        guard verse != lastSyncedVerse || lastSourcePane != paneId else { return }
        lastSourcePane = paneId
        lastSyncedVerse = verse
        for (otherId, proxy) in scrollProxies where otherId != paneId {
            suppressPane(otherId, for: 0.3)
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) {
                proxy.scrollTo("verse-\(otherId)-\(verse)", anchor: .top)
            }
        }
    }

    func suppressPane(_ paneId: UUID, for duration: TimeInterval = 0.3) {
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

// MARK: - Visible Verse Tracker

@MainActor
class VisibleVerseTracker {
    var verses: Set<Int> = []
    private var debounceWork: DispatchWorkItem?

    func insert(_ verse: Int) { verses.insert(verse) }
    func remove(_ verse: Int) { verses.remove(verse) }
    var topVerse: Int? { verses.min() }

    func clear() {
        verses.removeAll()
        debounceWork?.cancel()
    }

    func reportDebounced(interval: TimeInterval = 0.15, handler: @escaping (Int) -> Void) {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let top = self?.topVerse else { return }
            handler(top)
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: work)
    }
}

// MARK: - Single Reader Pane

struct ReaderPaneView: View {
    @EnvironmentObject var store: BibleStore
    @EnvironmentObject var windowState: WindowState

    let paneId: UUID
    @Binding var syncScrolling: Bool
    @ObservedObject var coordinator: ScrollSyncCoordinator

    @AppStorage("fontSize") private var fontSize: Double = 15
    @AppStorage("fontFamily") private var fontFamily: String = "System"
    @AppStorage("lineSpacing") private var lineSpacing: Double = 1.3
    @AppStorage("wordSpacing") private var wordSpacing: Double = 0.0
    @AppStorage("verseNumberStyle") private var verseNumberStyle: String = "superscript"
    @AppStorage("paragraphMode") private var paragraphMode: Bool = false
    @AppStorage("verseHighlightOpacity") private var verseHighlightOpacity: Double = 0.3
    @AppStorage("showChapterTitles") private var showChapterTitles: Bool = true
    @AppStorage("readerTheme") private var readerTheme: String = "auto"
    @AppStorage("textColorHex") private var textColorHex: String = ""
    @AppStorage("backgroundColorHex") private var backgroundColorHex: String = ""

    @State private var scrollProxy: ScrollViewProxy?
    @State private var hoveredVerse: Int?
    @State private var selectedVerse: Int?
    @State private var visibleVerseTracker = VisibleVerseTracker()
    @State private var noteEditingVerse: Verse?

    // Computed from windowState — never stored locally
    private var pane: ReaderPane? {
        windowState.panes.first { $0.id == paneId }
    }
    private var isSolo: Bool { windowState.panes.count == 1 }

    var body: some View {
        guard let pane else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(spacing: 0) {
                paneHeader(pane)
                Divider()
                verseContent(pane)
            }
            .vibrancyBackground(material: .contentBackground, blendingMode: .withinWindow)
            .onAppear {
                loadChapter(pane: pane)
            }
            .sheet(item: $noteEditingVerse) { verse in
                NoteEditorSheet(
                    verseId: verse.id,
                    verseRef: "\(pane.book) \(pane.chapter):\(verse.number)",
                    translationId: pane.translationId,
                    initialText: store.noteFor(verseId: verse.id, translationId: pane.translationId)?.content ?? "",
                    onSave: { content in
                        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            if let note = store.noteFor(verseId: verse.id, translationId: pane.translationId) {
                                store.removeNote(note.id)
                            }
                        } else {
                            store.addNote(verseId: verse.id, translationId: pane.translationId, content: content)
                        }
                    }
                )
            }
        )
    }

    // MARK: - Load chapter (the ONE place verses get loaded)

    private func loadChapter(pane: ReaderPane) {
        let verses = store.loadVerses(translationId: pane.translationId, book: pane.book, chapter: pane.chapter)
        let scheme = store.versificationScheme(for: pane.translationId)
        windowState.setVerses(paneId: paneId, verses: verses, versificationScheme: scheme)
        visibleVerseTracker.clear()
    }

    // MARK: - Navigation actions (called directly, no reactive chains)

    private func selectTranslation(_ newId: UUID, currentPane: ReaderPane) {
        guard newId != currentPane.translationId else { return }
        // Convert position if versification differs
        let (newBook, newChapter) = store.convertPosition(
            book: currentPane.book, chapter: currentPane.chapter, verse: visibleVerseTracker.topVerse ?? 1,
            from: currentPane.translationId, to: newId
        )
        windowState.navigate(paneId: paneId, book: newBook, chapter: newChapter, translationId: newId)
        guard let updated = pane else { return }
        loadChapter(pane: updated)
    }

    private func selectBook(_ newBook: String) {
        guard let currentPane = pane, newBook != currentPane.book else { return }
        windowState.navigate(paneId: paneId, book: newBook, chapter: 1)
        guard let updated = pane else { return }
        loadChapter(pane: updated)
        reportNavigation(updated)
    }

    private func selectChapter(_ newChapter: Int) {
        guard let currentPane = pane, newChapter != currentPane.chapter else { return }
        windowState.navigate(paneId: paneId, chapter: newChapter)
        guard let updated = pane else { return }
        loadChapter(pane: updated)
        reportNavigation(updated)
    }

    private func prevChapter() {
        guard let p = pane else { return }
        if p.chapter > 1 {
            selectChapter(p.chapter - 1)
        } else if let idx = BibleBooks.all.firstIndex(of: p.book), idx > 0 {
            let prevBook = BibleBooks.all[idx - 1]
            let lastChapter = VersificationService.shared.chapterCount(
                book: prevBook, scheme: VersificationScheme.from(p.versificationScheme))
            windowState.navigate(paneId: paneId, book: prevBook, chapter: lastChapter)
            guard let updated = pane else { return }
            loadChapter(pane: updated)
            reportNavigation(updated)
        }
    }

    private func nextChapter() {
        guard let p = pane else { return }
        if p.chapter < p.chapterCount {
            selectChapter(p.chapter + 1)
        } else if let idx = BibleBooks.all.firstIndex(of: p.book), idx < BibleBooks.all.count - 1 {
            let nextBook = BibleBooks.all[idx + 1]
            windowState.navigate(paneId: paneId, book: nextBook, chapter: 1)
            guard let updated = pane else { return }
            loadChapter(pane: updated)
            reportNavigation(updated)
        }
    }

    private func reportNavigation(_ p: ReaderPane) {
        guard syncScrolling else { return }
        // Sync other panes to same position
        for otherPane in windowState.panes where otherPane.id != paneId {
            windowState.navigate(paneId: otherPane.id, book: p.book, chapter: p.chapter)
            guard let updated = windowState.panes.first(where: { $0.id == otherPane.id }) else { continue }
            let verses = store.loadVerses(translationId: updated.translationId, book: updated.book, chapter: updated.chapter)
            let scheme = store.versificationScheme(for: updated.translationId)
            windowState.setVerses(paneId: otherPane.id, verses: verses, versificationScheme: scheme)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func paneHeader(_ pane: ReaderPane) -> some View {
        VStack(spacing: 0) {
            FlowLayout(spacing: 8) {
                // Translation picker
                let translationBinding = Binding<UUID>(
                    get: { pane.translationId },
                    set: { selectTranslation($0, currentPane: pane) }
                )
                Picker("", selection: translationBinding) {
                    ForEach(store.loadedTranslations) { t in
                        Text(t.abbreviation).tag(t.id)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .help(L("reader.select_translation"))

                Divider().frame(height: 20)

                // Book picker
                let bookBinding = Binding<String>(
                    get: { pane.book },
                    set: { selectBook($0) }
                )
                Picker("", selection: bookBinding) {
                    ForEach(BibleBooks.all, id: \.self) { book in
                        Text(BibleBooks.localizedName(for: book)).tag(book)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .help(L("reader.select_book"))

                // Chapter nav
                HStack(spacing: 4) {
                    Button(action: prevChapter) {
                        Image(systemName: "chevron.left")
                            .font(.caption.weight(.semibold))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(pane.chapter <= 1 && BibleBooks.all.firstIndex(of: pane.book) == 0)
                    .help(L("reader.prev_chapter"))

                    let chapterBinding = Binding<Int>(
                        get: { pane.chapter },
                        set: { selectChapter($0) }
                    )
                    Picker("", selection: chapterBinding) {
                        ForEach(1...max(1, pane.chapterCount), id: \.self) { ch in
                            Text("\(ch)").tag(ch)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .help(L("reader.select_chapter"))

                    Button(action: nextChapter) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(pane.chapter >= pane.chapterCount && BibleBooks.all.firstIndex(of: pane.book) == BibleBooks.all.count - 1)
                    .help(L("reader.next_chapter"))
                }

                // Font size
                HStack(spacing: 4) {
                    Button(action: { fontSize = max(10, fontSize - 1) }) {
                        Image(systemName: "textformat.size.smaller")
                            .font(.callout).frame(width: 26, height: 26).contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help(L("reader.decrease_font"))

                    Text("\(Int(fontSize))")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .center)

                    Button(action: { fontSize = min(36, fontSize + 1) }) {
                        Image(systemName: "textformat.size.larger")
                            .font(.callout).frame(width: 26, height: 26).contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help(L("reader.increase_font"))
                }

                // Split buttons
                if windowState.panes.count < 8 {
                    Divider().frame(height: 20)
                    Button(action: {
                        windowState.splitPane(paneId, direction: .horizontal)
                        // Load the new pane
                        if let newPane = windowState.panes.last {
                            let verses = store.loadVerses(translationId: newPane.translationId, book: newPane.book, chapter: newPane.chapter)
                            let scheme = store.versificationScheme(for: newPane.translationId)
                            windowState.setVerses(paneId: newPane.id, verses: verses, versificationScheme: scheme)
                        }
                    }) {
                        Image(systemName: "rectangle.split.2x1")
                            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            .frame(width: 22, height: 22).contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help(L("reader.split_right"))

                    Button(action: {
                        windowState.splitPane(paneId, direction: .vertical)
                        if let newPane = windowState.panes.last {
                            let verses = store.loadVerses(translationId: newPane.translationId, book: newPane.book, chapter: newPane.chapter)
                            let scheme = store.versificationScheme(for: newPane.translationId)
                            windowState.setVerses(paneId: newPane.id, verses: verses, versificationScheme: scheme)
                        }
                    }) {
                        Image(systemName: "rectangle.split.1x2")
                            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            .frame(width: 22, height: 22).contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help(L("reader.split_down"))
                }

                // Close pane button
                if !isSolo {
                    Divider().frame(height: 20)
                    Button(action: { windowState.removePane(paneId) }) {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                            .frame(width: 22, height: 22).contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help(L("reader.close_pane"))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if showChapterTitles {
                HStack {
                    Text(displayBookName(pane) + " \(pane.chapter)")
                        .font(.headline).foregroundStyle(.primary)
                    Spacer()
                    if let t = store.translation(for: pane.translationId) {
                        Text(t.name).font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
        .glassHeader()
    }

    private func displayBookName(_ pane: ReaderPane) -> String {
        if let t = store.translation(for: pane.translationId),
           let localized = t.metadata.bookNames?[pane.book] {
            return localized
        }
        return pane.book
    }

    // MARK: - Verse Content

    @ViewBuilder
    private func verseContent(_ pane: ReaderPane) -> some View {
        let metadata = buildMetadata(pane)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if pane.verses.isEmpty {
                        noVersesView(pane)
                    } else {
                        ForEach(pane.verses) { verse in
                            let meta = metadata[verse.id] ?? (false, nil, false)
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
                                isBookmarked: meta.0,
                                highlightColor: meta.1,
                                hasNote: meta.2,
                                customTextColor: resolvedTextColor,
                                customBackgroundColor: resolvedBackgroundColor,
                                onToggleBookmark: { toggleBookmark(verse: verse, pane: pane) },
                                onHighlightColor: { color in
                                    if let color {
                                        store.setHighlight(verseId: verse.id, translationId: pane.translationId, color: color)
                                    } else {
                                        store.removeHighlight(verseId: verse.id, translationId: pane.translationId)
                                    }
                                },
                                onNoteEdit: { noteEditingVerse = verse },
                                onVerseNumberTap: {
                                    windowState.lastActivePaneId = paneId
                                    windowState.showCrossRefsInspector(verseId: verse.id)
                                },
                                onWordTap: { wordTag in
                                    guard let wordTag,
                                          let t = store.translation(for: pane.translationId) else { return }
                                    windowState.lastActivePaneId = paneId
                                    windowState.showStrongsInspector(
                                        verseId: verse.id,
                                        displayRef: "\(pane.book) \(pane.chapter):\(verse.number)",
                                        filePath: t.filePath,
                                        wordIndex: wordTag.wordIndex
                                    )
                                }
                            )
                            .id("verse-\(paneId)-\(verse.number)")
                            .onHover { isHovered in hoveredVerse = isHovered ? verse.number : nil }
                            .onTapGesture { selectedVerse = (selectedVerse == verse.number) ? nil : verse.number }
                            .contextMenu { verseContextMenu(verse: verse, pane: pane) }
                            .onAppear {
                                visibleVerseTracker.insert(verse.number)
                                if syncScrolling {
                                    visibleVerseTracker.reportDebounced { [weak coordinator, paneId] top in
                                        coordinator?.reportVisibleVerse(top, from: paneId)
                                    }
                                }
                            }
                            .onDisappear { visibleVerseTracker.remove(verse.number) }
                        }
                        chapterNavFooter(pane)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(sepiaBackground)
            .onAppear {
                scrollProxy = proxy
                coordinator.registerScrollProxy(proxy, for: paneId)
            }
        }
    }

    private func buildMetadata(_ pane: ReaderPane) -> [String: (Bool, HighlightColor?, Bool)] {
        var meta: [String: (Bool, HighlightColor?, Bool)] = [:]
        for verse in pane.verses {
            meta[verse.id] = (
                store.isBookmarked(verseId: verse.id, translationId: pane.translationId),
                store.highlightFor(verseId: verse.id, translationId: pane.translationId)?.color,
                store.noteFor(verseId: verse.id, translationId: pane.translationId) != nil
            )
        }
        return meta
    }

    @ViewBuilder
    private func noVersesView(_ pane: ReaderPane) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "text.page").font(.title).foregroundStyle(.quaternary)
            Text(L("reader.no_verses")).font(.callout).foregroundStyle(.tertiary)
            if store.translation(for: pane.translationId) == nil {
                Text(L("reader.select_translation_above")).font(.caption).foregroundStyle(.quaternary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Chapter Nav Footer

    @ViewBuilder
    private func chapterNavFooter(_ pane: ReaderPane) -> some View {
        HStack {
            let bookIdx = BibleBooks.all.firstIndex(of: pane.book) ?? 0
            if pane.chapter > 1 || bookIdx > 0 {
                Button(action: prevChapter) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(prevLabel(pane))
                    }
                    .font(.callout)
                    .padding(.vertical, 6).padding(.horizontal, 8).contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
            Spacer()
            if pane.chapter < pane.chapterCount || bookIdx < BibleBooks.all.count - 1 {
                Button(action: nextChapter) {
                    HStack(spacing: 4) {
                        Text(nextLabel(pane))
                        Image(systemName: "chevron.right")
                    }
                    .font(.callout)
                    .padding(.vertical, 6).padding(.horizontal, 8).contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 16).padding(.horizontal, 8)
    }

    private func prevLabel(_ pane: ReaderPane) -> String {
        if pane.chapter > 1 { return "\(displayBookName(pane)) \(pane.chapter - 1)" }
        guard let idx = BibleBooks.all.firstIndex(of: pane.book), idx > 0 else { return "" }
        let prevBook = BibleBooks.all[idx - 1]
        let lastCh = VersificationService.shared.chapterCount(book: prevBook, scheme: VersificationScheme.from(pane.versificationScheme))
        return "\(prevBook) \(lastCh)"
    }

    private func nextLabel(_ pane: ReaderPane) -> String {
        if pane.chapter < pane.chapterCount { return "\(displayBookName(pane)) \(pane.chapter + 1)" }
        guard let idx = BibleBooks.all.firstIndex(of: pane.book), idx < BibleBooks.all.count - 1 else { return "" }
        return "\(BibleBooks.all[idx + 1]) 1"
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func verseContextMenu(verse: Verse, pane: ReaderPane) -> some View {
        if store.isBookmarked(verseId: verse.id, translationId: pane.translationId) {
            Button(L("reader.remove_bookmark")) {
                if let bm = store.bookmarks.first(where: { $0.verseId == verse.id && $0.translationId == pane.translationId }) {
                    store.removeBookmark(bm.id)
                }
            }
        } else {
            Button(L("reader.bookmark_verse_menu")) {
                store.addBookmark(verseId: verse.id, translationId: pane.translationId)
            }
        }
        Divider()
        Menu(L("reader.highlight_menu")) {
            ForEach(HighlightColor.allCases, id: \.self) { color in
                Button(color.label) {
                    store.setHighlight(verseId: verse.id, translationId: pane.translationId, color: color)
                }
            }
            if store.highlightFor(verseId: verse.id, translationId: pane.translationId) != nil {
                Divider()
                Button(L("reader.remove_highlight")) {
                    store.removeHighlight(verseId: verse.id, translationId: pane.translationId)
                }
            }
        }
        Button(L("reader.add_note_menu")) { noteEditingVerse = verse }
        Divider()
        Button(L("reader.view_cross_refs")) { windowState.showCrossRefsInspector(verseId: verse.id) }
        if let t = store.translation(for: pane.translationId) {
            Button(L("reader.view_strongs")) {
                windowState.showStrongsInspector(
                    verseId: verse.id,
                    displayRef: "\(pane.book) \(pane.chapter):\(verse.number)",
                    filePath: t.filePath
                )
            }
        }
        Divider()
        Button(L("reader.copy_verse")) {
            let ref = "\(pane.book) \(pane.chapter):\(verse.number)"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("\(ref) — \(verse.text)", forType: .string)
        }
        Button(L("reader.copy_reference")) {
            let ref = "\(pane.book) \(pane.chapter):\(verse.number)"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(ref, forType: .string)
        }
    }

    private func toggleBookmark(verse: Verse, pane: ReaderPane) {
        if store.isBookmarked(verseId: verse.id, translationId: pane.translationId) {
            if let bm = store.bookmarks.first(where: { $0.verseId == verse.id && $0.translationId == pane.translationId }) {
                store.removeBookmark(bm.id)
            }
        } else {
            store.addBookmark(verseId: verse.id, translationId: pane.translationId)
        }
    }

    // MARK: - Styling

    private var sepiaBackground: some View {
        Group {
            if readerTheme == "sepia" && backgroundColorHex.isEmpty {
                Color(red: 0.98, green: 0.95, blue: 0.88)
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
        Color.fromHex(backgroundColorHex)
    }
}

// MARK: - FlowLayout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        var width: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            height += rowHeight + (i > 0 ? spacing : 0)
            let rowWidth = row.enumerated().reduce(CGFloat(0)) { sum, pair in
                sum + pair.element.sizeThatFits(.unspecified).width + (pair.offset > 0 ? spacing : 0)
            }
            width = max(width, rowWidth)
        }
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        var y = bounds.minY
        for row in rows {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            var x = bounds.minX
            for view in row {
                let size = view.sizeThatFits(.unspecified)
                view.place(at: CGPoint(x: x, y: y + (rowHeight - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var currentWidth: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].isEmpty && currentWidth + spacing + size.width > maxWidth {
                rows.append([view])
                currentWidth = size.width
            } else {
                if !rows[rows.count - 1].isEmpty { currentWidth += spacing }
                rows[rows.count - 1].append(view)
                currentWidth += size.width
            }
        }
        return rows
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
    var highlightOpacity: Double = 0.3
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

    private var showActionButtons: Bool { isHovered || isSelected }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            actionButtons.frame(width: 44, alignment: .trailing)
            if verseNumberStyle == "margin" {
                verseNumberButton.frame(width: 30, alignment: .trailing)
            }
            if verseNumberStyle == "superscript" || verseNumberStyle == "inline" {
                if verse.wordTags.isEmpty {
                    HStack(spacing: 0) {
                        verseNumberButton
                        Text(" ")
                        verseBodyTextView
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: 0) { verseNumberButton; Text(" ") }
                    taggedVerseText.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                if verse.wordTags.isEmpty {
                    verseBodyTextView.frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    taggedVerseText.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 4).fill(backgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(
            isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
    }

    private var actionButtons: some View {
        HStack(spacing: 2) {
            if showActionButtons || isBookmarked {
                Button(action: { onToggleBookmark?() }) {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 12))
                        .foregroundColor(isBookmarked ? .accentColor : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help(isBookmarked ? L("reader.remove_bookmark") : L("reader.bookmark_verse"))
                .transition(.opacity)
            }
            if showActionButtons || highlightColor != nil || showHighlightPicker {
                Button(action: { showHighlightPicker.toggle() }) {
                    Image(systemName: highlightColor != nil ? "paintbrush.fill" : "paintbrush")
                        .font(.system(size: 12))
                        .foregroundColor(highlightColor?.displayColor ?? .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help(L("reader.highlight_verse"))
                .transition(.opacity)
                .popover(isPresented: $showHighlightPicker, arrowEdge: .trailing) {
                    HighlightColorPicker(currentColor: highlightColor, onSelect: { color in
                        onHighlightColor?(color)
                        showHighlightPicker = false
                    })
                }
            }
            if showActionButtons || hasNote {
                Button(action: { onNoteEdit?() }) {
                    Image(systemName: hasNote ? "note.text" : "note.text.badge.plus")
                        .font(.system(size: 12))
                        .foregroundColor(hasNote ? .orange : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help(hasNote ? L("reader.edit_note") : L("reader.add_note"))
                .transition(.opacity)
            }
        }
        .opacity(showActionButtons || isBookmarked || highlightColor != nil || hasNote || showHighlightPicker ? 1 : 0)
    }

    private var verseNumberButton: some View {
        Button(action: { onVerseNumberTap?() }) {
            if verseNumberStyle == "superscript" {
                Text("\(verse.number)")
                    .font(.system(size: fontSize * 0.6).monospacedDigit())
                    .foregroundColor(Color.accentColor.opacity(isSelected ? 1.0 : 0.8))
                    .baselineOffset(fontSize * 0.3)
            } else {
                Text("\(verse.number)")
                    .font(.system(size: fontSize * 0.7).monospacedDigit())
                    .foregroundColor(Color.accentColor.opacity(isSelected ? 1.0 : 0.8))
            }
        }
        .buttonStyle(.plain)
        .help(L("reader.view_cross_refs_help"))
    }

    private var verseBodyTextView: some View {
        Text(verse.text)
            .font(resolvedFont)
            .foregroundColor(customTextColor)
            .lineSpacing(fontSize * (lineSpacingMultiplier - 1.0))
            .tracking(wordSpacing)
            .textSelection(.enabled)
    }

    private var taggedVerseText: some View {
        TaggedVerseTextView(
            wordTags: verse.wordTags,
            fontSize: fontSize,
            fontFamily: fontFamily,
            lineSpacingMultiplier: lineSpacingMultiplier,
            customTextColor: customTextColor,
            onWordTap: { onWordTap?($0) }
        )
    }

    private var resolvedFont: Font {
        fontFamily == "System" ? .system(size: fontSize, design: .serif) : .custom(fontFamily, size: fontSize)
    }

    private var backgroundColor: Color {
        if let hl = highlightColor { return hl.displayColor.opacity(highlightOpacity) }
        if isSelected { return Color.accentColor.opacity(highlightOpacity) }
        if isHovered { return Color.primary.opacity(0.04) }
        return customBackgroundColor ?? Color.clear
    }
}

// MARK: - Tagged Verse Text View

struct TaggedVerseTextView: NSViewRepresentable {
    let wordTags: [WordTag]
    let fontSize: CGFloat
    let fontFamily: String
    let lineSpacingMultiplier: CGFloat
    let customTextColor: Color?
    let onWordTap: (WordTag) -> Void

    func makeNSView(context: Context) -> TaggedVerseNSTextField {
        let view = TaggedVerseNSTextField()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.isBordered = false
        view.isBezeled = false
        view.maximumNumberOfLines = 0
        view.lineBreakMode = .byWordWrapping
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.cell?.wraps = true
        view.cell?.isScrollable = false
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wordTapHandler = { [onWordTap] index in
            if index < wordTags.count { onWordTap(wordTags[index]) }
        }
        updateView(view)
        return view
    }

    func updateNSView(_ view: TaggedVerseNSTextField, context: Context) {
        view.wordTapHandler = { [onWordTap] index in
            if index < wordTags.count { onWordTap(wordTags[index]) }
        }
        updateView(view)
    }

    private func updateView(_ view: NSTextField) {
        let nsFont: NSFont = fontFamily == "System"
            ? NSFont.systemFont(ofSize: fontSize, weight: .regular)
            : (NSFont(name: fontFamily, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize))

        let baseColor: NSColor = customTextColor.map { NSColor($0) } ?? .labelColor

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = fontSize * (lineSpacingMultiplier - 1.0)

        let attributed = NSMutableAttributedString()
        for (i, tag) in wordTags.enumerated() {
            var attrs: [NSAttributedString.Key: Any] = [
                .font: nsFont, .foregroundColor: baseColor, .paragraphStyle: paragraphStyle
            ]
            if !tag.strongsNumbers.isEmpty {
                attrs[.cursor] = NSCursor.pointingHand
                attrs[.toolTip] = tag.strongsNumbers.joined(separator: ", ")
                attrs[TaggedVerseNSTextField.wordIndexKey] = i
            }
            attributed.append(NSAttributedString(string: tag.word, attributes: attrs))
            if i < wordTags.count - 1 {
                attributed.append(NSAttributedString(string: " ", attributes: [
                    .font: nsFont, .foregroundColor: baseColor, .paragraphStyle: paragraphStyle
                ]))
            }
        }
        view.attributedStringValue = attributed
    }
}

class TaggedVerseNSTextField: NSTextField {
    static let wordIndexKey = NSAttributedString.Key("wordIndex")
    var wordTapHandler: ((Int) -> Void)?
    private var hitTestStorage: NSTextStorage?
    private var hitTestLayoutManager: NSLayoutManager?
    private var hitTestContainer: NSTextContainer?

    private func ensureHitTestLayout() {
        if hitTestStorage == nil {
            let storage = NSTextStorage()
            let lm = NSLayoutManager()
            let tc = NSTextContainer(containerSize: NSSize(width: bounds.width, height: .greatestFiniteMagnitude))
            tc.lineFragmentPadding = 2.0
            storage.addLayoutManager(lm)
            lm.addTextContainer(tc)
            hitTestStorage = storage
            hitTestLayoutManager = lm
            hitTestContainer = tc
        }
        hitTestContainer?.containerSize = NSSize(width: bounds.width, height: .greatestFiniteMagnitude)
        hitTestStorage?.setAttributedString(attributedStringValue)
        hitTestLayoutManager?.ensureLayout(for: hitTestContainer!)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        ensureHitTestLayout()
        guard let storage = hitTestStorage, let lm = hitTestLayoutManager, let tc = hitTestContainer else {
            super.mouseDown(with: event)
            return
        }
        let charIndex = lm.characterIndex(for: NSPoint(x: point.x - 2.0, y: point.y), in: tc, fractionOfDistanceBetweenInsertionPoints: nil)
        if charIndex < storage.length {
            let attrs = storage.attributes(at: charIndex, effectiveRange: nil)
            if let wordIndex = attrs[TaggedVerseNSTextField.wordIndexKey] as? Int {
                wordTapHandler?(wordIndex)
                return
            }
        }
        super.mouseDown(with: event)
    }

    override var intrinsicContentSize: NSSize {
        guard let cell = self.cell else { return super.intrinsicContentSize }
        let width = superview?.bounds.width ?? bounds.width
        if width <= 0 { return super.intrinsicContentSize }
        let size = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude))
        return NSSize(width: NSView.noIntrinsicMetric, height: size.height)
    }

    override func layout() {
        super.layout()
        invalidateIntrinsicContentSize()
    }
}

// MARK: - Highlight Color Picker

struct HighlightColorPicker: View {
    let currentColor: HighlightColor?
    let onSelect: (HighlightColor?) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(HighlightColor.allCases, id: \.self) { color in
                Button(action: { onSelect(color) }) {
                    Circle().fill(color.displayColor).frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(
                            Color.primary.opacity(currentColor == color ? 0.6 : 0.2),
                            lineWidth: currentColor == color ? 2 : 0.5))
                        .scaleEffect(currentColor == color ? 1.15 : 1.0)
                }
                .buttonStyle(.plain)
                .help(color.label)
            }
            Divider().frame(height: 24)
            Button(action: { onSelect(nil) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(currentColor != nil ? .red.opacity(0.7) : .secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .help("Remove highlight")
            .disabled(currentColor == nil)
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
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Note").font(.headline)
                    Text(verseRef).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape, modifiers: []).buttonStyle(.bordered)
                Button("Save") { onSave(noteText); dismiss() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            Divider()
            TextEditor(text: $noteText).font(.body).padding(8).frame(minHeight: 150)
            if !initialText.isEmpty {
                Divider()
                HStack {
                    Spacer()
                    Button(role: .destructive) { onSave(""); dismiss() } label: {
                        Label("Delete Note", systemImage: "trash")
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 340, idealWidth: 400, maxWidth: 500, minHeight: 280)
        .onAppear { noteText = initialText }
    }
}

// MARK: - Keyboard Navigation

extension ReaderView {
    static func handleKeyNav(windowState: WindowState, store: BibleStore, event: KeyEquivalent) {
        guard let pane = windowState.panes.first else { return }
        switch event {
        case .leftArrow:
            if pane.chapter > 1 {
                windowState.navigate(paneId: pane.id, chapter: pane.chapter - 1)
                guard let updated = windowState.panes.first else { return }
                let verses = store.loadVerses(translationId: updated.translationId, book: updated.book, chapter: updated.chapter)
                windowState.setVerses(paneId: updated.id, verses: verses, versificationScheme: store.versificationScheme(for: updated.translationId))
            }
        case .rightArrow:
            if pane.chapter < pane.chapterCount {
                windowState.navigate(paneId: pane.id, chapter: pane.chapter + 1)
                guard let updated = windowState.panes.first else { return }
                let verses = store.loadVerses(translationId: updated.translationId, book: updated.book, chapter: updated.chapter)
                windowState.setVerses(paneId: updated.id, verses: verses, versificationScheme: store.versificationScheme(for: updated.translationId))
            }
        default:
            break
        }
    }
}
