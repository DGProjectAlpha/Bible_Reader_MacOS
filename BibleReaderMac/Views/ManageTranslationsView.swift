import SwiftUI

// MARK: - Translation Management Sheet

struct ManageTranslationsView: View {
    @EnvironmentObject var store: BibleStore
    @EnvironmentObject var windowState: WindowState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTranslationId: UUID?
    @State private var showDeleteConfirm = false
    @State private var pendingDeleteId: UUID?
    @State private var draggedTranslation: Translation?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(L("manage.title"))
                    .font(.title2.weight(.semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            .glassHeader()

            Divider()

            if store.loadedTranslations.isEmpty {
                emptyState
            } else {
                HSplitView {
                    translationList
                        .frame(minWidth: 220, idealWidth: 260)
                    translationDetail
                        .frame(minWidth: 280, idealWidth: 340)
                }
            }

            Divider()
            bottomBar
        }
        .frame(minWidth: 520, idealWidth: 640, minHeight: 380, idealHeight: 480)
        .glassSheet()
        .alert(L("manage.remove_confirm_title"), isPresented: $showDeleteConfirm, presenting: pendingDeleteId) { id in
            Button(L("remove"), role: .destructive) {
                store.removeTranslation(id)
                if selectedTranslationId == id {
                    selectedTranslationId = store.loadedTranslations.first?.id
                }
            }
            Button(L("cancel"), role: .cancel) {}
        } message: { id in
            if let t = store.loadedTranslations.first(where: { $0.id == id }) {
                Text("This will delete \(t.name) (\(t.abbreviation)) from disk. This cannot be undone.")
            }
        }
    }

    // MARK: - Translation List (left side)

