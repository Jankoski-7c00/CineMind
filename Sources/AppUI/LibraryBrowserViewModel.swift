import Application
import Domain
import SwiftUI

@MainActor
public final class LibraryBrowserViewModel: ObservableObject {
    @Published public var selectedSection: LibraryBrowserSection = .library
    @Published public var searchText = "" {
        didSet {
            guard oldValue != searchText else { return }
            selectedItemID = nil
        }
    }
    @Published public var searchMediaTypeFilter: LibrarySearchMediaTypeFilter = .all {
        didSet {
            guard oldValue != searchMediaTypeFilter else { return }
            selectedItemID = nil
        }
    }
    @Published public var searchAvailabilityFilter: LibrarySearchAvailabilityFilter = .any {
        didSet {
            guard oldValue != searchAvailabilityFilter else { return }
            selectedItemID = nil
        }
    }
    @Published public var searchFavoriteFilter: LibrarySearchFavoriteFilter = .any {
        didSet {
            guard oldValue != searchFavoriteFilter else { return }
            selectedItemID = nil
        }
    }
    @Published public var searchTagID: TagID? {
        didSet {
            guard oldValue != searchTagID else { return }
            selectedItemID = nil
        }
    }
    @Published public var searchSort: LibrarySearchSort = .relevance {
        didSet {
            guard oldValue != searchSort else { return }
            selectedItemID = nil
        }
    }
    @Published public private(set) var curationSnapshot: LibraryCurationSnapshot = .empty
    @Published public private(set) var snapshot: LibraryMediaSummarySnapshot?
    @Published public private(set) var searchSnapshot: LibrarySearchSnapshot?
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
    private let mediaSearcher: any LibraryMediaSearching
    private let curationBrowser: any LibraryCurationBrowsing
    private let folderSummaryBrowser: any LibraryFolderSummaryBrowsing
    private let folderPicker: any LibraryFolderPicking
    private let folderAdder: any LibraryFolderAdding
    private let libraryScanner: any LibraryScanning
    private let reloadSelectedItemDetail: @MainActor (MediaItemID) async -> Void
    private var loadGeneration = 0

    public init(
        mediaSummaryBrowser: any LibraryMediaSummaryBrowsing,
        mediaSearcher: any LibraryMediaSearching,
        curationBrowser: any LibraryCurationBrowsing,
        folderSummaryBrowser: any LibraryFolderSummaryBrowsing,
        folderPicker: any LibraryFolderPicking,
        folderAdder: any LibraryFolderAdding,
        libraryScanner: any LibraryScanning,
        reloadSelectedItemDetail: @escaping @MainActor (MediaItemID) async -> Void = { _ in }
    ) {
        self.mediaSummaryBrowser = mediaSummaryBrowser
        self.mediaSearcher = mediaSearcher
        self.curationBrowser = curationBrowser
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
        if !isSearchActive {
            searchSnapshot = nil
        }
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
        let trigger = loadTrigger

        isLoading = true
        errorMessage = nil

        do {
            let page = LibraryBrowserPage(limit: 50, offset: 0)
            try await loadCurationSnapshot(generation: generation)
            guard loadGeneration == generation else { return }
            if await restartLoadIfTriggerChanged(trigger: trigger, generation: generation) {
                return
            }

            if trigger.isSearchActive {
                let result = try await mediaSearcher.search(searchRequest(trigger: trigger, page: page))
                guard canApplyLoadResult(trigger: trigger, generation: generation) else {
                    await restartCurrentLoadIfStillActive(generation: generation)
                    return
                }
                searchSnapshot = result
                folderSnapshot = nil
            } else {
                switch trigger.section {
                case .library, .movies, .tvEpisodes, .recentlyPlayed, .needsMetadata,
                     .favorites, .collection(_):
                    let result = try await mediaSummaryBrowser.browse(section: trigger.section, page: page)
                    guard canApplyLoadResult(trigger: trigger, generation: generation) else {
                        await restartCurrentLoadIfStillActive(generation: generation)
                        return
                    }
                    snapshot = result
                    searchSnapshot = nil
                    folderSnapshot = nil
                case .folders:
                    let result = try await folderSummaryBrowser.browseFolders(page: page)
                    guard canApplyLoadResult(trigger: trigger, generation: generation) else {
                        await restartCurrentLoadIfStillActive(generation: generation)
                        return
                    }
                    snapshot = nil
                    searchSnapshot = nil
                    folderSnapshot = result
                }
            }
            isLoading = false
        } catch {
            guard canApplyLoadResult(trigger: trigger, generation: generation) else { return }
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    var loadTrigger: LibraryBrowserLoadTrigger {
        LibraryBrowserLoadTrigger(
            section: selectedSection,
            searchText: searchText,
            mediaType: searchMediaTypeFilter,
            availability: searchAvailabilityFilter,
            favorite: searchFavoriteFilter,
            tagID: searchTagID,
            sort: searchSort,
            isSearchActive: isSearchActive
        )
    }

    public var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || searchMediaTypeFilter != .all
            || searchAvailabilityFilter != .any
            || searchFavoriteFilter != .any
            || searchTagID != nil
            || searchSort != .relevance
    }

    public func clearSearch() {
        searchText = ""
        searchMediaTypeFilter = .all
        searchAvailabilityFilter = .any
        searchFavoriteFilter = .any
        searchTagID = nil
        searchSort = .relevance
        selectedItemID = nil
        searchSnapshot = nil
        errorMessage = nil
    }

    private func searchRequest(
        trigger: LibraryBrowserLoadTrigger,
        page: LibraryBrowserPage
    ) -> LibrarySearchRequest {
        LibrarySearchRequest(
            text: trigger.searchText,
            mediaType: trigger.mediaType,
            availability: trigger.availability,
            favorite: trigger.favorite,
            tagID: trigger.tagID,
            sort: trigger.sort,
            page: page
        )
    }

    public func reloadCurationSnapshot() async {
        do {
            try await loadCurationSnapshot(generation: nil)
        } catch {
            workflowErrorMessage = error.localizedDescription
        }
    }

    private func loadCurationSnapshot(generation: Int?) async throws {
        let snapshot = try await curationBrowser.fetchCurationSnapshot()
        if let generation, loadGeneration != generation {
            return
        }

        curationSnapshot = snapshot

        if let searchTagID,
           !snapshot.tags.contains(where: { $0.id == searchTagID }) {
            self.searchTagID = nil
        }

        if case .collection(let selectedCollectionID) = selectedSection,
           !snapshot.collections.contains(where: { $0.id == selectedCollectionID }) {
            selectSection(.library)
        }
    }

    private func canApplyLoadResult(trigger: LibraryBrowserLoadTrigger, generation: Int) -> Bool {
        loadTrigger == trigger && loadGeneration == generation
    }

    private func restartLoadIfTriggerChanged(
        trigger: LibraryBrowserLoadTrigger,
        generation: Int
    ) async -> Bool {
        guard loadGeneration == generation, loadTrigger != trigger else {
            return false
        }
        isLoading = false
        await loadCurrentSection()
        return true
    }

    private func restartCurrentLoadIfStillActive(generation: Int) async {
        guard loadGeneration == generation else {
            return
        }
        isLoading = false
        await loadCurrentSection()
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

struct LibraryBrowserLoadTrigger: Equatable {
    let section: LibraryBrowserSection
    let searchText: String
    let mediaType: LibrarySearchMediaTypeFilter
    let availability: LibrarySearchAvailabilityFilter
    let favorite: LibrarySearchFavoriteFilter
    let tagID: TagID?
    let sort: LibrarySearchSort
    let isSearchActive: Bool
}
