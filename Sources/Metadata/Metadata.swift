import Domain
import Foundation

public enum MetadataModule {
    public static let name = "Metadata"
}

public protocol MetadataProvider {
    var providerName: MetadataProviderName { get }

    func search(query: MetadataSearchQuery) async throws -> [MetadataCandidate]
    func fetchDetails(identifier: MetadataProviderIdentifier) async throws -> MetadataDetails
    func fetchImages(identifier: MetadataProviderIdentifier) async throws -> [RemoteImage]
}

public protocol MetadataHTTPClient {
    func send(_ request: URLRequest) async throws -> MetadataHTTPResponse
}

public struct MetadataHTTPResponse: Equatable {
    public var statusCode: Int
    public var data: Data
    public var headers: [String: String]

    public init(statusCode: Int, data: Data, headers: [String: String] = [:]) {
        self.statusCode = statusCode
        self.data = data
        self.headers = headers
    }
}

public struct MetadataSearchQuery: Equatable, Sendable {
    public var mediaItemID: MediaItemID?
    public var mediaType: MediaType
    public var title: String
    public var year: Int?
    public var seriesTitle: String?
    public var seasonNumber: Int?
    public var episodeNumber: Int?
    public var imdbID: String?
    public var language: String?

    public init(
        mediaItemID: MediaItemID? = nil,
        mediaType: MediaType,
        title: String,
        year: Int? = nil,
        seriesTitle: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        imdbID: String? = nil,
        language: String? = nil
    ) {
        self.mediaItemID = mediaItemID
        self.mediaType = mediaType
        self.title = title
        self.year = year
        self.seriesTitle = seriesTitle
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.imdbID = imdbID
        self.language = language
    }

    public static func movie(
        mediaItemID: MediaItemID? = nil,
        title: String,
        year: Int? = nil,
        imdbID: String? = nil,
        language: String? = nil
    ) -> MetadataSearchQuery {
        MetadataSearchQuery(
            mediaItemID: mediaItemID,
            mediaType: .movie,
            title: title,
            year: year,
            imdbID: imdbID,
            language: language
        )
    }

    public static func episode(
        mediaItemID: MediaItemID? = nil,
        seriesTitle: String,
        seasonNumber: Int,
        episodeNumber: Int,
        episodeTitle: String? = nil,
        imdbID: String? = nil,
        language: String? = nil
    ) -> MetadataSearchQuery {
        MetadataSearchQuery(
            mediaItemID: mediaItemID,
            mediaType: .episode,
            title: episodeTitle ?? seriesTitle,
            seriesTitle: seriesTitle,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            imdbID: imdbID,
            language: language
        )
    }
}

public struct MetadataProviderIdentifier: RawRepresentable, Codable, Equatable, Sendable, CustomStringConvertible {
    public enum Kind: String, Codable, Sendable {
        case movie
        case episode
    }

    public let rawValue: String
    public let kind: Kind
    public let movieID: Int?
    public let seriesID: Int?
    public let seasonNumber: Int?
    public let episodeNumber: Int?

    public var description: String {
        rawValue
    }

    public var providerMediaType: MetadataProviderMediaType {
        switch kind {
        case .movie:
            .movie
        case .episode:
            .episode
        }
    }

    public init?(rawValue: String) {
        let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false).map(String.init)

        if parts.count == 2, parts[0] == "movie", let movieID = Self.positiveInt(parts[1]) {
            self.rawValue = "movie:\(movieID)"
            self.kind = .movie
            self.movieID = movieID
            self.seriesID = nil
            self.seasonNumber = nil
            self.episodeNumber = nil
            return
        }

        if parts.count == 4,
           parts[0] == "tv",
           let seriesID = Self.positiveInt(parts[1]),
           let seasonNumber = Self.prefixedPositiveInt(parts[2], prefix: "s"),
           let episodeNumber = Self.prefixedPositiveInt(parts[3], prefix: "e") {
            self.rawValue = "tv:\(seriesID):s\(seasonNumber):e\(episodeNumber)"
            self.kind = .episode
            self.movieID = nil
            self.seriesID = seriesID
            self.seasonNumber = seasonNumber
            self.episodeNumber = episodeNumber
            return
        }

