import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: BibleStore
    @AppStorage("fontSize") private var fontSize: Double = 16
    @AppStorage("fontFamily") private var fontFamily: String = "System"

    var body: some View {
        TabView {
            Form {
                Section("Display") {
                    Slider(value: $fontSize, in: 10...32, step: 1) {
                        Text("Font Size: \(Int(fontSize))pt")
                    }

                    Picker("Font", selection: $fontFamily) {
                        Text("System").tag("System")
                        Text("Georgia").tag("Georgia")
                        Text("Palatino").tag("Palatino")
                        Text("Times New Roman").tag("Times New Roman")
                    }
                }

                Section("Modules") {
                    LabeledContent("Module Directory") {
                        Text(BibleStore.modulesDirectory.path(percentEncoded: false))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .tabItem { Label("General", systemImage: "gear") }
            .frame(width: 450, height: 250)
        }
        .padding()
        .vibrancyBackground(material: .underWindowBackground)
    }
}
