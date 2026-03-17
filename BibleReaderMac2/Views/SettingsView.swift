import SwiftUI
import UniformTypeIdentifiers

enum SettingsCategory: String, CaseIterable, Identifiable {
    case exportNotes = "Export Notes"
    case font = "Font"
    case modules = "Modules"
    case language = "Language"
    case color = "Color"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .exportNotes: return "square.and.arrow.up"
        case .font: return "textformat.size"
        case .modules: return "books.vertical"
        case .language: return "globe"
        case .color: return "paintpalette"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @Environment(UIStateStore.self) private var uiStateStore
    @Environment(BibleStore.self) private var bibleStore
    @State private var selectedCategory: SettingsCategory? = .font

    var body: some View {
        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $selectedCategory) { category in
                Label(category.rawValue, systemImage: category.icon)
                    .symbolRenderingMode(.hierarchical)
                    .tag(category)
                    .padding(.vertical, 2)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            Group {
                switch selectedCategory {
                case .exportNotes:
                    ExportNotesSettingsView()
                case .font:
                    FontSettingsView()
                case .modules:
                    ModulesSettingsView()
                case .language:
                    LanguageSettingsView()
                case .color:
                    ColorSettingsView()
                case .about:
                    AboutSettingsView()
                case nil:
                    Text("Select a category")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 700, height: 520)
    }
}

// MARK: - Export Notes

struct ExportNotesSettingsView: View {
    @State private var showWizard = false
    @State private var wizardStore = ExportWizardStore()

    var body: some View {
        if showWizard {
            ExportWizardView(onDismiss: {
                    showWizard = false
                })
                .environment(wizardStore)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            Form {
                GroupBox("Export Notes") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Export your bookmarks, highlights, and notes. Configure format and content in the export wizard.")
                            .foregroundStyle(.secondary)
                        Button("Configure Export") {
                            wizardStore = ExportWizardStore()
                            withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                                showWizard = true
                            }
                        }
                    }
                    .padding(12)
                }
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: - Font

struct FontSettingsView: View {
    @Environment(UIStateStore.self) private var uiStateStore

    var body: some View {
        @Bindable var uiState = uiStateStore

        Form {
            GroupBox("Font Size") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Size")
                        Spacer()
                        Text("\(Int(uiState.fontSize)) pt")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $uiState.fontSize, in: 12...32, step: 1)
                    HStack {
                        Text("A")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("A")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
            }

            GroupBox("Font Family") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Family", selection: $uiState.fontFamily) {
                        ForEach(NSFontManager.shared.availableFontFamilies, id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }
                    .pickerStyle(.menu)

                    Text("The quick brown fox jumps over the lazy dog.")
                        .font(.custom(uiState.fontFamily, size: uiState.fontSize))
                        .padding(.vertical, 4)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Modules

struct ModulesSettingsView: View {
    @Environment(BibleStore.self) private var bibleStore
    @Environment(UIStateStore.self) private var uiStateStore
    @State private var importError: String?
    @State private var showImportError = false

    var body: some View {
        Form {
            GroupBox("Installed Modules") {
                VStack(alignment: .leading, spacing: 4) {
                    if bibleStore.modules.isEmpty {
                        Text("No modules loaded.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(bibleStore.modules) { module in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(module.abbreviation)
                                            .fontWeight(.semibold)
                                        Text(module.name)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text("Language: \(module.language)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { uiStateStore.isModuleEnabled(module.id) },
                                    set: { _ in uiStateStore.toggleModule(module.id) }
                                ))
                                .toggleStyle(.switch)
                                .labelsHidden()
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    Divider().padding(.vertical, 4)

                    Text("User modules folder:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(ModuleManager.userModulesDirectory().path(percentEncoded: false))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Button {
                        importModule()
                    } label: {
                        Label("Import Module", systemImage: "square.and.arrow.down")
                    }
                    .padding(.top, 4)
                }
                .padding(12)
            }
        }
        .formStyle(.grouped)
        .alert("Import Error", isPresented: $showImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "Unknown error")
        }
    }

    private func importModule() {
        Task { @MainActor in
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "brbmod") ?? .data]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.message = "Select a Bible module (.brbmod) to import"

            guard panel.runModal() == .OK, let url = panel.url else { return }

            do {
                _ = try ModuleManager.importModule(from: url)
                try await bibleStore.loadModules()
            } catch {
                importError = error.localizedDescription
                showImportError = true
            }
        }
    }
}

// MARK: - Language

struct LanguageSettingsView: View {
    @Environment(UIStateStore.self) private var uiStateStore

    var body: some View {
        @Bindable var uiState = uiStateStore

        Form {
            GroupBox("Language") {
                Picker("App Language", selection: $uiState.appLanguage) {
                    Text("English").tag("en")
                    Text("Русский").tag("ru")
                }
                .pickerStyle(.radioGroup)
                .padding(12)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Color

struct ColorSettingsView: View {
    @Environment(UIStateStore.self) private var uiStateStore

    var body: some View {
        @Bindable var uiState = uiStateStore

        Form {
            GroupBox("Appearance") {
                Picker("Mode", selection: $uiState.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(12)
            }

        }
        .formStyle(.grouped)
    }
}

// MARK: - About

struct AboutSettingsView: View {
    var body: some View {
        Form {
            GroupBox("About") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("App") {
                        Text("Bible Reader")
                    }
                    LabeledContent("Version") {
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    }
                    LabeledContent("Build") {
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                    }
                    LabeledContent("Platform") {
                        Text("macOS (SwiftUI)")
                    }
                    Divider()
                    Text("A multi-pane Bible reader for macOS with support for multiple translations, Strong's numbers, cross-references, bookmarks, highlights, and notes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("GitHub: DGProjectAlpha/Bible_Reader_MacOS",
                         destination: URL(string: "https://github.com/DGProjectAlpha/Bible_Reader_MacOS")!)
                        .font(.caption)
                }
                .padding(12)
            }
        }
        .formStyle(.grouped)
    }
}
