import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: BibleStore
    @StateObject private var windowState = WindowState()
    @StateObject private var importHandler = FileImportHandler()
    @State private var showImportSheet = false
    @State private var showManageTranslations = false
    @State private var isDragTargeted = false
    @AppStorage("readerTheme") private var readerTheme: String = "auto"

    private var resolvedColorScheme: ColorScheme? {
        switch readerTheme {
        case "light", "sepia": return .light
        case "dark": return .dark
        default: return nil // system
        }
    }

    var body: some View {
        mainLayout
            .toolbar { toolbarContent }
            .sheet(isPresented: $showImportSheet) { ImportModuleView() }
            .sheet(isPresented: $showManageTranslations) { ManageTranslationsView() }
            .navigationTitle(windowState.windowTitle)
            .environmentObject(windowState)
            .onAppear(perform: handleOnAppear)
            .modifier(NotificationHandlers(store: store, windowState: windowState,
                                           showImportSheet: $showImportSheet,
                                           showManageTranslations: $showManageTranslations,
                                           importHandler: importHandler,
                                           navigateChapter: navigateChapter,
                                           navigateBook: navigateBook))
            .modifier(DragDropModifier(isDragTargeted: $isDragTargeted,
                                       importHandler: importHandler,
                                       store: store,
                                       dropOverlay: dropOverlay))
            .modifier(ImportToastModifier(importHandler: importHandler))
            .preferredColorScheme(resolvedColorScheme)
    }

    // MARK: - Extracted Sub-Views

    private var mainLayout: some View {
        ZStack(alignment: .leading) {
            // Main content fills the entire width
            Group {
                if windowState.showSearchPanel {
                    VSplitView {
                        SearchView()
                            .frame(minHeight: 200, idealHeight: 350)
                        ReaderView()
                            .vibrancyBackground(material: .contentBackground, blendingMode: .behindWindow)
                            .frame(minHeight: 200)
                    }
                } else {
                    ReaderView()
                        .vibrancyBackground(material: .contentBackground, blendingMode: .behindWindow)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: windowState.showSearchPanel)

            // Dim overlay when sidebar is open
            if windowState.showSidebar {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .onTapGesture {
                        windowState.toggleSidebar()
                    }
                    .transition(.opacity)
            }

            // Overlay sidebar
            if windowState.showSidebar {
                SidebarView()
                    .frame(width: 280, maxHeight: .infinity)
                    .vibrancyBackground(material: .sidebar)
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 2, y: 0)
                    .transition(.move(edge: .leading))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: windowState.showSidebar)
        .inspector(isPresented: $windowState.showInspector) {
            InspectorPanelView()
                .inspectorColumnWidth(min: 300, ideal: 320, max: 450)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: { windowState.toggleSidebar() }) {
                Label("Sidebar", systemImage: "sidebar.leading")
            }
            .help("Toggle Sidebar (⌘⇧S)")
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: { showImportSheet = true }) {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .help("Import .brbmod module")
            .keyboardShortcut("i", modifiers: [.command])

            Divider()

            Button(action: { windowState.toggleInspector(tab: .strongs) }) {
                Label("Strong's", systemImage: "textformat.abc")
            }
            .help("Toggle Strong's Concordance")

            Button(action: { windowState.toggleInspector(tab: .crossRefs) }) {
                Label("Cross-Refs", systemImage: "link")
            }
            .help("Toggle Cross-References")

            Button(action: { windowState.toggleSearchPanel() }) {
                Label("Search", systemImage: "magnifyingglass")
            }
            .help("Search (⌘F)")
        }
    }

    private func handleOnAppear() {
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

}

// MARK: - Notification Handlers Modifier

private struct NotificationHandlers: ViewModifier {
    @ObservedObject var store: BibleStore
    @ObservedObject var windowState: WindowState
    @Binding var showImportSheet: Bool
    @Binding var showManageTranslations: Bool
    var importHandler: FileImportHandler
    var navigateChapter: (Int) -> Void
    var navigateBook: (Int) -> Void

    func body(content: Content) -> some View {
        content
            .modifier(SheetNotifications(showImportSheet: $showImportSheet,
                                         showManageTranslations: $showManageTranslations,
                                         store: store, windowState: windowState))
            .modifier(NavigationNotifications(windowState: windowState,
                                              navigateChapter: navigateChapter,
                                              navigateBook: navigateBook))
            .modifier(InspectorNotifications(windowState: windowState, store: store))
            .modifier(MiscNotifications(importHandler: importHandler, store: store))
    }
}

// MARK: - Sheet Notifications
private struct SheetNotifications: ViewModifier {
    @Binding var showImportSheet: Bool
    @Binding var showManageTranslations: Bool
    @ObservedObject var store: BibleStore
    @ObservedObject var windowState: WindowState

