import AppUI
import Application
import Foundation
import Playback
import PlaybackAVFoundation
import Persistence
import Scanner

struct CineMindAppStartupEnvironment {
    let appShellEnvironment: AppShellEnvironment
    let playbackRuntime: CineMindPlaybackRuntime?
    let libraryExporter: any LibraryExporting
    let libraryExportDestinationPicker: any LibraryExportDestinationPicking
    let tmdbSettingsManager: any TMDBReadTokenSettingsManaging
}

final class CineMindPlaybackRuntime {
    let backend: AVFoundationPlaybackBackend
    let coordinator: PlaybackCoordinator
    let progressCoordinator: PlaybackProgressCoordinator
    let controller: PlaybackApplicationController

    init(
        backend: AVFoundationPlaybackBackend,
        coordinator: PlaybackCoordinator,
        progressCoordinator: PlaybackProgressCoordinator,
        controller: PlaybackApplicationController
    ) {
        self.backend = backend
        self.coordinator = coordinator
        self.progressCoordinator = progressCoordinator
        self.controller = controller
    }

    deinit {
        Task { [controller] in
            await controller.shutdown()
        }
    }
}

enum CineMindAppEnvironmentFactory {
    @MainActor
    static func start() throws -> CineMindAppStartupEnvironment {
        let appDirectoryURL = try appDirectoryURL()
        let databaseURL = appDirectoryURL.appendingPathComponent(
            "CineMind.sqlite",
            isDirectory: false
        )
        let store = try CineMindStore(path: databaseURL.path)
        _ = try store.ensureLibrary(name: "CineMind Library")
        let mediaSummaryBrowser = LibraryMediaSummaryUseCase(store: store)
        let mediaSearcher = LibraryMediaSearchUseCase(store: store)
        let itemDetailBrowser = LibraryItemDetailUseCase(store: store)
        let libraryCuration = LibraryCurationUseCase(store: store)
        let folderSummaryBrowser = LibraryFolderSummaryUseCase(store: store)
        let folderPicker = AppKitLibraryFolderPicker()
        let folderAdder = AddLibraryFolderUseCase(store: store)
        let scanRunner = ScannerLibraryScanRunner(scanner: LibraryScanner(store: store))
        let libraryScanner = RunLibraryScanUseCase(store: store, runner: scanRunner)
        let libraryExporter = LibraryExportUseCase(store: store)
        let libraryExportDestinationPicker = AppKitLibraryExportDestinationPicker()

        let playbackRuntime = makePlaybackRuntime(store: store)
        let environment = ProcessInfo.processInfo.environment
        let configuredLanguage = environment["CINEMIND_TMDB_LANGUAGE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let language = configuredLanguage.isEmpty ? "en-US" : configuredLanguage
        let metadataActionsState = LibraryMetadataActionsState()
        let metadataRuntime = TMDBMetadataRuntime(
            store: store,
            appDirectoryURL: appDirectoryURL,
            language: language,
            actionsState: metadataActionsState
        )
        let tmdbSettingsManager = TMDBReadTokenSettingsService(
            tokenStore: KeychainTMDBReadTokenStore(),
            environmentToken: environment["CINEMIND_TMDB_READ_TOKEN"],
            metadataRuntime: metadataRuntime
        )
        let subtitleActionConfiguration = makeSubtitleActions(
            store: store,
            playbackSubtitleRefresher: playbackRuntime?.controller
        )
        let appShellEnvironment = AppShellEnvironment(
            mediaSummaryBrowser: mediaSummaryBrowser,
            mediaSearcher: mediaSearcher,
            itemDetailBrowser: itemDetailBrowser,
            curationBrowser: libraryCuration,
            curationHandler: libraryCuration,
            folderSummaryBrowser: folderSummaryBrowser,
            folderPicker: folderPicker,
            folderAdder: folderAdder,
            libraryScanner: libraryScanner,
            playbackController: playbackRuntime?.controller,
            metadataActionsState: metadataActionsState,
            subtitleActions: subtitleActionConfiguration.actions,
            subtitleActionsUnavailableMessage: subtitleActionConfiguration.unavailableMessage
        )

        return CineMindAppStartupEnvironment(
            appShellEnvironment: appShellEnvironment,
            playbackRuntime: playbackRuntime,
            libraryExporter: libraryExporter,
            libraryExportDestinationPicker: libraryExportDestinationPicker,
            tmdbSettingsManager: tmdbSettingsManager
        )
    }

    private static func makePlaybackRuntime(store: CineMindStore) -> CineMindPlaybackRuntime? {
        let backend = AVFoundationPlaybackBackend()
        let coordinator = PlaybackCoordinator(backend: backend)
        let progressCoordinator = PlaybackProgressCoordinator(
            progressUseCase: PlaybackProgressUseCase(store: store)
        )
        let controller = PlaybackApplicationController(
            coordinator: coordinator,
            progressCoordinator: progressCoordinator,
            mediaOpening: OpenMediaUseCase(store: store),
            subtitleAssetReader: store
        )
        return CineMindPlaybackRuntime(
            backend: backend,
            coordinator: coordinator,
            progressCoordinator: progressCoordinator,
            controller: controller
        )
    }

    private static func makeSubtitleActions(
        store: CineMindStore,
        playbackSubtitleRefresher: (any PlaybackExternalSubtitleRefreshing)?
    ) -> SubtitleActionConfiguration {
        _ = store
        _ = playbackSubtitleRefresher
        return SubtitleActionConfiguration(
            actions: nil,
            unavailableMessage: "Subtitle search is not configured. Local and embedded subtitles are still available."
        )
    }

    private static func appDirectoryURL() throws -> URL {
        let fileManager = FileManager.default
        guard let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw StartupError.applicationSupportDirectoryUnavailable
        }

        let appDirectoryURL = applicationSupportURL.appendingPathComponent(
            "CineMind",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: appDirectoryURL,
            withIntermediateDirectories: true
        )

        return appDirectoryURL
    }

    static func startupFailureMessage(for error: Error) -> String {
        switch error {
        case StartupError.applicationSupportDirectoryUnavailable:
            return "CineMind could not locate your Application Support folder."
        case is CocoaError:
            return "CineMind could not create its Application Support folder. Check that your Library folder is writable."
        case let persistenceError as PersistenceError:
            return persistenceFailureMessage(for: persistenceError)
        default:
            return "CineMind could not start its local library."
        }
    }

    private static func persistenceFailureMessage(for error: PersistenceError) -> String {
        switch error {
        case .openFailed:
            return "CineMind could not open its local library database."
        case .migrationFailed:
            return "CineMind could not prepare its local library database."
        case .prepareFailed, .bindFailed, .stepFailed, .transactionFailed:
            return "CineMind could not initialize its local library database."
        case .mediaFileMediaItemMismatch,
             .duplicatePlaybackHistoryPair,
             .posterAssetNotFound,
             .libraryExportUnavailable,
             .libraryExportIntegrityViolation:
            return "CineMind could not initialize its local library data."
        }
    }

    private enum StartupError: Error {
        case applicationSupportDirectoryUnavailable
    }
}

private struct SubtitleActionConfiguration {
    let actions: (any LibrarySubtitleActionHandling)?
    let unavailableMessage: String?
}
