import SwiftUI

private struct ChapterNavButton: View {
    let systemImage: String
    let helpText: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(.borderless)
        .help(helpText)
        .scaleEffect(isHovering ? 1.03 : 1.0)
        .animation(.spring(duration: 0.2, bounce: 0.3), value: isHovering)
        .onHover { hovering in isHovering = hovering }
    }
}

struct ReaderView: View {
    @Environment(BibleStore.self) private var bibleStore
    @Environment(UIStateStore.self) private var uiState

    let pane: ReadingPane

    @Namespace private var glassNamespace
    @State private var verses: [Verse] = []
    @State private var isLoading = true
    @State private var chapterId = ""
    @State private var navigatingForward = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            chapterContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: pane.location) {
            await loadChapter()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            if let module = bibleStore.modules.first(where: { $0.id == pane.location.moduleId }) {
                Text(module.abbreviation)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                if let book = module.books.first(where: { $0.id == pane.location.book }) {
                    Text(book.name)
                        .font(.headline)
                } else {
                    Text(pane.location.book)
                        .font(.headline)
                }
            }

            Text("Chapter \(pane.location.chapter)")
                .font(.headline)

            Spacer()

            chapterNav
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var chapterNav: some View {
        HStack(spacing: 4) {
            ChapterNavButton(systemImage: "chevron.left", helpText: "Previous Chapter") {
                Task { await navigatePrevious() }
            }
            ChapterNavButton(systemImage: "chevron.right", helpText: "Next Chapter") {
                Task { await navigateNext() }
            }
        }
    }

    // MARK: - Content

    private var chapterContent: some View {
        Group {
            if isLoading {
                loadingSkeleton
            } else if verses.isEmpty {
                ContentUnavailableView("No Verses", systemImage: "book.closed")
            } else {
                verseList
                    .id(chapterId)
                    .transition(.asymmetric(
                        insertion: .move(edge: navigatingForward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: navigatingForward ? .leading : .trailing).combined(with: .opacity)
                    ))
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.2), value: chapterId)
    }

    private var verseList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(verses) { verse in
                    VerseRow(
                        verse: verse,
                        isSelected: uiState.selectedVerseId == verse.id,
                        fontSize: uiState.fontSize,
                        glassNamespace: glassNamespace,
                        onSelect: {
                            withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
                                uiState.selectedVerseId = verse.id
                            }
                        },
                        onStrongsTap: { strongsId in
                            uiState.selectedVerseId = verse.id
                            uiState.inspectorTab = .strongs
                            uiState.inspectorVisible = true
                        }
                    )
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var loadingSkeleton: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(0..<20, id: \.self) { i in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(i + 1)")
                            .font(.system(size: uiState.fontSize * 0.7, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 24, alignment: .trailing)

                        Text("Lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod")
                            .font(.system(size: uiState.fontSize))
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 8)
            .redacted(reason: .placeholder)
            .shimmer()
        }
    }

    // MARK: - Data Loading

    private func loadChapter() async {
        isLoading = true
        let loc = pane.location
        do {
            let loaded = try await bibleStore.loadChapter(
                moduleId: loc.moduleId,
                book: loc.book,
                chapter: loc.chapter
            )
            verses = loaded
            chapterId = "\(loc.moduleId).\(loc.book).\(loc.chapter)"
        } catch {
            verses = []
        }
        isLoading = false
    }

    // MARK: - Navigation

    private func navigatePrevious() async {
        navigatingForward = false
        bibleStore.setActivePane(id: pane.id)
        await bibleStore.navigatePreviousChapter()
    }

    private func navigateNext() async {
        navigatingForward = true
        bibleStore.setActivePane(id: pane.id)
        await bibleStore.navigateNextChapter()
    }
}
