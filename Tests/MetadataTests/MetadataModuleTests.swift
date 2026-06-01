import Domain
import Foundation
import Metadata
import XCTest

final class MetadataModuleTests: XCTestCase {
    func testMetadataTargetImportsAndBuilds() {
        XCTAssertEqual(MetadataModule.name, "Metadata")
    }

    func testMetadataTestsCanImportDomain() {
        XCTAssertEqual(MediaType.movie.rawValue, "movie")
    }
}

final class MetadataProviderIdentifierTests: XCTestCase {
    func testStrictMovieIdentifierParsing() {
        let identifier = MetadataProviderIdentifier(rawValue: "movie:550")

        XCTAssertEqual(identifier?.rawValue, "movie:550")
        XCTAssertEqual(identifier?.kind, .movie)
        XCTAssertEqual(identifier?.movieID, 550)
        XCTAssertEqual(identifier?.providerMediaType, .movie)
    }

    func testStrictEpisodeIdentifierParsing() {
        let identifier = MetadataProviderIdentifier(rawValue: "tv:95396:s1:e2")

        XCTAssertEqual(identifier?.rawValue, "tv:95396:s1:e2")
        XCTAssertEqual(identifier?.kind, .episode)
        XCTAssertEqual(identifier?.seriesID, 95396)
        XCTAssertEqual(identifier?.seasonNumber, 1)
        XCTAssertEqual(identifier?.episodeNumber, 2)
        XCTAssertEqual(identifier?.providerMediaType, .episode)
    }

    func testMalformedIdentifiersAreRejected() {
        let rejectedValues = [
            "",
            "movie:",
            "movie:+1",
            "movie:01",
            "movie:0",
            "movie:-1",
            "movie:abc",
            "movie:550:extra",
            "tv:",
            "tv:+1:s1:e2",
            "tv:01:s1:e2",
            "tv:0:s1:e2",
            "tv:-1:s1:e2",
            "tv:95396:s01:e2",
            "tv:95396:s1:e02",
            "tv:95396:s0:e2",
            "tv:95396:s1:e0",
            "tv:95396:1:2",
            "tv:95396:S1:e2",
            "tv:95396:s1:E2",
            "tv:95396:s1:e2:extra"
        ]

        for rawValue in rejectedValues {
            XCTAssertNil(MetadataProviderIdentifier(rawValue: rawValue), rawValue)
        }
    }
}

final class TMDBMetadataProviderTests: XCTestCase {
    func testAuthHeaderIsPresentAndCanBeInspectedCaseInsensitively() async throws {
        let client = FakeMetadataHTTPClient { _ in
            jsonResponse(#"{"results":[]}"#)
        }
        let provider = makeProvider(token: "secret-token", client: client)

        _ = try await provider.search(query: .movie(title: "Arrival", year: 2016))

        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.headerValue(caseInsensitive: "authorization"), "Bearer secret-token")
        XCTAssertEqual(request.headerValue(caseInsensitive: "AUTHORIZATION"), "Bearer secret-token")
    }