        return nil
    }

    public static func movie(id: Int) -> MetadataProviderIdentifier? {
        guard id > 0 else {
            return nil
        }
        return MetadataProviderIdentifier(rawValue: "movie:\(id)")
    }

    public static func episode(
        seriesID: Int,
        seasonNumber: Int,
        episodeNumber: Int
    ) -> MetadataProviderIdentifier? {
        guard seriesID > 0, seasonNumber > 0, episodeNumber > 0 else {
            return nil
        }
        return MetadataProviderIdentifier(rawValue: "tv:\(seriesID):s\(seasonNumber):e\(episodeNumber)")
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let identifier = MetadataProviderIdentifier(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid metadata provider identifier."
            )
        }
        self = identifier
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func positiveInt(_ value: String) -> Int? {
        guard let first = value.first,
              first >= "1",
              first <= "9",
              value.allSatisfy(\.isNumber),
              let parsed = Int(value) else {
            return nil
        }
        return parsed
    }

    private static func prefixedPositiveInt(_ value: String, prefix: Character) -> Int? {
        guard value.first == prefix else {
            return nil
        }
        return positiveInt(String(value.dropFirst()))
    }
}

public struct MetadataCandidate: Equatable, Sendable {
    public var identifier: MetadataProviderIdentifier
    public var displayTitle: String
    public var originalTitle: String?
    public var year: Int?
    public var airDate: String?
    public var episodeTitle: String?
    public var overviewPreview: String?
    public var confidence: Double
    public var confidenceInputs: [String: String]

    public init(
        identifier: MetadataProviderIdentifier,
        displayTitle: String,
        originalTitle: String? = nil,
        year: Int? = nil,
        airDate: String? = nil,
        episodeTitle: String? = nil,
        overviewPreview: String? = nil,
        confidence: Double,
        confidenceInputs: [String: String] = [:]
    ) {
        self.identifier = identifier
        self.displayTitle = displayTitle
        self.originalTitle = originalTitle
        self.year = year
        self.airDate = airDate
        self.episodeTitle = episodeTitle
        self.overviewPreview = overviewPreview
        self.confidence = min(1.0, max(0.0, confidence))
        self.confidenceInputs = confidenceInputs
    }
}

public struct MetadataDetails: Equatable, Sendable {
    public var identifier: MetadataProviderIdentifier
    public var title: String
    public var originalTitle: String?
    public var summary: String?
    public var language: String?
    public var releaseDate: String?
    public var airDate: String?
    public var externalIDs: [MetadataExternalIDType: String]
    public var rawPayloadJSON: String

    public var providerMediaType: MetadataProviderMediaType {
        identifier.providerMediaType
    }

    public init(
        identifier: MetadataProviderIdentifier,
        title: String,
        originalTitle: String? = nil,
        summary: String? = nil,
        language: String? = nil,
        releaseDate: String? = nil,
        airDate: String? = nil,
        externalIDs: [MetadataExternalIDType: String] = [:],
        rawPayloadJSON: String
    ) {
        self.identifier = identifier
        self.title = title
        self.originalTitle = originalTitle
        self.summary = summary
        self.language = language
        self.releaseDate = releaseDate
        self.airDate = airDate
        self.externalIDs = externalIDs
        self.rawPayloadJSON = rawPayloadJSON
    }
}

public struct RemoteImage: Equatable, Sendable {
    public var source: PosterAssetSource
    public var remotePath: String
    public var width: Int?
    public var height: Int?
    public var aspectRatio: Double?
    public var preferredCacheSize: String

    public init(
        source: PosterAssetSource,
        remotePath: String,
        width: Int? = nil,
        height: Int? = nil,
        aspectRatio: Double? = nil,
        preferredCacheSize: String
    ) {
        self.source = source
        self.remotePath = remotePath
        self.width = width
        self.height = height
        if let aspectRatio {
            self.aspectRatio = aspectRatio
        } else if let width, let height, height > 0 {
            self.aspectRatio = Double(width) / Double(height)
        } else {
            self.aspectRatio = nil
        }
        self.preferredCacheSize = preferredCacheSize
    }
}

public enum MetadataError: Error, Equatable, Sendable, CustomStringConvertible {
    case missingToken
    case unauthorized
    case notFound
    case rateLimited
    case serverUnavailable(statusCode: Int)
    case invalidResponse
    case transportFailure

