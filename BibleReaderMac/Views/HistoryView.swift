import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: BibleStore
    @EnvironmentObject var windowState: WindowState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(L("history.title"))
                    .font(.title2.weight(.semibold))
                Spacer()
                if !store.readingHistory.isEmpty {
                    Button(L("history.clear_all")) {
                        store.clearHistory()
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.borderless)
                }
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
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
                    Text(L("history.empty_title"))
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text(L("history.empty_hint"))
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
        .glassSheet()
    }

    // MARK: - Grouped by Day

    private struct HistoryGroup {
        let date: String
        let label: String
        let entries: [ReadingHistoryEntry]
    }

    private static let groupDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private var groupedHistory: [HistoryGroup] {
        let calendar = Calendar.current
        let formatter = Self.groupDateFormatter

        // readingHistory is already sorted DESC from SQLite, no need to reverse
        let reversed = store.readingHistory
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
            if key == today { label = L("history.today") }
            else if key == yesterday { label = L("history.yesterday") }
            else { label = key }
            return HistoryGroup(date: key, label: label, entries: groups[key] ?? [])
        }
    }

    private func navigateToHistory(_ entry: ReadingHistoryEntry) {
        guard let pane = windowState.panes.first else { return }
        let translationId = store.loadedTranslations.first(where: { $0.abbreviation == entry.translationAbbreviation })?.id ?? pane.translationId
        windowState.navigate(paneId: pane.id, book: entry.book, chapter: entry.chapter, translationId: translationId)
        guard let updated = windowState.panes.first else { return }
        let verses = store.loadVerses(translationId: updated.translationId, book: updated.book, chapter: updated.chapter)
        let scheme = store.versificationScheme(for: updated.translationId)
        windowState.setVerses(paneId: pane.id, verses: verses, versificationScheme: scheme)
        NotificationCenter.default.post(name: .navigateToReader, object: nil)
    }
}
