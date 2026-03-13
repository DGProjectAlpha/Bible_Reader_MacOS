import Foundation
import SwiftUI

@MainActor @Observable
final class UIStateStore {
    var sidebarVisible: Bool = true
    var inspectorVisible: Bool = false
    var searchVisible: Bool = false
    var selectedVerseId: String? = nil
    var inspectorTab: InspectorTab = .strongs
    var searchQuery: String = ""
    var searchResults: [Verse] = []

    @ObservationIgnored
    @AppStorage("fontSize") var fontSize: Double = 16.0

    func performSearch(using bibleStore: BibleStore) async {
        guard !searchQuery.isEmpty else {
            searchResults = []
            return
        }
        do {
            searchResults = try await bibleStore.searchVerses(
                moduleId: bibleStore.activeModuleId,
                query: searchQuery
            )
        } catch {
            searchResults = []
        }
    }
}
