import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: BibleStore
    @EnvironmentObject var windowState: WindowState
    @State private var showHistory = false

    var body: some View {
        VStack(spacing: 0) {
            // Tab selector at top
            sidebarTabPicker
            Divider()

            // Tab content
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Footer buttons
            sidebarFooter
        }
        .navigationTitle("BibleReader")
        .sheet(isPresented: $showHistory) {
            HistoryView()
                .environmentObject(store)
                .environmentObject(windowState)
                .frame(minWidth: 400, minHeight: 500)
        }
    }

    // MARK: - Tab Picker

    private var sidebarTabPicker: some View {
        Picker("", selection: $windowState.selectedSidebarTab) {
            ForEach(SidebarTab.allCases, id: \.self) { tab in
                Label(tab.label, systemImage: tab.icon)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch windowState.selectedSidebarTab {
        case .bookmarks:
            bookmarksTabContent
        case .notes:
            notesTabContent
        case .modules:
            modulesTabContent
        }
    }

    // MARK: - Bookmarks Tab

    private var bookmarksTabContent: some View {
        BookmarksView()
    }

    // MARK: - Notes Tab

    private var notesTabContent: some View {
        NotesView()
    }

    // MARK: - Modules Tab

    private var modulesTabContent: some View {
        List {
            ForEach(store.loadedTranslations) { translation in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(translation.abbreviation)
                            .font(.callout.weight(.medium))
                        Text(translation.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(translation.language.uppercased())
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(.secondary.opacity(0.12))
                        )
                }
                .contextMenu {
                    if let pane = windowState.panes.first {
                        Button("Open in Current Pane") {
                            pane.selectedTranslationId = translation.id
                        }
                    }
                    Button("Open in New Pane") {
                        windowState.addPane(translationId: translation.id)
                    }
                    Divider()
                    Button("Remove Translation", role: .destructive) {
                        store.removeTranslation(translation.id)
                    }
                }
            }
            .onMove { source, destination in
                store.reorderTranslations(from: source, to: destination)
            }

            if store.loadedTranslations.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 32))
                        .foregroundStyle(.quaternary)
                    Text("No Translations")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }

            Button(action: {
                NotificationCenter.default.post(name: .importModule, object: nil)
            }) {
                Label("Import Module...", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)

            Button(action: {
                NotificationCenter.default.post(name: .manageTranslations, object: nil)
            }) {
                Label("Manage...", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)
        }
        .listStyle(.sidebar)
    }

    // MARK: - Footer

    private var sidebarFooter: some View {
        HStack(spacing: 16) {
            Button(action: {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }) {
                Image(systemName: "gearshape")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
            .help("Settings")

            Button(action: { showHistory = true }) {
                Image(systemName: "clock")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
            .help("Reading History")

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

}
