import AppKit
import Application
import UniformTypeIdentifiers

struct AppKitLibraryExportDestinationPicker: LibraryExportDestinationPicking {
    @MainActor
    func pickLibraryExportDestination() async throws -> String? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "CineMind-Library.json"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.message = "Exports readable library data only. Media, subtitles, posters, and restore are not included."

        guard panel.runModal() == .OK,
              let selectedURL = panel.url else {
            return nil
        }

        return selectedURL.standardizedFileURL.path
    }
}
