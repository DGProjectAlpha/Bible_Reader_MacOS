import Foundation
import SwiftUI

@MainActor @Observable
final class UIStateStore {
    var sidebarVisibility: NavigationSplitViewVisibility = .automatic
    var selectedVerseId: String? = nil
    var searchQuery: String = ""
    var searchResults: [Verse] = []
    var searchModuleId: String = ""
    var expandedSidebarSections: Set<String> = []
    var inspectorTab: InspectorTab = .strongs
    var inspectorVisible: Bool = false
    var selectedStrongsId: String? = nil
    var selectedStrongsWord: String? = nil

    @ObservationIgnored @AppStorage("appLanguage") var appLanguage: String = "en"

    var fontSize: Double = UserDefaults.standard.double(forKey: "fontSize") == 0
        ? 16.0
        : UserDefaults.standard.double(forKey: "fontSize")
    {
        didSet {
            let clamped = max(10, min(40, fontSize))
            if clamped != fontSize { fontSize = clamped; return }
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
            let moduleId = searchModuleId.isEmpty ? bibleStore.activeModuleId : searchModuleId
            searchResults = try await bibleStore.searchVerses(
                moduleId: moduleId,
                query: searchQuery
            )
        } catch {
            searchResults = []
        }
    }
}
