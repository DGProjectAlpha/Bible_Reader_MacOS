import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: BibleStore

    var body: some View {
        TabView {
            DisplaySettingsTab()
                .tabItem { Label(L("settings.tab.display"), systemImage: "textformat") }

            AppearanceSettingsTab()
                .tabItem { Label(L("settings.tab.appearance"), systemImage: "paintbrush") }

            ReadingSettingsTab()
                .tabItem { Label(L("settings.tab.reading"), systemImage: "book") }

            ProfileSettingsTab()
                .environmentObject(store)
                .tabItem { Label(L("settings.tab.profiles"), systemImage: "person.2") }

            GeneralSettingsTab()
                .environmentObject(store)
                .tabItem { Label(L("settings.tab.general"), systemImage: "gear") }
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 400, idealHeight: 480)
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
            Section(L("settings.font")) {
                Picker(L("settings.font_family"), selection: $fontFamily) {
                    ForEach(fontOptions, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }

                HStack {
                    Text(L("settings.font_size"))
                    Slider(value: $fontSize, in: 10...36, step: 1)
                    Text("\(Int(fontSize))\(L("settings.font_size_pt"))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }

                HStack {
                    Text(L("settings.line_spacing"))
                    Spacer()
                    Slider(value: $lineSpacing, in: 1.0...2.5, step: 0.1)
                        .frame(width: 180)
                    Text(String(format: "%.1f×", lineSpacing))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }

                HStack {
                    Text(L("settings.word_spacing"))
                    Spacer()
                    Slider(value: $wordSpacing, in: -2.0...8.0, step: 0.5)
                        .frame(width: 180)
                    Text(String(format: "%+.1f", wordSpacing))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }

            Section(L("settings.layout")) {
                Picker(L("settings.verse_numbers"), selection: $verseNumberStyle) {
                    Text(L("settings.superscript")).tag("superscript")
                    Text(L("settings.inline")).tag("inline")
                    Text(L("settings.margin")).tag("margin")
                }

                Toggle(L("settings.paragraph_mode"), isOn: $paragraphMode)
            }

            Section(L("settings.preview")) {
                previewText
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(previewBgColor))
            }

            Section {
                Button(L("settings.reset_display")) {
                    fontSize = 15
                    fontFamily = "System"
                    lineSpacing = 1.3
                    wordSpacing = 0.0
                    verseNumberStyle = "superscript"
                    paragraphMode = false
                }
                .foregroundStyle(.secondary)
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
    @AppStorage("verseHighlightOpacity") private var verseHighlightOpacity: Double = 0.3
    @AppStorage("showChapterTitles") private var showChapterTitles: Bool = true
    @AppStorage("textColorHex") private var textColorHex: String = ""
    @AppStorage("backgroundColorHex") private var backgroundColorHex: String = ""

    @State private var textColor: Color = .primary
    @State private var bgColor: Color = .clear
    @State private var useCustomTextColor: Bool = false
    @State private var useCustomBgColor: Bool = false

    private var themeOptions: [(String, String)] {
        [
            ("auto",  L("settings.theme_auto")),
            ("light", L("settings.theme_light")),
            ("dark",  L("settings.theme_dark")),
            ("sepia", L("settings.theme_sepia"))
        ]
    }

    private let accentOptions = [
        ("blue",   Color.blue),
        ("purple", Color.purple),
        ("indigo", Color.indigo),
        ("brown",  Color.brown),
        ("red",    Color.red),
        ("green",  Color.green)
    ]

    var body: some View {
        Form {
            Section(L("settings.theme")) {
                Picker(L("settings.appearance"), selection: $readerTheme) {
                    ForEach(themeOptions, id: \.0) { value, label in
                        Text(label).tag(value)
                    }
                }
            }

            Section(L("settings.colors")) {
                HStack {
                    Text(L("settings.accent_color"))
                    Spacer()
                    ForEach(accentOptions, id: \.0) { name, color in
                        Circle()
                            .fill(color)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .strokeBorder(name == accentColorName ? Color.primary : Color.clear, lineWidth: 2)
                            )
                            .contentShape(Circle())
                            .onTapGesture { accentColorName = name }
                    }
                }

                HStack {
                    Text(L("settings.highlight_intensity"))
                    Spacer()
                    Slider(value: $verseHighlightOpacity, in: 0.05...0.6, step: 0.01)
                        .frame(width: 160)
                }
            }

            Section(L("settings.custom_colors")) {
                HStack {
                    Toggle(L("settings.text_color"), isOn: $useCustomTextColor)
                        .onChange(of: useCustomTextColor) { _, enabled in
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
                        .onChange(of: textColor) { _, newColor in
                            if useCustomTextColor {
                                textColorHex = newColor.toHex() ?? ""
                            }
                        }
                }

                HStack {
                    Toggle(L("settings.background_color"), isOn: $useCustomBgColor)
                        .onChange(of: useCustomBgColor) { _, enabled in
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
                        .onChange(of: bgColor) { _, newColor in
                            if useCustomBgColor {
                                backgroundColorHex = newColor.toHex() ?? ""
                            }
                        }
                }

                if useCustomTextColor || useCustomBgColor {
                    Button(L("settings.reset_colors")) {
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

            Section(L("settings.elements")) {
                Toggle(L("settings.show_chapter_titles"), isOn: $showChapterTitles)
            }

            Section {
                Button(L("settings.reset_appearance")) {
                    readerTheme = "auto"
                    accentColorName = "blue"
                    verseHighlightOpacity = 0.3
                    showChapterTitles = true
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
        .padding()
        .onAppear {
            useCustomTextColor = !textColorHex.isEmpty
            useCustomBgColor = !backgroundColorHex.isEmpty
            if let c = Color.fromHex(textColorHex) { textColor = c }
            if let c = Color.fromHex(backgroundColorHex) { bgColor = c }
        }
    }
}

// MARK: - Reading Tab

struct ReadingSettingsTab: View {

    @AppStorage("restoreLastPosition") private var restoreLastPosition: Bool = true
    @AppStorage("showChapterTitles") private var showChapterTitles: Bool = true
    @AppStorage("verseNumberStyle") private var verseNumberStyle: String = "superscript"

    var body: some View {
        Form {
            Section(L("settings.scroll_navigation")) {

                Toggle(L("settings.restore_position"), isOn: $restoreLastPosition)
            }

            Section(L("settings.verse_display")) {
                Picker(L("settings.verse_number_style"), selection: $verseNumberStyle) {
                    Text(L("settings.superscript")).tag("superscript")
                    Text(L("settings.inline")).tag("inline")
                    Text(L("settings.margin")).tag("margin")
                }

                Toggle(L("settings.show_chapter_titles_reader"), isOn: $showChapterTitles)
            }
        }
        .padding()
    }
}

// MARK: - Profile Tab

struct ProfileSettingsTab: View {
    @EnvironmentObject var store: BibleStore
    @AppStorage("activeProfile") private var activeProfile: String = "Default"
    @AppStorage("profileList") private var profileListRaw: String = "Default"

    @State private var showNewProfileSheet = false
    @State private var newProfileName: String = ""
    @State private var showDeleteConfirm = false
    @State private var profileToDelete: String?

    private var profiles: [String] {
        profileListRaw.split(separator: "|").map(String.init)
    }

    private func saveProfiles(_ list: [String]) {
        profileListRaw = list.joined(separator: "|")
    }

    var body: some View {
        Form {
            Section(L("settings.active_profile")) {
                Picker(L("settings.profile"), selection: $activeProfile) {
                    ForEach(profiles, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .onChange(of: activeProfile) { _, newProfile in
                    store.switchProfile(to: newProfile)
                }

                Text(L("settings.profile_description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("settings.manage_profiles")) {
                ForEach(profiles, id: \.self) { name in
                    HStack {
                        Image(systemName: name == activeProfile ? "person.circle.fill" : "person.circle")
                            .foregroundStyle(name == activeProfile ? Color.accentColor : Color.secondary)
                        Text(name)
                            .fontWeight(name == activeProfile ? .semibold : .regular)
                        Spacer()
                        if name == activeProfile {
                            Text(L("settings.active"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.secondary.opacity(0.12)))
                        }
                        if name != "Default" {
                            Button(role: .destructive) {
                                profileToDelete = name
                                showDeleteConfirm = true
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                            .buttonStyle(.borderless)
                            .help(L("settings.delete_profile"))
                        }
                    }
                }

                Button(action: { showNewProfileSheet = true }) {
                    Label(L("settings.new_profile"), systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding()
        .sheet(isPresented: $showNewProfileSheet) {
            newProfileSheet
        }
        .alert(L("settings.delete_profile_title"), isPresented: $showDeleteConfirm) {
            Button(L("cancel"), role: .cancel) { }
            Button(L("delete"), role: .destructive) {
                if let name = profileToDelete {
                    deleteProfile(name)
                }
            }
        } message: {
            if let name = profileToDelete {
                Text("\(L("settings.delete_profile_title")) \"\(name)\"? \(L("settings.profile_description"))")
            }
        }
    }

    private var newProfileSheet: some View {
        VStack(spacing: 16) {
            Text(L("settings.new_profile"))
                .font(.headline)

            TextField(L("settings.profile_name"), text: $newProfileName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit { createProfile() }

            if profiles.contains(newProfileName.trimmingCharacters(in: .whitespaces)) {
                Text(L("settings.profile_exists"))
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button(L("cancel")) {
                    newProfileName = ""
                    showNewProfileSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button(L("create")) {
                    createProfile()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty ||
                          profiles.contains(newProfileName.trimmingCharacters(in: .whitespaces)))
            }
        }
        .padding(24)
        .frame(width: 320)
    }

    private func createProfile() {
        let name = newProfileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !profiles.contains(name) else { return }
        var list = profiles
        list.append(name)
        saveProfiles(list)
        activeProfile = name
        store.switchProfile(to: name)
        newProfileName = ""
        showNewProfileSheet = false
    }

    private func deleteProfile(_ name: String) {
        guard name != "Default" else { return }
        var list = profiles
        list.removeAll { $0 == name }
        if list.isEmpty { list = ["Default"] }
        saveProfiles(list)

        if activeProfile == name {
            activeProfile = "Default"
            store.switchProfile(to: "Default")
        }

        store.deleteProfileData(name)
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
    @AppStorage("defaultTranslation") private var defaultTranslation: String = ""
    @State private var showClearHistoryConfirm = false
    @State private var showClearAllDataConfirm = false

    var body: some View {
        Form {
            Section(L("settings.language")) {
                Picker(L("settings.language"), selection: Binding(
                    get: { LocalizationService.shared.language },
                    set: { LocalizationService.shared.language = $0 }
                )) {
                    Text(L("settings.language_english")).tag("en")
                    Text(L("settings.language_russian")).tag("ru")
                }
                .pickerStyle(.segmented)
            }

            Section(L("settings.default_translation")) {
                Picker(L("settings.translation"), selection: $defaultTranslation) {
                    Text(L("settings.last_used")).tag("")
                    ForEach(store.loadedTranslations) { t in
                        Text(t.abbreviation).tag(t.abbreviation)
                    }
                }
            }

            Section(L("settings.modules")) {
                LabeledContent(L("settings.module_directory")) {
                    Text(BibleStore.modulesDirectory.path(percentEncoded: false))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack(spacing: 12) {
                    Button(L("settings.reveal_finder")) {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: BibleStore.modulesDirectory.path(percentEncoded: false))
                    }

                    Button(L("settings.import_module")) {
                        NotificationCenter.default.post(name: .importModule, object: nil)
                    }
                }
            }

            Section(L("settings.data_management")) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("settings.clear_history"))
                            .font(.callout)
                        Text(L("settings.clear_history_desc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L("settings.clear_history")) {
                        showClearHistoryConfirm = true
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("settings.clear_all_data"))
                            .font(.callout)
                        Text(L("settings.clear_all_data_desc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L("clear_all"), role: .destructive) {
                        showClearAllDataConfirm = true
                    }
                    .foregroundStyle(.red)
                }
            }

            Section(L("settings.about")) {
                LabeledContent(L("settings.version")) {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(.secondary)
                }
                LabeledContent(L("settings.build")) {
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .alert(L("alert.clear_history_title"), isPresented: $showClearHistoryConfirm) {
            Button(L("cancel"), role: .cancel) { }
            Button(L("clear"), role: .destructive) {
                store.clearHistory()
            }
        } message: {
            Text(L("alert.clear_history_msg"))
        }
        .alert(L("alert.clear_all_title"), isPresented: $showClearAllDataConfirm) {
            Button(L("cancel"), role: .cancel) { }
            Button(L("clear_all"), role: .destructive) {
                store.clearAllUserData()
            }
        } message: {
            Text(L("alert.clear_all_msg"))
        }
    }
}
