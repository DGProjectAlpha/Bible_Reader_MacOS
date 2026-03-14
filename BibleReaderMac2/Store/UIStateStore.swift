import Foundation
import SwiftUI

@MainActor @Observable
final class UIStateStore {
    var sidebarVisibility: NavigationSplitViewVisibility = .automatic
    var selectedVerseId: String? = nil
    var searchQuery: String = ""
    var searchResults: [SearchResult] = []
    var searchModuleId: String = ""  // empty = all modules
    var expandedSidebarSections: Set<String> = []
    var inspectorTab: InspectorTab = .strongs
    var inspectorVisible: Bool = false
    var selectedStrongsId: String? = nil
    var selectedStrongsWord: String? = nil

    var appLanguage: String = UserDefaults.standard.string(forKey: "appLanguage") ?? "en" {
        didSet { UserDefaults.standard.set(appLanguage, forKey: "appLanguage") }
    }

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
        // Search only modules that are currently open in panes
        let openModuleIds = Set(bibleStore.panes.map { $0.location.moduleId })
        var allResults: [SearchResult] = []
        for moduleId in openModuleIds {
            do {
                let verses = try await bibleStore.searchVerses(
                    moduleId: moduleId,
                    query: searchQuery
                )
                let module = bibleStore.modules.first(where: { $0.id == moduleId })
                let results = verses.map { verse in
                    SearchResult(
                        id: "\(moduleId):\(verse.id)",
                        moduleId: moduleId,
                        moduleName: module?.abbreviation ?? moduleId,
                        verse: verse
                    )
                }
                allResults.append(contentsOf: results)
            } catch {
                // skip failed module
            }
        }
        searchResults = allResults
    }
}
