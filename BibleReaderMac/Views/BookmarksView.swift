import SwiftUI

struct BookmarksView: View {
    @EnvironmentObject var store: BibleStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Bookmarks")
                    .font(.title2.weight(.semibold))
                Spacer()
                if !store.bookmarks.isEmpty {
                    Text("\(store.bookmarks.count)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            if store.bookmarks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.quaternary)
                    Text("No Bookmarks")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("Right-click a verse and select \"Bookmark Verse\" to save it here.")
                        .font(.callout)
                        .foregroundStyle(.quaternary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.bookmarks) { bookmark in
                        BookmarkRow(bookmark: bookmark)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                navigateToBookmark(bookmark)
                            }
                            .contextMenu {
                                Button("Go to Verse") {
                                    navigateToBookmark(bookmark)
                                }
                                Divider()
                                Button("Remove Bookmark", role: .destructive) {
                                    store.removeBookmark(bookmark.id)
                                }
                            }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            store.removeBookmark(store.bookmarks[index].id)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Navigation

    private func navigateToBookmark(_ bookmark: Bookmark) {
        let parts = bookmark.verseId.split(separator: ":")
        guard parts.count >= 2 else { return }
        let book = String(parts[0])
        let chapter = Int(parts[1]) ?? 1
        let verse = parts.count >= 3 ? (Int(parts[2]) ?? 1) : 1

        guard let pane = store.panes.first else { return }

        if store.loadedTranslations.contains(where: { $0.id == bookmark.translationId }) {
            pane.selectedTranslationId = bookmark.translationId
        }

        pane.selectedBook = book
        pane.selectedChapter = chapter
        store.loadVerses(for: pane)

        NotificationCenter.default.post(name: .navigateToReader, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(
                name: .navigateToVerse,
                object: nil,
                userInfo: ["book": book, "chapter": chapter, "verse": verse]
            )
        }
    }
}

// MARK: - Bookmark Row

struct BookmarkRow: View {
    let bookmark: Bookmark

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: "bookmark.fill")
                    .font(.caption)
                    .foregroundStyle(.accentColor)
                Text(formatVerseId(bookmark.verseId))
                    .font(.callout.weight(.medium))
            }
            if let label = bookmark.label, !label.isEmpty {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(Self.dateFormatter.string(from: bookmark.createdAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func formatVerseId(_ id: String) -> String {
        let parts = id.split(separator: ":")
        guard parts.count == 3 else { return id }
        return "\(parts[0]) \(parts[1]):\(parts[2])"
    }
}

// MARK: - History Row

struct HistoryRow: View {
    let entry: ReadingHistoryEntry

    private static let dateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayRef)
                    .font(.callout.weight(.medium))
                HStack(spacing: 4) {
                    Text(entry.translationAbbreviation)
                    if let v = entry.verse {
                        Text("·")
                        Text("verse \(v)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Self.dateFormatter.localizedString(for: entry.timestamp, relativeTo: Date()))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
