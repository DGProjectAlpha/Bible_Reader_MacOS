import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: BibleStore

    var body: some View {
        TabView {
            DisplaySettingsTab()
                .tabItem { Label("Display", systemImage: "textformat") }

            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            ReadingSettingsTab()
                .tabItem { Label("Reading", systemImage: "book") }

            ProfileSettingsTab()
                .environmentObject(store)
                .tabItem { Label("Profiles", systemImage: "person.2") }

            GeneralSettingsTab()
                .environmentObject(store)
                .tabItem { Label("General", systemImage: "gear") }
        }
        .frame(width: 520, height: 480)
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
                    Text("Size")
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

            Section {
                Button("Reset Display to Defaults") {
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
                    Toggle("Background Color", isOn: $useCustomBgColor)
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
                    Button("Reset Colors to Defaults") {
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

            Section {
                Button("Reset Appearance to Defaults") {
                    readerTheme = "auto"
                    accentColorName = "blue"
                    verseHighlightOpacity = 0.12
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

// MARK: - Reading Tab (Sync Scroll, Navigation behavior)

struct ReadingSettingsTab: View {
    @AppStorage("syncScrolling") private var syncScrolling: Bool = true
    @AppStorage("restoreLastPosition") private var restoreLastPosition: Bool = true
    @AppStorage("showChapterTitles") private var showChapterTitles: Bool = true
    @AppStorage("verseNumberStyle") private var verseNumberStyle: String = "superscript"

    var body: some View {
        Form {
            Section("Scroll & Navigation") {
                Toggle("Sync scroll across panes", isOn: $syncScrolling)

                Toggle("Restore last reading position on launch", isOn: $restoreLastPosition)
            }

            Section("Verse Display") {
                Picker("Verse Number Style", selection: $verseNumberStyle) {
                    Text("Superscript").tag("superscript")
                    Text("Inline").tag("inline")
                    Text("Margin").tag("margin")
                }

                Toggle("Show chapter titles in reader", isOn: $showChapterTitles)
            }
        }
        .padding()
    }
}

// MARK: - Profile Tab (matching Windows profile management)

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
            Section("Active Profile") {
                Picker("Profile", selection: $activeProfile) {
                    ForEach(profiles, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .onChange(of: activeProfile) { _, newProfile in
                    store.switchProfile(to: newProfile)
                }

                Text("Each profile has its own bookmarks, highlights, notes, and reading history.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Manage Profiles") {
                ForEach(profiles, id: \.self) { name in
                    HStack {
                        Image(systemName: name == activeProfile ? "person.circle.fill" : "person.circle")
                            .foregroundStyle(name == activeProfile ? Color.accentColor : Color.secondary)
                        Text(name)
                            .fontWeight(name == activeProfile ? .semibold : .regular)
                        Spacer()
                        if name == activeProfile {
                            Text("Active")
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
                            .help("Delete profile")
                        }
                    }
                }

                Button(action: { showNewProfileSheet = true }) {
                    Label("New Profile", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding()
        .sheet(isPresented: $showNewProfileSheet) {
            newProfileSheet
        }
        .alert("Delete Profile", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let name = profileToDelete {
                    deleteProfile(name)
                }
            }
        } message: {
            if let name = profileToDelete {
                Text("Delete profile \"\(name)\"? This will permanently remove all bookmarks, highlights, notes, and reading history associated with this profile.")
            }
        }
    }

    private var newProfileSheet: some View {
        VStack(spacing: 16) {
            Text("New Profile")
                .font(.headline)

            TextField("Profile name", text: $newProfileName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit { createProfile() }

            if profiles.contains(newProfileName.trimmingCharacters(in: .whitespaces)) {
                Text("A profile with this name already exists.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    newProfileName = ""
                    showNewProfileSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
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

        // If deleting the active profile, switch to Default
        if activeProfile == name {
            activeProfile = "Default"
            store.switchProfile(to: "Default")
        }

        // Clean up profile data
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
            Section("Default Translation") {
                Picker("Translation", selection: $defaultTranslation) {
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

                HStack(spacing: 12) {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: BibleStore.modulesDirectory.path(percentEncoded: false))
                    }

                    Button("Import Module...") {
                        NotificationCenter.default.post(name: .importModule, object: nil)
                    }
                }
            }

            Section("Data Management") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clear Reading History")
                            .font(.callout)
                        Text("Remove all reading history entries")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear History") {
                        showClearHistoryConfirm = true
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clear All User Data")
                            .font(.callout)
                        Text("Remove all bookmarks, highlights, notes, and history for this profile")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear All", role: .destructive) {
                        showClearAllDataConfirm = true
                    }
                    .foregroundStyle(.red)
                }
            }

            Section("About") {
                LabeledContent("Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Build") {
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .alert("Clear Reading History", isPresented: $showClearHistoryConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                store.clearHistory()
            }
        } message: {
            Text("This will permanently delete all reading history. This cannot be undone.")
        }
        .alert("Clear All User Data", isPresented: $showClearAllDataConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                store.clearAllUserData()
            }
        } message: {
            Text("This will permanently delete all bookmarks, highlights, notes, and reading history for the current profile. This cannot be undone.")
        }
    }
}
