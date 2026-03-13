import SwiftUI

struct SettingsView: View {
    @Environment(UIStateStore.self) private var uiStateStore
    @State private var installedModules: [ModuleInfo] = []

    var body: some View {
        @Bindable var uiState = uiStateStore

        Form {
            Section("Appearance") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Font Size")
                        Spacer()
                        Text("\(Int(uiState.fontSize)) pt")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $uiState.fontSize, in: 10...40, step: 1) {
                        Text("Font Size")
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

                Text("The quick brown fox jumps over the lazy dog.")
                    .font(.system(size: uiState.fontSize))
                    .padding(.vertical, 4)
            }

            Section("Installed Modules") {
                if installedModules.isEmpty {
                    Text("No modules found")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(installedModules) { module in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(module.id)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(module.source == .bundled ? "Bundled" : "User")
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

                Text("User modules folder:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                Text(ModuleManager.userModulesDirectory().path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section("About") {
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
                Text("A fast, offline Bible reader with Strong's concordance support.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 400)
        .onAppear {
            installedModules = ModuleManager.discoverModules()
        }
    }
}
