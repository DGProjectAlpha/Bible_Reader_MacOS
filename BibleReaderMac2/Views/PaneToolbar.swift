import SwiftUI

struct PaneToolbar: View {
    @Environment(BibleStore.self) private var bibleStore
    @Environment(UIStateStore.self) private var uiState

    @Environment(\.openWindow) private var openWindow

    let pane: ReadingPane
    var isDetached: Bool = false
    var verseCount: Int = 0
    var onScrollToVerse: ((Int) -> Void)? = nil

    private var currentModule: Module? {
        bibleStore.modules.first(where: { $0.id == pane.location.moduleId })
    }

    private var currentBook: Book? {
        currentModule?.books.first(where: { $0.id == pane.location.book })
    }

    var body: some View {
        HStack(spacing: 8) {
            modulePicker
            bookPicker
            chapterPicker
            versePicker

            previousChapterButton
            nextChapterButton

            Spacer()

            popOutButton
            if !isDetached {
                splitHorizontalButton
                splitVerticalButton
            }
            if !isDetached && bibleStore.panes.count > 1 {
                closePaneButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 10)
        )
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }

    // MARK: - Module Picker

    private var modulePicker: some View {
        Menu {
            ForEach(bibleStore.modules) { module in
                Button(module.name) {
                    Task {
                        let loc = BibleLocation(
                            moduleId: module.id,
                            book: pane.location.book,
                            chapter: pane.location.chapter
                        )
                        await bibleStore.navigate(paneId: pane.id, to: loc)
                    }
                }
            }
        } label: {
            Text(currentModule?.abbreviation ?? "—")
                .font(.callout)
                .fontWeight(.medium)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Book Picker

    private var bookPicker: some View {
        Menu {
            let books = currentModule?.books ?? []
            let otBooks = books.filter { $0.testament == .old }
            let ntBooks = books.filter { $0.testament == .new }

            Section(String(localized: "pane.oldTestament")) {
                ForEach(otBooks) { book in
                    Button(book.name) {
                        Task {
                            let loc = BibleLocation(
                                moduleId: pane.location.moduleId,
                                book: book.id,
                                chapter: 1
                            )
                            await bibleStore.navigate(paneId: pane.id, to: loc)
                        }
                    }
                }
            }
            Section(String(localized: "pane.newTestament")) {
                ForEach(ntBooks) { book in
                    Button(book.name) {
                        Task {
                            let loc = BibleLocation(
                                moduleId: pane.location.moduleId,
                                book: book.id,
                                chapter: 1
                            )
                            await bibleStore.navigate(paneId: pane.id, to: loc)
                        }
                    }
                }
            }
        } label: {
            Text(currentBook?.name ?? pane.location.book)
                .font(.callout)
                .fontWeight(.medium)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Chapter Picker

    private var chapterPicker: some View {
        Menu {
            let count = currentBook?.chapterCount ?? 1
            ForEach(1...count, id: \.self) { ch in
                Button("\(ch)") {
                    Task {
                        let loc = BibleLocation(
                            moduleId: pane.location.moduleId,
                            book: pane.location.book,
                            chapter: ch
                        )
                        await bibleStore.navigate(paneId: pane.id, to: loc)
                    }
                }
            }
        } label: {
            Text("pane.chapter \(pane.location.chapter)")
                .font(.callout)
                .fontWeight(.medium)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Verse Picker

    private var versePicker: some View {
        Menu {
            if verseCount > 0 {
                ForEach(1...verseCount, id: \.self) { v in
                    Button(String(localized: "pane.verse \(v)")) {
                        onScrollToVerse?(v)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.down.to.line")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Chapter Navigation

    private var previousChapterButton: some View {
        PaneToolbarButton(systemImage: "chevron.left") {
            Task {
                let loc = BibleLocation(
                    moduleId: pane.location.moduleId,
                    book: pane.location.book,
                    chapter: pane.location.chapter - 1
                )
                await bibleStore.navigate(paneId: pane.id, to: loc)
            }
        }
        .disabled(pane.location.chapter <= 1)
        .opacity(pane.location.chapter <= 1 ? 0.3 : 1.0)
        .help(String(localized: "toolbar.previousChapter"))
    }

    private var nextChapterButton: some View {
        PaneToolbarButton(systemImage: "chevron.right") {
            Task {
                let loc = BibleLocation(
                    moduleId: pane.location.moduleId,
                    book: pane.location.book,
                    chapter: pane.location.chapter + 1
                )
                await bibleStore.navigate(paneId: pane.id, to: loc)
            }
        }
        .disabled(pane.location.chapter >= (currentBook?.chapterCount ?? 1))
        .opacity(pane.location.chapter >= (currentBook?.chapterCount ?? 1) ? 0.3 : 1.0)
        .help(String(localized: "toolbar.nextChapter"))
    }

    // MARK: - Pop Out / Dock

    private var popOutButton: some View {
        PaneToolbarButton(systemImage: isDetached ? "rectangle.inset.filled.and.cursorarrow" : "macwindow.badge.plus") {
            if isDetached {
                uiState.detachedPaneIds.remove(pane.id)
            } else {
                uiState.detachedPaneIds.insert(pane.id)
                openWindow(value: pane.id)
            }
        }
        .help(isDetached ? String(localized: "pane.dock") : String(localized: "pane.popOut"))
    }

    // MARK: - Split Buttons

    private var splitHorizontalButton: some View {
        PaneToolbarButton(systemImage: "rectangle.split.2x1") {
            bibleStore.setActivePane(id: pane.id)
            withAnimation(nil) {
                bibleStore.addPane(direction: .horizontal)
            }
        }
        .help(String(localized: "pane.splitHorizontal"))
    }

    private var splitVerticalButton: some View {
        PaneToolbarButton(systemImage: "rectangle.split.1x2") {
            bibleStore.setActivePane(id: pane.id)
            withAnimation(nil) {
                bibleStore.addPane(direction: .vertical)
            }
        }
        .help(String(localized: "pane.splitVertical"))
    }

    private var closePaneButton: some View {
        PaneToolbarButton(systemImage: "xmark") {
            withAnimation(nil) {
                bibleStore.removePane(id: pane.id)
            }
        }
        .help(String(localized: "pane.closePane"))
    }

}

// MARK: - Toolbar Icon Button

private struct PaneToolbarButton: View {
    let systemImage: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.05 : 1.0)
        .animation(.spring(duration: 0.2, bounce: 0.3), value: isHovering)
        .onHover { hovering in isHovering = hovering }
    }
}
