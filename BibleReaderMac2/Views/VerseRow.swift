import SwiftUI

struct VerseRow: View {
    let verse: Verse
    let isSelected: Bool
    let fontSize: Double
    let fontFamily: String
    let glassNamespace: Namespace.ID
    let onSelect: () -> Void
    let onVerseNumberTap: () -> Void
    let onStrongsTap: (String) -> Void

    @Environment(UserDataStore.self) private var userDataStore
    @State private var showNoteEditor = false
    @State private var noteText = ""
    @State private var hasTextSelection = false
    @State private var selectionRect: CGRect = .zero

    private var verseId: String { verse.id }

    private var hasNote: Bool {
        userDataStore.notes.contains { $0.verseId == verseId }
    }

    private var isBookmarked: Bool {
        userDataStore.bookmarks.contains { $0.verseId == verseId }
    }

    private var isHighlighted: Bool {
        userDataStore.highlights.contains { $0.verseId == verseId }
    }

    private var highlightColor: Color? {
        guard let highlight = userDataStore.highlights.first(where: { $0.verseId == verseId }) else { return nil }
        return highlight.color.swiftUIColor
    }

    var body: some View {
        verseRowContent
            .padding(.vertical, 4)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .animation(.spring(duration: 0.25, bounce: 0.1), value: isSelected)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay { selectionOverlay }
            .contextMenu { verseContextMenu }
            .sheet(isPresented: $showNoteEditor) {
                noteEditorSheet
                    .if_available_glass_background()
            }
    }

    // MARK: - Body Subviews

