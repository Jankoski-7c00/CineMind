import Application

public struct AppShellEnvironment {
    public let mediaSummaryBrowser: any LibraryMediaSummaryBrowsing
    public let itemDetailBrowser: any LibraryItemDetailBrowsing
    public let folderSummaryBrowser: any LibraryFolderSummaryBrowsing

    public init(
        mediaSummaryBrowser: any LibraryMediaSummaryBrowsing,
        itemDetailBrowser: any LibraryItemDetailBrowsing,
        folderSummaryBrowser: any LibraryFolderSummaryBrowsing
    ) {
        self.mediaSummaryBrowser = mediaSummaryBrowser
        self.itemDetailBrowser = itemDetailBrowser
        self.folderSummaryBrowser = folderSummaryBrowser
    }
}
