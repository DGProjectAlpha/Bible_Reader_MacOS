import SwiftUI

// MARK: - Standalone Strong's Lookup View

/// Full-page Strong's concordance browser accessible from the sidebar.
/// Allows searching by Strong's number, transliteration, or English keyword.
struct StrongsLookupView: View {
    @EnvironmentObject var store: BibleStore
    @State private var searchText = ""
    @State private var selectedEntry: StrongsEntry?
    @State private var lookupResults: [StrongsEntry] = []
    @State private var isSearching = false
    @State private var testament: TestamentFilter = .all

    enum TestamentFilter: String, CaseIterable {
        case all = "All"
        case old = "Hebrew (OT)"
        case new = "Greek (NT)"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Strong's number (H1234, G3056) or word...", text: $searchText)
                        .textFieldStyle(.plain)
                        .onSubmit { performLookup() }

                    if !searchText.isEmpty {
                        Button(action: { withAnimation(.easeOut(duration: 0.2)) { searchText = ""; lookupResults = []; selectedEntry = nil } }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassPanel(cornerRadius: 8, material: .headerView)

                Picker("Testament", selection: $testament) {
                    ForEach(TestamentFilter.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            if isSearching {
                ProgressView("Searching...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lookupResults.isEmpty && !searchText.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(.quaternary)
                    Text("No results found")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Try a Strong's number like H7225 or G3056")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lookupResults.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "character.book.closed")
                        .font(.system(size: 48))
                        .foregroundStyle(.quaternary)
                    Text("Strong's Concordance")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("Search by number (H1234) or word to look up Hebrew/Greek definitions.\nOr tap any verse in the Reader to see its Strong's tags.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Results list + detail split
                HSplitView {
                    // Results list
                    List(lookupResults, selection: $selectedEntry) { entry in
                        HStack(spacing: 8) {
                            Text(entry.number)
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(entry.number.hasPrefix("H") ? Color.indigo : Color.teal)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 4))

                            Text(entry.lemma)
                                .font(.system(size: 14, design: .serif))

                            Text(entry.transliteration)
                                .font(.caption.italic())
                                .foregroundStyle(.secondary)

                            Spacer()
                        }
                        .tag(entry)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { selectedEntry = entry } }
                    }
                    .listStyle(.plain)
                    .frame(minWidth: 250, idealWidth: 300)

                    // Detail pane
                    if let entry = selectedEntry {
                        StrongsDetailView(entry: entry)
                    } else {
                        Text("Select an entry")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .navigationTitle("Strong's Concordance")
    }

    private func performLookup() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        // Direct number lookup
        let upperQuery = query.uppercased()
        if upperQuery.hasPrefix("H") || upperQuery.hasPrefix("G"),
           let _ = Int(upperQuery.dropFirst()) {
            directLookup(upperQuery)
            return
        }

        // Otherwise search is not yet supported without a full concordance index
        // Try treating as a number with prefix based on testament filter
        if let num = Int(query) {
            var results: [StrongsEntry] = []
            if testament != .new {
                directLookup("H\(num)", appendTo: &results)
            }
            if testament != .old {
                directLookup("G\(num)", appendTo: &results)
            }
            lookupResults = results
            selectedEntry = results.first
        }
    }

    private func directLookup(_ number: String) {
        guard let filePath = store.loadedTranslations.first?.filePath else { return }
        if let entry = StrongsService.lookup(number, in: filePath) {
            lookupResults = [entry]
            selectedEntry = entry
        } else {
            lookupResults = []
            selectedEntry = nil
        }
    }

    private func directLookup(_ number: String, appendTo results: inout [StrongsEntry]) {
        guard let filePath = store.loadedTranslations.first?.filePath else { return }
        if let entry = StrongsService.lookup(number, in: filePath) {
            results.append(entry)
        }
    }
}

// MARK: - Strong's Detail View

struct StrongsDetailView: View {
    let entry: StrongsEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(entry.number)
                        .font(.title2.monospacedDigit().weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(entry.number.hasPrefix("H") ? Color.indigo : Color.teal)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Text(entry.lemma)
                        .font(.system(size: 36, design: .serif))

                    Spacer()
                }

                // Transliteration + pronunciation
                VStack(alignment: .leading, spacing: 6) {
                    labeledField("Transliteration", entry.transliteration)
                    if let pron = entry.pronunciation {
                        labeledField("Pronunciation", pron)
                    }
                }

                Divider()

                // Definition
                if let def = entry.strongsDefinition {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Strong's Definition")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(cleanDef(def))
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // KJV usage
                if let kjv = entry.kjvDefinition {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("KJV Translation Usage")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(kjv)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Derivation
                if let deriv = entry.derivation {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Derivation")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(deriv)
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Testament
                HStack(spacing: 6) {
                    Image(systemName: entry.testament == .old ? "textformat.abc" : "textformat.abc.dottedunderline")
                    Text(entry.testament == .old ? "Hebrew (Old Testament)" : "Greek (New Testament)")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)

                Spacer()
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func labeledField(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)
            Text(value)
                .font(.callout.italic())
        }
    }

    private func cleanDef(_ raw: String) -> String {
        raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
