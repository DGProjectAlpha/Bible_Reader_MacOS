import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: BibleStore
    @StateObject private var windowState = WindowState()
    @StateObject private var importHandler = FileImportHandler()
    @State private var showImportSheet = false
    @State private var showManageTranslations = false
    @State private var isDragTargeted = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $windowState.selectedSidebarItem)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
                .vibrancyBackground(material: .sidebar)
        } detail: {
            detailView
                .vibrancyBackground(material: .contentBackground, blendingMode: .behindWindow)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { showImportSheet = true }) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Import .brbmod module")
                .keyboardShortcut("i", modifiers: [.command])
            }
        }
        .sheet(isPresented: $showImportSheet) {
            ImportModuleView()
        }
        .sheet(isPresented: $showManageTranslations) {
            ManageTranslationsView()
        }
        .navigationTitle(windowState.windowTitle)
        .environmentObject(windowState)
        .onAppear {
            // Restore last reading position for the first pane of this window
            if let pane = windowState.panes.first {
                store.restoreLastPosition(into: pane)
                if let firstTranslation = store.loadedTranslations.first,
                   pane.selectedTranslationId == ReaderPane().selectedTranslationId {
                    pane.selectedTranslationId = firstTranslation.id
                }
                store.loadVerses(for: pane)
            }
            windowState.updateTitle()
        }
        // MARK: - Notification Handlers
        .onReceive(NotificationCenter.default.publisher(for: .importModule)) { _ in
            showImportSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .manageTranslations)) { _ in
            showManageTranslations = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .addTranslationPane)) { _ in
            let tId = store.loadedTranslations.first?.id
            windowState.addPane(translationId: tId)
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookmarkCurrentVerse)) { _ in
            guard let pane = windowState.panes.first else { return }
            let verseId = "\(pane.selectedBook):\(pane.selectedChapter):1"
            if let translation = store.loadedTranslations.first(where: { $0.id == pane.selectedTranslationId }) {
                store.addBookmark(verseId: verseId, translationId: translation.id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigatePreviousChapter)) { _ in
            navigateChapter(delta: -1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateNextChapter)) { _ in
            navigateChapter(delta: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigatePreviousBook)) { _ in
            navigateBook(delta: -1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateNextBook)) { _ in
            navigateBook(delta: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .translationRemoved)) { notification in
            guard let removedId = notification.userInfo?["translationId"] as? UUID else { return }
            for pane in windowState.panes where pane.selectedTranslationId == removedId {
                pane.selectedTranslationId = store.loadedTranslations.first?.id ?? UUID()
            }
        }
        // App-wide drag-and-drop for .brbmod files
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            importHandler.handleDrop(providers: providers, store: store)
        }
        .overlay {
            if isDragTargeted {
                dropOverlay
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isDragTargeted)
        // Import status toast
        .overlay(alignment: .bottom) {
            if importHandler.showResult, let result = importHandler.lastResult {
                importToast(result)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation { importHandler.showResult = false }
                        }
                    }
            }
        }
        .animation(.spring(duration: 0.3), value: importHandler.showResult)
        .onReceive(NotificationCenter.default.publisher(for: .importModuleFile)) { notification in
            if let url = notification.object as? URL {
                Task {
                    _ = await importHandler.importFile(at: url, into: store)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToReader)) { _ in
            windowState.selectedSidebarItem = .reader
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCrossReferences)) { notification in
            windowState.selectedSidebarItem = .crossRefs
            // Forward the verse ID to CrossReferenceView via a second notification
            if let verseId = notification.userInfo?["verseId"] as? String {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NotificationCenter.default.post(
                        name: .crossRefLookup,
                        object: nil,
                        userInfo: ["verseId": verseId]
                    )
                }
            }
        }
    }

    // MARK: - Detail Router

    @ViewBuilder
    private var detailView: some View {
        switch windowState.selectedSidebarItem {
        case .reader, .none:
            ReaderView()
        case .search:
            SearchView()
        case .strongs:
            StrongsLookupView()
        case .bookmarks:
            BookmarksView()
        case .history:
            HistoryView()
        case .notes:
            PlaceholderView(title: "Notes", icon: "note.text")
        case .crossRefs:
            CrossReferenceView()
        }
    }

    // MARK: - Navigation Helpers

    private func navigateChapter(delta: Int) {
        guard let pane = windowState.panes.first else { return }
        let newChapter = pane.selectedChapter + delta
        if newChapter >= 1 && newChapter <= pane.chapterCount {
            pane.selectedChapter = newChapter
            store.loadVerses(for: pane)
        }
    }

    private func navigateBook(delta: Int) {
        guard let pane = windowState.panes.first else { return }
        guard let idx = BibleBooks.all.firstIndex(of: pane.selectedBook) else { return }
        let newIdx = idx + delta
        guard newIdx >= 0 && newIdx < BibleBooks.all.count else { return }
        pane.selectedBook = BibleBooks.all[newIdx]
        pane.selectedChapter = 1
        store.loadVerses(for: pane)
    }

    // MARK: - Drop Overlay

    private var dropOverlay: some View {
        ZStack {
            Color.black.opacity(0.15)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white)
                Text("Drop to Import Module")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(40)
            .glassPanel(cornerRadius: 20, material: .fullScreenUI)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    // MARK: - Toast

    private func importToast(_ status: ModuleImportStatus) -> some View {
        HStack(spacing: 8) {
            Image(systemName: FileImportHandler.statusIsError(status) ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(FileImportHandler.statusIsError(status) ? .red : .green)
            Text(FileImportHandler.statusMessage(status))
                .font(.callout)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassPanel(cornerRadius: 10, material: .popover)
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .padding(.bottom, 20)
    }
}

// MARK: - Placeholder Views (for future steps)

struct PlaceholderView: View {
    let title: String
    let icon: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text(title)
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("Coming soon")
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
        .environmentObject(BibleStore())
}
