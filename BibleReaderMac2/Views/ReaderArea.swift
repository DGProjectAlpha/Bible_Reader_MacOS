import SwiftUI

struct ReaderArea: View {
    @Environment(BibleStore.self) private var bibleStore

    var body: some View {
        if bibleStore.panes.isEmpty {
            ContentUnavailableView(
                String(localized: "reader.noModuleLoaded"),
                systemImage: "book.closed",
                description: Text("reader.importModuleHint")
            )
        } else {
            HSplitView {
                let columns = groupPanesIntoColumns()
                ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                    if column.count == 1 {
                        paneView(for: column[0])
                            .frame(minWidth: 250, idealWidth: 400)
                    } else {
                        VSplitView {
                            ForEach(column) { pane in
                                paneView(for: pane)
                                    .frame(minHeight: 150, idealHeight: 300)
                            }
                        }
                        .frame(minWidth: 250, idealWidth: 400)
                    }
                }
            }
        }
    }

    /// Groups panes into columns for layout.
    /// Horizontal panes start a new column; vertical panes stack below the previous column.
    private func groupPanesIntoColumns() -> [[ReadingPane]] {
        var columns: [[ReadingPane]] = []
        for pane in bibleStore.panes {
            if pane.splitDirection == .vertical, !columns.isEmpty {
                columns[columns.count - 1].append(pane)
            } else {
                columns.append([pane])
            }
        }
        return columns
    }

    @ViewBuilder
    private func paneView(for pane: ReadingPane) -> some View {
        PaneContainer(pane: pane)
    }
}

private struct PaneContainer: View {
    @Environment(BibleStore.self) private var bibleStore
    @Environment(UIStateStore.self) private var uiState
    let pane: ReadingPane

    private var isDetached: Bool {
        uiState.detachedPaneIds.contains(pane.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            if isDetached {
                DetachedPanePlaceholder(pane: pane)
            } else {
                ReaderView(pane: pane)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            bibleStore.setActivePane(id: pane.id)
        }
    }
}

private struct DetachedPanePlaceholder: View {
    @Environment(UIStateStore.self) private var uiState
    @Environment(BibleStore.self) private var bibleStore
    let pane: ReadingPane

    private var currentModule: Module? {
        bibleStore.modules.first(where: { $0.id == pane.location.moduleId })
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("This pane is in a separate window.")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("\(currentModule?.abbreviation ?? pane.location.moduleId) — \(pane.location.book) \(pane.location.chapter)")
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            Button {
                uiState.detachedPaneIds.remove(pane.id)
            } label: {
                Label("Dock", systemImage: "rectangle.inset.filled.and.cursorarrow")
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}
