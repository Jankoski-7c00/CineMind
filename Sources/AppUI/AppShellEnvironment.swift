import Application

public struct AppShellEnvironment {
    public let mediaSummaryBrowser: any LibraryMediaSummaryBrowsing
    public let mediaSearcher: any LibraryMediaSearching
    public let itemDetailBrowser: any LibraryItemDetailBrowsing
    public let curationBrowser: any LibraryCurationBrowsing
    public let curationHandler: any LibraryCurationHandling
    public let folderSummaryBrowser: any LibraryFolderSummaryBrowsing
    public let folderPicker: any LibraryFolderPicking
    public let folderAdder: any LibraryFolderAdding
    public let libraryScanner: any LibraryScanning
    public let playbackController: (any PlaybackApplicationControlling)?
    public let metadataActionsState: LibraryMetadataActionsState
    public let subtitleActions: (any LibrarySubtitleActionHandling)?
    public let subtitleActionsUnavailableMessage: String?

    public init(
        mediaSummaryBrowser: any LibraryMediaSummaryBrowsing,
        mediaSearcher: any LibraryMediaSearching,
        itemDetailBrowser: any LibraryItemDetailBrowsing,
        curationBrowser: any LibraryCurationBrowsing,
        curationHandler: any LibraryCurationHandling,
        folderSummaryBrowser: any LibraryFolderSummaryBrowsing,
        folderPicker: any LibraryFolderPicking,
        folderAdder: any LibraryFolderAdding,
        libraryScanner: any LibraryScanning,
        playbackController: (any PlaybackApplicationControlling)? = nil,
        metadataActionsState: LibraryMetadataActionsState,
        subtitleActions: (any LibrarySubtitleActionHandling)? = nil,
        subtitleActionsUnavailableMessage: String? = nil
    ) {
        self.mediaSummaryBrowser = mediaSummaryBrowser
        self.mediaSearcher = mediaSearcher
        self.itemDetailBrowser = itemDetailBrowser
        self.curationBrowser = curationBrowser
        self.curationHandler = curationHandler
        self.folderSummaryBrowser = folderSummaryBrowser
        self.folderPicker = folderPicker
        self.folderAdder = folderAdder
        self.libraryScanner = libraryScanner
        self.playbackController = playbackController
        self.metadataActionsState = metadataActionsState
        self.subtitleActions = subtitleActions
        self.subtitleActionsUnavailableMessage = subtitleActionsUnavailableMessage
    }
}
