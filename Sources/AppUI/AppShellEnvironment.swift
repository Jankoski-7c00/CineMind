import Application

public struct AppShellEnvironment {
    public let mediaSummaryBrowser: any LibraryMediaSummaryBrowsing
    public let itemDetailBrowser: any LibraryItemDetailBrowsing
    public let folderSummaryBrowser: any LibraryFolderSummaryBrowsing
    public let folderPicker: any LibraryFolderPicking
    public let folderAdder: any LibraryFolderAdding
    public let libraryScanner: any LibraryScanning
    public let playbackController: (any PlaybackApplicationControlling)?

    public init(
        mediaSummaryBrowser: any LibraryMediaSummaryBrowsing,
        itemDetailBrowser: any LibraryItemDetailBrowsing,
        folderSummaryBrowser: any LibraryFolderSummaryBrowsing,
        folderPicker: any LibraryFolderPicking,
        folderAdder: any LibraryFolderAdding,
        libraryScanner: any LibraryScanning,
        playbackController: (any PlaybackApplicationControlling)? = nil
    ) {
        self.mediaSummaryBrowser = mediaSummaryBrowser
        self.itemDetailBrowser = itemDetailBrowser
        self.folderSummaryBrowser = folderSummaryBrowser
        self.folderPicker = folderPicker
        self.folderAdder = folderAdder
        self.libraryScanner = libraryScanner
        self.playbackController = playbackController
    }
}
