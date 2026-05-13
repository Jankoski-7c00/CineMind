import Application
import Domain
import Foundation
import Metadata
import Persistence
import XCTest

final class MetadataUseCaseTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var databaseURL: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CineMindMetadataUseCaseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        databaseURL = temporaryDirectory.appendingPathComponent("test.sqlite")
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        databaseURL = nil
    }

    func testSearchReturnsCandidatesWithoutMutatingPersistence() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()
        let candidate = movieCandidate(id: 550, confidence: 0.9)
        provider.searchResults = [candidate]

        let candidates = try await SearchMetadataCandidatesUseCase(
            store: context.store,
            provider: provider
        ).search(mediaItemID: context.item.id, language: "en-US")

        XCTAssertEqual(candidates, [candidate])
        XCTAssertEqual(provider.searchQueries.count, 1)
        XCTAssertEqual(provider.searchQueries[0].mediaItemID, context.item.id)
        XCTAssertEqual(provider.searchQueries[0].language, "en-US")
        XCTAssertNil(try context.store.fetchMetadataItem(mediaItemID: context.item.id))
        XCTAssertNil(
            try context.store.fetchMetadataSourceRecord(
                mediaItemID: context.item.id,
                provider: .tmdb
            )
        )
        XCTAssertEqual(try context.store.fetchMetadataExternalIDs(mediaItemID: context.item.id), [])
        XCTAssertEqual(try context.store.fetchPosterAssets(mediaItemID: context.item.id), [])
    }

    func testAutoMatchSkipsManualLockWithoutSearching() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()
        try context.store.saveMetadataSourceRecord(
            try MetadataSourceRecord.validated(
                mediaItemID: context.item.id,
                provider: .tmdb,
                providerID: "movie:550",
                providerMediaType: .movie,
                confidence: 1.0,
                matchSource: .manual,
                manualMatchLocked: true
            )
        )

        let result = try await AutoMatchMetadataUseCase(
            store: context.store,
            provider: provider
        ).match(mediaItemID: context.item.id)

        XCTAssertEqual(result, .skippedManualLock)
        XCTAssertEqual(provider.searchQueries, [])
        XCTAssertEqual(provider.detailsRequests, [])
        XCTAssertEqual(provider.imageRequests, [])
    }

    func testHighConfidenceAutoMatchPersistsMetadataSourceExternalIDsAndPosters() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()
        let now = Date(timeIntervalSince1970: 10_000)
        let identifier = movieID(550)
        let candidate = movieCandidate(id: 550, confidence: 0.96)
        provider.searchResults = [candidate]
        provider.detailsByID[identifier.rawValue] = movieDetails(
            id: 550,
            title: "Arrival Provider",
            summary: "Provider summary",
            language: "en",
            rawPayloadJSON: #"{"id":550}"#
        )
        provider.imagesByID[identifier.rawValue] = [
            RemoteImage(
                source: .tmdb,
                remotePath: "/arrival.jpg",
                width: 500,
                height: 750,
                preferredCacheSize: "w500"
            )
        ]

        let result = try await AutoMatchMetadataUseCase(
            store: context.store,
            provider: provider,
            now: { now }
        ).match(mediaItemID: context.item.id)

        XCTAssertEqual(result, .matched(candidate))
        let metadata = try XCTUnwrap(context.store.fetchMetadataItem(mediaItemID: context.item.id))
        XCTAssertEqual(metadata.title, "Arrival Provider")
        XCTAssertEqual(metadata.summary, "Provider summary")
        XCTAssertEqual(metadata.language, "en")
        XCTAssertFalse(metadata.titleOverrideLocked)
        XCTAssertFalse(metadata.summaryOverrideLocked)
        XCTAssertFalse(metadata.languageOverrideLocked)
        XCTAssertEqual(metadata.updatedAt, now)

        let externalIDs = try context.store.fetchMetadataExternalIDs(mediaItemID: context.item.id)
        XCTAssertEqual(Set(externalIDs.map(\.externalIDType)), [.tmdbMovie, .imdb])
        XCTAssertEqual(
            externalIDs.first { $0.externalIDType == .tmdbMovie }?.externalIDValue,
            "550"
        )

        let source = try XCTUnwrap(
            context.store.fetchMetadataSourceRecord(
                mediaItemID: context.item.id,
                provider: .tmdb
            )
        )
        XCTAssertEqual(source.providerID, "movie:550")
        XCTAssertEqual(source.providerMediaType, .movie)
        XCTAssertEqual(source.confidence, 0.96)
        XCTAssertEqual(source.matchSource, .automatic)
        XCTAssertFalse(source.manualMatchLocked)
        XCTAssertEqual(source.rawPayloadJSON, #"{"id":550}"#)
        XCTAssertEqual(source.matchedAt, now)
        XCTAssertEqual(source.refreshedAt, now)

        let posters = try context.store.fetchPosterAssets(mediaItemID: context.item.id)
        XCTAssertEqual(posters.count, 1)
        XCTAssertEqual(posters[0].remotePath, "/arrival.jpg")
        XCTAssertFalse(posters[0].isSelected)
        XCTAssertNil(posters[0].localCachePath)
        XCTAssertNil(posters[0].cachedAt)
    }

    func testLowConfidenceAutoMatchLeavesPersistenceUnchanged() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()
        provider.searchResults = [movieCandidate(id: 550, confidence: 0.60)]

        let result = try await AutoMatchMetadataUseCase(
            store: context.store,
            provider: provider
        ).match(mediaItemID: context.item.id)

        XCTAssertEqual(result, .lowConfidence)
        XCTAssertEqual(provider.detailsRequests, [])
        XCTAssertNil(try context.store.fetchMetadataItem(mediaItemID: context.item.id))
        XCTAssertNil(
            try context.store.fetchMetadataSourceRecord(
                mediaItemID: context.item.id,
                provider: .tmdb
            )
        )
        XCTAssertEqual(try context.store.fetchPosterAssets(mediaItemID: context.item.id), [])
    }

    func testAmbiguousAutoMatchLeavesPersistenceUnchanged() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()
        provider.searchResults = [
            movieCandidate(id: 550, confidence: 0.90),
            movieCandidate(id: 551, confidence: 0.85)
        ]

        let result = try await AutoMatchMetadataUseCase(
            store: context.store,
            provider: provider
        ).match(mediaItemID: context.item.id)

        XCTAssertEqual(result, .ambiguous)
        XCTAssertEqual(provider.detailsRequests, [])
        XCTAssertNil(try context.store.fetchMetadataItem(mediaItemID: context.item.id))
        XCTAssertNil(
            try context.store.fetchMetadataSourceRecord(
                mediaItemID: context.item.id,
                provider: .tmdb
            )
        )
        XCTAssertEqual(try context.store.fetchPosterAssets(mediaItemID: context.item.id), [])
    }

    func testManualMatchRejectsInvalidProviderID() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()

        await assertThrowsMetadataError(
            try await ManualMatchMetadataUseCase(
                store: context.store,
                provider: provider
            ).match(mediaItemID: context.item.id, providerID: "not-valid"),
            .invalidProviderID("not-valid")
        )
        XCTAssertEqual(provider.detailsRequests, [])
    }

    func testManualMatchRejectsMediaTypeMismatch() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()

        await assertThrowsMetadataError(
            try await ManualMatchMetadataUseCase(
                store: context.store,
                provider: provider
            ).match(mediaItemID: context.item.id, providerID: "tv:1:s1:e1"),
            .providerMediaTypeMismatch(
                mediaItemID: context.item.id,
                providerID: "tv:1:s1:e1"
            )
        )
        XCTAssertEqual(provider.detailsRequests, [])
    }

    func testManualEpisodeMatchRequiresMatchingSeasonAndEpisode() async throws {
        let episode = MediaItem(
            mediaType: .episode,
            title: "Pilot",
            episodeInfo: EpisodeInfo(
                seriesTitle: "Example Show",
                seasonNumber: 1,
                episodeNumber: 2,
                episodeTitle: "Pilot"
            )
        )
        let context = try makeMediaContext(item: episode)
        let provider = FakeMetadataProvider()

        await assertThrowsMetadataError(
            try await ManualMatchMetadataUseCase(
                store: context.store,
                provider: provider
            ).match(mediaItemID: context.item.id, providerID: "tv:10:s1:e3"),
            .episodeProviderIDMismatch(
                mediaItemID: context.item.id,
                expectedSeason: 1,
                expectedEpisode: 2,
                providerID: "tv:10:s1:e3"
            )
        )
        XCTAssertEqual(provider.detailsRequests, [])
    }

    func testManualMatchWritesManualSourceRecordAndLock() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()
        let now = Date(timeIntervalSince1970: 20_000)
        provider.detailsByID["movie:550"] = movieDetails(
            id: 550,
            title: "Arrival Manual",
            summary: "Manual summary",
            rawPayloadJSON: #"{"manual":true}"#
        )
        provider.imagesByID["movie:550"] = [
            RemoteImage(source: .tmdb, remotePath: "/manual.jpg", preferredCacheSize: "w500")
        ]

        let source = try await ManualMatchMetadataUseCase(
            store: context.store,
            provider: provider,
            now: { now }
        ).match(mediaItemID: context.item.id, providerID: "movie:550")

        XCTAssertEqual(source.providerID, "movie:550")
        XCTAssertEqual(source.matchSource, .manual)
        XCTAssertEqual(source.confidence, 1.0)
        XCTAssertTrue(source.manualMatchLocked)
        XCTAssertEqual(source.matchedAt, now)
        XCTAssertEqual(source.refreshedAt, now)

        let fetched = try XCTUnwrap(
            context.store.fetchMetadataSourceRecord(
                mediaItemID: context.item.id,
                provider: .tmdb
            )
        )
        XCTAssertEqual(fetched.providerID, "movie:550")
        XCTAssertEqual(fetched.matchSource, .manual)
        XCTAssertEqual(fetched.confidence, 1.0)
        XCTAssertTrue(fetched.manualMatchLocked)
        XCTAssertEqual(try context.store.fetchPosterAssets(mediaItemID: context.item.id).count, 1)
    }

    func testManualRematchReplacesExistingSourceRecord() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()
        provider.detailsByID["movie:550"] = movieDetails(id: 550, title: "Arrival First")
        provider.detailsByID["movie:551"] = movieDetails(id: 551, title: "Arrival Second")

        _ = try await ManualMatchMetadataUseCase(
            store: context.store,
            provider: provider
        ).match(mediaItemID: context.item.id, providerID: "movie:550")
        let firstSource = try XCTUnwrap(
            context.store.fetchMetadataSourceRecord(
                mediaItemID: context.item.id,
                provider: .tmdb
            )
        )

        _ = try await ManualMatchMetadataUseCase(
            store: context.store,
            provider: provider
        ).match(mediaItemID: context.item.id, providerID: "movie:551")

        let rematchedSource = try XCTUnwrap(
            context.store.fetchMetadataSourceRecord(
                mediaItemID: context.item.id,
                provider: .tmdb
            )
        )
        XCTAssertEqual(rematchedSource.id, firstSource.id)
        XCTAssertEqual(rematchedSource.providerID, "movie:551")
        XCTAssertEqual(rematchedSource.matchSource, .manual)
        XCTAssertTrue(rematchedSource.manualMatchLocked)
        XCTAssertEqual(
            try context.store.fetchMetadataItem(mediaItemID: context.item.id)?.title,
            "Arrival Second"
        )
    }

    func testExistingLockedMetadataFieldsSurviveMatchWrites() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()
        try context.store.saveMetadataItem(
            MetadataItem(
                id: "locked-metadata",
                mediaItemID: context.item.id,
                title: "Custom Title",
                summary: "Custom Summary",
                language: "fr",
                titleOverrideLocked: true,
                summaryOverrideLocked: true,
                languageOverrideLocked: true,
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        provider.detailsByID["movie:550"] = movieDetails(
            id: 550,
            title: "Provider Title",
            summary: "Provider Summary",
            language: "en"
        )

        _ = try await ManualMatchMetadataUseCase(
            store: context.store,
            provider: provider
        ).match(mediaItemID: context.item.id, providerID: "movie:550")

        let metadata = try XCTUnwrap(context.store.fetchMetadataItem(mediaItemID: context.item.id))
        XCTAssertEqual(metadata.id, "locked-metadata")
        XCTAssertEqual(metadata.title, "Custom Title")
        XCTAssertEqual(metadata.summary, "Custom Summary")
        XCTAssertEqual(metadata.language, "fr")
        XCTAssertTrue(metadata.titleOverrideLocked)
        XCTAssertTrue(metadata.summaryOverrideLocked)
        XCTAssertTrue(metadata.languageOverrideLocked)
        XCTAssertEqual(metadata.originalTitle, "Original Arrival")
    }

    func testProviderFailureBeforeWriteLeavesExistingMetadataUnchanged() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()
        let existingMetadata = MetadataItem(
            id: "metadata-existing",
            mediaItemID: context.item.id,
            title: "Existing Title",
            summary: "Existing Summary",
            language: "en",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let existingSource = try MetadataSourceRecord.validated(
            id: "source-existing",
            mediaItemID: context.item.id,
            provider: .tmdb,
            providerID: "movie:1",
            providerMediaType: .movie,
            confidence: 0.9,
            matchSource: .automatic,
            rawPayloadJSON: "{}",
            matchedAt: Date(timeIntervalSince1970: 100),
            refreshedAt: Date(timeIntervalSince1970: 100),
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let existingPoster = try PosterAsset.validated(
            id: "poster-existing",
            mediaItemID: context.item.id,
            assetType: .poster,
            source: .tmdb,
            remotePath: "/existing.jpg",
            preferredCacheSize: "w500",
            isSelected: false,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        try context.store.saveMetadataItem(existingMetadata)
        try context.store.saveMetadataSourceRecord(existingSource)
        try context.store.savePosterAsset(existingPoster)

        provider.searchResults = [movieCandidate(id: 550, confidence: 0.96)]
        provider.detailsError = MetadataError.transportFailure

        do {
            _ = try await AutoMatchMetadataUseCase(
                store: context.store,
                provider: provider
            ).match(mediaItemID: context.item.id)
            XCTFail("Expected provider failure.")
        } catch MetadataError.transportFailure {
        } catch {
            XCTFail("Expected transportFailure, got \(error).")
        }

        XCTAssertEqual(
            try context.store.fetchMetadataItem(mediaItemID: context.item.id),
            existingMetadata
        )
        XCTAssertEqual(
            try context.store.fetchMetadataSourceRecord(
                mediaItemID: context.item.id,
                provider: .tmdb
            ),
            existingSource
        )
        XCTAssertEqual(try context.store.fetchPosterAssets(mediaItemID: context.item.id), [existingPoster])
    }

    func testMetadataMatchesDoNotModifyPlaybackHistory() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()
        let history = PlaybackHistory(
            id: "history-existing",
            mediaItemID: context.item.id,
            mediaFileID: context.file.id,
            positionMS: 42_000,
            durationMS: 120_000,
            completed: false,
            playCount: 3,
            lastPlayedAt: Date(timeIntervalSince1970: 500),
            createdAt: Date(timeIntervalSince1970: 500),
            updatedAt: Date(timeIntervalSince1970: 500)
        )
        try context.store.savePlaybackHistory(history)
        provider.detailsByID["movie:550"] = movieDetails(id: 550, title: "Arrival Manual")

        _ = try await ManualMatchMetadataUseCase(
            store: context.store,
            provider: provider
        ).match(mediaItemID: context.item.id, providerID: "movie:550")

        XCTAssertEqual(
            try context.store.fetchPlaybackHistory(
                mediaItemID: context.item.id,
                mediaFileID: context.file.id
            ),
            history
        )
    }

    private func makeMediaContext(
        item: MediaItem = MediaItem(mediaType: .movie, title: "Arrival", year: 2016)
    ) throws -> MetadataTestContext {
        let store = try CineMindStore(path: databaseURL.path)
        let library = try store.createOrLoadLibrary(name: "Local")
        let folder = LibraryFolder(
            libraryID: library.id,
            displayName: "Movies",
            rootPath: "/media/movies"
        )
        let file = MediaFile(
            mediaItemID: item.id,
            libraryFolderID: folder.id,
            relativePath: "\(item.id).mkv",
            absolutePathHash: "metadata-test-\(UUID().uuidString)",
            fileName: "\(item.id).mkv",
            fileExtension: "mkv",
            fileSizeBytes: 1,
            modifiedAt: Date(timeIntervalSince1970: 100),
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        try store.addLibraryFolder(folder)
        try store.saveMediaItem(item)
        try store.saveMediaFile(file)

        return MetadataTestContext(
            store: store,
            item: item,
            file: file
        )
    }

    private func movieID(_ id: Int) -> MetadataProviderIdentifier {
        MetadataProviderIdentifier.movie(id: id)!
    }

    private func movieCandidate(id: Int, confidence: Double) -> MetadataCandidate {
        MetadataCandidate(
            identifier: movieID(id),
            displayTitle: "Arrival",
            originalTitle: "Arrival",
            year: 2016,
            overviewPreview: "Preview",
            confidence: confidence
        )
    }

    private func movieDetails(
        id: Int,
        title: String,
        summary: String? = "Summary",
        language: String? = "en",
        rawPayloadJSON: String = "{}"
    ) -> MetadataDetails {
        MetadataDetails(
            identifier: movieID(id),
            title: title,
            originalTitle: "Original Arrival",
            summary: summary,
            language: language,
            releaseDate: "2016-11-11",
            externalIDs: [
                .tmdbMovie: "\(id)",
                .imdb: "tt\(id)"
            ],
            rawPayloadJSON: rawPayloadJSON
        )
    }

    private func assertThrowsMetadataError<T>(
        _ expression: @autoclosure () async throws -> T,
        _ expected: ApplicationMetadataError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected \(expected).", file: file, line: line)
        } catch let error as ApplicationMetadataError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Expected \(expected), got \(error).", file: file, line: line)
        }
    }
}

