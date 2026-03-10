import SwiftUI
import UniformTypeIdentifiers

// MARK: - Sort Options

enum NoteSortOrder: String, CaseIterable {
    case dateNewest = "Newest First"
    case dateOldest = "Oldest First"
    case bookOrder = "Book Order"
}

// MARK: - Notes View

struct NotesView: View {
    @EnvironmentObject var store: BibleStore
    @EnvironmentObject var windowState: WindowState
    @State private var searchText: String = ""
    @State private var sortOrder: NoteSortOrder = .dateNewest
    @State private var groupByBook: Bool = false
    @State private var showDeleteAllConfirmation: Bool = false
    @State private var editingNoteId: UUID?
    @State private var editingNoteContent: String = ""

    private var filteredNotes: [Note] {
        var result = store.notes

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { note in
                formatVerseId(note.verseId).lowercased().contains(query)
                || note.content.lowercased().contains(query)
            }
        }

        switch sortOrder {
        case .dateNewest:
            result.sort { $0.updatedAt > $1.updatedAt }
        case .dateOldest:
            result.sort { $0.updatedAt < $1.updatedAt }
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

    private var groupedNotes: [(String, [Note])] {
        let notes = filteredNotes
        var groups: [(String, [Note])] = []
        var seen: [String: Int] = [:]

        for note in notes {
            let book = bookName(from: note.verseId)
            if let idx = seen[book] {
                groups[idx].1.append(note)
            } else {
                seen[book] = groups.count
                groups.append((book, [note]))
            }
        }

        return groups
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Notes")
                    .font(.title2.weight(.semibold))
                Spacer()
                if !store.notes.isEmpty {
                    Text("\(store.notes.count)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Search & toolbar
            if !store.notes.isEmpty {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        TextField("Filter notes...", text: $searchText)
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
                    .foregroundStyle(groupByBook ? Color.accentColor : Color.secondary)
                    .help(groupByBook ? "Show flat list" : "Group by book")

                    // Sort menu
                    Menu {
                        ForEach(NoteSortOrder.allCases, id: \.self) { order in
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

                    // Export notes
                    Button(action: { exportNotes() }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Export notes to text file")

                    // Delete all
                    Button(action: { showDeleteAllConfirmation = true }) {
                        Image(systemName: "trash")
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Delete all notes")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            Divider()

            // Content
            if store.notes.isEmpty {
                emptyState
            } else if filteredNotes.isEmpty {
                noResultsState
            } else if groupByBook {
                groupedList
            } else {
                flatList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Delete All Notes?", isPresented: $showDeleteAllConfirmation) {
            Button("Delete All", role: .destructive) {
                for note in store.notes {
                    store.removeNote(note.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all \(store.notes.count) notes. This cannot be undone.")
        }
        .sheet(isPresented: Binding(
            get: { editingNoteId != nil },
            set: { if !$0 { editingNoteId = nil } }
        )) {
            if let noteId = editingNoteId,
               let note = store.notes.first(where: { $0.id == noteId }) {
                NoteContentEditor(
                    verseRef: formatVerseId(note.verseId),
                    noteText: $editingNoteContent,
                    onSave: { text in
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            store.removeNote(noteId)
                        } else {
                            store.addNote(verseId: note.verseId, translationId: note.translationId, content: trimmed)
                        }
                        editingNoteId = nil
                    },
                    onCancel: {
                        editingNoteId = nil
                    }
                )
            }
        }
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("No Notes")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("Right-click a verse and select \"Add Note\" to save notes here.")
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
            Text("No matching notes")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List Views

    private var flatList: some View {
        List {
            ForEach(filteredNotes) { note in
                noteRow(note)
            }
            .onDelete { indexSet in
                let filtered = filteredNotes
                for index in indexSet {
                    store.removeNote(filtered[index].id)
                }
            }
        }
        .listStyle(.inset)
    }

    private var groupedList: some View {
        List {
            ForEach(groupedNotes, id: \.0) { bookName, notes in
                Section {
                    ForEach(notes) { note in
                        noteRow(note)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            store.removeNote(notes[index].id)
                        }
                    }
                } header: {
                    HStack {
                        Text(bookName)
                            .font(.callout.weight(.semibold))
                        Spacer()
                        Text("\(notes.count)")
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
    private func noteRow(_ note: Note) -> some View {
        NoteRow(note: note)
            .contentShape(Rectangle())
            .onTapGesture {
                navigateToNote(note)
            }
            .contextMenu {
                Button("Go to Verse") {
                    navigateToNote(note)
                }
                Divider()
                Button("Edit Note") {
                    editingNoteContent = note.content
                    editingNoteId = note.id
                }
                Button("Copy Note") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        "\(formatVerseId(note.verseId))\n\(note.content)",
                        forType: .string
                    )
                }
                Divider()
                Button("Delete Note", role: .destructive) {
                    store.removeNote(note.id)
                }
            }
    }

    // MARK: - Navigation

    private func navigateToNote(_ note: Note) {
        let parts = note.verseId.split(separator: ":")
        guard parts.count >= 2 else { return }
        let book = String(parts[0])
        let chapter = Int(parts[1]) ?? 1
        let verse = parts.count >= 3 ? (Int(parts[2]) ?? 1) : 1

        guard let pane = windowState.panes.first else { return }

        if store.loadedTranslations.contains(where: { $0.id == note.translationId }) {
            pane.selectedTranslationId = note.translationId
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

    // MARK: - Export

    private func exportNotes() {
        let notes = filteredNotes
        guard !notes.isEmpty else { return }

        var lines: [String] = ["Bible Reader — Notes Export", ""]
        for note in notes {
            lines.append(formatVerseId(note.verseId))
            lines.append(note.content)
            lines.append("")
        }
        let text = lines.joined(separator: "\n")

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "BibleReader_Notes.txt"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? text.write(to: url, atomically: true, encoding: .utf8)
            }
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

// MARK: - Note Row

struct NoteRow: View {
    let note: Note

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: "note.text")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text(formatVerseId(note.verseId))
                    .font(.callout.weight(.medium))
            }
            Text(note.content)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Text(Self.dateFormatter.string(from: note.updatedAt))
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

// MARK: - Note Content Editor

struct NoteContentEditor: View {
    let verseRef: String
    @Binding var noteText: String
    var onSave: (String) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Edit Note")
                    .font(.headline)
                Spacer()
                Text(verseRef)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
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
        .frame(width: 400, height: 280)
    }
}