    func testMissingTokenDoesNotSendRequest() async throws {
        let client = FakeMetadataHTTPClient { _ in
            XCTFail("Missing-token validation should happen before HTTP send.")
            return jsonResponse(#"{"results":[]}"#)
        }
        let provider = makeProvider(token: "  ", client: client)

        do {
            _ = try await provider.search(query: .movie(title: "Arrival"))
            XCTFail("Expected missing-token error.")
        } catch {
            XCTAssertEqual(error as? MetadataError, .missingToken)
        }

        XCTAssertTrue(client.requests.isEmpty)
    }

    func testTokenAndHeadersAreNotExposedInErrorDescriptions() async throws {
        let token = "very-secret-read-token"
        let client = FakeMetadataHTTPClient { _ in
            jsonResponse(#"{"status_message":"Authorization: Bearer very-secret-read-token"}"#, statusCode: 401)
        }
        let provider = makeProvider(token: token, client: client)

        do {
            _ = try await provider.search(query: .movie(title: "Arrival"))
            XCTFail("Expected unauthorized error.")
        } catch let error as MetadataError {
            assertSanitized(error.description, token: token)
        }
    }

    func testTransportFailureDescriptionDoesNotLeakTokenOrHeaders() async throws {
        let token = "very-secret-read-token"
        let client = FakeMetadataHTTPClient { _ in
            throw LeakyTransportError()
        }
        let provider = makeProvider(token: token, client: client)

        do {
            _ = try await provider.search(query: .movie(title: "Arrival"))
            XCTFail("Expected transport failure.")
        } catch let error as MetadataError {
            XCTAssertEqual(error, .transportFailure)
            assertSanitized(error.description, token: token)
        }
    }

    func testMovieSearchRequestPathAndQueryUseSafePercentEncoding() async throws {
        let client = FakeMetadataHTTPClient { _ in
            jsonResponse(#"{"results":[]}"#)
        }
        let provider = makeProvider(client: client)

        _ = try await provider.search(
            query: .movie(title: "Spider-Man: Across & Beyond", year: 2023)
        )

        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.url?.path, "/3/search/movie")
        XCTAssertEqual(request.queryValue("query"), "Spider-Man: Across & Beyond")
        XCTAssertEqual(request.queryValue("include_adult"), "false")
        XCTAssertEqual(request.queryValue("language"), "en-US")
        XCTAssertEqual(request.queryValue("page"), "1")
        XCTAssertEqual(request.queryValue("primary_release_year"), "2023")
        XCTAssertTrue(request.url?.absoluteString.contains("%26") == true)
    }

    func testMovieSearchFallsBackFromPrimaryReleaseYearToYearThenNoYear() async throws {
        let client = FakeMetadataHTTPClient { request in
            if request.queryValue("primary_release_year") != nil {
                return jsonResponse(#"{"results":[]}"#)
            }
            if request.queryValue("year") != nil {
                return jsonResponse(
                    movieSearchJSON(
                        id: 1,
                        title: "Unrelated",
                        releaseDate: "2015-01-01"
                    )
                )
            }
            return jsonResponse(
                movieSearchJSON(
                    id: 34000,
                    title: "The Million Pound Note",
                    releaseDate: "1954-01-07"
                )
            )
        }
        let provider = makeProvider(client: client)

        let candidates = try await provider.search(
            query: .movie(title: "The Million Pound Bank Note", year: 1954)
        )

        XCTAssertEqual(client.requests.map { $0.url?.path }, [
            "/3/search/movie",
            "/3/search/movie",
            "/3/search/movie"
        ])
        XCTAssertEqual(client.requests[0].queryValue("primary_release_year"), "1954")
        XCTAssertEqual(client.requests[1].queryValue("year"), "1954")
        XCTAssertNil(client.requests[2].queryValue("primary_release_year"))
        XCTAssertNil(client.requests[2].queryValue("year"))
        XCTAssertEqual(candidates.first?.identifier.rawValue, "movie:34000")
        XCTAssertGreaterThanOrEqual(candidates.first?.confidence ?? 0.0, 0.85)
    }

    func testMovieSearchStopsAfterHighConfidencePrimaryResult() async throws {
        let client = FakeMetadataHTTPClient { _ in
            jsonResponse(movieSearchJSON(id: 550, title: "Arrival", releaseDate: "2016-11-11"))
        }
        let provider = makeProvider(client: client)

        let candidates = try await provider.search(query: .movie(title: "Arrival", year: 2016))

        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.requests[0].queryValue("primary_release_year"), "2016")
        XCTAssertEqual(candidates.first?.identifier.rawValue, "movie:550")
        XCTAssertEqual(candidates.first?.confidence, 0.99)
    }

    func testMovieSearchFallbackDeduplicatesAttemptsBeforeRanking() async throws {
        let client = FakeMetadataHTTPClient { request in
            if request.queryValue("primary_release_year") != nil {
                return jsonResponse(movieSearchJSON(id: 1, title: "Unrelated", releaseDate: "2016-01-01"))
            }
            return jsonResponse(
                #"{"results":["# +
                movieSearchResultJSON(id: 1, title: "Unrelated", releaseDate: "2016-01-01") + "," +
                movieSearchResultJSON(id: 550, title: "Arrival", releaseDate: "2016-11-11") +
                #"]}"#
            )
        }
        let provider = makeProvider(client: client)

        let candidates = try await provider.search(query: .movie(title: "Arrival", year: 2016))

        XCTAssertEqual(client.requests.count, 2)
        XCTAssertEqual(candidates.map(\.identifier.rawValue), ["movie:550", "movie:1"])
    }

    func testMovieSearchUsesIMDBFindBeforeTextSearch() async throws {
        let client = FakeMetadataHTTPClient { request in
            XCTAssertEqual(request.url?.path, "/3/find/tt0137523")
            return jsonResponse(findJSON(movieResults: [
                movieSearchResultJSON(id: 550, title: "Fight Club", releaseDate: "1999-10-15")
            ]))
        }
        let provider = makeProvider(client: client)

        let candidates = try await provider.search(
            query: .movie(title: "Fight Club", year: 1999, imdbID: "TT0137523")
        )

        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.requests[0].queryValue("external_source"), "imdb_id")
        XCTAssertEqual(candidates.first?.identifier.rawValue, "movie:550")
    }

    func testMovieSearchFallsBackToTextSearchWhenIMDBFindHasNoMovieResult() async throws {
        let client = FakeMetadataHTTPClient { request in
            if request.url?.path.starts(with: "/3/find/") == true {
                return jsonResponse(findJSON(movieResults: []))
            }
            return jsonResponse(movieSearchJSON(id: 550, title: "Arrival", releaseDate: "2016-11-11"))
        }
        let provider = makeProvider(client: client)

        let candidates = try await provider.search(
            query: .movie(title: "Arrival", year: 2016, imdbID: "tt0000001")
        )

        XCTAssertEqual(client.requests.map { $0.url?.path }, ["/3/find/tt0000001", "/3/search/movie"])
        XCTAssertEqual(candidates.first?.identifier.rawValue, "movie:550")
    }

    func testMovieDetailsRequestUsesExternalIDs() async throws {
        let client = FakeMetadataHTTPClient { _ in
            jsonResponse(movieDetailsJSON())
        }
        let provider = makeProvider(client: client)

        let details = try await provider.fetchDetails(identifier: MetadataProviderIdentifier(rawValue: "movie:550")!)

        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.url?.path, "/3/movie/550")
        XCTAssertEqual(request.queryValue("append_to_response"), "external_ids")
        XCTAssertEqual(request.queryValue("language"), "en-US")
        XCTAssertEqual(details.title, "Fight Club")
        XCTAssertEqual(details.externalIDs[.tmdbMovie], "550")
        XCTAssertEqual(details.externalIDs[.imdb], "tt0137523")
    }