    private var translationList: some View {
        VStack(spacing: 0) {
            // Pane assignment header
            HStack {
                Text(L("manage.installed"))
                    .font(.headline)
                Spacer()
                Text("\(store.loadedTranslations.count) " + L("manage.modules_count"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            List(selection: $selectedTranslationId) {
                ForEach(store.loadedTranslations) { translation in
                    TranslationListRow(
                        translation: translation,
                        isAssignedToPane: windowState.panes.contains(where: { $0.translationId == translation.id }),
                        paneIndex: paneIndex(for: translation.id)
                    )
                    .tag(translation.id)
                    .onDrag {
                        draggedTranslation = translation
                        return NSItemProvider(object: translation.id.uuidString as NSString)
                    }
                    .onDrop(of: [.text], delegate: TranslationDropDelegate(
                        item: translation,
                        store: store,
                        draggedItem: $draggedTranslation
                    ))
                    .contextMenu {
                        Button(L("manage.assign_new_pane")) {
                            assignToNewPane(translation)
                        }
                        .disabled(windowState.panes.count >= 4)

                        if windowState.panes.count > 0 {
                            Menu(L("manage.assign_pane")) {
                                ForEach(Array(windowState.panes.enumerated()), id: \.element.id) { idx, pane in
                                    Button("\(L("manage.pane_label")) \(idx + 1)\(paneLabel(pane))") {
                                        windowState.navigate(paneId: pane.id, translationId: translation.id)
                                    }
                                }
                            }
                        }

                        Divider()

                        Button(L("manage.remove_ellipsis"), role: .destructive) {
                            pendingDeleteId = translation.id
                            showDeleteConfirm = true
                        }
                    }
                }
                .onMove { indices, destination in
                    store.reorderTranslations(from: indices, to: destination)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .onAppear {
                if selectedTranslationId == nil {
                    selectedTranslationId = store.loadedTranslations.first?.id
                }
            }
        }
    }

    // MARK: - Detail Pane (right side)

    @ViewBuilder
    private var translationDetail: some View {
        if let id = selectedTranslationId,
           let translation = store.loadedTranslations.first(where: { $0.id == id }) {
            TranslationDetailView(translation: translation, store: store)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "book.closed")
                    .font(.system(size: 36))
                    .foregroundStyle(.quaternary)
                Text(L("manage.select_translation"))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text(L("manage.no_translations_title"))
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text(L("manage.no_translations_hint"))
                .font(.callout)
                .foregroundStyle(.tertiary)
            Button(L("manage.import_module")) {
                NotificationCenter.default.post(name: .importModule, object: nil)
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            // Import button
            Button(action: {
                NotificationCenter.default.post(name: .importModule, object: nil)
            }) {
                Label(L("manage.import_ellipsis"), systemImage: "plus")
            }

            // Pane controls
            Divider().frame(height: 20)

            Text(L("manage.panes_label") + "\(windowState.panes.count)")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button(action: {
                if let tId = store.firstTranslationId() { windowState.addPane(translationId: tId) }
            }) {
                Image(systemName: "plus.rectangle.on.rectangle")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(windowState.panes.count >= 4 || store.loadedTranslations.isEmpty)
            .help(L("manage.add_pane_help"))

            if windowState.panes.count > 1 {
                Button(action: {
                    if let last = windowState.panes.last {
                        windowState.removePane(last.id)
                    }
                }) {
                    Image(systemName: "minus.rectangle")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(L("manage.remove_pane_help"))
            }

            Spacer()

            Button(L("done")) { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassToolbar()
    }

    // MARK: - Helpers

    private func paneIndex(for translationId: UUID) -> Int? {
        guard let idx = windowState.panes.firstIndex(where: { $0.translationId == translationId }) else {
            return nil
        }
        return idx
    }

    private func paneLabel(_ pane: ReaderPane) -> String {
        if let t = store.loadedTranslations.first(where: { $0.id == pane.translationId }) {
            return " — \(t.abbreviation)"
        }
        return ""
    }

    private func assignToNewPane(_ translation: Translation) {
        guard windowState.panes.count < 4 else { return }
        windowState.addPane(translationId: translation.id)
    }
}

// MARK: - Translation List Row

struct TranslationListRow: View {
    let translation: Translation
    let isAssignedToPane: Bool
    let paneIndex: Int?

    var body: some View {
        HStack(spacing: 8) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(translation.abbreviation)
                        .font(.callout.weight(.semibold))
                    if let idx = paneIndex {
                        Text("\(L("manage.pane_label")) \(idx + 1)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor, in: Capsule())
                    }
                }
                Text(translation.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Language badge
            Text(translation.language.uppercased())
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Translation Detail View

struct TranslationDetailView: View {
    let translation: Translation
    @ObservedObject var store: BibleStore
    @EnvironmentObject var windowState: WindowState

    private var moduleInfo: CachedModuleInfo? {
        store.moduleInfo(for: translation.id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                VStack(alignment: .leading, spacing: 4) {
                    Text(translation.name)
                        .font(.title3.weight(.semibold))
                    Text(translation.abbreviation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Metadata grid
                LazyVGrid(columns: [
                    GridItem(.fixed(120), alignment: .topTrailing),
                    GridItem(.flexible(), alignment: .topLeading)
                ], alignment: .leading, spacing: 8) {
                    metadataRow(L("manage.language"), translation.language)
                    metadataRow(L("manage.versification"), translation.versificationScheme)
                    metadataRow(L("manage.format"), translation.metadata.format == .tagged ? L("manage.tagged") : L("manage.plain_text"))

                    if let info = moduleInfo {
                        metadataRow(L("manage.books"), "\(info.bookCount)")
                        metadataRow(L("manage.verses"), "\(info.totalVerses)")
                        metadataRow(L("manage.file_size"), ByteCountFormatter.string(fromByteCount: Int64(info.fileSize), countStyle: .file))
                        if info.hasWordTags {
                            metadataRow(L("manage.strongs"), L("yes"))
                        }
                        if info.hasCrossRefs {
                            metadataRow(L("manage.crossrefs"), L("yes"))
                        }
                    }

                    if let copyright = translation.metadata.copyright, !copyright.isEmpty {
                        metadataRow(L("manage.copyright"), copyright)
                    }

                    if let notes = translation.metadata.notes, !notes.isEmpty {
                        metadataRow(L("manage.notes_field"), notes)
                    }
                }

                Divider()

                // Pane assignment
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("manage.pane_assignment"))
                        .font(.callout.weight(.medium))

                    ForEach(Array(windowState.panes.enumerated()), id: \.element.id) { idx, pane in
                        HStack {
                            Text("\(L("manage.pane_label")) \(idx + 1)")
                                .font(.callout)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { pane.translationId },
                                set: { windowState.navigate(paneId: pane.id, translationId: $0) }
                            )) {
                                ForEach(store.loadedTranslations) { t in
                                    Text(t.abbreviation).tag(t.id)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 120)
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
    }

    @ViewBuilder
    private func metadataRow(_ label: String, _ value: String) -> some View {
        Text(label)
            .font(.callout)
            .foregroundStyle(.secondary)
        Text(value)
            .font(.callout)
            .textSelection(.enabled)
    }
}

// MARK: - Drag & Drop Reordering

struct TranslationDropDelegate: DropDelegate {
    let item: Translation
    @ObservedObject var store: BibleStore
    @Binding var draggedItem: Translation?

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedItem, dragged.id != item.id else { return }
        guard let fromIndex = store.loadedTranslations.firstIndex(where: { $0.id == dragged.id }),
              let toIndex = store.loadedTranslations.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            store.loadedTranslations.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
