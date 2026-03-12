import SwiftUI
import UniformTypeIdentifiers

// MARK: - Sort Options

enum NoteSortOrder: String, CaseIterable {
    case dateNewest = "dateNewest"
    case dateOldest = "dateOldest"
    case bookOrder  = "bookOrder"

    var label: String {
        switch self {
        case .dateNewest: return L("notes.sort_newest")
        case .dateOldest: return L("notes.sort_oldest")
        case .bookOrder:  return L("notes.sort_book_order")
        }
    }
}

// MARK: - Notes View

struct NotesView: View {
    @EnvironmentObject var store: BibleStore
    @EnvironmentObject var windowState: WindowState
    @State private var searchText: String = ""
    @State private var sortOrder: NoteSortOrder = .dateNewest
    @State private var groupByBook: Bool = false
    @State private var showDeleteAllConfirmation: Bool = false
    @State private var showPDFExport: Bool = false
    @State private var editingNoteId: UUID?
    @State private var editingNoteContent: String = ""

    // Cached book-order index for O(1) lookups during sort
    private static let bookOrderIndex: [String: Int] = {
        var map = [String: Int]()
        for (i, book) in BibleBooks.all.enumerated() { map[book] = i }
        return map
    }()

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
                Text(L("notes.title"))
                    .font(.title2.weight(.semibold))
                Spacer()
                if !store.notes.isEmpty {
                    Text("\(store.notes.count)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                // Export to PDF — always visible
                Button(action: { showPDFExport = true }) {
                    Image(systemName: "arrow.down.doc")
                        .font(.callout)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Export notes to PDF")
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
                        TextField(L("notes.filter"), text: $searchText)
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
                    .help(groupByBook ? L("notes.show_flat") : L("notes.group_by_book"))

                    // Sort menu
                    Menu {
                        ForEach(NoteSortOrder.allCases, id: \.self) { order in
                            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { sortOrder = order } }) {
                                HStack {
                                    Text(order.label)
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
                    .help(L("notes.sort_order"))

                    // Delete all
                    Button(action: { showDeleteAllConfirmation = true }) {
                        Image(systemName: "trash")
                            .font(.callout)
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(L("notes.delete_all_help"))
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
        .alert(L("notes.delete_all_title"), isPresented: $showDeleteAllConfirmation) {
            Button(L("delete_all"), role: .destructive) {
                for note in store.notes {
                    store.removeNote(note.id)
                }
            }
            Button(L("cancel"), role: .cancel) {}
        } message: {
            Text(String(format: L("notes.delete_all_msg"), store.notes.count))
        }
        .sheet(isPresented: $showPDFExport) {
            NoteExportView(notes: filteredNotes)
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
            Text(L("notes.empty_title"))
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text(L("notes.empty_hint"))
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
            Text(L("notes.no_match"))
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
        HStack {
            NoteRow(note: note)
            Spacer()
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    store.removeNote(note.id)
                }
            }) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("notes.delete_help"))
        }
            .contentShape(Rectangle())
            .onTapGesture {
                navigateToNote(note)
            }
            .contextMenu {
                Button(L("notes.go_to_verse")) {
                    navigateToNote(note)
                }
                Divider()
                Button(L("notes.edit")) {
                    editingNoteContent = note.content
                    editingNoteId = note.id
                }
                Button(L("notes.copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        "\(formatVerseId(note.verseId))\n\(note.content)",
                        forType: .string
                    )
                }
                Divider()
                Button(L("notes.delete"), role: .destructive) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        store.removeNote(note.id)
                    }
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

        let newTranslationId = store.loadedTranslations.contains(where: { $0.id == note.translationId })
            ? note.translationId : pane.translationId
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
                    .foregroundStyle(Color.accentColor)
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
        .padding(.vertical, 4)
    }

    private func formatVerseId(_ id: String) -> String {
        let parts = id.split(separator: ":")
        guard parts.count == 3 else { return id }
        return "\(parts[0]) \(parts[1]):\(parts[2])"
    }
}

// MARK: - Note Export View

struct NoteExportView: View {
    @Environment(\.dismiss) private var dismiss
    let notes: [Note]

    @State private var includeVerseRefs: Bool = true
    @State private var includeTimestamps: Bool = false
    @State private var groupByBook: Bool = false
    @State private var titleText: String = "Bible Reader — Notes Export"

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    // Cached book-order index for grouping
    private static let bookOrderIndex: [String: Int] = {
        var map = [String: Int]()
        for (i, book) in BibleBooks.all.enumerated() { map[book] = i }
        return map
    }()

    private var previewText: String {
        var lines: [String] = []
        if !titleText.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append(titleText)
            lines.append(String(repeating: "─", count: 40))
            lines.append("")
        }

        let sorted: [Note]
        if groupByBook {
            let idx = Self.bookOrderIndex
            sorted = notes.sorted { lhs, rhs in
                let lb = String(lhs.verseId.split(separator: ":").first ?? "")
                let rb = String(rhs.verseId.split(separator: ":").first ?? "")
                let li = idx[lb] ?? 999
                let ri = idx[rb] ?? 999
                if li != ri { return li < ri }
                return lhs.verseId < rhs.verseId
            }
        } else {
            sorted = notes
        }

        var currentBook: String? = nil
        for note in sorted {
            let book = String(note.verseId.split(separator: ":").first ?? "")
            if groupByBook && book != currentBook {
                if currentBook != nil { lines.append("") }
                lines.append("── \(book) ──")
                currentBook = book
            }
            if includeVerseRefs {
                lines.append(formatVerseId(note.verseId))
            }
            lines.append(note.content)
            if includeTimestamps {
                lines.append("  \(Self.dateFormatter.string(from: note.updatedAt))")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export Notes to PDF")
                        .font(.headline)
                    Text("\(notes.count) note\(notes.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider()

            HStack(alignment: .top, spacing: 0) {
                // Options panel
                VStack(alignment: .leading, spacing: 20) {
                    Text("Options")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Document Title")
                            .font(.callout.weight(.medium))
                        TextField("Title", text: $titleText)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Include")
                            .font(.callout.weight(.medium))
                        Toggle("Verse references", isOn: $includeVerseRefs)
                            .toggleStyle(.checkbox)
                        Toggle("Timestamps", isOn: $includeTimestamps)
                            .toggleStyle(.checkbox)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Layout")
                            .font(.callout.weight(.medium))
                        Toggle("Group by book", isOn: $groupByBook)
                            .toggleStyle(.checkbox)
                    }

                    Spacer()
                }
                .padding(20)
                .frame(width: 200)

                Divider()

                // Preview panel
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 2)

                    ScrollView {
                        Text(previewText.isEmpty ? "No notes to preview." : previewText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.primary.opacity(0.04))
                            )
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)

            Divider()

            // Footer buttons
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(action: exportAsPDF) {
                    Label("Export PDF", systemImage: "arrow.down.doc.fill")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(notes.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(minWidth: 580, idealWidth: 640, minHeight: 420, idealHeight: 500)
        .glassSheet()
    }

    private func exportAsPDF() {
        let content = previewText
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "BibleReader_Notes.pdf"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 510, height: 792))
            textView.string = content
            textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            textView.isEditable = false
            textView.textContainerInset = NSSize(width: 40, height: 40)

            let printInfo = NSPrintInfo()
            printInfo.paperSize = NSSize(width: 612, height: 792)
            printInfo.topMargin = 36
            printInfo.bottomMargin = 36
            printInfo.leftMargin = 36
            printInfo.rightMargin = 36
            printInfo.isVerticallyCentered = false

            let pdfData = textView.dataWithPDF(inside: textView.bounds)
            try? pdfData.write(to: url)
            dismiss()
        }
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
                Text(L("notes.edit_title"))
                    .font(.headline)
                Spacer()
                Text(verseRef)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
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
        .frame(minWidth: 340, idealWidth: 400, minHeight: 240, idealHeight: 280)
        .glassSheet()
    }
}
