import SwiftUI

// MARK: - Sort & Group Options

enum BookmarkSortOrder: String, CaseIterable {
    case dateNewest = "Newest First"
    case dateOldest = "Oldest First"
    case bookOrder = "Book Order"
}

// MARK: - Bookmarks View

struct BookmarksView: View {
    @EnvironmentObject var store: BibleStore
    @State private var editingBookmarkId: UUID?
    @State private var editingNoteText: String = ""
    @State private var searchText: String = ""
    @State private var sortOrder: BookmarkSortOrder = .dateNewest
    @State private var groupByBook: Bool = false

    private var filteredBookmarks: [Bookmark] {
        var result = store.bookmarks

        // Filter by search text
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { bm in
                formatVerseId(bm.verseId).lowercased().contains(query)
                || (bm.label ?? "").lowercased().contains(query)
                || (bm.note ?? "").lowercased().contains(query)
            }
        }

        // Sort
        switch sortOrder {
        case .dateNewest:
            result.sort { $0.createdAt > $1.createdAt }
        case .dateOldest:
            result.sort { $0.createdAt < $1.createdAt }
        case .bookOrder:
            result.sort { lhs, rhs in
                let lBook = bookName(from: lhs.verseId)
                let rBook = bookName(from: rhs.verseId)
                let lIndex = BibleBooks.all.firstIndex(of: lBook) ?? 999
                let rIndex = BibleBooks.all.firstIndex(of: rBook) ?? 999
                if lIndex != rIndex { return lIndex < rIndex }
                let lChapter = chapterNumber(from: lhs.verseId)
                let rChapter = chapterNumber(from: rhs.verseId)
                if lChapter != rChapter { return lChapter < rChapter }
                return verseNumber(from: lhs.verseId) < verseNumber(from: rhs.verseId)
            }
        }

        return result
    }

    private var groupedBookmarks: [(String, [Bookmark])] {
        let bookmarks = filteredBookmarks
        var groups: [(String, [Bookmark])] = []
        var seen: [String: Int] = [:]

        for bm in bookmarks {
            let book = bookName(from: bm.verseId)
            if let idx = seen[book] {
                groups[idx].1.append(bm)
            } else {
                seen[book] = groups.count
                groups.append((book, [bm]))
            }
        }

        return groups
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
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

            // Search & toolbar
            if !store.bookmarks.isEmpty {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        TextField("Filter bookmarks...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.callout)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.quaternary.opacity(0.5))
                    .cornerRadius(6)

                    // Group by book toggle
                    Button(action: { groupByBook.toggle() }) {
                        Image(systemName: groupByBook ? "folder.fill" : "folder")
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(groupByBook ? .accentColor : .secondary)
                    .help(groupByBook ? "Show flat list" : "Group by book")

                    // Sort menu
                    Menu {
                        ForEach(BookmarkSortOrder.allCases, id: \.self) { order in
                            Button(action: { sortOrder = order }) {
                                HStack {
                                    Text(order.rawValue)
                                    if sortOrder == order {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.callout)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 20)
                    .help("Sort order")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            Divider()

            // Content
            if store.bookmarks.isEmpty {
                emptyState
            } else if filteredBookmarks.isEmpty {
                noResultsState
            } else if groupByBook {
                groupedList
            } else {
                flatList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: Binding(
            get: { editingBookmarkId != nil },
            set: { if !$0 { editingBookmarkId = nil } }
        )) {
            if let bmId = editingBookmarkId {
                BookmarkNoteEditor(
                    noteText: $editingNoteText,
                    onSave: { text in
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.updateBookmarkNote(id: bmId, note: trimmed.isEmpty ? nil : trimmed)
                        editingBookmarkId = nil
                    },
                    onCancel: {
                        editingBookmarkId = nil
                    }
                )
            }
        }
    }

    // MARK: - Empty States

    private var emptyState: some View {
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
    }

    private var noResultsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.quaternary)
            Text("No matching bookmarks")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List Views

    private var flatList: some View {
        List {
            ForEach(filteredBookmarks) { bookmark in
                bookmarkRow(bookmark)
            }
            .onDelete { indexSet in
                let filtered = filteredBookmarks
                for index in indexSet {
                    store.removeBookmark(filtered[index].id)
                }
            }
        }
        .listStyle(.inset)
    }

    private var groupedList: some View {
        List {
            ForEach(groupedBookmarks, id: \.0) { bookName, bookmarks in
                Section {
                    ForEach(bookmarks) { bookmark in
                        bookmarkRow(bookmark)
                    }
                } header: {
                    HStack {
                        Text(bookName)
                            .font(.callout.weight(.semibold))
                        Spacer()
                        Text("\(bookmarks.count)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Row Builder

    @ViewBuilder
    private func bookmarkRow(_ bookmark: Bookmark) -> some View {
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
                Button(bookmark.note == nil ? "Add Note" : "Edit Note") {
                    editingNoteText = bookmark.note ?? ""
                    editingBookmarkId = bookmark.id
                }
                if bookmark.note != nil {
                    Button("Remove Note") {
                        store.updateBookmarkNote(id: bookmark.id, note: nil)
                    }
                }
                Divider()
                Button("Remove Bookmark", role: .destructive) {
                    store.removeBookmark(bookmark.id)
                }
            }
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

    // MARK: - Helpers

    private func formatVerseId(_ id: String) -> String {
        let parts = id.split(separator: ":")
        guard parts.count == 3 else { return id }
        return "\(parts[0]) \(parts[1]):\(parts[2])"
    }

    private func bookName(from verseId: String) -> String {
        String(verseId.split(separator: ":").first ?? "")
    }

    private func chapterNumber(from verseId: String) -> Int {
        let parts = verseId.split(separator: ":")
        guard parts.count >= 2 else { return 0 }
        return Int(parts[1]) ?? 0
    }

    private func verseNumber(from verseId: String) -> Int {
        let parts = verseId.split(separator: ":")
        guard parts.count >= 3 else { return 0 }
        return Int(parts[2]) ?? 0
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
            if let note = bookmark.note, !note.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "note.text")
                        .font(.caption2)
                    Text(note)
                        .lineLimit(2)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
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

// MARK: - Bookmark Note Editor

struct BookmarkNoteEditor: View {
    @Binding var noteText: String
    var onSave: (String) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Bookmark Note")
                .font(.headline)
            TextEditor(text: $noteText)
                .font(.body)
                .frame(minHeight: 120)
                .border(Color.secondary.opacity(0.3), width: 1)
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { onSave(noteText) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400, height: 260)
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
