import SwiftUI

struct SearchView: View {
    @Environment(BibleStore.self) private var bibleStore
    @Environment(UIStateStore.self) private var uiState

    var body: some View {
        @Bindable var uiState = uiState

        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "search.searchIn \(activeModuleName)"), text: $uiState.searchQuery)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        Task {
                            await uiState.performSearch(using: bibleStore)
                        }
                    }
                if !uiState.searchQuery.isEmpty {
                    Button {
                        uiState.searchQuery = ""
                        uiState.searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)

            Divider()

            // Results
            if uiState.searchResults.isEmpty && !uiState.searchQuery.isEmpty {
                ContentUnavailableView(String(localized: "search.noResults"), systemImage: "magnifyingglass", description: Text(String(localized: "search.noVersesMatch \(uiState.searchQuery)")))
                    .frame(maxHeight: .infinity)
            } else {
                List(uiState.searchResults) { result in
                    Button {
                        navigateToVerse(result)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verseReference(result))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            Text(result.verse.text)
                                .font(.body)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 350, idealWidth: 450, minHeight: 300, idealHeight: 500)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private var activeModuleName: String {
        bibleStore.modules.first(where: { $0.id == bibleStore.activeModuleId })?.abbreviation ?? "Bible"
    }

    private func verseReference(_ result: SearchResult) -> String {
        let v = result.verse
        let bookName = bibleStore.modules
            .first(where: { $0.id == result.moduleId })?
            .books.first(where: { $0.id == v.book })?.name ?? v.book
        return "\(result.moduleName) — \(bookName) \(v.chapter):\(v.verseNumber)"
    }

    private func navigateToVerse(_ result: SearchResult) {
        let v = result.verse
        guard let paneId = bibleStore.activePaneId else { return }
        let location = BibleLocation(
            moduleId: result.moduleId,
            book: v.book,
            chapter: v.chapter,
            verseNumber: v.verseNumber
        )
        Task {
            await bibleStore.navigate(paneId: paneId, to: location)
        }
        // Search is now inline in sidebar, no sheet to dismiss
    }
}
