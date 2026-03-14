import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(UIStateStore.self) private var uiStateStore
    @Environment(BibleStore.self) private var bibleStore
    @State private var installedModules: [ModuleInfo] = []
    @State private var importError: String?
    @State private var showImportError = false

    var body: some View {
        @Bindable var uiState = uiStateStore

        Form {
            Section(String(localized: "settings.appearance")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("settings.fontSize")
                        Spacer()
                        Text(String(localized: "settings.fontSizeValue \(Int(uiState.fontSize))"))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $uiState.fontSize, in: 10...40, step: 1) {
                        Text("settings.fontSize")
                    }
                    HStack {
                        Text("A")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("A")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                    }
                }

                Text("settings.sampleText")
                    .font(.system(size: uiState.fontSize))
                    .padding(.vertical, 4)
            }

            Section(String(localized: "settings.installedModules")) {
                if installedModules.isEmpty {
                    Text("settings.noModulesFound")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(installedModules) { module in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(module.id)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(module.source == .bundled ? String(localized: "settings.bundled") : String(localized: "settings.user"))
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(module.source == .bundled ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            Text(module.path.path(percentEncoded: false))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Text("settings.userModulesFolder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                Text(ModuleManager.userModulesDirectory().path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Button {
                    importModule()
                } label: {
                    Label(String(localized: "settings.importModule"), systemImage: "square.and.arrow.down")
                }
            }

            Section(String(localized: "settings.language")) {
                Picker(String(localized: "settings.language"), selection: $uiState.appLanguage) {
                    Text("settings.english").tag("en")
                    Text("settings.russian").tag("ru")
                }
            }

            Section(String(localized: "settings.about")) {
                LabeledContent(String(localized: "settings.app")) {
                    Text("settings.appName")
                }
                LabeledContent(String(localized: "settings.version")) {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
                LabeledContent(String(localized: "settings.build")) {
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                }
                LabeledContent(String(localized: "settings.platform")) {
                    Text("settings.platformValue")
                }
                Text("settings.aboutDescription")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .alert(String(localized: "settings.importError"), isPresented: $showImportError) {
            Button(String(localized: "settings.ok"), role: .cancel) {}
        } message: {
            Text(importError ?? String(localized: "settings.unknownError"))
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 400)
        .onAppear {
            installedModules = ModuleManager.discoverModules()
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
                installedModules = ModuleManager.discoverModules()
            } catch {
                importError = error.localizedDescription
                showImportError = true
            }
        }
    }
}
