import AppKit
import Application
import Foundation

struct AppKitLibraryFolderPicker: LibraryFolderPicking {
    @MainActor
    func pickLibraryFolder() async throws -> PickedLibraryFolder? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK,
              let selectedURL = panel.url else {
            return nil
        }

        let standardizedURL = selectedURL.standardizedFileURL
        let bookmarkData = try? standardizedURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        return PickedLibraryFolder(
            rootPath: standardizedURL.path,
            displayName: standardizedURL.lastPathComponent,
            accessBookmark: bookmarkData
        )
    }
}
