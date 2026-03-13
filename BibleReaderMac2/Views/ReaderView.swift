import SwiftUI

struct ReaderView: View {
    @Environment(BibleStore.self) private var bibleStore
    @Environment(UIStateStore.self) private var uiState

    let pane: ReadingPane

    @Namespace private var glassNamespace
    @State private var verses: [Verse] = []
    @State private var isLoading = true
    @State private var chapterId = ""
    @State private var navigatingForward = true
    @State private var scrollTarget: Int? = nil

    var body: some View {
        ZStack(alignment: .top) {
            chapterContent
                .padding(.top, 44)

            PaneToolbar(
                pane: pane,
                verseCount: verses.count,
                onScrollToVerse: { verseNumber in
                    scrollTarget = verseNumber
                }
            )
            .frame(maxWidth: CGFloat.infinity, alignment: Alignment.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: pane.location) {
            await loadChapter()
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
            }
        }
        .animation(nil, value: chapterId)
    }

    private var verseList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(verses) { verse in
                        VerseRow(
                            verse: verse,
                            isSelected: uiState.selectedVerseId == verse.id,
                            fontSize: uiState.fontSize,
                            glassNamespace: glassNamespace,
                            onSelect: {
                                withAnimation(nil) {
                                    uiState.selectedVerseId = verse.id
                                }
                            },
                            onStrongsTap: { strongsId in
                                uiState.selectedVerseId = verse.id
                                uiState.sidebarVisible = true
                                uiState.expandedSidebarSections.insert(SidebarSection.strongs.rawValue)
                            }
                        )
                        .id(verse.verseNumber)
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: scrollTarget) { _, target in
                if let target {
                    withAnimation(nil) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                    scrollTarget = nil
                }
            }
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

}
