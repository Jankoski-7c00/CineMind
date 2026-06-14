import AppUI
import Application
import Foundation
import Metadata
import Persistence

@MainActor
final class TMDBMetadataRuntime: TMDBMetadataRuntimeConfiguring {
    private let store: CineMindStore
    private let appDirectoryURL: URL
    private let language: String
    private let actionsState: LibraryMetadataActionsState

    init(
        store: CineMindStore,
        appDirectoryURL: URL,
        language: String,
        actionsState: LibraryMetadataActionsState
    ) {
        self.store = store
        self.appDirectoryURL = appDirectoryURL
        self.language = language
        self.actionsState = actionsState
    }

    func configureMetadataActions(readToken: String?) {
        let token = readToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else {
            actionsState.update(
                actions: nil,
                unavailableMessage: "Open CineMind Settings to configure TMDB metadata actions."
            )
            return
        }

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

        actionsState.update(
            actions: LibraryMetadataActionService(
                store: store,
                provider: provider,
                posterCache: posterCache,
                language: language
            ),
            unavailableMessage: nil
        )
    }
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
