import Application

public struct AppShellEnvironment {
    public let mediaSummaryBrowser: any LibraryMediaSummaryBrowsing
    public let itemDetailBrowser: any LibraryItemDetailBrowsing

    public init(
        mediaSummaryBrowser: any LibraryMediaSummaryBrowsing,
        itemDetailBrowser: any LibraryItemDetailBrowsing
    ) {
        self.mediaSummaryBrowser = mediaSummaryBrowser
        self.itemDetailBrowser = itemDetailBrowser
    }
}
