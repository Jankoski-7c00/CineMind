import Application
import Domain
import SwiftUI

@MainActor
public final class LibraryBrowserViewModel: ObservableObject {
    @Published public var selectedSection: LibraryBrowserSection = .library
    @Published public private(set) var snapshot: LibraryMediaSummarySnapshot?
    @Published public private(set) var folderSnapshot: LibraryFolderSummarySnapshot?
    @Published public private(set) var isLoading = false
    @Published public private(set) var isAddingFolder = false
    @Published public private(set) var isScanning = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var workflowMessage: String?
    @Published public private(set) var workflowErrorMessage: String?
    @Published public private(set) var lastScanResult: LibraryScanResultSummary?
    @Published public var selectedItemID: MediaItemID?

    private let mediaSummaryBrowser: any LibraryMediaSummaryBrowsing
    private let folderSummaryBrowser: any LibraryFolderSummaryBrowsing
    private let folderPicker: any LibraryFolderPicking
    private let folderAdder: any LibraryFolderAdding
    private let libraryScanner: any LibraryScanning
    private let reloadSelectedItemDetail: @MainActor (MediaItemID) async -> Void
    private var loadGeneration = 0

    public init(
        mediaSummaryBrowser: any LibraryMediaSummaryBrowsing,
        folderSummaryBrowser: any LibraryFolderSummaryBrowsing,
        folderPicker: any LibraryFolderPicking,
        folderAdder: any LibraryFolderAdding,
        libraryScanner: any LibraryScanning,
        reloadSelectedItemDetail: @escaping @MainActor (MediaItemID) async -> Void = { _ in }
    ) {
        self.mediaSummaryBrowser = mediaSummaryBrowser
        self.folderSummaryBrowser = folderSummaryBrowser
        self.folderPicker = folderPicker
        self.folderAdder = folderAdder
        self.libraryScanner = libraryScanner
        self.reloadSelectedItemDetail = reloadSelectedItemDetail
    }

    public func selectSection(_ section: LibraryBrowserSection) {
        guard section != selectedSection else { return }
        selectedSection = section
        selectedItemID = nil
        snapshot = nil
        folderSnapshot = nil
        errorMessage = nil
    }

    public func load() async {
        await loadCurrentSection()
    }

    public func reloadCurrentSection() async {
        await loadCurrentSection()
    }

    private func loadCurrentSection() async {
        loadGeneration += 1
        let generation = loadGeneration
        let section = selectedSection

        isLoading = true
        errorMessage = nil

        do {
            let page = LibraryBrowserPage(limit: 50, offset: 0)
            switch section {
            case .library, .movies, .tvEpisodes, .recentlyPlayed, .needsMetadata:
                let result = try await mediaSummaryBrowser.browse(section: section, page: page)
                guard canApplyLoadResult(section: section, generation: generation) else { return }
                snapshot = result
                folderSnapshot = nil
            case .folders:
                let result = try await folderSummaryBrowser.browseFolders(page: page)
                guard canApplyLoadResult(section: section, generation: generation) else { return }
                snapshot = nil
                folderSnapshot = result
            }
            isLoading = false
        } catch {
            guard canApplyLoadResult(section: section, generation: generation) else { return }
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func canApplyLoadResult(section: LibraryBrowserSection, generation: Int) -> Bool {
        selectedSection == section && loadGeneration == generation
    }

    public func addFolder() async {
        guard !isAddingFolder, !isScanning else {
            return
        }

        isAddingFolder = true
        workflowMessage = nil
        workflowErrorMessage = nil
        defer { isAddingFolder = false }

        do {
            guard let pickedFolder = try await folderPicker.pickLibraryFolder() else {
                return
            }

            let addedFolder = try await folderAdder.addFolder(
                AddLibraryFolderRequest(
                    rootPath: pickedFolder.rootPath,
                    displayName: pickedFolder.displayName,
                    accessBookmark: pickedFolder.accessBookmark
                )
            )

            workflowMessage = "Added folder: \(addedFolder.displayName)"
            selectedSection = .folders
            selectedItemID = nil
            snapshot = nil
            folderSnapshot = nil
            errorMessage = nil
            await reloadCurrentSection()
        } catch {
            workflowErrorMessage = error.localizedDescription
        }
    }

    public func scanLibrary() async {
        guard !isAddingFolder, !isScanning else {
            return
        }

        isScanning = true
        workflowMessage = nil
        workflowErrorMessage = nil
        defer { isScanning = false }

        do {
            let result = try await libraryScanner.scanLibrary()
            lastScanResult = result
            workflowMessage = "Scan completed."
            let selectedItemIDBeforeRefresh = selectedItemID
            await reloadCurrentSection()

            if let selectedItemIDBeforeRefresh,
               selectedItemID == selectedItemIDBeforeRefresh {
                await reloadSelectedItemDetail(selectedItemIDBeforeRefresh)
            }
        } catch {
            workflowErrorMessage = error.localizedDescription
        }
    }
}
