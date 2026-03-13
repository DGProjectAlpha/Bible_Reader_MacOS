import SwiftUI

struct VerseRow: View {
    let verse: Verse
    let isSelected: Bool
    let fontSize: Double
    let glassNamespace: Namespace.ID
    let onSelect: () -> Void
    let onStrongsTap: (String) -> Void

    @Environment(UserDataStore.self) private var userDataStore
    @State private var isHovering = false
    @State private var showNoteEditor = false
    @State private var noteText = ""

    private var verseId: String { verse.id }

    private var isBookmarked: Bool {
        userDataStore.bookmarks.contains { $0.verseId == verseId }
    }

    private var isHighlighted: Bool {
        userDataStore.highlights.contains { $0.verseId == verseId }
    }

    private var highlightColor: Color? {
        guard let highlight = userDataStore.highlights.first(where: { $0.verseId == verseId }) else { return nil }
        return swiftColor(for: highlight.color)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(verse.verseNumber)")
                .font(.system(size: fontSize * 0.7, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 24, alignment: .trailing)

            if verse.strongsNumbers.isEmpty {
                Text(verse.text)
                    .font(.system(size: fontSize))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            } else {
                strongsTextView
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Group {
                if let color = highlightColor {
                    color.opacity(0.2)
                } else if isSelected {
                    Color.accentColor.opacity(0.15)
                } else {
                    Color.clear
                }
            }
        )
        .animation(.spring(duration: 0.25, bounce: 0.1), value: isSelected)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .scaleEffect(isHovering ? 1.03 : 1.0)
        .animation(.spring(duration: 0.2, bounce: 0.3), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            // Bookmark
            if isBookmarked {
                Button(role: .destructive) {
                    Task { await removeBookmark() }
                } label: {
                    Label("Remove Bookmark", systemImage: "bookmark.slash")
                }
            } else {
                Menu {
                    ForEach(BookmarkColor.allCases, id: \.self) { color in
                        Button {
                            Task { await addBookmark(color: color) }
                        } label: {
                            Label(color.rawValue.capitalized, systemImage: "bookmark.fill")
                        }
                    }
                } label: {
                    Label("Bookmark", systemImage: "bookmark")
                }
            }

            Divider()

            // Highlight
            if isHighlighted {
                Button(role: .destructive) {
                    Task { await userDataStore.removeHighlight(verseId: verseId) }
                } label: {
                    Label("Remove Highlight", systemImage: "highlighter")
                }
            } else {
                Menu {
                    ForEach(BookmarkColor.allCases, id: \.self) { color in
                        Button {
                            Task { await addHighlight(color: color) }
                        } label: {
                            Label(color.rawValue.capitalized, systemImage: "paintbrush.fill")
                        }
                    }
                } label: {
                    Label("Highlight", systemImage: "highlighter")
                }
            }

            Divider()

            // Note
            Button {
                let existing = userDataStore.notes.first(where: { $0.verseId == verseId })
                noteText = existing?.text ?? ""
                showNoteEditor = true
            } label: {
                let hasNote = userDataStore.notes.contains { $0.verseId == verseId }
                Label(hasNote ? "Edit Note" : "Add Note", systemImage: "note.text")
            }

            Divider()

            // Copy
            Button {
                let copyText = "\(verse.book) \(verse.chapter):\(verse.verseNumber) — \(verse.text)"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(copyText, forType: .string)
            } label: {
                Label("Copy Verse", systemImage: "doc.on.doc")
            }
        }
        .sheet(isPresented: $showNoteEditor) {
            noteEditorSheet
                .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: - Note Editor Sheet

    private var noteEditorSheet: some View {
        VStack(spacing: 16) {
            Text("Note for \(verse.book) \(verse.chapter):\(verse.verseNumber)")
                .font(.headline)

            TextEditor(text: $noteText)
                .font(.body)
                .frame(minHeight: 120)
                .border(Color.secondary.opacity(0.3))

            HStack {
                if let existing = userDataStore.notes.first(where: { $0.verseId == verseId }) {
                    Button(role: .destructive) {
                        Task {
                            await userDataStore.deleteNote(id: existing.id)
                            showNoteEditor = false
                        }
                    } label: {
                        Text("Delete")
                    }
                }

                Spacer()

                Button("Cancel") {
                    showNoteEditor = false
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    Task { await saveNote() }
                } label: {
                    Text("Save")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 360, minHeight: 240)
    }

    // MARK: - Strong's Text

    private var strongsTextView: some View {
        var result = Text("")
        let words = verse.text.split(separator: " ", omittingEmptySubsequences: false)

        for (i, word) in words.enumerated() {
            if i > 0 {
                result = Text("\(result)\(Text(" "))")
            }

            if i < verse.strongsNumbers.count, !verse.strongsNumbers[i].isEmpty {
                let styledWord = Text(String(word))
                    .font(.system(size: fontSize))
                    .foregroundStyle(Color.accentColor)
                    .underline(color: Color.accentColor.opacity(0.4))
                result = Text("\(result)\(styledWord)")
            } else {
                let styledWord = Text(String(word))
                    .font(.system(size: fontSize))
                    .foregroundStyle(.primary)
                result = Text("\(result)\(styledWord)")
            }
        }

        return result
            .textSelection(.enabled)
    }

    // MARK: - Actions

    private func addBookmark(color: BookmarkColor) async {
        let bookmark = Bookmark(
            id: UUID(),
            verseId: verseId,
            color: color,
            note: "",
            createdAt: Date()
        )
        await userDataStore.addBookmark(bookmark)
    }

    private func removeBookmark() async {
        guard let bookmark = userDataStore.bookmarks.first(where: { $0.verseId == verseId }) else { return }
        await userDataStore.deleteBookmark(id: bookmark.id)
    }

    private func addHighlight(color: BookmarkColor) async {
        let highlight = HighlightedVerse(
            id: UUID(),
            verseId: verseId,
            color: color
        )
        await userDataStore.addHighlight(highlight)
    }

    private func saveNote() async {
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existing = userDataStore.notes.first(where: { $0.verseId == verseId }) {
            await userDataStore.updateNote(id: existing.id, text: trimmed)
        } else {
            let note = Note(
                id: UUID(),
                verseId: verseId,
                text: trimmed,
                createdAt: Date(),
                updatedAt: Date()
            )
            await userDataStore.addNote(note)
        }
        showNoteEditor = false
    }

    // MARK: - Helpers

    private func swiftColor(for color: BookmarkColor) -> Color {
        switch color {
        case .yellow: return .yellow
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        }
    }
}