    func testMovieImagesRequestMapsRemoteImages() async throws {
        let client = FakeMetadataHTTPClient { _ in
            jsonResponse(imagesJSON())
        }
        let provider = makeProvider(client: client)

        let images = try await provider.fetchImages(identifier: MetadataProviderIdentifier(rawValue: "movie:550")!)

        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.url?.path, "/3/movie/550/images")
        XCTAssertEqual(images, [
            RemoteImage(
                source: .tmdb,
                remotePath: "/poster.jpg",
                width: 500,
                height: 750,
                aspectRatio: 0.666,
                preferredCacheSize: "w500"
            )
        ])
    }

    func testTVSearchRequestPathAndQueryUseSafePercentEncoding() async throws {
        let client = FakeMetadataHTTPClient { request in
            if request.url?.path == "/3/search/tv" {
                return jsonResponse(tvSearchJSON(count: 1))
            }
            return jsonResponse(episodeDetailsJSON(id: 1001, season: 1, episode: 2))
        }
        let provider = makeProvider(client: client)

        _ = try await provider.search(
            query: .episode(
                seriesTitle: "Law & Order: Special Victims Unit",
                seasonNumber: 1,
                episodeNumber: 2
            )
        )

        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.url?.path, "/3/search/tv")
        XCTAssertEqual(request.queryValue("query"), "Law & Order: Special Victims Unit")
        XCTAssertEqual(request.queryValue("include_adult"), "false")
        XCTAssertEqual(request.queryValue("language"), "en-US")
        XCTAssertEqual(request.queryValue("page"), "1")
        XCTAssertTrue(request.url?.absoluteString.contains("%26") == true)
    }

    func testEpisodeDetailsRequestUsesExternalIDs() async throws {
        let client = FakeMetadataHTTPClient { _ in
            jsonResponse(episodeDetailsJSON(id: 12345, season: 1, episode: 2))
        }
        let provider = makeProvider(client: client)

        let details = try await provider.fetchDetails(
            identifier: MetadataProviderIdentifier(rawValue: "tv:95396:s1:e2")!
        )

        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.url?.path, "/3/tv/95396/season/1/episode/2")
        XCTAssertEqual(request.queryValue("append_to_response"), "external_ids")
        XCTAssertEqual(request.queryValue("language"), "en-US")
        XCTAssertEqual(details.title, "Half Loop")
        XCTAssertEqual(details.externalIDs[.tmdbTVSeries], "95396")
        XCTAssertEqual(details.externalIDs[.tmdbEpisode], "12345")
        XCTAssertEqual(details.externalIDs[.imdb], "tt0000000")
    }

    func testEpisodeSearchProbesAtMostTopTenTVCandidates() async throws {
        let client = FakeMetadataHTTPClient { request in
            if request.url?.path == "/3/search/tv" {
                return jsonResponse(tvSearchJSON(count: 12))
            }
            return jsonResponse(
                episodeDetailsJSON(
                    id: 10_000 + (request.seriesIDFromEpisodePath() ?? 0),
                    season: 1,
                    episode: 2
                )
            )
        }
        let provider = makeProvider(client: client)

        let candidates = try await provider.search(
            query: .episode(seriesTitle: "Severance", seasonNumber: 1, episodeNumber: 2)
        )

        let episodeProbeRequests = client.requests.filter {
            $0.url?.path.contains("/season/1/episode/2") == true
        }
        XCTAssertEqual(client.requests.first?.url?.path, "/3/search/tv")
        XCTAssertEqual(episodeProbeRequests.count, 10)
        XCTAssertEqual(candidates.count, 10)
        XCTAssertEqual(episodeProbeRequests.compactMap { $0.seriesIDFromEpisodePath() }, Array(1...10))
    }

    func testEpisodeSearchCanReturnCandidateAfterFirstFiveSeriesMiss() async throws {
        let client = FakeMetadataHTTPClient { request in
            if request.url?.path == "/3/search/tv" {
                return jsonResponse(tvSearchJSON(count: 10))
            }
            if request.seriesIDFromEpisodePath() == 6 {
                return jsonResponse(episodeDetailsJSON(id: 1006, season: 1, episode: 2))
            }
            return jsonResponse(#"{"status_message":"Not found"}"#, statusCode: 404)
        }
        let provider = makeProvider(client: client)

        let candidates = try await provider.search(
            query: .episode(seriesTitle: "Severance", seasonNumber: 1, episodeNumber: 2)
        )

        XCTAssertEqual(candidates.map(\.identifier.rawValue), ["tv:6:s1:e2"])
        XCTAssertEqual(candidates.first?.episodeTitle, "Half Loop")
    }

    func testEpisodeSearchUsesIMDBFindBeforeTVSearch() async throws {
        let client = FakeMetadataHTTPClient { request in
            XCTAssertEqual(request.url?.path, "/3/find/tt0000000")
            return jsonResponse(findJSON(tvEpisodeResults: [
                tvEpisodeFindResultJSON(
                    id: 12345,
                    name: "Half Loop",
                    showID: 95396,
                    season: 1,
                    episode: 2
                )
            ]))
        }
        let provider = makeProvider(client: client)

        let candidates = try await provider.search(
            query: .episode(
                seriesTitle: "Severance",
                seasonNumber: 1,
                episodeNumber: 2,
                imdbID: "tt0000000"
            )
        )

        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.requests[0].queryValue("external_source"), "imdb_id")
        XCTAssertEqual(candidates.first?.identifier.rawValue, "tv:95396:s1:e2")
        XCTAssertEqual(candidates.first?.episodeTitle, "Half Loop")
    }

    func testTVSeriesImageRequestUsesSeriesIdentifier() async throws {
        let client = FakeMetadataHTTPClient { _ in
            jsonResponse(imagesJSON())
        }
        let provider = makeProvider(client: client)

        _ = try await provider.fetchImages(identifier: MetadataProviderIdentifier(rawValue: "tv:95396:s1:e2")!)

        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.url?.path, "/3/tv/95396/images")
    }

    func testConfigurationRequestAndRuntimeImageURLDerivation() async throws {
        let client = FakeMetadataHTTPClient { _ in
            jsonResponse(
                """
                {
                  "images": {
                    "secure_base_url": "https://image.tmdb.org/t/p/",
                    "poster_sizes": ["w92", "w500", "original"],
                    "backdrop_sizes": ["w300", "original"]
                  }
                }
                """
            )
        }
        let provider = makeProvider(client: client)

        let configuration = try await provider.fetchImageConfiguration()
        let image = RemoteImage(source: .tmdb, remotePath: "/poster.jpg", preferredCacheSize: "w500")
        let url = provider.imageURL(for: image, using: configuration)

        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.url?.path, "/3/configuration")
        XCTAssertEqual(url?.absoluteString, "https://image.tmdb.org/t/p/w500/poster.jpg")
    }

    func testCompactMoviePayloadMapping() async throws {
        let client = FakeMetadataHTTPClient { _ in
            jsonResponse(movieDetailsJSON())
        }
        let provider = makeProvider(client: client)

        let details = try await provider.fetchDetails(identifier: MetadataProviderIdentifier(rawValue: "movie:550")!)
        let payload = try rawPayloadDictionary(details.rawPayloadJSON)

        XCTAssertEqual(payload["id"] as? Int, 550)
        XCTAssertEqual(payload["title"] as? String, "Fight Club")
        XCTAssertEqual(payload["original_title"] as? String, "Fight Club")
        XCTAssertEqual(payload["overview"] as? String, "A ticking-time-bomb insomniac meets a soap maker.")
        XCTAssertEqual(payload["original_language"] as? String, "en")
        XCTAssertEqual(payload["release_date"] as? String, "1999-10-15")
        XCTAssertEqual(payload["imdb_id"] as? String, "tt0137523")
        XCTAssertEqual(payload["poster_path"] as? String, "/pB8BM7pd.jpg")
    }

    func testCompactEpisodePayloadMapping() async throws {
        let client = FakeMetadataHTTPClient { _ in
            jsonResponse(episodeDetailsJSON(id: 12345, season: 1, episode: 2))
        }
        let provider = makeProvider(client: client)

        let details = try await provider.fetchDetails(
            identifier: MetadataProviderIdentifier(rawValue: "tv:95396:s1:e2")!
        )
        let payload = try rawPayloadDictionary(details.rawPayloadJSON)

        XCTAssertEqual(payload["series_id"] as? Int, 95396)
        XCTAssertEqual(payload["season_number"] as? Int, 1)
        XCTAssertEqual(payload["episode_number"] as? Int, 2)
        XCTAssertEqual(payload["episode_id"] as? Int, 12345)
        XCTAssertEqual(payload["name"] as? String, "Half Loop")
        XCTAssertEqual(payload["overview"] as? String, "The team trains new refiners.")
        XCTAssertEqual(payload["air_date"] as? String, "2022-02-18")
        XCTAssertEqual(payload["imdb_id"] as? String, "tt0000000")
    }

    func testImagesCastAndCrewAreIgnoredFromRawPayload() async throws {
        let client = FakeMetadataHTTPClient { _ in
            jsonResponse(
                """
                {
                  "id": 550,
                  "title": "Fight Club",
                  "original_title": "Fight Club",
                  "overview": "A ticking-time-bomb insomniac meets a soap maker.",
                  "original_language": "en",
                  "release_date": "1999-10-15",
                  "poster_path": "/pB8BM7pd.jpg",
                  "external_ids": { "imdb_id": "tt0137523" },
                  "images": { "posters": [{ "file_path": "/too-large.jpg" }] },
                  "credits": {
                    "cast": [{ "name": "Actor" }],
                    "crew": [{ "name": "Director" }]
                  },
                  "cast": [{ "name": "Actor" }],
                  "crew": [{ "name": "Director" }]
                }
                """
            )
        }
        let provider = makeProvider(client: client)

        let details = try await provider.fetchDetails(identifier: MetadataProviderIdentifier(rawValue: "movie:550")!)
        let payload = try rawPayloadDictionary(details.rawPayloadJSON)

        XCTAssertNil(payload["images"])
        XCTAssertNil(payload["credits"])
        XCTAssertNil(payload["cast"])
        XCTAssertNil(payload["crew"])
        XCTAssertFalse(details.rawPayloadJSON.contains("too-large"))
        XCTAssertFalse(details.rawPayloadJSON.contains("Actor"))
        XCTAssertFalse(details.rawPayloadJSON.contains("Director"))
    }

    func testStatusErrorMapping() async throws {
        let cases: [(Int, MetadataError)] = [
            (401, .unauthorized),
            (404, .notFound),
            (429, .rateLimited),
            (503, .serverUnavailable(statusCode: 503))
        ]

        for (statusCode, expectedError) in cases {
            let client = FakeMetadataHTTPClient { _ in
                jsonResponse(#"{"status_message":"failure"}"#, statusCode: statusCode)
            }
            let provider = makeProvider(client: client)

            do {
                _ = try await provider.search(query: .movie(title: "Arrival"))
                XCTFail("Expected \(expectedError) for status \(statusCode).")
            } catch {
                XCTAssertEqual(error as? MetadataError, expectedError)
            }
        }
    }

    func testInvalidJSONMapsToInvalidResponse() async throws {
        let client = FakeMetadataHTTPClient { _ in
            MetadataHTTPResponse(statusCode: 200, data: Data("{".utf8))
        }
        let provider = makeProvider(client: client)

        do {
            _ = try await provider.search(query: .movie(title: "Arrival"))
            XCTFail("Expected invalid response.")
        } catch {
            XCTAssertEqual(error as? MetadataError, .invalidResponse)
        }
    }

    func testTransportFailureMapsToTransportFailure() async throws {
        let client = FakeMetadataHTTPClient { _ in
            throw URLError(.notConnectedToInternet)
        }
        let provider = makeProvider(client: client)

        do {
            _ = try await provider.search(query: .movie(title: "Arrival"))
            XCTFail("Expected transport failure.")
        } catch {
            XCTAssertEqual(error as? MetadataError, .transportFailure)
        }
    }
}

