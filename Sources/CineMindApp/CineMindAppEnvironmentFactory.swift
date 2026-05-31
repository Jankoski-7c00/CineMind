import AppUI
import Application
import Foundation
import Metadata
import Playback
import PlaybackAVFoundation
import Persistence
import Scanner

struct CineMindAppStartupEnvironment {
    let appShellEnvironment: AppShellEnvironment
    let playbackRuntime: CineMindPlaybackRuntime?
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
    static func start() throws -> CineMindAppStartupEnvironment {
        let appDirectoryURL = try appDirectoryURL()
        let databaseURL = appDirectoryURL.appendingPathComponent(
            "CineMind.sqlite",
            isDirectory: false
        )
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
        let metadataActionConfiguration = makeMetadataActions(
            store: store,
            appDirectoryURL: appDirectoryURL
        )
        let subtitleActionConfiguration = makeSubtitleActions(
            store: store,
            playbackSubtitleRefresher: playbackRuntime?.controller
        )
        let appShellEnvironment = AppShellEnvironment(
            mediaSummaryBrowser: mediaSummaryBrowser,
            itemDetailBrowser: itemDetailBrowser,
            folderSummaryBrowser: folderSummaryBrowser,
            folderPicker: folderPicker,
            folderAdder: folderAdder,
            libraryScanner: libraryScanner,
            playbackController: playbackRuntime?.controller,
            metadataActions: metadataActionConfiguration.actions,
            metadataActionsUnavailableMessage: metadataActionConfiguration.unavailableMessage,
            subtitleActions: subtitleActionConfiguration.actions,
            subtitleActionsUnavailableMessage: subtitleActionConfiguration.unavailableMessage
        )

        return CineMindAppStartupEnvironment(
            appShellEnvironment: appShellEnvironment,
            playbackRuntime: playbackRuntime
        )
    }

    private static func makeMetadataActions(
        store: CineMindStore,
        appDirectoryURL: URL
    ) -> MetadataActionConfiguration {
        let environment = ProcessInfo.processInfo.environment
        let token = environment["CINEMIND_TMDB_READ_TOKEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else {
            return MetadataActionConfiguration(
                actions: nil,
                unavailableMessage: "Set CINEMIND_TMDB_READ_TOKEN to enable metadata actions."
            )
        }

        let language = environment["CINEMIND_TMDB_LANGUAGE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmptyValue ?? "en-US"
        let httpClient = URLSessionMetadataHTTPClient()
        let provider = TMDBMetadataProvider(
            configuration: TMDBMetadataProvider.Configuration(
                bearerToken: token,
                defaultLanguage: language
            ),
            httpClient: httpClient
        )
        let posterCache = LazyTMDBPosterCache(
            provider: provider,
            posterCache: PosterCache(
                configuration: PosterCacheConfiguration(
                    cacheRoot: appDirectoryURL.appendingPathComponent(
                        "PosterCache",
                        isDirectory: true
                    )
                ),
                httpClient: httpClient
            )
        )

        return MetadataActionConfiguration(
            actions: LibraryMetadataActionService(
                store: store,
                provider: provider,
                posterCache: posterCache,
                language: language
            ),
            unavailableMessage: nil
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
             .posterAssetNotFound:
            return "CineMind could not initialize its local library data."
        }
    }

    private enum StartupError: Error {
        case applicationSupportDirectoryUnavailable
    }
}

private struct MetadataActionConfiguration {
    let actions: (any LibraryMetadataActionHandling)?
    let unavailableMessage: String?
}

private struct SubtitleActionConfiguration {
    let actions: (any LibrarySubtitleActionHandling)?
    let unavailableMessage: String?
}

private final class LazyTMDBPosterCache: ApplicationPosterCaching, @unchecked Sendable {
    private let provider: TMDBMetadataProvider
    private let posterCache: PosterCache
    private var imageConfiguration: TMDBImageConfiguration?

    init(provider: TMDBMetadataProvider, posterCache: PosterCache) {
        self.provider = provider
        self.posterCache = posterCache
    }

    func cache(_ image: RemoteImage) async throws -> PosterCacheResult {
        let configuration: TMDBImageConfiguration
        if let cachedConfiguration = imageConfiguration {
            configuration = cachedConfiguration
        } else {
            let fetchedConfiguration = try await provider.fetchImageConfiguration()
            imageConfiguration = fetchedConfiguration
            configuration = fetchedConfiguration
        }

        return try await posterCache.cache(image, using: configuration)
    }
}

private final class URLSessionMetadataHTTPClient: MetadataHTTPClient {
    func send(_ request: URLRequest) async throws -> MetadataHTTPResponse {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SanitizedHTTPClientError.invalidResponse
            }
            return MetadataHTTPResponse(statusCode: httpResponse.statusCode, data: data)
        } catch let error as SanitizedHTTPClientError {
            throw error
        } catch {
            throw SanitizedHTTPClientError.transportFailure
        }
    }
}

private enum SanitizedHTTPClientError: Error {
    case invalidResponse
    case transportFailure
}

private extension String {
    var nonEmptyValue: String? {
        isEmpty ? nil : self
    }
}