    public var description: String {
        switch self {
        case .missingToken:
            "TMDB read token is missing."
        case .unauthorized:
            "Metadata provider rejected authentication."
        case .notFound:
            "Metadata provider resource was not found."
        case .rateLimited:
            "Metadata provider rate limit was reached."
        case .serverUnavailable:
            "Metadata provider is temporarily unavailable."
        case .invalidResponse:
            "Metadata provider returned an invalid response."
        case .transportFailure:
            "Metadata provider request failed before a response was received."
        }
    }
}

public struct TMDBImageConfiguration: Equatable, Sendable {
    public var secureBaseURL: URL
    public var posterSizes: [String]
    public var backdropSizes: [String]

    public init(secureBaseURL: URL, posterSizes: [String], backdropSizes: [String] = []) {
        self.secureBaseURL = secureBaseURL
        self.posterSizes = posterSizes
        self.backdropSizes = backdropSizes
    }
}

public struct TMDBMetadataProvider: MetadataProvider {
    public struct Configuration: Equatable, Sendable {
        public var apiBaseURL: URL
        public var bearerToken: String
        public var defaultLanguage: String

        public init(
            bearerToken: String,
            defaultLanguage: String = "en-US",
            apiBaseURL: URL = TMDBMetadataProvider.defaultAPIBaseURL
        ) {
            self.apiBaseURL = apiBaseURL
            self.bearerToken = bearerToken
            self.defaultLanguage = defaultLanguage
        }
    }

    public static let defaultAPIBaseURL = URL(string: "https://api.themoviedb.org")!

    public let providerName: MetadataProviderName = .tmdb

    private static let fallbackConfidenceThreshold = 0.85
    private static let episodeSeriesProbeLimit = 10

    private let configuration: Configuration
    private let httpClient: any MetadataHTTPClient
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder

    public init(configuration: Configuration, httpClient: any MetadataHTTPClient) {
        self.configuration = configuration
        self.httpClient = httpClient
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
    }

    public func search(query: MetadataSearchQuery) async throws -> [MetadataCandidate] {
        switch query.mediaType {
        case .movie:
            try await searchMovies(query: query)
        case .episode:
            try await searchEpisodes(query: query)
        }
    }

    public func fetchDetails(identifier: MetadataProviderIdentifier) async throws -> MetadataDetails {
        switch identifier.kind {
        case .movie:
            guard let movieID = identifier.movieID else {
                throw MetadataError.invalidResponse
            }
            let data = try await send(
                path: "/3/movie/\(movieID)",
                queryItems: [
                    URLQueryItem(name: "append_to_response", value: "external_ids"),
                    URLQueryItem(name: "language", value: configuration.defaultLanguage)
                ]
            )
            let details = try decode(TMDBMovieDetailsResponse.self, from: data)
            return try mapMovieDetails(details, identifier: identifier)
        case .episode:
            guard let seriesID = identifier.seriesID,
                  let seasonNumber = identifier.seasonNumber,
                  let episodeNumber = identifier.episodeNumber else {
                throw MetadataError.invalidResponse
            }
            let data = try await send(
                path: "/3/tv/\(seriesID)/season/\(seasonNumber)/episode/\(episodeNumber)",
                queryItems: [
                    URLQueryItem(name: "append_to_response", value: "external_ids"),
                    URLQueryItem(name: "language", value: configuration.defaultLanguage)
                ]
            )
            let details = try decode(TMDBEpisodeDetailsResponse.self, from: data)
            return try mapEpisodeDetails(details, identifier: identifier)
        }
    }

    public func fetchImages(identifier: MetadataProviderIdentifier) async throws -> [RemoteImage] {
        let path: String

        switch identifier.kind {
        case .movie:
            guard let movieID = identifier.movieID else {
                throw MetadataError.invalidResponse
            }
            path = "/3/movie/\(movieID)/images"
        case .episode:
            guard let seriesID = identifier.seriesID else {
                throw MetadataError.invalidResponse
            }
            path = "/3/tv/\(seriesID)/images"
        }

        let data = try await send(path: path)
        let response = try decode(TMDBImagesResponse.self, from: data)
        return response.posters.compactMap { image in
            guard !image.filePath.isEmpty else {
                return nil
            }
            return RemoteImage(
                source: .tmdb,
                remotePath: image.filePath,
                width: image.width,
                height: image.height,
                aspectRatio: image.aspectRatio,
                preferredCacheSize: "w500"
            )
        }
    }

