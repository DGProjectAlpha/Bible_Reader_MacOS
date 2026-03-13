import SwiftUI

/// Extracted from InspectorView to reduce Swift type-checker complexity
struct BookmarksTabView: View {
    @Environment(BibleStore.self) private var bibleStore
    @Environment(UserDataStore.self) private var userDataStore
    @Environment(UIStateStore.self) private var uiStateStore

    var body: some View {
        if let verseId = uiStateStore.selectedVerseId {
            verseBookmarksView(verseId: verseId)
        } else {
            allBookmarksList
        }
    }

    // MARK: - Verse Bookmarks

    private func verseBookmarksView(verseId: String) -> some View {
        let verseBookmarks = userDataStore.bookmarks.filter { $0.verseId == verseId }

        return VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bookmarks")
                        .font(.headline)
                    Text(verseId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task {
                        let bookmark = Bookmark(
                            id: UUID(),
                            verseId: verseId,
                            color: .yellow,
                            note: "",
                            createdAt: Date()
                        )
                        await userDataStore.addBookmark(bookmark)
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Add bookmark")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            if verseBookmarks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bookmark")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No bookmarks for this verse")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Tap + to add one")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(verseBookmarks) { bookmark in
                            BookmarkRowView(bookmark: bookmark)
                                .environment(userDataStore)
                        }
                    }
                }
            }
        }
    }

    // MARK: - All Bookmarks

    private var allBookmarksList: some View {
        Group {
            if userDataStore.bookmarks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bookmark")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No bookmarks yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Select a verse to add a bookmark")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Summary header
                        HStack(spacing: 8) {
                            Image(systemName: "bookmark.fill")
                                .foregroundStyle(Color.accentColor)
                            Text("\(userDataStore.bookmarks.count) bookmark\(userDataStore.bookmarks.count == 1 ? "" : "s")")
                                .font(.subheadline.bold())
                            Spacer()

                            // Color summary dots
                            ForEach(BookmarkColor.allCases, id: \.self) { color in
                                let count = userDataStore.bookmarks.filter { $0.color == color }.count
                                if count > 0 {
                                    HStack(spacing: 2) {
                                        Circle()
                                            .fill(colorForBookmark(color))
                                            .frame(width: 8, height: 8)
                                        Text("\(count)")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)

                        Divider()

                        ForEach(userDataStore.bookmarks.sorted(by: { $0.dateAdded > $1.dateAdded })) { bookmark in
                            bookmarkListRow(bookmark)
                        }
                    }
                }
            }
        }
    }

    private func bookmarkListRow(_ bookmark: Bookmark) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(colorForBookmark(bookmark.color))
                    .frame(width: 10, height: 10)
                Text(bookmark.verseId)
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Text(bookmark.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if !bookmark.note.isEmpty {
                Text(bookmark.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Divider()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            navigateToBookmark(bookmark)
        }
        .hoverHighlight()
    }

    // MARK: - Navigation

    private func navigateToBookmark(_ bookmark: Bookmark) {
        let parts = bookmark.verseId.split(separator: ".")
        guard parts.count == 3,
              let chapter = Int(parts[1]),
              let verse = Int(parts[2]) else { return }
        let book = String(parts[0])
        let moduleId = bibleStore.activeModuleId
        let location = BibleLocation(moduleId: moduleId, book: book, chapter: chapter, verseNumber: verse)

        Task {
            if let paneId = bibleStore.activePaneId {
                await bibleStore.navigate(paneId: paneId, to: location)
            }
            await MainActor.run {
                uiStateStore.selectedVerseId = bookmark.verseId
            }
        }
    }

    // MARK: - Helpers

    private func colorForBookmark(_ color: BookmarkColor) -> Color {
        switch color {
        case .yellow: return .yellow
        case .blue:   return .blue
        case .green:  return .green
        case .orange: return .orange
        case .purple: return .purple
        }
    }
}
