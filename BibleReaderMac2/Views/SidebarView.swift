import SwiftUI

struct SidebarView: View {
    @Environment(BibleStore.self) private var bibleStore
    @Environment(UIStateStore.self) private var uiStateStore
    @Environment(UserDataStore.self) private var userDataStore

    @State private var expandedBookId: String? = nil

    // MARK: - Computed

    private var activeModule: Module? {
        bibleStore.modules.first(where: { $0.id == bibleStore.activeModuleId })
    }

    private var activePane: ReadingPane? {
        bibleStore.panes.first(where: { $0.id == bibleStore.activePaneId })
    }

    private var oldTestamentBooks: [Book] {
        activeModule?.books.filter { $0.testament == .old } ?? []
    }

    private var newTestamentBooks: [Book] {
        activeModule?.books.filter { $0.testament == .new } ?? []
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            modulePicker
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            bookList
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Module Picker

    private var modulePicker: some View {
        @Bindable var store = bibleStore

        return Picker("Module", selection: $store.activeModuleId) {
            ForEach(bibleStore.modules) { module in
                Text(module.abbreviation).tag(module.id)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }

    // MARK: - Book List

    private var bookList: some View {
        List {
            if !oldTestamentBooks.isEmpty {
                Section("Old Testament") {
                    ForEach(oldTestamentBooks) { book in
                        bookRow(book)
                    }
                }
            }

            if !newTestamentBooks.isEmpty {
                Section("New Testament") {
                    ForEach(newTestamentBooks) { book in
                        bookRow(book)
                    }
                }
            }

            if !userDataStore.readingHistory.isEmpty {
                Section {
                    ForEach(Array(userDataStore.readingHistory.prefix(15).enumerated()), id: \.offset) { _, location in
                        Button {
                            navigateToHistory(location)
                        } label: {
                            Label {
                                Text(historyLabel(for: location))
                                    .font(.subheadline)
                            } icon: {
                                Image(systemName: "clock")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text("Recents")
                        Spacer()
                        Button("Clear") {
                            Task { await userDataStore.clearHistory() }
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            if !userDataStore.bookmarks.isEmpty {
                Section("Bookmarks") {
                    ForEach(userDataStore.bookmarks.sorted(by: { $0.createdAt > $1.createdAt })) { bookmark in
                        sidebarBookmarkRow(bookmark)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Book Row

    @ViewBuilder
    private func bookRow(_ book: Book) -> some View {
        let isCurrentBook = activePane?.location.book == book.id

        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedBookId == book.id },
                set: { expanded in
                    withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                        expandedBookId = expanded ? book.id : nil
                    }
                }
            )
        ) {
            chapterGrid(for: book)
        } label: {
            Label {
                Text(book.name)
                    .fontWeight(isCurrentBook ? .semibold : .regular)
                    .foregroundStyle(isCurrentBook ? Color.accentColor : .primary)
            } icon: {
                Image(systemName: book.testament == .old ? "book.closed" : "book")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isCurrentBook ? Color.accentColor : .secondary)
            }
        }
    }

    // MARK: - Chapter Grid

    private func chapterGrid(for book: Book) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 5)
        let currentChapter = (activePane?.location.book == book.id) ? activePane?.location.chapter : nil

        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(1...book.chapterCount, id: \.self) { chapter in
                let isActive = currentChapter == chapter

                ChapterButton(
                    chapter: chapter,
                    isActive: isActive,
                    action: {
                        guard let paneId = bibleStore.activePaneId else { return }
                        let location = BibleLocation(
                            moduleId: bibleStore.activeModuleId,
                            book: book.id,
                            chapter: chapter
                        )
                        Task {
                            await bibleStore.navigate(paneId: paneId, to: location)
                        }
                    }
                )
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Sidebar Bookmark Row

    private func sidebarBookmarkRow(_ bookmark: Bookmark) -> some View {
        Button {
            navigateToBookmark(bookmark)
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bookmark.verseId)
                        .font(.subheadline)
                    if !bookmark.note.isEmpty {
                        Text(bookmark.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } icon: {
                Circle()
                    .fill(swiftColor(for: bookmark.color))
                    .frame(width: 10, height: 10)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                Task { await userDataStore.deleteBookmark(id: bookmark.id) }
            } label: {
                Label("Remove Bookmark", systemImage: "trash")
            }
        }
    }

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

    // MARK: - Reading History Helpers

    private func historyLabel(for location: BibleLocation) -> String {
        let bookName = activeModule?.books.first(where: { $0.id == location.book })?.shortName ?? location.book
        if let verse = location.verseNumber {
            return "\(bookName) \(location.chapter):\(verse)"
        }
        return "\(bookName) \(location.chapter)"
    }

    private func navigateToHistory(_ location: BibleLocation) {
        guard let paneId = bibleStore.activePaneId else { return }
        Task {
            await bibleStore.navigate(paneId: paneId, to: location)
        }
    }

    private func swiftColor(for color: BookmarkColor) -> Color {
        switch color {
        case .yellow: .yellow
        case .blue: .blue
        case .green: .green
        case .orange: .orange
        case .purple: .purple
        }
    }
}

// MARK: - Chapter Button with Hover

private struct ChapterButton: View {
    let chapter: Int
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text("\(chapter)")
                .font(.caption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(
                    isActive ? Color.accentColor.opacity(0.2) :
                    isHovering ? Color.primary.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 4)
                )
                .foregroundStyle(isActive ? Color.accentColor : .primary)
                .fontWeight(isActive ? .bold : .regular)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.03 : 1.0)
        .animation(.spring(duration: 0.2, bounce: 0.3), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