    public func fetchImageConfiguration() async throws -> TMDBImageConfiguration {
        let data = try await send(path: "/3/configuration")
        let response = try decode(TMDBConfigurationResponse.self, from: data)
        guard let secureBaseURL = URL(string: response.images.secureBaseURL) else {
            throw MetadataError.invalidResponse
        }
        return TMDBImageConfiguration(
            secureBaseURL: secureBaseURL,
            posterSizes: response.images.posterSizes,
            backdropSizes: response.images.backdropSizes
        )
    }

    public func imageURL(
        for image: RemoteImage,
        using imageConfiguration: TMDBImageConfiguration,
        size requestedSize: String? = nil
    ) -> URL? {
        TMDBImageURLResolver.imageURL(
            for: image,
            using: imageConfiguration,
            size: requestedSize
        )
    }

    private func searchMovies(query: MetadataSearchQuery) async throws -> [MetadataCandidate] {
        if let foundCandidates = try await findCandidates(query: query), !foundCandidates.isEmpty {
            return MetadataCandidateRankingPolicy().rankMovieCandidates(for: query, candidates: foundCandidates)
        }

        var mergedCandidates: [MetadataCandidate] = []
        for attempt in movieSearchAttempts(for: query) {
            let candidates = try await searchMovieCandidates(query: query, attempt: attempt)
            mergedCandidates = merged(mergedCandidates, with: candidates)
            let ranked = MetadataCandidateRankingPolicy().rankMovieCandidates(for: query, candidates: mergedCandidates)
            if (ranked.first?.confidence ?? 0.0) >= Self.fallbackConfidenceThreshold {
                return ranked
            }
        }

        return MetadataCandidateRankingPolicy().rankMovieCandidates(for: query, candidates: mergedCandidates)
    }

    private func searchMovieCandidates(
        query: MetadataSearchQuery,
        attempt: MovieSearchAttempt
    ) async throws -> [MetadataCandidate] {
        let data = try await send(
            path: "/3/search/movie",
            queryItems: movieSearchQueryItems(query: query, attempt: attempt)
        )
        let response = try decode(TMDBMovieSearchResponse.self, from: data)
        return response.results.compactMap {
            movieCandidate(from: $0)
        }
    }

    private func searchEpisodes(query: MetadataSearchQuery) async throws -> [MetadataCandidate] {
        guard let seriesTitle = query.seriesTitle?.nonEmptyValue ?? query.title.nonEmptyValue,
              let seasonNumber = query.seasonNumber,
              let episodeNumber = query.episodeNumber else {
            throw MetadataError.invalidResponse
        }

        if let foundCandidates = try await findCandidates(query: query), !foundCandidates.isEmpty {
            return MetadataCandidateRankingPolicy().rankEpisodeCandidates(for: query, candidates: foundCandidates)
        }

        let data = try await send(
            path: "/3/search/tv",
            queryItems: defaultSearchQueryItems(query: seriesTitle, language: query.language)
        )
        let response = try decode(TMDBTVSearchResponse.self, from: data)
        var candidates: [MetadataCandidate] = []

        for series in response.results.prefix(Self.episodeSeriesProbeLimit) {
            guard let identifier = MetadataProviderIdentifier.episode(
                seriesID: series.id,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber
            ) else {
                continue
            }

            let episodeDetails: TMDBEpisodeDetailsResponse
            do {
                let episodeData = try await send(
                    path: "/3/tv/\(series.id)/season/\(seasonNumber)/episode/\(episodeNumber)",
                    queryItems: [
                        URLQueryItem(name: "append_to_response", value: "external_ids"),
                        URLQueryItem(name: "language", value: query.language ?? configuration.defaultLanguage)
                    ]
                )
                episodeDetails = try decode(TMDBEpisodeDetailsResponse.self, from: episodeData)
            } catch MetadataError.notFound {
                continue
            }

            let year = year(from: series.firstAirDate)
            candidates.append(
                MetadataCandidate(
                    identifier: identifier,
                    displayTitle: series.name ?? series.originalName ?? "Untitled Series",
                    originalTitle: series.originalName,
                    year: year,
                    airDate: episodeDetails.airDate,
                    episodeTitle: episodeDetails.name,
                    overviewPreview: overviewPreview(episodeDetails.overview ?? series.overview),
                    confidence: 0.0
                )
            )
        }

        return MetadataCandidateRankingPolicy().rankEpisodeCandidates(for: query, candidates: candidates)
    }

