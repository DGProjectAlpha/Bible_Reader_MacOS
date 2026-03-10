import SwiftUI
import UniformTypeIdentifiers

struct ImportModuleView: View {
    @EnvironmentObject var store: BibleStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var importHandler = FileImportHandler()
    @State private var isDragTargeted = false

    var body: some View {
        VStack(spacing: 20) {
            // Drop zone
            dropZone
                .frame(height: 200)
                .padding(.horizontal, 30)

            // Status message
            if importHandler.showResult, let result = importHandler.lastResult {
                HStack(spacing: 6) {
                    Image(systemName: FileImportHandler.statusIsError(result) ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(FileImportHandler.statusIsError(result) ? .red : .green)
                    Text(FileImportHandler.statusMessage(result))
                        .font(.callout)
                        .foregroundStyle(FileImportHandler.statusIsError(result) ? .red : .primary)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Buttons
            HStack(spacing: 12) {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Choose File...") {
                    importHandler.showOpenPanel(store: store)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(importHandler.isProcessing)
            }
        }
        .padding(30)
        .frame(width: 440)
        .glassSheet()
        .animation(.easeInOut(duration: 0.2), value: importHandler.showResult)
        .animation(.easeInOut(duration: 0.15), value: isDragTargeted)
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(
                isDragTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                style: StrokeStyle(lineWidth: isDragTargeted ? 3 : 2, dash: [8, 4])
            )
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isDragTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .overlay {
                VStack(spacing: 12) {
                    if importHandler.isProcessing {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Importing...")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: isDragTargeted ? "arrow.down.circle.fill" : "square.and.arrow.down")
                            .font(.system(size: 40))
                            .foregroundStyle(isDragTargeted ? .accent : .secondary)
                            .symbolEffect(.bounce, value: isDragTargeted)

                        Text("Drop .brbmod files here")
                            .font(.headline)
                            .foregroundStyle(isDragTargeted ? .primary : .secondary)

                        Text("or click \"Choose File\" to browse")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
                importHandler.handleDrop(providers: providers, store: store)
            }
    }
}

#Preview {
    ImportModuleView()
        .environmentObject(BibleStore())
}
