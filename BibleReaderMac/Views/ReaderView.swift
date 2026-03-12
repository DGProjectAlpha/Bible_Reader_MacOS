import SwiftUI
import Combine

// MARK: - Reader View (top-level container)

struct ReaderView: View {
    @EnvironmentObject var store: BibleStore
    @EnvironmentObject var windowState: WindowState
    @StateObject private var syncCoordinator = ScrollSyncCoordinator()

    var body: some View {
        Group {
            if store.loadedTranslations.isEmpty {
                emptyState
            } else if windowState.panes.isEmpty {
                // Panes not yet created (handleOnAppear hasn't fired)
                Color.clear
            } else if windowState.panes.count == 1 {
                ReaderPaneView(paneId: windowState.panes[0].id,
                               coordinator: syncCoordinator)
            } else {
                splitPaneGrid()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Cross-ref / search navigation: jump reader to a specific verse
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

            // Navigate the target pane
            navigateTo(paneId: targetId, book: book, chapter: chapter)

            // If the target pane has sync enabled, propagate to all other synced panes
            if let targetPane = windowState.panes.first(where: { $0.id == targetId }),
               targetPane.isSyncEnabled {
                for otherPane in windowState.panes where otherPane.id != targetId && otherPane.isSyncEnabled {
                    navigateTo(paneId: otherPane.id, book: book, chapter: chapter)
                }
            }

            // Scroll all relevant panes to the target verse after chapter loads
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let panesToScroll: [UUID]
                if let targetPane = windowState.panes.first(where: { $0.id == targetId }),
                   targetPane.isSyncEnabled {
                    panesToScroll = windowState.panes.filter { $0.isSyncEnabled }.map { $0.id }
                } else {
                    panesToScroll = [targetId]
                }
                for paneId in panesToScroll {
                    syncCoordinator.scrollProxies[paneId]?.scrollTo(
                        "verse-\(paneId)-\(verse)", anchor: .top
                    )
                }
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

    private func columnContent(_ col: PaneColumn) -> AnyView {
        if let bottomId = col.bottom {
            // Vertical split — stacked panes inside a column
            return AnyView(
                EqualSplitView(
                    isVertical: false,
                    panes: [
                        AnyView(ReaderPaneView(paneId: col.top, coordinator: syncCoordinator)
                            .frame(minHeight: 100, maxHeight: .infinity)),
                        AnyView(ReaderPaneView(paneId: bottomId, coordinator: syncCoordinator)
                            .frame(minHeight: 100, maxHeight: .infinity))
                    ]
                )
            )
        } else {
            return AnyView(ReaderPaneView(paneId: col.top, coordinator: syncCoordinator))
        }
    }

    @ViewBuilder
    private func splitPaneGrid() -> some View {
        let cols = buildColumns()
        if cols.isEmpty {
            Color.clear
        } else if cols.count == 1 {
            columnContent(cols[0])
        } else {
            // Horizontal split — side-by-side columns, each equal width
            EqualSplitView(
                isVertical: true,
                panes: cols.map { col in
                    AnyView(columnContent(col).frame(minWidth: 200, maxWidth: .infinity))
                }
            )
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

// MARK: - Equal Split View
//
// Wraps NSSplitView to equalise divider positions whenever the pane count changes.
// Accepts views as [AnyView] so the coordinator can manage individual subviews.
// The user can still drag dividers freely after the initial equalisation.

struct EqualSplitView: NSViewRepresentable {
    /// true  → vertical dividers, side-by-side (like HSplitView)
    /// false → horizontal dividers, stacked (like VSplitView)
    let isVertical: Bool
    /// The individual pane views.
    let panes: [AnyView]

    // MARK: Coordinator

    @MainActor
    class Coordinator: NSObject, NSSplitViewDelegate {
        var hostingViews: [NSHostingView<AnyView>] = []
        var lastEqualizedCount: Int = 0

        /// Set all dividers to equal positions.
        func equalizeNow(_ splitView: NSSplitView) {
            let count = splitView.arrangedSubviews.count
            guard count > 1 else { return }
            let thickness = splitView.dividerThickness
            let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
            guard total > 0 else { return }
            let paneSize = (total - CGFloat(count - 1) * thickness) / CGFloat(count)
            var pos: CGFloat = 0
            for i in 0..<(count - 1) {
                pos += paneSize
                splitView.setPosition(pos, ofDividerAt: i)
                pos += thickness
            }
            lastEqualizedCount = count
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: NSViewRepresentable

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = isVertical
        splitView.dividerStyle = .thin
        splitView.delegate = context.coordinator

        for view in panes {
            let hosting = NSHostingView(rootView: view)
            hosting.translatesAutoresizingMaskIntoConstraints = false
            splitView.addArrangedSubview(hosting)
            context.coordinator.hostingViews.append(hosting)
        }

        // Equalize after the view has been laid out
        DispatchQueue.main.async {
            context.coordinator.equalizeNow(splitView)
        }
        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        let coordinator = context.coordinator

        // Sync hosting views with current panes array
        let existingCount = coordinator.hostingViews.count
        let newCount = panes.count

        if newCount > existingCount {
            // Add new panes
            for i in existingCount..<newCount {
                let hosting = NSHostingView(rootView: panes[i])
                hosting.translatesAutoresizingMaskIntoConstraints = false
                splitView.addArrangedSubview(hosting)
                coordinator.hostingViews.append(hosting)
            }
            DispatchQueue.main.async {
                coordinator.equalizeNow(splitView)
            }
        } else if newCount < existingCount {
            // Remove extra panes (from the end)
            for i in (newCount..<existingCount).reversed() {
                let hosting = coordinator.hostingViews[i]
                splitView.removeArrangedSubview(hosting)
                hosting.removeFromSuperview()
                coordinator.hostingViews.remove(at: i)
            }
            DispatchQueue.main.async {
                coordinator.equalizeNow(splitView)
            }
        } else {
            // Same count — update root views in place
            for (i, view) in panes.enumerated() {
                coordinator.hostingViews[i].rootView = view
            }
        }
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

    func reportVisibleVerse(_ verse: Int, from paneId: UUID, syncedPaneIds: Set<UUID>) {
        guard syncedPaneIds.contains(paneId) else { return }
        guard !suppressedPanes.contains(paneId) else { return }
        guard verse != lastSyncedVerse || lastSourcePane != paneId else { return }
        lastSourcePane = paneId
        lastSyncedVerse = verse
        for (otherId, proxy) in scrollProxies where otherId != paneId && syncedPaneIds.contains(otherId) {
            suppressPane(otherId, for: 0.4)
            withAnimation(.easeInOut(duration: 0.25)) {
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

    /// Cached metadata — rebuilt only when verse set or user-data changes, not every render.
    @State private var cachedMetadata: [String: (Bool, HighlightColor?, Bool)] = [:]
    @State private var metadataCacheKey: String = ""

    // Computed from windowState — never stored locally
    private var pane: ReaderPane? {
        windowState.panes.first { $0.id == paneId }
    }
    private var isSolo: Bool { windowState.panes.count == 1 }

    /// A string that changes whenever the verse set, bookmarks, highlights, or notes change.
    private func metadataKey(for pane: ReaderPane) -> String {
        let verseIds = pane.verses.map(\.id).joined(separator: ",")
        let bmKey = store.bookmarks.map { "\($0.verseId)|\($0.translationId)" }.joined()
        let hlKey = store.highlights.map { "\($0.verseId)|\($0.translationId)" }.joined()
        let ntKey = store.notes.map { "\($0.verseId)|\($0.translationId)" }.joined()
        return "\(verseIds)|\(bmKey)|\(hlKey)|\(ntKey)"
    }

    var body: some View {
        if let pane {
            VStack(spacing: 0) {
                paneHeader(pane)
                Divider()
                verseContent(pane)
            }
            .background {
                VisualEffectBackground(
                    material: .contentBackground,
                    blendingMode: .behindWindow,
                    isEmphasized: false
                )
            }
            .onAppear {
                loadChapter(pane: pane)
                refreshMetadataIfNeeded(pane: pane)
            }
            .onChange(of: metadataKey(for: pane)) {
                cachedMetadata = buildMetadata(pane)
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
        }
    }

    // MARK: - Load chapter (the ONE place verses get loaded)

    private func loadChapter(pane: ReaderPane) {
        let verses = store.loadVerses(translationId: pane.translationId, book: pane.book, chapter: pane.chapter)
        let scheme = store.versificationScheme(for: pane.translationId)
        windowState.setVerses(paneId: paneId, verses: verses, versificationScheme: scheme)
        visibleVerseTracker.clear()
    }

    private func refreshMetadataIfNeeded(pane: ReaderPane) {
        let key = metadataKey(for: pane)
        guard key != metadataCacheKey else { return }
        metadataCacheKey = key
        cachedMetadata = buildMetadata(pane)
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
        // Only sync if this pane has sync enabled
        guard p.isSyncEnabled else { return }
        // Sync other panes that also have sync enabled
        for otherPane in windowState.panes where otherPane.id != paneId && otherPane.isSyncEnabled {
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

                // Chapter nav — prev/next flat buttons, chapter picker inline
                HStack(spacing: 2) {
                    Button(action: prevChapter) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.flatToolbar)
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
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.flatToolbar)
                    .disabled(pane.chapter >= pane.chapterCount && BibleBooks.all.firstIndex(of: pane.book) == BibleBooks.all.count - 1)
                    .help(L("reader.next_chapter"))
                }

                // Font size group: [A-  15  A+]
                HStack(spacing: 0) {
                    Button(action: { fontSize = max(10, fontSize - 1) }) {
                        Image(systemName: "textformat.size.smaller")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 8).padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary.opacity(0.7))
                    .help(L("reader.decrease_font"))

                    Divider().frame(height: 14)

                    Text("\(Int(fontSize))")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.primary.opacity(0.75))
                        .frame(width: 24)

                    Divider().frame(height: 14)

                    Button(action: { fontSize = min(36, fontSize + 1) }) {
                        Image(systemName: "textformat.size.larger")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 8).padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary.opacity(0.7))
                    .help(L("reader.increase_font"))
                }
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75)
                }

                // Split buttons
                if windowState.panes.count < 8 {
                    Divider().frame(height: 20)
                    Button(action: {
                        windowState.splitPane(paneId, direction: .horizontal)
                        if let newPane = windowState.panes.last {
                            let verses = store.loadVerses(translationId: newPane.translationId, book: newPane.book, chapter: newPane.chapter)
                            let scheme = store.versificationScheme(for: newPane.translationId)
                            windowState.setVerses(paneId: newPane.id, verses: verses, versificationScheme: scheme)
                        }
                    }) {
                        Image(systemName: "rectangle.split.2x1")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.flatToolbar)
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
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.flatToolbar)
                    .help(L("reader.split_down"))
                }

                // Per-pane sync button
                if !isSolo {
                    Divider().frame(height: 20)
                    Button(action: { windowState.togglePaneSync(paneId) }) {
                        Image(systemName: pane.isSyncEnabled ? "link" : "link.badge.plus")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.flatToolbar(isActive: pane.isSyncEnabled))
                    .help(pane.isSyncEnabled ? L("reader.sync_enabled") : L("reader.sync_disabled"))
                }

                // Close pane button
                if !isSolo {
                    Divider().frame(height: 20)
                    Button(action: { windowState.removePane(paneId) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.flatToolbar)
                    .help(L("reader.close_pane"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            if showChapterTitles {
                HStack {
                    Text(displayBookName(pane) + " \(pane.chapter)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    if let t = store.translation(for: pane.translationId) {
                        Text(t.name).font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 5)
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
        let metadata = cachedMetadata
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
                                if pane.isSyncEnabled {
                                    visibleVerseTracker.reportDebounced { [weak coordinator] top in
                                        let syncedIds = Set(windowState.panes.filter { $0.isSyncEnabled }.map { $0.id })
                                        coordinator?.reportVisibleVerse(top, from: paneId, syncedPaneIds: syncedIds)
                                    }
                                }
                            }
                            .onDisappear { visibleVerseTracker.remove(verse.number) }
                        }
                        chapterNavFooter(pane)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .background(sepiaBackground)
            .onAppear {
                scrollProxy = proxy
                coordinator.registerScrollProxy(proxy, for: paneId)
            }
        }
        // Force the ScrollView + LazyVStack to fully recreate when the loaded verse set changes.
        // Without this, LazyVStack caches previously-rendered verse rows and shows stale content.
        // Includes translationId so switching translations also forces a full refresh.
        .id("\(pane.verses.first?.id ?? "\(pane.book):\(pane.chapter)")|\(pane.translationId)")
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