    private func findCandidates(query: MetadataSearchQuery) async throws -> [MetadataCandidate]? {
        guard let imdbID = normalizedIMDBID(query.imdbID) else {
            return nil
        }

        let data = try await send(
            path: "/3/find/\(imdbID)",
            queryItems: [URLQueryItem(name: "external_source", value: "imdb_id")]
        )
        let response = try decode(TMDBFindResponse.self, from: data)

        switch query.mediaType {
        case .movie:
            return response.movieResults.compactMap {
                movieCandidate(from: $0)
            }
        case .episode:
            guard let seasonNumber = query.seasonNumber,
                  let episodeNumber = query.episodeNumber else {
                return []
            }
            let seriesTitle = query.seriesTitle ?? query.title
            return response.tvEpisodeResults.compactMap { result in
                guard result.seasonNumber == seasonNumber,
                      result.episodeNumber == episodeNumber,
                      let showID = result.showID,
                      let identifier = MetadataProviderIdentifier.episode(
                        seriesID: showID,
                        seasonNumber: seasonNumber,
                        episodeNumber: episodeNumber
                      ) else {
                    return nil
                }

                return MetadataCandidate(
                    identifier: identifier,
                    displayTitle: seriesTitle,
                    airDate: result.airDate,
                    episodeTitle: result.name,
                    overviewPreview: overviewPreview(result.overview),
                    confidence: 0.0
                )
            }
        }
    }

    private func movieCandidate(from result: TMDBMovieSearchResult) -> MetadataCandidate? {
        guard let identifier = MetadataProviderIdentifier.movie(id: result.id) else {
            return nil
        }
        let year = year(from: result.releaseDate)
        return MetadataCandidate(
            identifier: identifier,
            displayTitle: result.title ?? result.originalTitle ?? "Untitled Movie",
            originalTitle: result.originalTitle,
            year: year,
            overviewPreview: overviewPreview(result.overview),
            confidence: 0.0
        )
    }

    private func movieSearchAttempts(for query: MetadataSearchQuery) -> [MovieSearchAttempt] {
        guard let year = query.year else {
            return [.none]
        }
        return [.primaryReleaseYear(year), .year(year), .none]
    }

    private func movieSearchQueryItems(
        query: MetadataSearchQuery,
        attempt: MovieSearchAttempt
    ) -> [URLQueryItem] {
        var queryItems = defaultSearchQueryItems(query: query.title, language: query.language)
        switch attempt {
        case .primaryReleaseYear(let year):
            queryItems.append(URLQueryItem(name: "primary_release_year", value: "\(year)"))
        case .year(let year):
            queryItems.append(URLQueryItem(name: "year", value: "\(year)"))
        case .none:
            break
        }
        return queryItems
    }

    private func merged(
        _ existingCandidates: [MetadataCandidate],
        with newCandidates: [MetadataCandidate]
    ) -> [MetadataCandidate] {
        var seenIdentifiers = Set(existingCandidates.map(\.identifier.rawValue))
        var mergedCandidates = existingCandidates
        for candidate in newCandidates where !seenIdentifiers.contains(candidate.identifier.rawValue) {
            seenIdentifiers.insert(candidate.identifier.rawValue)
            mergedCandidates.append(candidate)
        }
        return mergedCandidates
    }

