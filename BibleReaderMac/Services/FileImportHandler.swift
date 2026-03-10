import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - BRBMod UTType

extension UTType {
    static let brbmod = UTType(exportedAs: "com.biblereader.brbmod", conformingTo: .data)
}

// MARK: - Import Result

enum ModuleImportStatus {
    case success(Translation)
    case alreadyInstalled(String) // abbreviation
    case validationFailed(String) // error message
    case fileError(String)
}

// MARK: - FileImportHandler

/// Handles all file import pathways: drag-and-drop, NSOpenPanel, Finder open-with, and URL schemes.
/// Designed as a single entry point so every import path runs the same validation and copy logic.
@MainActor
final class FileImportHandler: ObservableObject {

    @Published var isProcessing = false
    @Published var lastResult: ModuleImportStatus?
    @Published var showResult = false

    private let moduleManager = ModuleManager.shared

    // MARK: - Single File Import

    /// Import a single .brbmod file. Returns the import status.
    func importFile(at url: URL, into store: BibleStore) async -> ModuleImportStatus {
        isProcessing = true
        defer {
            isProcessing = false
        }

        // Gain security-scoped access if needed (for sandboxed drag-and-drop / open panel)
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        // Basic extension check
        guard url.pathExtension.lowercased() == "brbmod" else {
            let status = ModuleImportStatus.fileError("Not a .brbmod file: \(url.lastPathComponent)")
            lastResult = status
            showResult = true
            return status
        }

        // Pre-validate before copying
        let validation = moduleManager.validate(fileURL: url)
        guard validation.isValid, let meta = validation.metadata else {
            let msg = validation.errors.first?.localizedDescription ?? "Unknown validation error"
            let status = ModuleImportStatus.validationFailed(msg)
            lastResult = status
            showResult = true
            return status
        }

        // Check for duplicate
        if moduleManager.isInstalled(abbreviation: meta.abbreviation) {
            let status = ModuleImportStatus.alreadyInstalled(meta.abbreviation)
            lastResult = status
            showResult = true
            return status
        }

        // Import (copies to modules dir, validates, caches)
        do {
            let translation = try moduleManager.importModule(from: url)
            store.loadedTranslations.append(translation)
            let status = ModuleImportStatus.success(translation)
            lastResult = status
            showResult = true
            return status
        } catch {
            let status = ModuleImportStatus.fileError(error.localizedDescription)
            lastResult = status
            showResult = true
            return status
        }
    }

    // MARK: - Batch Import

    /// Import multiple files. Returns a status for each.
    func importFiles(at urls: [URL], into store: BibleStore) async -> [ModuleImportStatus] {
        var results: [ModuleImportStatus] = []
        for url in urls {
            let status = await importFile(at: url, into: store)
            results.append(status)
        }
        return results
    }

    // MARK: - Drop Handling

    /// Handle items dropped via SwiftUI onDrop. Returns true if any items were accepted.
    func handleDrop(providers: [NSItemProvider], store: BibleStore) -> Bool {
        let validProviders = providers.filter { provider in
            provider.hasItemConformingToTypeIdentifier(UTType.brbmod.identifier) ||
            provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ||
            provider.hasItemConformingToTypeIdentifier(UTType.data.identifier)
        }

        guard !validProviders.isEmpty else { return false }

        Task { @MainActor in
            isProcessing = true
            var importURLs: [URL] = []

            for provider in validProviders {
                if let url = await loadFileURL(from: provider) {
                    if url.pathExtension.lowercased() == "brbmod" {
                        importURLs.append(url)
                    }
                }
            }

            if !importURLs.isEmpty {
                _ = await importFiles(at: importURLs, into: store)
            }
            isProcessing = false
        }

        return true
    }

    /// Extract a file URL from an NSItemProvider.
    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        // Try loading as file URL first
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    if let urlData = data as? Data,
                       let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Open Panel

    /// Show an NSOpenPanel for .brbmod files and import selected files.
    func showOpenPanel(store: BibleStore) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.brbmod]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Select .brbmod Bible module files to import"
        panel.prompt = "Import"

        guard panel.runModal() == .OK else { return }
        let urls = panel.urls

        Task {
            _ = await importFiles(at: urls, into: store)
        }
    }

    // MARK: - Status Descriptions

    static func statusMessage(_ status: ModuleImportStatus) -> String {
        switch status {
        case .success(let t):
            return "Successfully imported \(t.metadata.name) (\(t.abbreviation))"
        case .alreadyInstalled(let abbr):
            return "\(abbr) is already installed"
        case .validationFailed(let msg):
            return "Invalid module: \(msg)"
        case .fileError(let msg):
            return "Import error: \(msg)"
        }
    }

    static func statusIsError(_ status: ModuleImportStatus) -> Bool {
        switch status {
        case .success: return false
        case .alreadyInstalled: return false
        case .validationFailed: return true
        case .fileError: return true
        }
    }
}
