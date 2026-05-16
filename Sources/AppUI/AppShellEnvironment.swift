import Application

public struct AppShellEnvironment {
    public let mediaSummaryBrowser: any LibraryMediaSummaryBrowsing

    public init(mediaSummaryBrowser: any LibraryMediaSummaryBrowsing) {
        self.mediaSummaryBrowser = mediaSummaryBrowser
    }
}
