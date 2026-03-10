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
        .frame(width: 500, height: 440)
        .vibrancyBackground(material: .underWindowBackground)
    }
}

// MARK: - Display Tab

struct DisplaySettingsTab: View {
    @AppStorage("fontSize") private var fontSize: Double = 15
    @AppStorage("fontFamily") private var fontFamily: String = "System"
    @AppStorage("lineSpacing") private var lineSpacing: Double = 1.3
    @AppStorage("wordSpacing") private var wordSpacing: Double = 0.0
    @AppStorage("verseNumberStyle") private var verseNumberStyle: String = "superscript"
    @AppStorage("paragraphMode") private var paragraphMode: Bool = false
    @AppStorage("textColorHex") private var textColorHex: String = ""
    @AppStorage("backgroundColorHex") private var backgroundColorHex: String = ""

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

                HStack {
                    Text("Word Spacing")
                    Spacer()
                    Slider(value: $wordSpacing, in: -2.0...8.0, step: 0.5)
                        .frame(width: 180)
                    Text(String(format: "%+.1f", wordSpacing))
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
                    .background(RoundedRectangle(cornerRadius: 6).fill(previewBgColor))
            }
        }
        .padding()
    }

    private var previewTextColor: Color {
        Color.fromHex(textColorHex) ?? .primary
    }

    private var previewBgColor: Color {
        Color.fromHex(backgroundColorHex) ?? Color(nsColor: .controlBackgroundColor)
    }

    @ViewBuilder
    private var previewText: some View {
        let font = resolvedFont(size: CGFloat(fontSize))
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("1")
                .font(.system(size: CGFloat(fontSize) * 0.7).monospacedDigit())
                .foregroundStyle(textColorHex.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(previewTextColor.opacity(0.6)))
            Text("In the beginning God created the heaven and the earth.")
                .font(font)
                .foregroundStyle(previewTextColor)
                .lineSpacing(CGFloat(fontSize) * CGFloat(lineSpacing - 1.0))
                .tracking(CGFloat(wordSpacing))
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
    @AppStorage("textColorHex") private var textColorHex: String = ""
    @AppStorage("backgroundColorHex") private var backgroundColorHex: String = ""

    @State private var textColor: Color = .primary
    @State private var bgColor: Color = .clear
    @State private var useCustomTextColor: Bool = false
    @State private var useCustomBgColor: Bool = false

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

            Section("Custom Colors") {
                HStack {
                    Toggle("Text Color", isOn: $useCustomTextColor)
                        .onChange(of: useCustomTextColor) { enabled in
                            if !enabled {
                                textColorHex = ""
                                textColor = .primary
                            } else {
                                textColor = .primary
                                textColorHex = Color.primary.toHex() ?? ""
                            }
                        }
                    Spacer()
                    ColorPicker("", selection: $textColor, supportsOpacity: false)
                        .labelsHidden()
                        .disabled(!useCustomTextColor)
                        .opacity(useCustomTextColor ? 1.0 : 0.4)
                        .onChange(of: textColor) { newColor in
                            if useCustomTextColor {
                                textColorHex = newColor.toHex() ?? ""
                            }
                        }
                }

                HStack {
                    Toggle("Background Color", isOn: $useCustomBgColor)
                        .onChange(of: useCustomBgColor) { enabled in
                            if !enabled {
                                backgroundColorHex = ""
                                bgColor = .clear
                            } else {
                                bgColor = Color(nsColor: NSColor(calibratedRed: 1.0, green: 0.98, blue: 0.94, alpha: 1.0))
                                backgroundColorHex = bgColor.toHex() ?? ""
                            }
                        }
                    Spacer()
                    ColorPicker("", selection: $bgColor, supportsOpacity: false)
                        .labelsHidden()
                        .disabled(!useCustomBgColor)
                        .opacity(useCustomBgColor ? 1.0 : 0.4)
                        .onChange(of: bgColor) { newColor in
                            if useCustomBgColor {
                                backgroundColorHex = newColor.toHex() ?? ""
                            }
                        }
                }

                if useCustomTextColor || useCustomBgColor {
                    Button("Reset to Defaults") {
                        useCustomTextColor = false
                        useCustomBgColor = false
                        textColorHex = ""
                        backgroundColorHex = ""
                        textColor = .primary
                        bgColor = .clear
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Section("Elements") {
                Toggle("Show Chapter Titles", isOn: $showChapterTitles)
            }
        }
        .padding()
        .onAppear {
            useCustomTextColor = !textColorHex.isEmpty
            useCustomBgColor = !backgroundColorHex.isEmpty
            if let c = Color.fromHex(textColorHex) { textColor = c }
            if let c = Color.fromHex(backgroundColorHex) { bgColor = c }
        }
    }
}

// MARK: - Color Hex Helpers

extension Color {
    func toHex() -> String? {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int(round(components.redComponent * 255))
        let g = Int(round(components.greenComponent * 255))
        let b = Int(round(components.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    static func fromHex(_ hex: String) -> Color? {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let val = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((val >> 16) & 0xFF) / 255.0
        let g = Double((val >> 8) & 0xFF) / 255.0
        let b = Double(val & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
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