    func body(content: Content) -> some View {
        content
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
    }
}

// MARK: - Navigation Notifications
private struct NavigationNotifications: ViewModifier {
    @ObservedObject var windowState: WindowState
    var navigateChapter: (Int) -> Void
    var navigateBook: (Int) -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .navigatePreviousChapter)) { _ in
                navigateChapter(-1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateNextChapter)) { _ in
                navigateChapter(1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigatePreviousBook)) { _ in
                navigateBook(-1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateNextBook)) { _ in
                navigateBook(1)
            }
    }
}

// MARK: - Inspector Notifications
private struct InspectorNotifications: ViewModifier {
    @ObservedObject var windowState: WindowState
    @ObservedObject var store: BibleStore

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .translationRemoved)) { notification in
                guard let removedId = notification.userInfo?["translationId"] as? UUID else { return }
                for pane in windowState.panes where pane.selectedTranslationId == removedId {
                    pane.selectedTranslationId = store.loadedTranslations.first?.id ?? UUID()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showCrossReferences)) { notification in
                if let verseId = notification.userInfo?["verseId"] as? String {
                    windowState.showCrossRefsInspector(verseId: verseId)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .globalSearch)) { _ in
                windowState.toggleSearchPanel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchSidebarTab)) { notification in
                if let tab = notification.userInfo?["tab"] as? SidebarTab {
                    windowState.selectedSidebarTab = tab
                    if !windowState.showSidebar {
                        windowState.toggleSidebar()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleStrongsInspector)) { _ in
                windowState.toggleInspector(tab: .strongs)
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleCrossRefsInspector)) { _ in
                windowState.toggleInspector(tab: .crossRefs)
            }
    }
}

// MARK: - Misc Notifications
private struct MiscNotifications: ViewModifier {
    var importHandler: FileImportHandler
    @ObservedObject var store: BibleStore

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .navigateToReader)) { _ in }
.onReceive(NotificationCenter.default.publisher(for: .importModuleFile)) { notification in
                if let url = notification.object as? URL {
                    Task {
                        _ = await importHandler.importFile(at: url, into: store)
                    }
                }
            }
    }
}

// MARK: - Drag-Drop Modifier

private struct DragDropModifier<Overlay: View>: ViewModifier {
    @Binding var isDragTargeted: Bool
    var importHandler: FileImportHandler
    var store: BibleStore
    var dropOverlay: Overlay

    func body(content: Content) -> some View {
        content
            .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
                importHandler.handleDrop(providers: providers, store: store)
            }
            .overlay {
                if isDragTargeted {
                    dropOverlay
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isDragTargeted)
    }
}

// MARK: - Import Toast Modifier

private struct ImportToastModifier: ViewModifier {
    @ObservedObject var importHandler: FileImportHandler

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if importHandler.showResult, let result = importHandler.lastResult {
                    importToast(result)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                withAnimation(.spring(duration: 0.3)) { importHandler.showResult = false }
                            }
                        }
                }
            }
            .animation(.spring(duration: 0.3), value: importHandler.showResult)
    }

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

// MARK: - Inspector Panel View

struct InspectorPanelView: View {
    @EnvironmentObject var store: BibleStore
    @EnvironmentObject var windowState: WindowState

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("", selection: $windowState.inspectorTab) {
                ForEach(InspectorTab.allCases, id: \.self) { tab in
                    Label(tab.label, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 8)
            .padding(.vertical, 8)

            Divider()

            // Tab content
            inspectorContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.15), value: windowState.inspectorTab)
        }
    }

    @ViewBuilder
    private var inspectorContent: some View {
        switch windowState.inspectorTab {
        case .strongs:
            if let verseId = windowState.inspectorStrongsVerseId,
               let filePath = windowState.inspectorStrongsFilePath {
                StrongsSidebarView(
                    verseRef: windowState.inspectorStrongsDisplayRef ?? verseId,
                    verseId: verseId,
                    translationFilePath: filePath,
                    isVisible: $windowState.showInspector
                )
            } else {
                inspectorPlaceholder(
                    icon: "textformat.abc",
                    title: "Strong's Concordance",
                    message: "Tap a verse to see Strong's numbers"
                )
            }

        case .crossRefs:
            if let verseId = windowState.inspectorCrossRefVerseId {
                CrossReferenceView(initialVerseId: verseId)
            } else {
                inspectorPlaceholder(
                    icon: "link",
                    title: "Cross-References",
                    message: "Right-click a verse and select Cross-References"
                )
            }

        }
    }

    private func inspectorPlaceholder(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