private final class FakeMetadataHTTPClient: MetadataHTTPClient {
    private(set) var requests: [URLRequest] = []
    private let handler: (URLRequest) async throws -> MetadataHTTPResponse

    init(handler: @escaping (URLRequest) async throws -> MetadataHTTPResponse) {
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> MetadataHTTPResponse {
        requests.append(request)
        return try await handler(request)
    }
}

private struct LeakyTransportError: Error, CustomStringConvertible {
    var description: String {
        "Authorization: Bearer very-secret-read-token"
    }
}

private func makeProvider(
    token: String = "test-token",
    client: FakeMetadataHTTPClient
) -> TMDBMetadataProvider {
    TMDBMetadataProvider(
        configuration: TMDBMetadataProvider.Configuration(bearerToken: token),
        httpClient: client
    )
}

private func jsonResponse(_ json: String, statusCode: Int = 200) -> MetadataHTTPResponse {
    MetadataHTTPResponse(statusCode: statusCode, data: Data(json.utf8))
}

private func movieDetailsJSON() -> String {
    """
    {
      "id": 550,
      "title": "Fight Club",
      "original_title": "Fight Club",
      "overview": "A ticking-time-bomb insomniac meets a soap maker.",
      "original_language": "en",
      "release_date": "1999-10-15",
      "poster_path": "/pB8BM7pd.jpg",
      "external_ids": { "imdb_id": "tt0137523" }
    }
    """
}

private func movieSearchJSON(id: Int, title: String, releaseDate: String) -> String {
    #"{"results":["# + movieSearchResultJSON(id: id, title: title, releaseDate: releaseDate) + #"]}"#
}

private func movieSearchResultJSON(id: Int, title: String, releaseDate: String) -> String {
    """
    {
      "id": \(id),
      "title": "\(title)",
      "original_title": "\(title)",
      "overview": "Search result.",
      "release_date": "\(releaseDate)"
    }
    """
}

private func findJSON(
    movieResults: [String] = [],
    tvEpisodeResults: [String] = []
) -> String {
    """
    {
      "movie_results": [\(movieResults.joined(separator: ","))],
      "tv_episode_results": [\(tvEpisodeResults.joined(separator: ","))]
    }
    """
}

private func tvEpisodeFindResultJSON(
    id: Int,
    name: String,
    showID: Int,
    season: Int,
    episode: Int
) -> String {
    """
    {
      "id": \(id),
      "name": "\(name)",
      "overview": "Episode search result.",
      "air_date": "2022-02-18",
      "show_id": \(showID),
      "season_number": \(season),
      "episode_number": \(episode)
    }
    """
}

private func episodeDetailsJSON(id: Int, season: Int, episode: Int) -> String {
    """
    {
      "id": \(id),
      "name": "Half Loop",
      "overview": "The team trains new refiners.",
      "air_date": "2022-02-18",
      "season_number": \(season),
      "episode_number": \(episode),
      "external_ids": { "imdb_id": "tt0000000" },
      "guest_stars": [{ "name": "Guest" }],
      "crew": [{ "name": "Director" }]
    }
    """
}

private func imagesJSON() -> String {
    """
    {
      "posters": [
        {
          "file_path": "/poster.jpg",
          "width": 500,
          "height": 750,
          "aspect_ratio": 0.666
        }
      ],
      "backdrops": [
        {
          "file_path": "/backdrop.jpg",
          "width": 1280,
          "height": 720,
          "aspect_ratio": 1.777
        }
      ]
    }
    """
}

private func tvSearchJSON(count: Int) -> String {
    let results = (1...count).map { id in
        """
        {
          "id": \(id),
          "name": "Severance",
          "original_name": "Severance",
          "overview": "Workers split their memories.",
          "first_air_date": "2022-02-18"
        }
        """
    }
    .joined(separator: ",")

    return #"{"results":["# + results + #"]}"#
}

private func rawPayloadDictionary(_ rawPayloadJSON: String) throws -> [String: Any] {
    let data = try XCTUnwrap(rawPayloadJSON.data(using: .utf8))
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func assertSanitized(
    _ description: String,
    token: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertFalse(description.contains(token), file: file, line: line)
    XCTAssertFalse(description.localizedCaseInsensitiveContains("bearer"), file: file, line: line)
    XCTAssertFalse(description.localizedCaseInsensitiveContains("authorization"), file: file, line: line)
}

private extension URLRequest {
    func headerValue(caseInsensitive name: String) -> String? {
        allHTTPHeaderFields?.first {
            $0.key.caseInsensitiveCompare(name) == .orderedSame
        }?.value
    }

    func queryValue(_ name: String) -> String? {
        URLComponents(url: url!, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }

    func seriesIDFromEpisodePath() -> Int? {
        let parts = url?.path.split(separator: "/").map(String.init) ?? []
        guard parts.count >= 3, parts[0] == "3", parts[1] == "tv" else {
            return nil
        }
        return Int(parts[2])
    }
}
