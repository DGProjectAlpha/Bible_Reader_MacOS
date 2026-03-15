import SwiftUI
import CoreText

// MARK: - Step 1: Content Selection

struct ContentSelectionStep: View {
    @Environment(ExportWizardStore.self) private var wizardStore

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ExportSectionView(
                    title: "Bookmarks",
                    icon: "bookmark.fill",
                    items: wizardStore.bookmarkItems,
                    type: .bookmark
                )

                ExportSectionView(
                    title: "Highlights",
                    icon: "highlighter",
                    items: wizardStore.highlightItems,
                    type: .highlight
                )

                ExportSectionView(
                    title: "Notes",
                    icon: "note.text",
                    items: wizardStore.noteItems,
                    type: .note
                )
            }
            .padding(20)
        }
    }
}

// MARK: - Export Section

private struct ExportSectionView: View {
    @Environment(ExportWizardStore.self) private var wizardStore

    let title: String
    let icon: String
    let items: [ExportItem]
    let type: ExportItemType

    @State private var isExpanded = true

    private var selectedCount: Int {
        items.filter { wizardStore.isSelected($0.id) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .frame(width: 12)

                        Image(systemName: icon)
                            .font(.subheadline)
                            .foregroundStyle(Color.accentColor)

                        Text(title)
                            .font(.headline)

                        Text("\(selectedCount)/\(items.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                if !items.isEmpty {
                    Button("Select All") {
                        wizardStore.selectAll(for: type)
                    }
                    .font(.caption)
                    .disabled(wizardStore.allSelected(for: type))

                    Button("Deselect All") {
                        wizardStore.deselectAll(for: type)
                    }
                    .font(.caption)
                    .disabled(selectedCount == 0)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if isExpanded {
                if items.isEmpty {
                    Text("No \(title.lowercased()) to export.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                } else {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            ExportItemRow(item: item)

                            if item.id != items.last?.id {
                                Divider()
                                    .padding(.leading, 36)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .padding(.horizontal, 4)
                }
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Export Item Row

private struct ExportItemRow: View {
    @Environment(ExportWizardStore.self) private var wizardStore
    let item: ExportItem

    @State private var isHovered = false

    var body: some View {
        Button {
            wizardStore.toggleItem(item.id)
        } label: {
            HStack(spacing: 10) {
                // Checkbox
                Image(systemName: wizardStore.isSelected(item.id) ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(wizardStore.isSelected(item.id) ? Color.accentColor : .secondary)
                    .frame(width: 20)

                // Color badge
                if let color = item.color {
                    Circle()
                        .fill(color.swiftUIColor)
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle().stroke(Color.primary.opacity(0.2), lineWidth: 0.5)
                        )
                }

                // Verse reference + preview
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.verseReference)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Text(item.previewText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Type badge
                Text(item.type.rawValue.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Step 2: Ordering & Grouping

struct OrderingStep: View {
    @Environment(ExportWizardStore.self) private var wizardStore

    var body: some View {
        @Bindable var store = wizardStore

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Ordering section
                VStack(alignment: .leading, spacing: 12) {
                    Label("Sort Order", systemImage: "arrow.up.arrow.down")
                        .font(.headline)

                    VStack(spacing: 0) {
                        ForEach(ExportOrdering.allCases) { option in
                            Button {
                                wizardStore.ordering = option
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: wizardStore.ordering == option ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(wizardStore.ordering == option ? Color.accentColor : .secondary)
                                        .font(.body)

                                    Text(option.label)
                                        .foregroundStyle(.primary)

                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if option != ExportOrdering.allCases.last {
                                Divider().padding(.leading, 34)
                            }
                        }
                    }
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }

                // Grouping section
                VStack(alignment: .leading, spacing: 12) {
                    Label("Grouping", systemImage: "folder")
                        .font(.headline)

                    HStack {
                        Toggle("Group by book", isOn: $store.groupByBook)
                            .toggleStyle(.switch)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )

                    Text("When enabled, exported items are grouped under book headers (e.g. Genesis, Exodus).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Preview summary
                VStack(alignment: .leading, spacing: 8) {
                    Label("Preview", systemImage: "eye")
                        .font(.headline)

                    OrderingPreview()
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Ordering Preview

private struct OrderingPreview: View {
    @Environment(ExportWizardStore.self) private var wizardStore

    var body: some View {
        let groups = wizardStore.groupedSelectedItems()

        VStack(alignment: .leading, spacing: 0) {
            if groups.isEmpty || (groups.count == 1 && groups[0].items.isEmpty) {
                Text("No items selected.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(12)
            } else {
                let maxItems = 8
                let shown = 0

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                            if wizardStore.groupByBook && !group.bookName.isEmpty {
                                Text(group.bookName)
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 8)
                                    .padding(.bottom, 2)
                            }

                            ForEach(group.items.prefix(max(0, maxItems - shown))) { item in
                                HStack(spacing: 8) {
                                    if let color = item.color {
                                        Circle()
                                            .fill(color.swiftUIColor)
                                            .frame(width: 8, height: 8)
                                    }

                                    Text(item.verseReference)
                                        .font(.caption)
                                        .foregroundStyle(.primary)

                                    Text("— \(item.previewText)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)

                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 3)
                            }
                        }

                        let totalCount = groups.reduce(0) { $0 + $1.items.count }
                        if totalCount > maxItems {
                            Text("… and \(totalCount - maxItems) more items")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Step 3: Bible Version & Formatting

struct FormattingStep: View {
    @Environment(ExportWizardStore.self) private var wizardStore
    @Environment(BibleStore.self) private var bibleStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Bible version selection
                BibleVersionSelectionSection()

                Divider()

                // Font configuration sections
                FontConfigSection(
                    title: "Verse Reference Title",
                    icon: "textformat.size",
                    keyPath: \.referenceFontConfig,
                    description: "Font for verse references like \"Genesis 1:1\""
                )

                FontConfigSection(
                    title: "Bible Verse Text",
                    icon: "text.book.closed",
                    keyPath: \.verseTextFontConfig,
                    description: "Font for the Bible verse content"
                )

                FontConfigSection(
                    title: "Note Text",
                    icon: "note.text",
                    keyPath: \.noteFontConfig,
                    description: "Font for your notes and annotations"
                )

                Divider()

                // Preview
                FormattingPreviewSection()
            }
            .padding(20)
        }
    }
}

// MARK: - Bible Version Selection

private struct BibleVersionSelectionSection: View {
    @Environment(ExportWizardStore.self) private var wizardStore
    @Environment(BibleStore.self) private var bibleStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Bible Versions", systemImage: "book")
                .font(.headline)

            Text("Select which Bible version(s) to include verse text from. At least one is required.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if bibleStore.modules.isEmpty {
                Text("No Bible modules loaded.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(12)
            } else {
                VStack(spacing: 0) {
                    ForEach(bibleStore.modules) { module in
                        Button {
                            if wizardStore.selectedModuleIds.contains(module.id) {
                                if wizardStore.selectedModuleIds.count > 1 {
                                    wizardStore.selectedModuleIds.remove(module.id)
                                }
                            } else {
                                wizardStore.selectedModuleIds.insert(module.id)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: wizardStore.selectedModuleIds.contains(module.id) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(wizardStore.selectedModuleIds.contains(module.id) ? Color.accentColor : .secondary)
                                    .font(.body)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(module.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(module.abbreviation)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if module.id != bibleStore.modules.last?.id {
                            Divider().padding(.leading, 34)
                        }
                    }
                }
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }
}

// MARK: - Font Config Section

private struct FontConfigSection: View {
    @Environment(ExportWizardStore.self) private var wizardStore

    let title: String
    let icon: String
    let keyPath: WritableKeyPath<ExportWizardStore, ExportFontConfig>
    let description: String

    @State private var isExpanded = false

    private var config: ExportFontConfig {
        wizardStore[keyPath: keyPath]
    }

    private static let availableFontFamilies: [String] = {
        var families = ["System"]
        families.append(contentsOf: NSFontManager.shared.availableFontFamilies.sorted())
        return families
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(fontSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    // Font family picker
                    HStack {
                        Text("Font Family")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { config.family },
                            set: { newVal in @Bindable var store = wizardStore; store[keyPath: keyPath].family = newVal }
                        )) {
                            ForEach(Self.availableFontFamilies, id: \.self) { family in
                                Text(family).tag(family)
                            }
                        }
                        .frame(maxWidth: 200)
                    }

                    // Size slider
                    HStack {
                        Text("Size")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { config.size },
                                set: { newVal in @Bindable var store = wizardStore; store[keyPath: keyPath].size = newVal }
                            ),
                            in: 8...36,
                            step: 1
                        )
                        Text("\(Int(config.size))pt")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }

                    // Bold / Italic toggles
                    HStack(spacing: 16) {
                        Toggle(isOn: Binding(
                            get: { config.isBold },
                            set: { newVal in @Bindable var store = wizardStore; store[keyPath: keyPath].isBold = newVal }
                        )) {
                            Text("Bold")
                                .font(.caption)
                        }
                        .toggleStyle(.checkbox)

                        Toggle(isOn: Binding(
                            get: { config.isItalic },
                            set: { newVal in @Bindable var store = wizardStore; store[keyPath: keyPath].isItalic = newVal }
                        )) {
                            Text("Italic")
                                .font(.caption)
                        }
                        .toggleStyle(.checkbox)

                        Spacer()

                        // Reset button
                        Button("Reset") {
                            resetToDefault()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    // Font sample
                    Text("The quick brown fox jumps over the lazy dog")
                        .font(.custom(
                            config.family == "System" ? ".AppleSystemUIFont" : config.family,
                            size: config.size
                        ))
                        .bold(config.isBold)
                        .italic(config.isItalic)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var fontSummary: String {
        let family = config.family == "System" ? "System" : config.family
        var traits: [String] = []
        if config.isBold { traits.append("Bold") }
        if config.isItalic { traits.append("Italic") }
        let traitStr = traits.isEmpty ? "" : " \(traits.joined(separator: ", "))"
        return "\(family), \(Int(config.size))pt\(traitStr)"
    }

    private func resetToDefault() {
        @Bindable var store = wizardStore
        switch keyPath {
        case \.referenceFontConfig:
            store[keyPath: keyPath] = .defaultReference
        case \.noteFontConfig:
            store[keyPath: keyPath] = .defaultNote
        default:
            store[keyPath: keyPath] = ExportFontConfig(family: "System", size: 14, isBold: false, isItalic: false)
        }
    }
}

// MARK: - Formatting Preview

private struct FormattingPreviewSection: View {
    @Environment(ExportWizardStore.self) private var wizardStore
    @Environment(BibleStore.self) private var bibleStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Preview", systemImage: "eye")
                .font(.headline)

            Text("Sample export entry with current formatting applied.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                // Reference title
                Text("Genesis 1:1")
                    .font(.custom(
                        fontFamily(wizardStore.referenceFontConfig),
                        size: wizardStore.referenceFontConfig.size
                    ))
                    .bold(wizardStore.referenceFontConfig.isBold)
                    .italic(wizardStore.referenceFontConfig.isItalic)

                // Verse text for each selected module
                let moduleNames = selectedModuleNames()
                if moduleNames.isEmpty {
                    Text("No Bible version selected.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(moduleNames, id: \.self) { name in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("[\(name)]")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Text("In the beginning God created the heaven and the earth.")
                                .font(.custom(
                                    fontFamily(wizardStore.verseTextFontConfig),
                                    size: wizardStore.verseTextFontConfig.size
                                ))
                                .bold(wizardStore.verseTextFontConfig.isBold)
                                .italic(wizardStore.verseTextFontConfig.isItalic)
                        }
                    }
                }

                Divider()

                // Note text
                Text("This is a sample note attached to the verse.")
                    .font(.custom(
                        fontFamily(wizardStore.noteFontConfig),
                        size: wizardStore.noteFontConfig.size
                    ))
                    .bold(wizardStore.noteFontConfig.isBold)
                    .italic(wizardStore.noteFontConfig.isItalic)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private func fontFamily(_ config: ExportFontConfig) -> String {
        config.family == "System" ? ".AppleSystemUIFont" : config.family
    }

    private func selectedModuleNames() -> [String] {
        bibleStore.modules
            .filter { wizardStore.selectedModuleIds.contains($0.id) }
            .map { $0.abbreviation }
    }
}

// MARK: - Step 4: Export

struct ExportStep: View {
    @Environment(ExportWizardStore.self) private var wizardStore
    @Environment(BibleStore.self) private var bibleStore

    var body: some View {
        @Bindable var store = wizardStore

        ScrollView {
            VStack(spacing: 20) {
                // Format selection
                ExportFormatSection()

                // Export summary
                ExportSummarySection()

                // Export action / progress
                ExportActionSection()
            }
            .padding(20)
        }
    }
}

// MARK: - Format Selection

private struct ExportFormatSection: View {
    @Environment(ExportWizardStore.self) private var wizardStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Export Format", systemImage: "doc.badge.gearshape")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(ExportFormat.allCases) { format in
                    formatRow(format)
                }
            }
        }
    }

    @ViewBuilder
    private func formatRow(_ format: ExportFormat) -> some View {
        let isSelected = wizardStore.exportFormat == format
        Button {
            wizardStore.exportFormat = format
        } label: {
            HStack(spacing: 12) {
                Image(systemName: formatIcon(format))
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(format.label)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(formatDescription(format))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.title3)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func formatIcon(_ format: ExportFormat) -> String {
        switch format {
        case .pdf: return "doc.richtext"
        case .plainText: return "doc.text"
        case .markdown: return "text.badge.checkmark"
        }
    }

    private func formatDescription(_ format: ExportFormat) -> String {
        switch format {
        case .pdf: return "Formatted document with fonts and styling"
        case .plainText: return "Simple text file, compatible everywhere"
        case .markdown: return "Structured text with headers and formatting"
        }
    }
}

// MARK: - Export Summary

private struct ExportSummarySection: View {
    @Environment(ExportWizardStore.self) private var wizardStore
    @Environment(BibleStore.self) private var bibleStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Export Summary", systemImage: "list.clipboard")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                summaryRow("Items", value: "\(wizardStore.selectedItemIds.count)")
                summaryRow("Order", value: wizardStore.ordering.label)
                summaryRow("Grouping", value: wizardStore.groupByBook ? "Grouped by book" : "Flat list")
                summaryRow("Bible Versions", value: selectedModuleNames())
                summaryRow("Format", value: wizardStore.exportFormat.label)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.subheadline.weight(.medium))
        }
    }

    private func selectedModuleNames() -> String {
        let names = bibleStore.modules
            .filter { wizardStore.selectedModuleIds.contains($0.id) }
            .map { $0.abbreviation }
        return names.isEmpty ? "None" : names.joined(separator: ", ")
    }
}

// MARK: - Export Action

private struct ExportActionSection: View {
    @Environment(ExportWizardStore.self) private var wizardStore
    @Environment(BibleStore.self) private var bibleStore

    var body: some View {
        VStack(spacing: 16) {
            switch wizardStore.exportState {
            case .idle:
                Button {
                    startExport()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            case .exporting(let progress):
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    Text("Exporting… \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        wizardStore.cancelExport()
                    } label: {
                        Text("Cancel")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

            case .completed(let url):
                VStack(spacing: 12) {
                    Label("Export Complete", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)

                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        wizardStore.exportState = .idle
                    } label: {
                        Text("Export Again")
                    }
                    .buttonStyle(.bordered)
                }

            case .failed(let message):
                VStack(spacing: 12) {
                    Label("Export Failed", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.red)

                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        wizardStore.exportState = .idle
                    } label: {
                        Text("Try Again")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.top, 8)
    }

    private func startExport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "BibleReader Export.\(wizardStore.exportFormat.fileExtension)"
        panel.allowedContentTypes = [wizardStore.exportFormat.utType]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let store = wizardStore
        let items = store.sortedSelectedItems()
        let grouped = store.groupedSelectedItems()
        let format = store.exportFormat
        let moduleIds = Array(store.selectedModuleIds)
        let modules = bibleStore.modules.filter { moduleIds.contains($0.id) }
        let refFont = store.referenceFontConfig
        let verseFont = store.verseTextFontConfig
        let noteFont = store.noteFontConfig
        let groupByBook = store.groupByBook

        store.exportState = .exporting(progress: 0)

        store.exportTask = Task.detached {
            do {
                try Task.checkCancellation()
                let db = DatabaseService.shared
                let totalItems = items.count
                let batchSize = max(1, totalItems / 100) // Report ~100 progress updates
                var entries: [ExportEntry] = []
                entries.reserveCapacity(totalItems)

                for (index, item) in items.enumerated() {
                    try Task.checkCancellation()

                    let parts = item.verseId.split(separator: ".")
                    var verseTexts: [(module: String, text: String)] = []

                    if parts.count >= 3 {
                        let book = String(parts[0])
                        let chapter = Int(parts[1]) ?? 1
                        let verse = Int(parts[2]) ?? 1

                        for mod in modules {
                            if let text = try? await db.fetchVerseText(moduleId: mod.id, book: book, chapter: chapter, verse: verse) {
                                verseTexts.append((mod.abbreviation, text))
                            }
                        }
                    }

                    entries.append(ExportEntry(
                        reference: item.verseReference,
                        type: item.type,
                        noteText: item.previewText,
                        color: item.color,
                        verseTexts: verseTexts
                    ))

                    if index % batchSize == 0 || index == totalItems - 1 {
                        let progress = Double(index + 1) / Double(totalItems)
                        await MainActor.run {
                            store.exportState = .exporting(progress: progress * 0.8)
                        }
                        // Yield to prevent starving other tasks
                        await Task.yield()
                    }
                }

                try Task.checkCancellation()

                // Build grouped entries if needed
                let groupedEntries: [(bookName: String, entries: [ExportEntry])]
                if groupByBook {
                    var groups: [(String, [ExportEntry])] = []
                    for group in grouped {
                        let groupEntries = group.items.compactMap { item in
                            entries.first(where: { $0.reference == item.verseReference && $0.noteText == item.previewText })
                        }
                        if !groupEntries.isEmpty {
                            groups.append((group.bookName, groupEntries))
                        }
                    }
                    groupedEntries = groups
                } else {
                    groupedEntries = [("", entries)]
                }

                await MainActor.run {
                    store.exportState = .exporting(progress: 0.85)
                }

                try Task.checkCancellation()

                switch format {
                case .pdf:
                    try ExportRenderer.renderPDF(
                        to: url,
                        groupedEntries: groupedEntries,
                        refFont: refFont,
                        verseFont: verseFont,
                        noteFont: noteFont
                    )
                case .plainText:
                    try ExportRenderer.renderPlainText(to: url, groupedEntries: groupedEntries)
                case .markdown:
                    try ExportRenderer.renderMarkdown(to: url, groupedEntries: groupedEntries)
                }

                try Task.checkCancellation()

                await MainActor.run {
                    store.exportState = .completed(url: url)
                }
            } catch is CancellationError {
                // User cancelled — state already set to .idle by cancelExport()
            } catch {
                await MainActor.run {
                    store.exportState = .failed(message: error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Export Data Structures

struct ExportEntry {
    let reference: String
    let type: ExportItemType
    let noteText: String
    let color: BookmarkColor?
    let verseTexts: [(module: String, text: String)]
}

// MARK: - Export Renderer

enum ExportRenderer {

    // MARK: PDF

    static func renderPDF(
        to url: URL,
        groupedEntries: [(bookName: String, entries: [ExportEntry])],
        refFont: ExportFontConfig,
        verseFont: ExportFontConfig,
        noteFont: ExportFontConfig
    ) throws {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50
        let contentWidth = pageWidth - margin * 2
        let separatorSpacing: CGFloat = 12

        let refAttributes: [NSAttributedString.Key: Any] = [
            .font: refFont.nsFont,
            .foregroundColor: NSColor.labelColor
        ]
        let verseAttributes: [NSAttributedString.Key: Any] = [
            .font: verseFont.nsFont,
            .foregroundColor: NSColor.labelColor
        ]
        let noteAttributes: [NSAttributedString.Key: Any] = [
            .font: noteFont.nsFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let bookHeaderAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: NSColor.labelColor
        ]
        let moduleLabel: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: verseFont.size - 1, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ExportError.pdfCreationFailed
        }

        var currentY: CGFloat = 0

        func beginPage() {
            context.beginPDFPage(nil)
            currentY = pageHeight - margin
        }

        func endPage() {
            context.endPDFPage()
        }

        func drawString(_ string: NSAttributedString, at y: inout CGFloat, maxWidth: CGFloat) {
            let framesetter = CTFramesetterCreateWithAttributedString(string)
            let fitSize = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter, CFRange(location: 0, length: string.length),
                nil, CGSize(width: maxWidth, height: .greatestFiniteMagnitude), nil
            )
            let textHeight = ceil(fitSize.height)

            if y - textHeight < margin {
                endPage()
                beginPage()
            }

            let textRect = CGRect(x: margin, y: y - textHeight, width: maxWidth, height: textHeight)
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: string.length), path, nil)

            context.saveGState()
            CTFrameDraw(frame, context)
            context.restoreGState()

            y -= textHeight
        }

        func drawSeparator(at y: inout CGFloat) {
            y -= separatorSpacing
            if y < margin {
                endPage()
                beginPage()
            }
            context.saveGState()
            context.setStrokeColor(NSColor.separatorColor.cgColor)
            context.setLineWidth(0.5)
            context.move(to: CGPoint(x: margin, y: y))
            context.addLine(to: CGPoint(x: margin + contentWidth, y: y))
            context.strokePath()
            context.restoreGState()
            y -= separatorSpacing
        }

        beginPage()

        for (groupIndex, group) in groupedEntries.enumerated() {
            // Book header
            if !group.bookName.isEmpty {
                if groupIndex > 0 {
                    currentY -= 20
                }
                let headerStr = NSAttributedString(string: group.bookName, attributes: bookHeaderAttributes)
                drawString(headerStr, at: &currentY, maxWidth: contentWidth)
                currentY -= 8
            }

            for (entryIndex, entry) in group.entries.enumerated() {
                // Reference
                let typePrefix: String
                switch entry.type {
                case .bookmark: typePrefix = "🔖 "
                case .highlight: typePrefix = "🖍️ "
                case .note: typePrefix = "📝 "
                }
                let refStr = NSAttributedString(string: "\(typePrefix)\(entry.reference)", attributes: refAttributes)
                drawString(refStr, at: &currentY, maxWidth: contentWidth)
                currentY -= 4

                // Verse texts
                for vt in entry.verseTexts {
                    let labelStr = NSAttributedString(string: "[\(vt.module)] ", attributes: moduleLabel)
                    let textStr = NSAttributedString(string: vt.text, attributes: verseAttributes)
                    let combined = NSMutableAttributedString()
                    combined.append(labelStr)
                    combined.append(textStr)
                    drawString(combined, at: &currentY, maxWidth: contentWidth)
                    currentY -= 2
                }

                // Note text
                if entry.noteText != "Bookmark" && entry.noteText != "Highlight" {
                    let noteStr = NSAttributedString(string: entry.noteText, attributes: noteAttributes)
                    drawString(noteStr, at: &currentY, maxWidth: contentWidth)
                }

                // Separator
                if entryIndex < group.entries.count - 1 || groupIndex < groupedEntries.count - 1 {
                    drawSeparator(at: &currentY)
                }
            }
        }

        endPage()
        context.closePDF()

        try pdfData.write(to: url, options: .atomic)
    }

    // MARK: Plain Text

    static func renderPlainText(
        to url: URL,
        groupedEntries: [(bookName: String, entries: [ExportEntry])]
    ) throws {
        var output = "Bible Reader — Notes Export\n"
        output += String(repeating: "=", count: 40) + "\n\n"

        for group in groupedEntries {
            if !group.bookName.isEmpty {
                output += "\(group.bookName)\n"
                output += String(repeating: "-", count: group.bookName.count) + "\n\n"
            }

            for entry in group.entries {
                let typeLabel: String
                switch entry.type {
                case .bookmark: typeLabel = "[Bookmark]"
                case .highlight: typeLabel = "[Highlight]"
                case .note: typeLabel = "[Note]"
                }
                output += "\(typeLabel) \(entry.reference)\n"

                for vt in entry.verseTexts {
                    output += "  [\(vt.module)] \(vt.text)\n"
                }

                if entry.noteText != "Bookmark" && entry.noteText != "Highlight" {
                    output += "  Note: \(entry.noteText)\n"
                }

                output += "\n"
            }
        }

        try output.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: Markdown

    static func renderMarkdown(
        to url: URL,
        groupedEntries: [(bookName: String, entries: [ExportEntry])]
    ) throws {
        var output = "# Bible Reader — Notes Export\n\n"

        for group in groupedEntries {
            if !group.bookName.isEmpty {
                output += "## \(group.bookName)\n\n"
            }

            for entry in group.entries {
                let typeEmoji: String
                switch entry.type {
                case .bookmark: typeEmoji = "🔖"
                case .highlight: typeEmoji = "🖍️"
                case .note: typeEmoji = "📝"
                }
                output += "### \(typeEmoji) \(entry.reference)\n\n"

                for vt in entry.verseTexts {
                    output += "> **[\(vt.module)]** \(vt.text)\n\n"
                }

                if entry.noteText != "Bookmark" && entry.noteText != "Highlight" {
                    output += "*\(entry.noteText)*\n\n"
                }

                output += "---\n\n"
            }
        }

        try output.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Export Errors

enum ExportError: LocalizedError {
    case pdfCreationFailed

    var errorDescription: String? {
        switch self {
        case .pdfCreationFailed: return "Failed to create PDF document"
        }
    }
}
