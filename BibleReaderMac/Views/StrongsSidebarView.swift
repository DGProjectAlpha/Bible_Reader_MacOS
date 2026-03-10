import SwiftUI

// MARK: - Strong's Concordance Sidebar

/// Displays Strong's concordance data for the selected verse.
/// Shows each tagged word with its original language, transliteration, and definition.
struct StrongsSidebarView: View {
    @EnvironmentObject var store: BibleStore
    let verseRef: String          // e.g. "Genesis 1:1"
    let verseId: String           // e.g. "Genesis:1:1"
    let translationFilePath: String
    @Binding var isVisible: Bool

    @State private var resolvedTags: [ResolvedWordTag] = []
    @State private var isLoading = false
    @State private var expandedEntry: String?  // Strong's number currently expanded
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if isLoading {
                ProgressView("Loading concordance...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if resolvedTags.isEmpty {
                emptyState
            } else {
                wordList
            }
        }
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 400)
        .vibrancyBackground(material: .sidebar)
        .onAppear { loadStrongsData() }
        .onChange(of: verseId) { _ in loadStrongsData() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Strong's Concordance")
                        .font(.headline)
                    Text(verseRef)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: { withAnimation { isVisible = false } }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Close concordance sidebar")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Search/filter within tags
            if !resolvedTags.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("Filter words...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.callout)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .glassPanel(cornerRadius: 6, material: .headerView)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .glassHeader()
    }

    // MARK: - Word List

    private var wordList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(filteredTags) { resolved in
                    StrongsWordRow(
                        resolved: resolved,
                        isExpanded: expandedEntry == resolved.strongsNumbers.first,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                let num = resolved.strongsNumbers.first
                                expandedEntry = (expandedEntry == num) ? nil : num
                            }
                        }
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var filteredTags: [ResolvedWordTag] {
        guard !searchText.isEmpty else { return resolvedTags }
        let query = searchText.lowercased()
        return resolvedTags.filter { tag in
            tag.word.lowercased().contains(query) ||
            tag.strongsNumbers.joined().lowercased().contains(query) ||
            tag.primaryEntry?.lemma.lowercased().contains(query) == true ||
            tag.primaryEntry?.transliteration.lowercased().contains(query) == true
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)
            Text("No Strong's Data")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Text("This verse has no Strong's concordance tags. Try a tagged translation like KJV.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    private func loadStrongsData() {
        isLoading = true
        expandedEntry = nil
        searchText = ""

        DispatchQueue.global(qos: .userInitiated).async {
            let tags = StrongsService.entriesForVerse(
                verseId: verseId,
                filePath: translationFilePath
            )
            DispatchQueue.main.async {
                resolvedTags = tags
                isLoading = false
            }
        }
    }
}

// MARK: - Single Word Row

struct StrongsWordRow: View {
    let resolved: ResolvedWordTag
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Compact row — always visible
            HStack(spacing: 8) {
                // Word from the verse text
                Text(resolved.word)
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .foregroundStyle(.primary)

                Spacer()

                // Strong's number badge(s)
                ForEach(resolved.strongsNumbers, id: \.self) { num in
                    Text(num)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(strongsBadgeColor(num))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)

            // Expanded detail — shows when tapped
            if isExpanded {
                expandedDetail
            }
        }
        .background(isExpanded ? Color.accentColor.opacity(0.06) : Color.clear)
        .background(isExpanded ? .ultraThinMaterial : .regularMaterial, in: Rectangle())
    }

    // MARK: - Expanded Detail

    @ViewBuilder
    private var expandedDetail: some View {
        if let entry = resolved.primaryEntry {
            VStack(alignment: .leading, spacing: 8) {
                // Original word + transliteration
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Original")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(entry.lemma)
                            .font(.system(size: 22, design: .serif))
                            .foregroundStyle(.primary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Transliteration")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(entry.transliteration)
                            .font(.system(size: 14).italic())
                            .foregroundStyle(.primary)
                    }
                }

                // Pronunciation
                if let pron = entry.pronunciation, !pron.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pronunciation")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(pron)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                // Strong's definition
                if let def = entry.strongsDefinition, !def.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Definition")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(cleanDefinition(def))
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // KJV usage
                if let kjv = entry.kjvDefinition, !kjv.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("KJV Usage")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(kjv)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Derivation
                if let deriv = entry.derivation, !deriv.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Derivation")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(deriv)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Testament indicator
                HStack(spacing: 4) {
                    Image(systemName: entry.testament == .old ? "textformat.abc" : "textformat.abc.dottedunderline")
                        .font(.caption2)
                    Text(entry.testament == .old ? "Hebrew (OT)" : "Greek (NT)")
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)
                .padding(.top, 2)

                // Show additional entries if compound word
                if resolved.entries.count > 1 {
                    Divider()
                    ForEach(resolved.entries.dropFirst(), id: \.number) { extra in
                        additionalEntryRow(extra)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
            // No entry data resolved
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("Concordance entry not found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private func additionalEntryRow(_ entry: StrongsEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.number)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(strongsBadgeColor(entry.number))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                Text(entry.lemma)
                    .font(.system(size: 16, design: .serif))

                Text("(\(entry.transliteration))")
                    .font(.caption.italic())
                    .foregroundStyle(.secondary)
            }

            if let def = entry.strongsDefinition {
                Text(cleanDefinition(def))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func strongsBadgeColor(_ number: String) -> Color {
        number.hasPrefix("H") ? .indigo : .teal
    }

    /// Strip HTML-like tags from Strong's definitions.
    private func cleanDefinition(_ raw: String) -> String {
        raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
