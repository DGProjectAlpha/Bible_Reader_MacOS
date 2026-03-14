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
    let pane: ReadingPane

    var body: some View {
        VStack(spacing: 0) {
            ReaderView(pane: pane)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            bibleStore.setActivePane(id: pane.id)
        }
    }
}
