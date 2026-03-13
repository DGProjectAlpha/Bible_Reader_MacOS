import SwiftUI

private struct CloseButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Close Pane")
        .scaleEffect(isHovering ? 1.2 : 1.0)
        .animation(.spring(duration: 0.2, bounce: 0.3), value: isHovering)
        .onHover { hovering in isHovering = hovering }
    }
}

struct ReaderArea: View {
    @Environment(BibleStore.self) private var bibleStore

    var body: some View {
        if bibleStore.panes.isEmpty {
            ContentUnavailableView(
                "No Module Loaded",
                systemImage: "book.closed",
                description: Text("Import a .brbmod module to get started")
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
        let isActive = bibleStore.activePaneId == pane.id

        VStack(spacing: 0) {
            // Close button bar (only when multiple panes)
            if bibleStore.panes.count > 1 {
                HStack {
                    Spacer()
                    CloseButton {
                        withAnimation(nil) {
                            bibleStore.removePane(id: pane.id)
                        }
                    }
                    .padding(.trailing, 6)
                    .padding(.top, 4)
                }
                .frame(height: 20)
            }

            ReaderView(pane: pane)
        }
        .background(isActive ? Color.accentColor.opacity(0.04) : .clear)
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(isActive ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            bibleStore.setActivePane(id: pane.id)
        }
    }
}
