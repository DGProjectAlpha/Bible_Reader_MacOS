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
    var isToolsWindowDetached: Bool = false
    var detachedPaneIds: Set<UUID> = []

    var sidebarTintColor: Color {
        get {
            let raw = UserDefaults.standard.string(forKey: "sidebarTintColor") ?? "clear"
            return Self.colorFromString(raw)
        }
        set {
            UserDefaults.standard.set(Self.stringFromColor(newValue), forKey: "sidebarTintColor")
        }
    }

    static let tintColorOptions: [(name: String, color: Color)] = [
        ("clear", .clear),
        ("blue", .blue),
        ("purple", .purple),
        ("green", .green),
        ("orange", .orange),
        ("red", .red),
        ("pink", .pink),
        ("teal", .teal)
    ]

    private static func colorFromString(_ raw: String) -> Color {
        switch raw {
        case "blue":   return .blue
        case "purple": return .purple
        case "green":  return .green
        case "orange": return .orange
        case "red":    return .red
        case "pink":   return .pink
        case "teal":   return .teal
        default:       return .clear
        }
    }

    private static func stringFromColor(_ color: Color) -> String {
        for option in tintColorOptions where option.color == color {
            return option.name
        }
        return "clear"
    }

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

    var fontFamily: String = UserDefaults.standard.string(forKey: "fontFamily") ?? "Georgia" {
        didSet { UserDefaults.standard.set(fontFamily, forKey: "fontFamily") }
    }

    var appearanceMode: AppearanceMode = {
        let raw = UserDefaults.standard.string(forKey: "appearanceMode") ?? "system"
        return AppearanceMode(rawValue: raw) ?? .system
    }() {
        didSet { UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode") }
    }

    var disabledModuleIds: Set<String> = {
        let arr = UserDefaults.standard.stringArray(forKey: "disabledModuleIds") ?? []
        return Set(arr)
    }() {
        didSet { UserDefaults.standard.set(Array(disabledModuleIds), forKey: "disabledModuleIds") }
    }

    func isModuleEnabled(_ moduleId: String) -> Bool {
        !disabledModuleIds.contains(moduleId)
    }

    func toggleModule(_ moduleId: String) {
        if disabledModuleIds.contains(moduleId) {
            disabledModuleIds.remove(moduleId)
        } else {
            disabledModuleIds.insert(moduleId)
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