private struct MetadataTestContext {
    let store: CineMindStore
    let item: MediaItem
    let file: MediaFile
}

private final class FakeMetadataProvider: MetadataProvider {
    let providerName: MetadataProviderName = .tmdb

    var searchResults: [MetadataCandidate] = []
    var detailsByID: [String: MetadataDetails] = [:]
    var imagesByID: [String: [RemoteImage]] = [:]
    var searchError: Error?
    var detailsError: Error?
    var imagesError: Error?

    private(set) var searchQueries: [MetadataSearchQuery] = []
    private(set) var detailsRequests: [MetadataProviderIdentifier] = []
    private(set) var imageRequests: [MetadataProviderIdentifier] = []

    func search(query: MetadataSearchQuery) async throws -> [MetadataCandidate] {
        searchQueries.append(query)
        if let searchError {
            throw searchError
        }
        return searchResults
    }

    func fetchDetails(identifier: MetadataProviderIdentifier) async throws -> MetadataDetails {
        detailsRequests.append(identifier)
        if let detailsError {
            throw detailsError
        }
        guard let details = detailsByID[identifier.rawValue] else {
            throw MetadataError.notFound
        }
        return details
    }

    func fetchImages(identifier: MetadataProviderIdentifier) async throws -> [RemoteImage] {
        imageRequests.append(identifier)
        if let imagesError {
            throw imagesError
        }
        return imagesByID[identifier.rawValue] ?? []
    }
}
