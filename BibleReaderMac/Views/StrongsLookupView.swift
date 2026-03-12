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
        case all = "all"
        case old = "old"
        case new = "new"

        var label: String {
            switch self {
            case .all: return L("strongs_lookup.all")
            case .old: return L("strongs_lookup.hebrew")
            case .new: return L("strongs_lookup.greek")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(L("strongs_lookup.placeholder"), text: $searchText)
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

                Picker(L("strongs_lookup.testament"), selection: $testament) {
                    ForEach(TestamentFilter.allCases, id: \.self) { t in
                        Text(t.label).tag(t)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            if isSearching {
                ProgressView(L("strongs_lookup.searching"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lookupResults.isEmpty && !searchText.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(.quaternary)
                    Text(L("strongs_lookup.no_results"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(L("strongs_lookup.try_hint"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lookupResults.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "character.book.closed")
                        .font(.system(size: 48))
                        .foregroundStyle(.quaternary)
                    Text(L("strongs_lookup.title"))
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text(L("strongs_lookup.intro"))
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
                        Text(L("strongs_lookup.select_entry"))
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .navigationTitle(L("strongs_lookup.nav_title"))
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
                    labeledField(L("strongs.transliteration"), entry.transliteration)
                    if let pron = entry.pronunciation {
                        labeledField(L("strongs.pronunciation"), pron)
                    }
                }

                Divider()

                // Definition
                if let def = entry.strongsDefinition {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("strongs.definition"))
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
                        Text(L("strongs.kjv_usage"))
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
                        Text(L("strongs.derivation"))
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
                    Text(entry.testament == .old ? L("strongs.hebrew") : L("strongs.greek"))
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
