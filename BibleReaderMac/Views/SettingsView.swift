import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: BibleStore

    var body: some View {
        TabView {
            DisplaySettingsTab()
                .tabItem { Label("Display", systemImage: "textformat") }

            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            GeneralSettingsTab()
                .environmentObject(store)
                .tabItem { Label("General", systemImage: "gear") }
        }
        .frame(width: 500, height: 380)
        .vibrancyBackground(material: .underWindowBackground)
    }
}

// MARK: - Display Tab

struct DisplaySettingsTab: View {
    @AppStorage("fontSize") private var fontSize: Double = 15
    @AppStorage("fontFamily") private var fontFamily: String = "System"
    @AppStorage("lineSpacing") private var lineSpacing: Double = 1.3
    @AppStorage("verseNumberStyle") private var verseNumberStyle: String = "superscript"
    @AppStorage("paragraphMode") private var paragraphMode: Bool = false

    private let fontOptions = ["System", "Georgia", "Palatino", "Times New Roman", "Baskerville", "Charter", "Iowan Old Style"]

    var body: some View {
        Form {
            Section("Font") {
                Picker("Family", selection: $fontFamily) {
                    ForEach(fontOptions, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }

                HStack {
                    Slider(value: $fontSize, in: 10...36, step: 1)
                    Text("\(Int(fontSize))pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }

                HStack {
                    Text("Line Spacing")
                    Spacer()
                    Slider(value: $lineSpacing, in: 1.0...2.5, step: 0.1)
                        .frame(width: 180)
                    Text(String(format: "%.1f×", lineSpacing))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }

            Section("Layout") {
                Picker("Verse Numbers", selection: $verseNumberStyle) {
                    Text("Superscript").tag("superscript")
                    Text("Inline").tag("inline")
                    Text("Margin").tag("margin")
                }

                Toggle("Paragraph Mode (no line breaks between verses)", isOn: $paragraphMode)
            }

            Section("Preview") {
                previewText
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.background))
            }
        }
        .padding()
    }

    @ViewBuilder
    private var previewText: some View {
        let font = resolvedFont(size: CGFloat(fontSize))
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("1")
                .font(.system(size: CGFloat(fontSize) * 0.7).monospacedDigit())
                .foregroundStyle(.secondary)
            Text("In the beginning God created the heaven and the earth.")
                .font(font)
                .lineSpacing(CGFloat(fontSize) * CGFloat(lineSpacing - 1.0))
        }
    }

    private func resolvedFont(size: CGFloat) -> Font {
        if fontFamily == "System" {
            return .system(size: size, design: .serif)
        }
        return .custom(fontFamily, size: size)
    }
}

// MARK: - Appearance Tab

struct AppearanceSettingsTab: View {
    @AppStorage("readerTheme") private var readerTheme: String = "auto"
    @AppStorage("accentColorName") private var accentColorName: String = "blue"
    @AppStorage("verseHighlightOpacity") private var verseHighlightOpacity: Double = 0.12
    @AppStorage("showChapterTitles") private var showChapterTitles: Bool = true

    private let themeOptions = [
        ("auto", "System Default"),
        ("light", "Light"),
        ("dark", "Dark"),
        ("sepia", "Sepia")
    ]

    private let accentOptions = [
        ("blue", Color.blue),
        ("purple", Color.purple),
        ("indigo", Color.indigo),
        ("brown", Color.brown),
        ("red", Color.red),
        ("green", Color.green)
    ]

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $readerTheme) {
                    ForEach(themeOptions, id: \.0) { value, label in
                        Text(label).tag(value)
                    }
                }
            }

            Section("Colors") {
                HStack {
                    Text("Accent Color")
                    Spacer()
                    ForEach(accentOptions, id: \.0) { name, color in
                        Circle()
                            .fill(color)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle()
                                    .strokeBorder(name == accentColorName ? Color.primary : Color.clear, lineWidth: 2)
                            )
                            .onTapGesture { accentColorName = name }
                    }
                }

                HStack {
                    Text("Verse Highlight Intensity")
                    Spacer()
                    Slider(value: $verseHighlightOpacity, in: 0.05...0.3, step: 0.01)
                        .frame(width: 160)
                }
            }

            Section("Elements") {
                Toggle("Show Chapter Titles", isOn: $showChapterTitles)
            }
        }
        .padding()
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @EnvironmentObject var store: BibleStore
    @AppStorage("restoreLastPosition") private var restoreLastPosition: Bool = true
    @AppStorage("defaultTranslation") private var defaultTranslation: String = ""

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Restore last reading position on launch", isOn: $restoreLastPosition)

                Picker("Default Translation", selection: $defaultTranslation) {
                    Text("Last Used").tag("")
                    ForEach(store.loadedTranslations) { t in
                        Text(t.abbreviation).tag(t.abbreviation)
                    }
                }
            }

            Section("Modules") {
                LabeledContent("Module Directory") {
                    Text(BibleStore.modulesDirectory.path(percentEncoded: false))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: BibleStore.modulesDirectory.path(percentEncoded: false))
                }
            }
        }
        .padding()
    }
}