    private func defaultSearchQueryItems(query: String, language: String?) -> [URLQueryItem] {
        [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "language", value: language ?? configuration.defaultLanguage),
            URLQueryItem(name: "page", value: "1")
        ]
    }

    private func send(path: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        let request = try makeRequest(path: path, queryItems: queryItems)
        let response: MetadataHTTPResponse
        do {
            response = try await httpClient.send(request)
        } catch {
            throw MetadataError.transportFailure
        }

        switch response.statusCode {
        case 200...299:
            return response.data
        case 401:
            throw MetadataError.unauthorized
        case 404:
            throw MetadataError.notFound
        case 429:
            throw MetadataError.rateLimited
        case 500...599:
            throw MetadataError.serverUnavailable(statusCode: response.statusCode)
        default:
            throw MetadataError.invalidResponse
        }
    }

    private func makeRequest(path: String, queryItems: [URLQueryItem]) throws -> URLRequest {
        let token = configuration.bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw MetadataError.missingToken
        }

        guard var components = URLComponents(url: configuration.apiBaseURL, resolvingAgainstBaseURL: false) else {
            throw MetadataError.invalidResponse
        }

        let basePath = components.path == "/" ? "" : components.path
        components.path = basePath + path
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw MetadataError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw MetadataError.invalidResponse
        }
    }

    private func encodeCompactPayload<T: Encodable>(_ value: T) throws -> String {
        do {
            let data = try encoder.encode(value)
            guard let string = String(data: data, encoding: .utf8) else {
                throw MetadataError.invalidResponse
            }
            return string
        } catch let error as MetadataError {
            throw error
        } catch {
            throw MetadataError.invalidResponse
        }
    }

    private func mapMovieDetails(
        _ details: TMDBMovieDetailsResponse,
        identifier: MetadataProviderIdentifier
    ) throws -> MetadataDetails {
        let imdbID = details.externalIDs?.imdbID?.nonEmptyValue
        var externalIDs: [MetadataExternalIDType: String] = [.tmdbMovie: "\(details.id)"]
        if let imdbID {
            externalIDs[.imdb] = imdbID
        }

        let payload = CompactMoviePayload(
            id: details.id,
            title: details.title,
            originalTitle: details.originalTitle,
            overview: details.overview,
            originalLanguage: details.originalLanguage,
            releaseDate: details.releaseDate,
            imdbID: imdbID,
            posterPath: details.posterPath
        )

        return MetadataDetails(
            identifier: identifier,
            title: details.title ?? details.originalTitle ?? "Untitled Movie",
            originalTitle: details.originalTitle,
            summary: details.overview,
            language: details.originalLanguage,
            releaseDate: details.releaseDate,
            externalIDs: externalIDs,
            rawPayloadJSON: try encodeCompactPayload(payload)
        )
    }

    private func mapEpisodeDetails(
        _ details: TMDBEpisodeDetailsResponse,
        identifier: MetadataProviderIdentifier
    ) throws -> MetadataDetails {
        guard let seriesID = identifier.seriesID else {
            throw MetadataError.invalidResponse
        }

        let imdbID = details.externalIDs?.imdbID?.nonEmptyValue
        var externalIDs: [MetadataExternalIDType: String] = [
            .tmdbTVSeries: "\(seriesID)",
            .tmdbEpisode: "\(details.id)"
        ]
        if let imdbID {
            externalIDs[.imdb] = imdbID
        }

        let payload = CompactEpisodePayload(
            seriesID: seriesID,
            seasonNumber: details.seasonNumber,
            episodeNumber: details.episodeNumber,
            episodeID: details.id,
            name: details.name,
            overview: details.overview,
            airDate: details.airDate,
            imdbID: imdbID
        )

        return MetadataDetails(
            identifier: identifier,
            title: details.name ?? "Untitled Episode",
            summary: details.overview,
            airDate: details.airDate,
            externalIDs: externalIDs,
            rawPayloadJSON: try encodeCompactPayload(payload)
        )
    }

}

private struct TMDBMovieSearchResponse: Decodable {
    var results: [TMDBMovieSearchResult]
}

private struct TMDBMovieSearchResult: Decodable {
    var id: Int
    var title: String?
    var originalTitle: String?
    var overview: String?
    var releaseDate: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case originalTitle = "original_title"
        case overview
        case releaseDate = "release_date"
    }
}

private struct TMDBTVSearchResponse: Decodable {
    var results: [TMDBTVSearchResult]
}

private struct TMDBTVSearchResult: Decodable {
    var id: Int
    var name: String?
    var originalName: String?
    var overview: String?
    var firstAirDate: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case originalName = "original_name"
        case overview
        case firstAirDate = "first_air_date"
    }
}

private enum MovieSearchAttempt {
    case primaryReleaseYear(Int)
    case year(Int)
    case none
}

