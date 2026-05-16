import Application
import Domain
import SwiftUI

@MainActor
public final class LibraryBrowserViewModel: ObservableObject {
    @Published public var selectedSection: LibraryBrowserSection = .library
    @Published public private(set) var snapshot: LibraryMediaSummarySnapshot?
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    @Published public var selectedItemID: MediaItemID?

    private let mediaSummaryBrowser: any LibraryMediaSummaryBrowsing

    public init(mediaSummaryBrowser: any LibraryMediaSummaryBrowsing) {
        self.mediaSummaryBrowser = mediaSummaryBrowser
    }

    public func selectSection(_ section: LibraryBrowserSection) {
        guard section != selectedSection else { return }
        selectedSection = section
        selectedItemID = nil
        snapshot = nil
        errorMessage = nil
    }

    public func load() async {
        guard !isLoading else { return }
        let section = selectedSection

        isLoading = true
        errorMessage = nil

        do {
            let page = LibraryBrowserPage(limit: 50, offset: 0)
            let result = try await mediaSummaryBrowser.browse(section: section, page: page)

            guard selectedSection == section else { return }
            snapshot = result
            isLoading = false
        } catch {
            guard selectedSection == section else { return }
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