    private var verseRowContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            noteButton
            bookmarkButton
            highlightButton
            verseNumberButton
            verseTextContent
        }
    }

    private var noteButton: some View {
        Button {
            let existing = userDataStore.notes.first(where: { $0.verseId == verseId })
            noteText = existing?.text ?? ""
            showNoteEditor = true
        } label: {
            Image(systemName: hasNote ? "note.text" : "note.text.badge.plus")
                .font(.system(size: fontSize * 0.55))
                .foregroundStyle(hasNote ? Color.accentColor : Color.secondary.opacity(0.4))
                .frame(width: 16, alignment: .center)
        }
        .buttonStyle(.plain)
        .help(hasNote ? String(localized: "verse.editNote") : String(localized: "verse.addNote"))
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private var bookmarkButton: some View {
        Button {
            Task {
                if isBookmarked { await removeBookmark() } else { await addBookmark(color: .yellow) }
            }
        } label: {
            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                .font(.system(size: fontSize * 0.55))
                .foregroundStyle(isBookmarked ? Color.yellow : Color.secondary.opacity(0.4))
                .frame(width: 16, alignment: .center)
                .animation(.spring(duration: 0.25, bounce: 0.1), value: isBookmarked)
        }
        .buttonStyle(.plain)
        .help(isBookmarked ? String(localized: "verse.removeBookmark") : String(localized: "verse.bookmark"))
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    @State private var showHighlightPopover = false

    @State private var highlightHovered = false

    private var highlightButton: some View {
        Button {
            Task {
                if isHighlighted {
                    await userDataStore.removeHighlight(verseId: verseId)
                } else {
                    showHighlightPopover = true
                }
            }
        } label: {
            Image(systemName: isHighlighted ? "highlighter" : "highlighter")
                .font(.system(size: fontSize * 0.55))
                .foregroundStyle(isHighlighted ? (highlightColor ?? Color.yellow) : Color.secondary.opacity(0.4))
                .padding(4)
                .background {
                    if isHighlighted || highlightHovered {
                        Group {
                            if #available(macOS 26.0, *) {
                                Circle()
                                    .fill(.clear)
                                    .glassEffect(.regular.tint((highlightColor ?? Color.yellow).opacity(isHighlighted ? 0.15 : 0.08)), in: .circle)
                            } else {
                                Circle()
                                    .fill((highlightColor ?? Color.yellow).opacity(isHighlighted ? 0.15 : 0.08))
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 24, height: 24, alignment: .center)
                .animation(.spring(duration: 0.3, bounce: 0.15), value: isHighlighted)
                .animation(.easeInOut(duration: 0.2), value: highlightHovered)
        }
        .buttonStyle(.plain)
        .help(isHighlighted ? String(localized: "verse.removeHighlight") : String(localized: "verse.highlight"))
        .onHover { hovering in
            highlightHovered = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .popover(isPresented: $showHighlightPopover, arrowEdge: .bottom) {
            HighlightBubble(
                isHighlighted: isHighlighted,
                onColorSelected: { color in
                    Task { await addHighlight(color: color) }
                    showHighlightPopover = false
                },
                onClear: {
                    Task { await userDataStore.removeHighlight(verseId: verseId) }
                    showHighlightPopover = false
                }
            )
            .padding(4)
        }
    }

    private var verseNumberButton: some View {
        Button {
            onSelect()
            onVerseNumberTap()
        } label: {
            Text("\(verse.verseNumber)")
                .font(.system(size: fontSize * 0.7, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 24, alignment: .trailing)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private var verseTextContent: some View {
        SelectableVerseText(
            text: verse.text,
            fontSize: fontSize,
            fontFamily: fontFamily,
            attributedText: verse.strongsNumbers.isEmpty ? nil : strongsAttributedString,
            onSelectionChange: { selected, rect in
                hasTextSelection = selected
                selectionRect = rect
            },
            onWordTap: { tappedValue in
                onStrongsTap(tappedValue)
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var rowBackground: some View {
        if let color = highlightColor {
            color.opacity(0.3)
        } else if isSelected {
            Color.accentColor.opacity(0.15)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var selectionOverlay: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }


    @ViewBuilder
    private var verseContextMenu: some View {
        bookmarkContextMenu
        Divider()
        highlightContextMenu
        Divider()
        noteContextMenuItem
        Divider()
        copyContextMenuItem
    }

    @ViewBuilder
    private var bookmarkContextMenu: some View {
        if isBookmarked {
            Button(role: .destructive) {
                Task { await removeBookmark() }
            } label: {
                Label(String(localized: "verse.removeBookmark"), systemImage: "bookmark.slash")
            }
        } else {
            Menu {
                ForEach(BookmarkColor.allCases, id: \.self) { color in
                    Button {
                        Task { await addBookmark(color: color) }
                    } label: {
                        Label(color.displayName, systemImage: "bookmark.fill")
                    }
                }
            } label: {
                Label(String(localized: "verse.bookmark"), systemImage: "bookmark")
            }
        }
    }

    @ViewBuilder
    private var highlightContextMenu: some View {
        if isHighlighted {
            Button(role: .destructive) {
                Task { await userDataStore.removeHighlight(verseId: verseId) }
            } label: {
                Label(String(localized: "verse.removeHighlight"), systemImage: "highlighter")
            }
        } else {
            Menu {
                ForEach(BookmarkColor.allCases, id: \.self) { color in
                    Button {
                        Task { await addHighlight(color: color) }
                    } label: {
                        Label(color.displayName, systemImage: "paintbrush.fill")
                    }
                }
            } label: {
                Label(String(localized: "verse.highlight"), systemImage: "highlighter")
            }
        }
    }

    private var noteContextMenuItem: some View {
        Button {
            let existing = userDataStore.notes.first(where: { $0.verseId == verseId })
            noteText = existing?.text ?? ""
            showNoteEditor = true
        } label: {
            let hasNote = userDataStore.notes.contains { $0.verseId == verseId }
            Label(hasNote ? String(localized: "verse.editNote") : String(localized: "verse.addNote"), systemImage: "note.text")
        }
    }

    private var copyContextMenuItem: some View {
        Button {
            let copyText = "\(verse.book) \(verse.chapter):\(verse.verseNumber) — \(verse.text)"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(copyText, forType: .string)
        } label: {
            Label(String(localized: "verse.copyVerse"), systemImage: "doc.on.doc")
        }
    }

    // MARK: - Note Editor Sheet

    private var noteEditorSheet: some View {
        VStack(spacing: 16) {
            Text("verse.noteFor \(verse.book) \(verse.chapter) \(verse.verseNumber)")
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
                        Text("verse.delete")
                    }
                }

                Spacer()

                Button(String(localized: "verse.cancel")) {
                    showNoteEditor = false
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    Task { await saveNote() }
                } label: {
                    Text("verse.save")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 360, minHeight: 240)
    }

    // MARK: - Strong's Attributed String (for NSTextView)

    private var strongsAttributedString: NSAttributedString {
        let result = NSMutableAttributedString()
        let words = verse.text.split(separator: " ", omittingEmptySubsequences: false)
        let normalFont = NSFont(name: fontFamily, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let normalColor = NSColor.labelColor

        for (i, word) in words.enumerated() {
            if i > 0 {
                result.append(NSAttributedString(string: " ", attributes: [.font: normalFont]))
            }

            if i < verse.strongsNumbers.count, !verse.strongsNumbers[i].isEmpty {
                let strongsNum = verse.strongsNumbers[i]
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: normalFont,
                    .foregroundColor: normalColor,
                    .strongsNumber: strongsNum
                ]
                result.append(NSAttributedString(string: String(word), attributes: attrs))
            } else {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: normalFont,
                    .foregroundColor: normalColor
                ]
                result.append(NSAttributedString(string: String(word), attributes: attrs))
            }
        }

        return result
    }

    // MARK: - Strong's Text (legacy, kept for reference)

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

// MARK: - Glass Background Availability Helper

private extension View {
    @ViewBuilder
    func if_available_glass_background() -> some View {
        self.presentationBackground(.ultraThinMaterial)
    }
}