private struct TMDBFindResponse: Decodable {
    var movieResults: [TMDBMovieSearchResult]
    var tvEpisodeResults: [TMDBTVEpisodeFindResult]

    private enum CodingKeys: String, CodingKey {
        case movieResults = "movie_results"
        case tvEpisodeResults = "tv_episode_results"
    }
}

private struct TMDBTVEpisodeFindResult: Decodable {
    var id: Int
    var name: String?
    var overview: String?
    var airDate: String?
    var seasonNumber: Int?
    var episodeNumber: Int?
    var showID: Int?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case overview
        case airDate = "air_date"
        case seasonNumber = "season_number"
        case episodeNumber = "episode_number"
        case showID = "show_id"
    }
}

private struct TMDBMovieDetailsResponse: Decodable {
    var id: Int
    var title: String?
    var originalTitle: String?
    var overview: String?
    var originalLanguage: String?
    var releaseDate: String?
    var posterPath: String?
    var externalIDs: TMDBExternalIDs?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case originalTitle = "original_title"
        case overview
        case originalLanguage = "original_language"
        case releaseDate = "release_date"
        case posterPath = "poster_path"
        case externalIDs = "external_ids"
    }
}

private struct TMDBEpisodeDetailsResponse: Decodable {
    var id: Int
    var name: String?
    var overview: String?
    var airDate: String?
    var seasonNumber: Int
    var episodeNumber: Int
    var externalIDs: TMDBExternalIDs?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case overview
        case airDate = "air_date"
        case seasonNumber = "season_number"
        case episodeNumber = "episode_number"
        case externalIDs = "external_ids"
    }
}

private struct TMDBExternalIDs: Decodable {
    var imdbID: String?

    private enum CodingKeys: String, CodingKey {
        case imdbID = "imdb_id"
    }
}

private struct TMDBImagesResponse: Decodable {
    var posters: [TMDBImage]
}

private struct TMDBImage: Decodable {
    var aspectRatio: Double?
    var filePath: String
    var height: Int?
    var width: Int?

    private enum CodingKeys: String, CodingKey {
        case aspectRatio = "aspect_ratio"
        case filePath = "file_path"
        case height
        case width
    }
}

private struct TMDBConfigurationResponse: Decodable {
    var images: TMDBConfigurationImages
}

private struct TMDBConfigurationImages: Decodable {
    var secureBaseURL: String
    var posterSizes: [String]
    var backdropSizes: [String]

    private enum CodingKeys: String, CodingKey {
        case secureBaseURL = "secure_base_url"
        case posterSizes = "poster_sizes"
        case backdropSizes = "backdrop_sizes"
    }
}

private struct CompactMoviePayload: Encodable {
    var id: Int
    var title: String?
    var originalTitle: String?
    var overview: String?
    var originalLanguage: String?
    var releaseDate: String?
    var imdbID: String?
    var posterPath: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case originalTitle = "original_title"
        case overview
        case originalLanguage = "original_language"
        case releaseDate = "release_date"
        case imdbID = "imdb_id"
        case posterPath = "poster_path"
    }
}

private struct CompactEpisodePayload: Encodable {
    var seriesID: Int
    var seasonNumber: Int
    var episodeNumber: Int
    var episodeID: Int
    var name: String?
    var overview: String?
    var airDate: String?
    var imdbID: String?

    private enum CodingKeys: String, CodingKey {
        case seriesID = "series_id"
        case seasonNumber = "season_number"
        case episodeNumber = "episode_number"
        case episodeID = "episode_id"
        case name
        case overview
        case airDate = "air_date"
        case imdbID = "imdb_id"
    }
}

private func year(from date: String?) -> Int? {
    guard let date, date.count >= 4 else {
        return nil
    }
    return Int(date.prefix(4))
}

private func normalizedIMDBID(_ value: String?) -> String? {
    guard let candidate = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
          candidate.range(of: #"^tt\d{7,9}$"#, options: .regularExpression) != nil else {
        return nil
    }
    return candidate
}

private func overviewPreview(_ overview: String?) -> String? {
    guard let overview = overview?.nonEmptyValue else {
        return nil
    }
    if overview.count <= 240 {
        return overview
    }
    return String(overview.prefix(240))
}

private extension String {
    var nonEmptyValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
