import Foundation
import SwiftUI

@MainActor @Observable
final class UIStateStore {
    var sidebarVisible: Bool = true
    var selectedVerseId: String? = nil
    var searchQuery: String = ""
    var searchResults: [Verse] = []
    var expandedSidebarSections: Set<String> = []

    var fontSize: Double = UserDefaults.standard.double(forKey: "fontSize") == 0
        ? 16.0
        : UserDefaults.standard.double(forKey: "fontSize")
    {
        didSet {
            fontSize = max(10, min(40, fontSize))
            UserDefaults.standard.set(fontSize, forKey: "fontSize")
        }
    }

    func isSectionExpanded(_ section: SidebarSection) -> Bool {
        expandedSidebarSections.contains(section.rawValue)
    }

    func toggleSection(_ section: SidebarSection) {
        if expandedSidebarSections.contains(section.rawValue) {
            expandedSidebarSections.remove(section.rawValue)
        } else {
            expandedSidebarSections.insert(section.rawValue)
        }
    }

    func bindingForSection(_ section: SidebarSection) -> Binding<Bool> {
        Binding(
            get: { self.expandedSidebarSections.contains(section.rawValue) },
            set: { newValue in
                if newValue {
                    self.expandedSidebarSections.insert(section.rawValue)
                } else {
                    self.expandedSidebarSections.remove(section.rawValue)
                }
            }
        )
    }

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
