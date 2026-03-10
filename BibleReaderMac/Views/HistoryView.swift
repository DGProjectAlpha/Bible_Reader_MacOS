import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: BibleStore

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Reading History")
                    .font(.title2.weight(.semibold))
                Spacer()
                if !store.readingHistory.isEmpty {
                    Button("Clear All") {
                        store.clearHistory()
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            if store.readingHistory.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock")
                        .font(.system(size: 48))
                        .foregroundStyle(.quaternary)
                    Text("No Reading History")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("Your reading history will appear here as you navigate chapters.")
                        .font(.callout)
                        .foregroundStyle(.quaternary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groupedHistory, id: \.date) { group in
                        Section(group.label) {
                            ForEach(group.entries) { entry in
                                HistoryRow(entry: entry)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        navigateToHistory(entry)
                                    }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Grouped by Day

    private struct HistoryGroup {
        let date: String
        let label: String
        let entries: [ReadingHistoryEntry]
    }

    private var groupedHistory: [HistoryGroup] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let reversed = store.readingHistory.reversed()
        var groups: [String: [ReadingHistoryEntry]] = [:]
        var order: [String] = []

        for entry in reversed {
            let key = formatter.string(from: entry.timestamp)
            if groups[key] == nil {
                order.append(key)
                groups[key] = []
            }
            groups[key]?.append(entry)
        }

        let today = formatter.string(from: Date())
        let yesterday = formatter.string(from: calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date())

        return order.map { key in
            let label: String
            if key == today { label = "Today" }
            else if key == yesterday { label = "Yesterday" }
            else { label = key }
            return HistoryGroup(date: key, label: label, entries: groups[key] ?? [])
        }
    }

    private func navigateToHistory(_ entry: ReadingHistoryEntry) {
        guard let pane = store.panes.first else { return }
        if let translation = store.loadedTranslations.first(where: { $0.abbreviation == entry.translationAbbreviation }) {
            pane.selectedTranslationId = translation.id
        }
        pane.selectedBook = entry.book
        pane.selectedChapter = entry.chapter
        store.loadVerses(for: pane)
        NotificationCenter.default.post(name: .navigateToReader, object: nil)
    }
}
