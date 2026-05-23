import AppUI
import Application
import Foundation
import LibMPVPlayback
import Playback
import Persistence
import Scanner

struct CineMindAppStartupEnvironment {
    let appShellEnvironment: AppShellEnvironment
    let playbackRuntime: CineMindPlaybackRuntime?
}

final class CineMindPlaybackRuntime {
    let backend: LibMPVPlaybackBackend
    let coordinator: PlaybackCoordinator
    let progressCoordinator: PlaybackProgressCoordinator
    let controller: PlaybackApplicationController

    init(
        backend: LibMPVPlaybackBackend,
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
        Task { [coordinator] in
            await coordinator.shutdown()
        }
    }
}

enum CineMindAppEnvironmentFactory {
    static func start() throws -> CineMindAppStartupEnvironment {
        let databaseURL = try databaseURL()
        let store = try CineMindStore(path: databaseURL.path)
        _ = try store.ensureLibrary(name: "CineMind Library")
        let mediaSummaryBrowser = LibraryMediaSummaryUseCase(store: store)
        let itemDetailBrowser = LibraryItemDetailUseCase(store: store)
        let folderSummaryBrowser = LibraryFolderSummaryUseCase(store: store)
        let folderPicker = AppKitLibraryFolderPicker()
        let folderAdder = AddLibraryFolderUseCase(store: store)
        let scanRunner = ScannerLibraryScanRunner(scanner: LibraryScanner(store: store))
        let libraryScanner = RunLibraryScanUseCase(store: store, runner: scanRunner)

        let playbackRuntime = makePlaybackRuntime(store: store)
        let appShellEnvironment = AppShellEnvironment(
            mediaSummaryBrowser: mediaSummaryBrowser,
            itemDetailBrowser: itemDetailBrowser,
            folderSummaryBrowser: folderSummaryBrowser,
            folderPicker: folderPicker,
            folderAdder: folderAdder,
            libraryScanner: libraryScanner,
            playbackController: playbackRuntime?.controller
        )

        return CineMindAppStartupEnvironment(
            appShellEnvironment: appShellEnvironment,
            playbackRuntime: playbackRuntime
        )
    }

    private static func makePlaybackRuntime(store: CineMindStore) -> CineMindPlaybackRuntime? {
        do {
            let backend = try LibMPVPlaybackBackend(mode: .embedded)
            let coordinator = PlaybackCoordinator(backend: backend)
            let progressCoordinator = PlaybackProgressCoordinator(
                progressUseCase: PlaybackProgressUseCase(store: store)
            )
            let controller = PlaybackApplicationController(
                coordinator: coordinator,
                progressCoordinator: progressCoordinator,
                mediaOpening: OpenMediaUseCase(store: store)
            )
            return CineMindPlaybackRuntime(
                backend: backend,
                coordinator: coordinator,
                progressCoordinator: progressCoordinator,
                controller: controller
            )
        } catch {
            writeWarning("Playback runtime unavailable: \(error)")
            return nil
        }
    }

    private static func databaseURL() throws -> URL {
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

        return appDirectoryURL.appendingPathComponent(
            "CineMind.sqlite",
            isDirectory: false
        )
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
             .posterAssetNotFound:
            return "CineMind could not initialize its local library data."
        }
    }

    private enum StartupError: Error {
        case applicationSupportDirectoryUnavailable
    }
}

private func writeWarning(_ message: String) {
    FileHandle.standardError.write(Data(("Warning: " + message + "\n").utf8))
}
