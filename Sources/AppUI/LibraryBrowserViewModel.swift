import Application
import Domain
import SwiftUI

@MainActor
public final class LibraryBrowserViewModel: ObservableObject {
    @Published public var selectedSection: LibraryBrowserSection = .library
    @Published public private(set) var snapshot: LibraryMediaSummarySnapshot?
    @Published public private(set) var folderSnapshot: LibraryFolderSummarySnapshot?
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    @Published public var selectedItemID: MediaItemID?

    private let mediaSummaryBrowser: any LibraryMediaSummaryBrowsing
    private let folderSummaryBrowser: any LibraryFolderSummaryBrowsing

    public init(
        mediaSummaryBrowser: any LibraryMediaSummaryBrowsing,
        folderSummaryBrowser: any LibraryFolderSummaryBrowsing
    ) {
        self.mediaSummaryBrowser = mediaSummaryBrowser
        self.folderSummaryBrowser = folderSummaryBrowser
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
        let section = selectedSection

        isLoading = true
        errorMessage = nil

        do {
            let page = LibraryBrowserPage(limit: 50, offset: 0)
            switch section {
            case .library, .movies, .tvEpisodes, .recentlyPlayed, .needsMetadata:
                let result = try await mediaSummaryBrowser.browse(section: section, page: page)
                guard selectedSection == section else { return }
                snapshot = result
                folderSnapshot = nil
            case .folders:
                let result = try await folderSummaryBrowser.browseFolders(page: page)
                guard selectedSection == section else { return }
                snapshot = nil
                folderSnapshot = result
            }
            isLoading = false
        } catch {
            guard selectedSection == section else { return }
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
