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
    @EnvironmentObject var windowState: WindowState
    @State private var editingBookmarkId: UUID?
    @State private var editingNoteText: String = ""
    @State private var searchText: String = ""
    @State private var sortOrder: BookmarkSortOrder = .dateNewest
    @State private var groupByBook: Bool = false
    @State private var showDeleteAllConfirmation: Bool = false

    // Cached book-order index for O(1) lookups during sort
    private static let bookOrderIndex: [String: Int] = {
        var map = [String: Int]()
        for (i, book) in BibleBooks.all.enumerated() { map[book] = i }
        return map
    }()

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
            let idx = Self.bookOrderIndex
            result.sort { lhs, rhs in
                let lBook = bookName(from: lhs.verseId)
                let rBook = bookName(from: rhs.verseId)
                let lIndex = idx[lBook] ?? 999
                let rIndex = idx[rBook] ?? 999
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
                Text(L("bookmarks.title"))
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
                        TextField(L("bookmarks.filter"), text: $searchText)
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
                    .padding(.vertical, 6)
                    .background(.quaternary.opacity(0.5))
                    .cornerRadius(6)

                    // Group by book toggle
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { groupByBook.toggle() } }) {
                        Image(systemName: groupByBook ? "folder.fill" : "folder")
                            .font(.callout)
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(groupByBook ? Color.accentColor : Color.secondary)
                    .help(groupByBook ? L("bookmarks.show_flat") : L("bookmarks.group_by_book"))

                    // Sort menu
                    Menu {
                        ForEach(BookmarkSortOrder.allCases, id: \.self) { order in
                            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { sortOrder = order } }) {
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
                    .help(L("bookmarks.sort_order"))

                    // Delete all
                    Button(action: { showDeleteAllConfirmation = true }) {
                        Image(systemName: "trash")
                            .font(.callout)
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(L("bookmarks.delete_all_help"))
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
        .alert(L("bookmarks.delete_all_title"), isPresented: $showDeleteAllConfirmation) {
            Button(L("bookmarks.delete_all_title"), role: .destructive) {
                for bm in store.bookmarks {
                    store.removeBookmark(bm.id)
                }
            }
            Button(L("cancel"), role: .cancel) {}
        } message: {
            Text("\(L("bookmarks.empty_title")): \(store.bookmarks.count). \(L("alert.clear_history_msg"))")
        }
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
            Text(L("bookmarks.empty_title"))
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text(L("bookmarks.empty_hint"))
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
            Text(L("bookmarks.no_match"))
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
                    .onDelete { indexSet in
                        for index in indexSet {
                            store.removeBookmark(bookmarks[index].id)
                        }
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
        HStack {
            BookmarkRow(bookmark: bookmark)
            Spacer()
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    store.removeBookmark(bookmark.id)
                }
            }) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("bookmarks.delete_help"))
        }
            .contentShape(Rectangle())
            .onTapGesture {
                navigateToBookmark(bookmark)
            }
            .contextMenu {
                Button(L("bookmarks.go_to_verse")) {
                    navigateToBookmark(bookmark)
                }
                Divider()
                Button(bookmark.note == nil ? L("bookmarks.add_note") : L("bookmarks.edit_note")) {
                    editingNoteText = bookmark.note ?? ""
                    editingBookmarkId = bookmark.id
                }
                if bookmark.note != nil {
                    Button(L("bookmarks.remove_note")) {
                        store.updateBookmarkNote(id: bookmark.id, note: nil)
                    }
                }
                Divider()
                Button(L("bookmarks.remove"), role: .destructive) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        store.removeBookmark(bookmark.id)
                    }
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

        guard let pane = windowState.panes.first else { return }

        let newTranslationId = store.loadedTranslations.contains(where: { $0.id == bookmark.translationId })
            ? bookmark.translationId : pane.translationId
        windowState.navigate(paneId: pane.id, book: book, chapter: chapter, translationId: newTranslationId)
        guard let updated = windowState.panes.first else { return }
        let verses = store.loadVerses(translationId: updated.translationId, book: book, chapter: chapter)
        let scheme = store.versificationScheme(for: updated.translationId)
        windowState.setVerses(paneId: pane.id, verses: verses, versificationScheme: scheme)

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
                    .foregroundStyle(Color.accentColor)
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
        .padding(.vertical, 4)
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
            Text(L("bookmarks.note_title"))
                .font(.headline)
            TextEditor(text: $noteText)
                .font(.body)
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack {
                Button(L("cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L("save")) { onSave(noteText) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 340, idealWidth: 400, minHeight: 220, idealHeight: 260)
        .glassSheet()
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
        .padding(.vertical, 4)
    }
}
