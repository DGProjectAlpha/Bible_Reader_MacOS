import SwiftUI

// MARK: - Cross-Reference Navigation View

/// A TSK cross-reference with resolved verse text for display.
struct TSKDisplayRef: Identifiable {
    let id = UUID()
    let book: String
    let chapter: Int
    let verse: Int
    let verseId: String       // "Book:Chapter:Verse"
    let label: String         // "John 3:16"
    let verseText: String     // Actual verse text from loaded module
    let translationAbbr: String
}

struct CrossReferenceView: View {
    @EnvironmentObject var store: BibleStore
    @State private var tskRefs: [TSKDisplayRef] = []
    @State private var isLoading = false
    @State private var selectedVerseId: String?
    @State private var manualRefInput: String = ""
    @State private var navigationHistory: [String] = []  // stack of verse IDs

    /// Optional initial verse ID to load on appear (used when embedded in inspector)
    var initialVerseId: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .vibrancyBackground(material: .contentBackground, blendingMode: .behindWindow)
        .onAppear {
            if let verseId = initialVerseId, selectedVerseId == nil {
                navigateToRef(verseId)
            }
        }
        .onChange(of: initialVerseId) {
            if let verseId = initialVerseId {
                navigateToRef(verseId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .crossRefLookup)) { notification in
            if let verseId = notification.userInfo?["verseId"] as? String {
                navigateToRef(verseId)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(.secondary)
                Text("Cross References")
                    .font(.headline)
                Spacer()

                if !navigationHistory.isEmpty {
                    Button(action: navigateBack) {
                        Image(systemName: "chevron.left")
                            .font(.caption.weight(.semibold))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help("Go back to previous verse")
                }
            }

            // Current verse display
            if let verseId = selectedVerseId {
                HStack {
                    Text(formatVerseId(verseId))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    Button("Open in Reader") {
                        navigateReaderTo(verseId: verseId)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }

            // Manual verse reference input
            HStack(spacing: 6) {
                TextField("Enter verse (e.g. John 3:16)", text: $manualRefInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    .onSubmit { lookupManualRef() }

                Button("Look Up") { lookupManualRef() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(manualRefInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassHeader()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if selectedVerseId == nil {
            emptyState
        } else if isLoading {
            ProgressView("Loading cross-references...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if tskRefs.isEmpty {
            noRefsState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    sectionHeader("Cross References (TSK)", count: tskRefs.count)
                    ForEach(tskRefs) { ref in
                        tskRefRow(ref)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            Text("\(count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1), in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .padding(.top, 4)
    }

    // MARK: - TSK Reference Row

    private func tskRefRow(_ ref: TSKDisplayRef) -> some View {
        Button(action: {
            navigateReaderTo(verseId: ref.verseId)
        }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    // Target verse reference
                    Text(ref.label)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color.accentColor)

                    Spacer()

                    // Module badge
                    Text(ref.translationAbbr)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))

                    Image(systemName: "arrow.right.circle")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Verse text preview
                if !ref.verseText.isEmpty {
                    Text(ref.verseText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.clear)
        .onHover { isHovered in
            if isHovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    // MARK: - Empty / No-Results States

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("Cross References")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("Enter a verse reference above, or tap a verse\nin the reader to see its cross-references.")
                .font(.callout)
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noRefsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)
            Text("No cross-references found")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Text("This verse has no cross-references\nin the loaded modules.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Navigation

    /// Navigate to a cross-referenced verse — push current onto history, load new refs.
    private func navigateToRef(_ verseId: String) {
        if let current = selectedVerseId {
            navigationHistory.append(current)
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedVerseId = verseId
        }
        loadCrossReferences(for: verseId)
    }

    /// Go back in navigation history.
    private func navigateBack() {
        guard let previous = navigationHistory.popLast() else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedVerseId = previous
        }
        loadCrossReferences(for: previous)
    }

    /// Navigate the main reader to show the target verse.
    private func navigateReaderTo(verseId: String) {
        guard let parts = parseVerseId(verseId) else { return }
        NotificationCenter.default.post(
            name: .navigateToVerse,
            object: nil,
            userInfo: [
                "book": parts.book,
                "chapter": parts.chapter,
                "verse": parts.verse
            ]
        )
        // Also switch to reader view
        NotificationCenter.default.post(name: .navigateToReader, object: nil)
    }

    /// Parse manual input like "John 3:16" or "1 Corinthians 13:4" into a verse ID.
    private func lookupManualRef() {
        let input = manualRefInput.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }

        if let verseId = parseHumanReference(input) {
            navigateToRef(verseId)
            manualRefInput = ""
        }
    }

    // MARK: - Data Loading

    private func loadCrossReferences(for verseId: String) {
        isLoading = true
        let translations = store.loadedTranslations.map {
            (filePath: $0.filePath, abbreviation: $0.abbreviation)
        }

        Task.detached {
            let rawRefs = TSKService.getRefs(for: verseId)

            // Use first loaded translation for verse text
            let primaryTranslation = translations.first

            let displayRefs: [TSKDisplayRef] = rawRefs.map { ref in
                var verseText = ""
                var translationAbbr = ""

                if let primary = primaryTranslation,
                   let conn = try? ModuleConnectionPool.shared.connection(for: primary.filePath),
                   let verses = try? conn.loadVerses(book: ref.book, chapter: ref.chapter),
                   let verse = verses.first(where: { $0.number == ref.verse }) {
                    verseText = verse.text
                    translationAbbr = primary.abbreviation
                }

                return TSKDisplayRef(
                    book: ref.book,
                    chapter: ref.chapter,
                    verse: ref.verse,
                    verseId: ref.verseId,
                    label: ref.label,
                    verseText: verseText,
                    translationAbbr: translationAbbr
                )
            }

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    tskRefs = displayRefs
                    isLoading = false
                }
            }
        }
    }

    private func formatVerseId(_ verseId: String) -> String {
        guard let parts = parseVerseId(verseId) else { return verseId }
        return "\(parts.book) \(parts.chapter):\(parts.verse)"
    }

    private func parseVerseId(_ verseId: String) -> (book: String, chapter: Int, verse: Int)? {
        let parts = verseId.components(separatedBy: ":")
        guard parts.count >= 3,
              let chapter = Int(parts[parts.count - 2]),
              let verse = Int(parts[parts.count - 1]) else { return nil }
        let book = parts.dropLast(2).joined(separator: ":")
        guard !book.isEmpty else { return nil }
        return (book, chapter, verse)
    }

    /// Parse human-readable references like "John 3:16", "1 Corinthians 13:4", "Genesis 1:1"
    private func parseHumanReference(_ input: String) -> String? {
        // Split on last space-before-chapter:verse pattern
        // Match: "BookName Chapter:Verse"
        let pattern = /^(.+?)\s+(\d+):(\d+)$/
        guard let match = input.firstMatch(of: pattern) else { return nil }

        let bookInput = String(match.1).trimmingCharacters(in: .whitespaces)
        guard let chapter = Int(match.2), let verse = Int(match.3) else { return nil }

        // Fuzzy-match book name against BibleBooks.all
        let bookName = BibleBooks.all.first { book in
            book.localizedCaseInsensitiveCompare(bookInput) == .orderedSame
        } ?? BibleBooks.all.first { book in
            book.localizedCaseInsensitiveContains(bookInput) ||
            bookInput.localizedCaseInsensitiveContains(book)
        }

        guard let resolvedBook = bookName else { return nil }
        return "\(resolvedBook):\(chapter):\(verse)"
    }
}
