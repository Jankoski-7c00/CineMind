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

    func testSearchQueryIncludesUniqueIMDBIDFromMediaFilePath() async throws {
        let context = try makeMediaContext(
            relativePath: "Movies/Arrival.tt0137523.2016.mkv",
            fileName: "Arrival.tt0137523.2016.mkv"
        )
        let provider = FakeMetadataProvider()

        _ = try await SearchMetadataCandidatesUseCase(
            store: context.store,
            provider: provider
        ).search(mediaItemID: context.item.id)

        XCTAssertEqual(provider.searchQueries.first?.imdbID, "tt0137523")
    }

    func testSearchQueryIgnoresConflictingIMDBIDs() async throws {
        let item = MediaItem(mediaType: .movie, title: "Arrival tt0137523", year: 2016)
        let context = try makeMediaContext(
            item: item,
            relativePath: "Movies/Arrival.tt0000001.mkv",
            fileName: "Arrival.tt0000001.mkv"
        )
        let provider = FakeMetadataProvider()

        _ = try await SearchMetadataCandidatesUseCase(
            store: context.store,
            provider: provider
        ).search(mediaItemID: context.item.id)

        XCTAssertNil(provider.searchQueries.first?.imdbID)
    }

    func testMetadataActionServiceMapsSearchCandidatesForAppUI() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()
        provider.searchResults = [
            MetadataCandidate(
                identifier: movieID(550),
                displayTitle: "Arrival",
                originalTitle: "Arrival",
                year: 2016,
                overviewPreview: "A linguist works with alien visitors.",
                confidence: 0.875
            )
        ]

        let candidates = try await LibraryMetadataActionService(
            store: context.store,
            provider: provider,
            language: "en-US"
        ).searchMetadataCandidates(mediaItemID: context.item.id)

        XCTAssertEqual(
            candidates,
            [
                LibraryMetadataCandidate(
                    providerID: "movie:550",
                    title: "Arrival",
                    subtitle: "2016",
                    overviewPreview: "A linguist works with alien visitors.",
                    confidenceLabel: "88%"
                )
            ]
        )
        XCTAssertEqual(provider.searchQueries.first?.language, "en-US")
        XCTAssertNil(try context.store.fetchMetadataItem(mediaItemID: context.item.id))
    }

    func testMetadataActionServiceRefreshMapsAutoMatchResultToActionMessage() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()
        provider.searchResults = [movieCandidate(id: 550, confidence: 0.96)]
        provider.detailsByID["movie:550"] = movieDetails(id: 550, title: "Arrival Matched")

        let result = try await LibraryMetadataActionService(
            store: context.store,
            provider: provider
        ).refreshMetadata(mediaItemID: context.item.id)

        XCTAssertEqual(result.message, "Metadata matched and refreshed.")
        XCTAssertEqual(
            try context.store.fetchMetadataItem(mediaItemID: context.item.id)?.title,
            "Arrival Matched"
        )
    }

    func testMetadataActionServiceManualRematchWritesManualLock() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()
        provider.detailsByID["movie:550"] = movieDetails(id: 550, title: "Manual Arrival")

        let result = try await LibraryMetadataActionService(
            store: context.store,
            provider: provider
        ).rematchMetadata(mediaItemID: context.item.id, providerID: "movie:550")

        XCTAssertEqual(result.message, "Metadata match saved.")
        let source = try XCTUnwrap(
            context.store.fetchMetadataSourceRecord(
                mediaItemID: context.item.id,
                provider: .tmdb
            )
        )
        XCTAssertEqual(source.providerID, "movie:550")
        XCTAssertEqual(source.matchSource, .manual)
        XCTAssertTrue(source.manualMatchLocked)
    }

    func testMetadataActionServiceSetsAndClearsOverride() async throws {
        let context = try makeMediaContext()
        let service = LibraryMetadataActionService(
            store: context.store,
            provider: FakeMetadataProvider()
        )

        let setResult = try await service.setMetadataOverride(
            mediaItemID: context.item.id,
            field: .title,
            value: "Manual Title"
        )

        XCTAssertEqual(setResult.message, "Title override saved.")
        var metadata = try XCTUnwrap(
            context.store.fetchMetadataItem(mediaItemID: context.item.id)
        )
        XCTAssertEqual(metadata.title, "Manual Title")
        XCTAssertTrue(metadata.titleOverrideLocked)

        let clearResult = try await service.clearMetadataOverride(
            mediaItemID: context.item.id,
            field: .title
        )

        XCTAssertEqual(clearResult.message, "Title override cleared.")
        metadata = try XCTUnwrap(context.store.fetchMetadataItem(mediaItemID: context.item.id))
        XCTAssertEqual(metadata.title, "Manual Title")
        XCTAssertFalse(metadata.titleOverrideLocked)
    }

    func testMetadataActionServiceSelectsPoster() async throws {
        let context = try makeMediaContext()
        let first = try posterAsset(
            id: "action-service-poster-first",
            mediaItemID: context.item.id,
            remotePath: "/action-first.jpg",
            isSelected: true
        )
        let second = try posterAsset(
            id: "action-service-poster-second",
            mediaItemID: context.item.id,
            remotePath: "/action-second.jpg"
        )
        try context.store.savePosterAsset(first)
        try context.store.savePosterAsset(second)

        let result = try await LibraryMetadataActionService(
            store: context.store,
            provider: FakeMetadataProvider()
        ).selectPoster(
            mediaItemID: context.item.id,
            posterAssetID: second.id
        )

        XCTAssertEqual(result.message, "Poster selected.")
        let posters = try context.store.fetchPosterAssets(mediaItemID: context.item.id)
        XCTAssertFalse(try XCTUnwrap(posters.first { $0.id == first.id }).isSelected)
        let selected = try XCTUnwrap(posters.first { $0.id == second.id })
        XCTAssertTrue(selected.isSelected)
        XCTAssertEqual(selected.selectionSource, .manual)
    }

    func testMetadataActionServiceMapsProviderErrorToUISafeMessage() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()
        provider.searchError = MetadataError.missingToken

        do {
            _ = try await LibraryMetadataActionService(
                store: context.store,
                provider: provider
            ).searchMetadataCandidates(mediaItemID: context.item.id)
            XCTFail("Expected LibraryMetadataActionError.")
        } catch let error as LibraryMetadataActionError {
            XCTAssertEqual(
                error.message,
                "TMDB read token is missing. Open CineMind Settings to configure it."
            )
        } catch {
            XCTFail("Expected LibraryMetadataActionError, got \(error).")
        }
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
        XCTAssertTrue(posters[0].isSelected)
        XCTAssertEqual(posters[0].selectionSource, .automatic)
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
        let posters = try context.store.fetchPosterAssets(mediaItemID: context.item.id)
        XCTAssertEqual(posters.count, 1)
        XCTAssertTrue(posters[0].isSelected)
        XCTAssertEqual(posters[0].selectionSource, .automatic)
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

    func testRefreshWithoutSourceDelegatesToAutoMatch() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()
        let candidate = movieCandidate(id: 550, confidence: 0.96)
        provider.searchResults = [candidate]
        provider.detailsByID["movie:550"] = movieDetails(id: 550, title: "Arrival Auto")

        let result = try await RefreshMetadataUseCase(
            store: context.store,
            provider: provider
        ).refresh(mediaItemID: context.item.id)

        XCTAssertEqual(result, .autoMatched(.matched(candidate)))
        XCTAssertEqual(provider.searchQueries.count, 1)
        XCTAssertEqual(provider.detailsRequests.map(\.rawValue), ["movie:550"])
        XCTAssertEqual(
            try context.store.fetchMetadataSourceRecord(
                mediaItemID: context.item.id,
                provider: .tmdb
            )?.providerID,
            "movie:550"
        )
    }

    func testRefreshWithSourceUsesExactProviderIDAndDoesNotSearch() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()
        let matchedAt = Date(timeIntervalSince1970: 100)
        let previousRefresh = Date(timeIntervalSince1970: 200)
        let refreshedAt = Date(timeIntervalSince1970: 300)
        let existingSource = try sourceRecord(
            mediaItemID: context.item.id,
            providerID: "movie:550",
            confidence: 0.42,
            matchedAt: matchedAt,
            refreshedAt: previousRefresh
        )
        try context.store.saveMetadataSourceRecord(existingSource)
        provider.detailsByID["movie:550"] = movieDetails(
            id: 550,
            title: "Arrival Refreshed",
            rawPayloadJSON: #"{"refreshed":true}"#
        )
        provider.imagesByID["movie:550"] = [
            RemoteImage(source: .tmdb, remotePath: "/refreshed.jpg", preferredCacheSize: "w500")
        ]

        let result = try await RefreshMetadataUseCase(
            store: context.store,
            provider: provider,
            now: { refreshedAt }
        ).refresh(mediaItemID: context.item.id)

        let source = try XCTUnwrap(
            context.store.fetchMetadataSourceRecord(
                mediaItemID: context.item.id,
                provider: .tmdb
            )
        )
        XCTAssertEqual(result, .refreshed(source))
        XCTAssertEqual(provider.searchQueries, [])
        XCTAssertEqual(provider.detailsRequests.map(\.rawValue), ["movie:550"])
        XCTAssertEqual(provider.imageRequests.map(\.rawValue), ["movie:550"])
        XCTAssertEqual(source.id, existingSource.id)
        XCTAssertEqual(source.providerID, "movie:550")
        XCTAssertEqual(source.confidence, 0.42)
        XCTAssertEqual(source.matchSource, .automatic)
        XCTAssertFalse(source.manualMatchLocked)
        XCTAssertEqual(source.matchedAt, matchedAt)
        XCTAssertEqual(source.refreshedAt, refreshedAt)
        XCTAssertEqual(source.rawPayloadJSON, #"{"refreshed":true}"#)
        let posters = try context.store.fetchPosterAssets(mediaItemID: context.item.id)
        XCTAssertEqual(posters.count, 1)
        XCTAssertTrue(posters[0].isSelected)
        XCTAssertEqual(posters[0].remotePath, "/refreshed.jpg")
        XCTAssertEqual(posters[0].selectionSource, .automatic)
    }

    func testForcedRefreshWithSourceUsesExactProviderIDAndDoesNotSearch() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()
        try context.store.saveMetadataSourceRecord(
            try sourceRecord(mediaItemID: context.item.id, providerID: "movie:550")
        )
        provider.searchResults = [movieCandidate(id: 551, confidence: 0.99)]
        provider.detailsByID["movie:550"] = movieDetails(id: 550, title: "Forced Exact")

        _ = try await RefreshMetadataUseCase(
            store: context.store,
            provider: provider
        ).refresh(mediaItemID: context.item.id, force: true)

        XCTAssertEqual(provider.searchQueries, [])
        XCTAssertEqual(provider.detailsRequests.map(\.rawValue), ["movie:550"])
        XCTAssertEqual(
            try context.store.fetchMetadataSourceRecord(
                mediaItemID: context.item.id,
                provider: .tmdb
            )?.providerID,
            "movie:550"
        )
    }

    func testRefreshPreservesExistingSelectedPosterWhenProviderStillReturnsIt() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()
        try context.store.saveMetadataSourceRecord(
            try sourceRecord(mediaItemID: context.item.id, providerID: "movie:550")
        )
        let selectedPoster = try posterAsset(
            id: "poster-selected-existing",
            mediaItemID: context.item.id,
            remotePath: "/selected.jpg",
            isSelected: true,
            selectionSource: .manual
        )
        let otherPoster = try posterAsset(
            id: "poster-other-existing",
            mediaItemID: context.item.id,
            remotePath: "/other.jpg"
        )
        try context.store.savePosterAsset(selectedPoster)
        try context.store.savePosterAsset(otherPoster)
        provider.detailsByID["movie:550"] = movieDetails(id: 550, title: "Preserve Selected")
        provider.imagesByID["movie:550"] = [
            RemoteImage(source: .tmdb, remotePath: "/selected.jpg", preferredCacheSize: "w500"),
            RemoteImage(source: .tmdb, remotePath: "/new.jpg", preferredCacheSize: "w500")
        ]

        _ = try await RefreshMetadataUseCase(
            store: context.store,
            provider: provider
        ).refresh(mediaItemID: context.item.id)

        let posters = try context.store.fetchPosterAssets(mediaItemID: context.item.id)
        let selected = try XCTUnwrap(posters.first { $0.id == selectedPoster.id })
        let other = try XCTUnwrap(posters.first { $0.id == otherPoster.id })
        let newPoster = try XCTUnwrap(posters.first { $0.remotePath == "/new.jpg" })
        XCTAssertTrue(selected.isSelected)
        XCTAssertEqual(selected.selectionSource, .manual)
        XCTAssertFalse(other.isSelected)
        XCTAssertFalse(newPoster.isSelected)
    }

    func testRefreshWithManualLockUsesExactProviderIDAndDoesNotSearch() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()
        let existingSource = try sourceRecord(
            mediaItemID: context.item.id,
            providerID: "movie:550",
            confidence: 1.0,
            matchSource: .manual,
            manualMatchLocked: true
        )
        try context.store.saveMetadataSourceRecord(existingSource)
        provider.searchResults = [movieCandidate(id: 551, confidence: 0.99)]
        provider.detailsByID["movie:550"] = movieDetails(id: 550, title: "Locked Refresh")

        _ = try await RefreshMetadataUseCase(
            store: context.store,
            provider: provider
        ).refresh(mediaItemID: context.item.id)

        let source = try XCTUnwrap(
            context.store.fetchMetadataSourceRecord(
                mediaItemID: context.item.id,
                provider: .tmdb
            )
        )
        XCTAssertEqual(provider.searchQueries, [])
        XCTAssertEqual(provider.detailsRequests.map(\.rawValue), ["movie:550"])
        XCTAssertEqual(source.providerID, "movie:550")
        XCTAssertEqual(source.matchSource, .manual)
        XCTAssertEqual(source.confidence, 1.0)
        XCTAssertTrue(source.manualMatchLocked)
    }

    func testLockedTitleSurvivesRefresh() async throws {
        let context = try makeRefreshContextWithLockedMetadata(
            title: "Custom Title",
            titleLocked: true
        )
        let provider = FakeMetadataProvider()
        provider.detailsByID["movie:550"] = movieDetails(id: 550, title: "Provider Title")

        _ = try await RefreshMetadataUseCase(
            store: context.store,
            provider: provider
        ).refresh(mediaItemID: context.item.id)

        let metadata = try XCTUnwrap(context.store.fetchMetadataItem(mediaItemID: context.item.id))
        XCTAssertEqual(metadata.title, "Custom Title")
        XCTAssertTrue(metadata.titleOverrideLocked)
    }

    func testLockedSummarySurvivesRefresh() async throws {
        let context = try makeRefreshContextWithLockedMetadata(
            summary: "Custom Summary",
            summaryLocked: true
        )
        let provider = FakeMetadataProvider()
        provider.detailsByID["movie:550"] = movieDetails(
            id: 550,
            title: "Provider Title",
            summary: "Provider Summary"
        )

        _ = try await RefreshMetadataUseCase(
            store: context.store,
            provider: provider
        ).refresh(mediaItemID: context.item.id)

        let metadata = try XCTUnwrap(context.store.fetchMetadataItem(mediaItemID: context.item.id))
        XCTAssertEqual(metadata.summary, "Custom Summary")
        XCTAssertTrue(metadata.summaryOverrideLocked)
    }

    func testLockedLanguageSurvivesRefresh() async throws {
        let context = try makeRefreshContextWithLockedMetadata(
            language: "fr",
            languageLocked: true
        )
        let provider = FakeMetadataProvider()
        provider.detailsByID["movie:550"] = movieDetails(
            id: 550,
            title: "Provider Title",
            language: "en"
        )

        _ = try await RefreshMetadataUseCase(
            store: context.store,
            provider: provider
        ).refresh(mediaItemID: context.item.id)

        let metadata = try XCTUnwrap(context.store.fetchMetadataItem(mediaItemID: context.item.id))
        XCTAssertEqual(metadata.language, "fr")
        XCTAssertTrue(metadata.languageOverrideLocked)
    }

    func testRefreshProviderFailureLeavesExistingMetadataUnchanged() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()
        let existingMetadata = MetadataItem(
            id: "refresh-metadata-existing",
            mediaItemID: context.item.id,
            title: "Existing Title",
            summary: "Existing Summary",
            language: "en",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let existingSource = try sourceRecord(
            id: "refresh-source-existing",
            mediaItemID: context.item.id,
            providerID: "movie:550",
            confidence: 0.8,
            rawPayloadJSON: #"{"old":true}"#,
            matchedAt: Date(timeIntervalSince1970: 100),
            refreshedAt: Date(timeIntervalSince1970: 100),
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let existingPoster = try posterAsset(
            id: "refresh-poster-existing",
            mediaItemID: context.item.id,
            remotePath: "/existing-refresh.jpg",
            isSelected: true,
            selectionSource: .manual
        )
        try context.store.saveMetadataItem(existingMetadata)
        try context.store.saveMetadataSourceRecord(existingSource)
        try context.store.savePosterAsset(existingPoster)
        provider.detailsError = MetadataError.transportFailure

        do {
            _ = try await RefreshMetadataUseCase(
                store: context.store,
                provider: provider
            ).refresh(mediaItemID: context.item.id)
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

    func testRefreshDoesNotModifyPlaybackHistory() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()
        let history = PlaybackHistory(
            id: "refresh-history-existing",
            mediaItemID: context.item.id,
            mediaFileID: context.file.id,
            positionMS: 24_000,
            durationMS: 120_000,
            completed: false,
            playCount: 2,
            lastPlayedAt: Date(timeIntervalSince1970: 500),
            createdAt: Date(timeIntervalSince1970: 500),
            updatedAt: Date(timeIntervalSince1970: 500)
        )
        try context.store.savePlaybackHistory(history)
        try context.store.saveMetadataSourceRecord(
            try sourceRecord(mediaItemID: context.item.id, providerID: "movie:550")
        )
        provider.detailsByID["movie:550"] = movieDetails(id: 550, title: "Refresh Title")

        _ = try await RefreshMetadataUseCase(
            store: context.store,
            provider: provider
        ).refresh(mediaItemID: context.item.id)

        XCTAssertEqual(
            try context.store.fetchPlaybackHistory(
                mediaItemID: context.item.id,
                mediaFileID: context.file.id
            ),
            history
        )
    }

    func testRefreshLibraryProcessesMissingBeforeStaleAndDeduplicatesOverlap() async throws {
        let missingOverlap = MediaItem(
            mediaType: .movie,
            title: "Missing Overlap",
            year: 2010,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let context = try makeMediaContext(item: missingOverlap)
        let stale = MediaItem(
            mediaType: .movie,
            title: "Stale",
            year: 2011,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        try addMediaItem(stale, to: context.store)
        try context.store.saveMetadataItem(
            MetadataItem(mediaItemID: stale.id, title: "Stale Existing")
        )
        try context.store.saveMetadataSourceRecord(
            try sourceRecord(
                mediaItemID: missingOverlap.id,
                providerID: "movie:550",
                refreshedAt: nil
            )
        )
        try context.store.saveMetadataSourceRecord(
            try sourceRecord(
                mediaItemID: stale.id,
                providerID: "movie:551",
                refreshedAt: Date(timeIntervalSince1970: 100)
            )
        )
        let provider = FakeMetadataProvider()
        provider.detailsByID["movie:550"] = movieDetails(id: 550, title: "Missing Refreshed")
        provider.detailsByID["movie:551"] = movieDetails(id: 551, title: "Stale Refreshed")

        let result = try await RefreshLibraryMetadataUseCase(
            store: context.store,
            provider: provider
        ).refresh(
            limit: 2,
            staleThreshold: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(result, RefreshLibraryMetadataResult(refreshed: 2))
        XCTAssertEqual(provider.detailsRequests.map(\.rawValue), ["movie:550", "movie:551"])
        XCTAssertEqual(provider.searchQueries, [])
    }

    func testRefreshLibraryLimitIsRespected() async throws {
        let context = try makeMediaContext()
        let stale = MediaItem(mediaType: .movie, title: "Stale", year: 2011)
        try addMediaItem(stale, to: context.store)
        try context.store.saveMetadataItem(
            MetadataItem(mediaItemID: stale.id, title: "Stale Existing")
        )
        try context.store.saveMetadataSourceRecord(
            try sourceRecord(
                mediaItemID: context.item.id,
                providerID: "movie:550",
                refreshedAt: nil
            )
        )
        try context.store.saveMetadataSourceRecord(
            try sourceRecord(
                mediaItemID: stale.id,
                providerID: "movie:551",
                refreshedAt: Date(timeIntervalSince1970: 100)
            )
        )
        let provider = FakeMetadataProvider()
        provider.detailsByID["movie:550"] = movieDetails(id: 550, title: "Only Item")
        provider.detailsByID["movie:551"] = movieDetails(id: 551, title: "Should Not Run")

        let result = try await RefreshLibraryMetadataUseCase(
            store: context.store,
            provider: provider
        ).refresh(
            limit: 1,
            staleThreshold: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(result, RefreshLibraryMetadataResult(refreshed: 1))
        XCTAssertEqual(provider.detailsRequests.map(\.rawValue), ["movie:550"])
    }

    func testRefreshLibraryItemFailureIncrementsFailedAndContinues() async throws {
        let first = MediaItem(
            mediaType: .movie,
            title: "First",
            year: 2010,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let context = try makeMediaContext(item: first)
        let second = MediaItem(
            mediaType: .movie,
            title: "Second",
            year: 2011,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        try addMediaItem(second, to: context.store)
        try context.store.saveMetadataItem(
            MetadataItem(mediaItemID: first.id, title: "First Existing")
        )
        try context.store.saveMetadataItem(
            MetadataItem(mediaItemID: second.id, title: "Second Existing")
        )
        try context.store.saveMetadataSourceRecord(
            try sourceRecord(
                mediaItemID: first.id,
                providerID: "movie:550",
                refreshedAt: Date(timeIntervalSince1970: 100)
            )
        )
        try context.store.saveMetadataSourceRecord(
            try sourceRecord(
                mediaItemID: second.id,
                providerID: "movie:551",
                refreshedAt: Date(timeIntervalSince1970: 100)
            )
        )
        let provider = FakeMetadataProvider()
        provider.detailsErrorsByID["movie:550"] = MetadataError.transportFailure
        provider.detailsByID["movie:551"] = movieDetails(id: 551, title: "Second Refreshed")

        let result = try await RefreshLibraryMetadataUseCase(
            store: context.store,
            provider: provider
        ).refresh(
            limit: 2,
            staleThreshold: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(result, RefreshLibraryMetadataResult(refreshed: 1, failed: 1))
        XCTAssertEqual(provider.detailsRequests.map(\.rawValue), ["movie:550", "movie:551"])
        XCTAssertEqual(
            try context.store.fetchMetadataItem(mediaItemID: second.id)?.title,
            "Second Refreshed"
        )
    }

    func testRefreshLibraryUnmatchedIncrementsUnmatched() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()

        let result = try await RefreshLibraryMetadataUseCase(
            store: context.store,
            provider: provider
        ).refresh(limit: 1)

        XCTAssertEqual(result, RefreshLibraryMetadataResult(unmatched: 1))
        XCTAssertEqual(provider.searchQueries.count, 1)
        XCTAssertEqual(provider.detailsRequests, [])
    }

    func testRefreshLibraryAutoMatchIncrementsRefreshed() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()
        provider.searchResults = [movieCandidate(id: 550, confidence: 0.96)]
        provider.detailsByID["movie:550"] = movieDetails(id: 550, title: "Auto Batch")

        let result = try await RefreshLibraryMetadataUseCase(
            store: context.store,
            provider: provider
        ).refresh(limit: 1)

        XCTAssertEqual(result, RefreshLibraryMetadataResult(refreshed: 1))
        XCTAssertEqual(
            try context.store.fetchMetadataItem(mediaItemID: context.item.id)?.title,
            "Auto Batch"
        )
    }

    func testRefreshLibraryManualLockedItemFollowsItemRefreshBehavior() async throws {
        let context = try makeMediaContext()
        try context.store.saveMetadataItem(
            MetadataItem(mediaItemID: context.item.id, title: "Locked Existing")
        )
        try context.store.saveMetadataSourceRecord(
            try sourceRecord(
                mediaItemID: context.item.id,
                providerID: "movie:550",
                confidence: 1.0,
                matchSource: .manual,
                manualMatchLocked: true,
                refreshedAt: Date(timeIntervalSince1970: 100)
            )
        )
        let provider = FakeMetadataProvider()
        provider.searchResults = [movieCandidate(id: 551, confidence: 0.99)]
        provider.detailsByID["movie:550"] = movieDetails(id: 550, title: "Locked Batch")

        let result = try await RefreshLibraryMetadataUseCase(
            store: context.store,
            provider: provider
        ).refresh(
            limit: 1,
            staleThreshold: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(result, RefreshLibraryMetadataResult(refreshed: 1))
        XCTAssertEqual(provider.searchQueries, [])
        XCTAssertEqual(provider.detailsRequests.map(\.rawValue), ["movie:550"])
        let source = try XCTUnwrap(
            context.store.fetchMetadataSourceRecord(
                mediaItemID: context.item.id,
                provider: .tmdb
            )
        )
        XCTAssertTrue(source.manualMatchLocked)
        XCTAssertEqual(source.matchSource, .manual)
    }

    func testPosterCacheSuccessWritesLocalPathAndTimestamp() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()
        let posterCache = FakePosterCache()
        let cachedAt = Date(timeIntervalSince1970: 2_000)
        provider.searchResults = [movieCandidate(id: 550, confidence: 0.96)]
        provider.detailsByID["movie:550"] = movieDetails(id: 550, title: "Cached Poster")
        provider.imagesByID["movie:550"] = [
            RemoteImage(source: .tmdb, remotePath: "/cached.jpg", preferredCacheSize: "w500")
        ]
        posterCache.resultsByRemotePath["/cached.jpg"] = PosterCacheResult(
            localPath: "/cache/cached.jpg",
            cachedAt: cachedAt,
            byteCount: 123,
            state: .miss
        )

        _ = try await AutoMatchMetadataUseCase(
            store: context.store,
            provider: provider,
            posterCache: posterCache
        ).match(mediaItemID: context.item.id)

        let poster = try XCTUnwrap(
            try context.store.fetchPosterAssets(mediaItemID: context.item.id).first
        )
        XCTAssertEqual(poster.localCachePath, "/cache/cached.jpg")
        XCTAssertEqual(poster.cachedAt, cachedAt)
        XCTAssertEqual(posterCache.requests.map(\.remotePath), ["/cached.jpg"])
    }

    func testPosterCacheFailurePreservesExistingCacheFields() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()
        let posterCache = FakePosterCache()
        let existingCachedAt = Date(timeIntervalSince1970: 1_000)
        try context.store.saveMetadataSourceRecord(
            try sourceRecord(mediaItemID: context.item.id, providerID: "movie:550")
        )
        try context.store.savePosterAsset(
            try posterAsset(
                id: "poster-cached-existing",
                mediaItemID: context.item.id,
                remotePath: "/cached-existing.jpg",
                localCachePath: "/cache/existing.jpg",
                cachedAt: existingCachedAt
            )
        )
        provider.detailsByID["movie:550"] = movieDetails(id: 550, title: "Cache Failure")
        provider.imagesByID["movie:550"] = [
            RemoteImage(
                source: .tmdb,
                remotePath: "/cached-existing.jpg",
                preferredCacheSize: "w500"
            )
        ]
        posterCache.errorsByRemotePath["/cached-existing.jpg"] = MetadataError.transportFailure

        _ = try await RefreshMetadataUseCase(
            store: context.store,
            provider: provider,
            posterCache: posterCache
        ).refresh(mediaItemID: context.item.id)

        let poster = try XCTUnwrap(
            try context.store.fetchPosterAssets(mediaItemID: context.item.id)
                .first { $0.remotePath == "/cached-existing.jpg" }
        )
        XCTAssertEqual(poster.localCachePath, "/cache/existing.jpg")
        XCTAssertEqual(poster.cachedAt, existingCachedAt)
        XCTAssertEqual(
            try context.store.fetchMetadataItem(mediaItemID: context.item.id)?.title,
            "Cache Failure"
        )
    }

    func testPosterCacheFailureStoresNewPosterWithoutCacheFields() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()
        let posterCache = FakePosterCache()
        provider.searchResults = [movieCandidate(id: 550, confidence: 0.96)]
        provider.detailsByID["movie:550"] = movieDetails(id: 550, title: "Uncached Poster")
        provider.imagesByID["movie:550"] = [
            RemoteImage(source: .tmdb, remotePath: "/uncached.jpg", preferredCacheSize: "w500")
        ]
        posterCache.errorsByRemotePath["/uncached.jpg"] = MetadataError.transportFailure

        _ = try await AutoMatchMetadataUseCase(
            store: context.store,
            provider: provider,
            posterCache: posterCache
        ).match(mediaItemID: context.item.id)

        let poster = try XCTUnwrap(
            try context.store.fetchPosterAssets(mediaItemID: context.item.id)
                .first { $0.remotePath == "/uncached.jpg" }
        )
        XCTAssertNil(poster.localCachePath)
        XCTAssertNil(poster.cachedAt)
        XCTAssertEqual(
            try context.store.fetchMetadataItem(mediaItemID: context.item.id)?.title,
            "Uncached Poster"
        )
    }

    func testManualSelectedPosterSurvivesRefreshWhenProviderOmitsIt() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()
        let posterCache = FakePosterCache()
        try context.store.saveMetadataSourceRecord(
            try sourceRecord(mediaItemID: context.item.id, providerID: "movie:550")
        )
        let manualPoster = try posterAsset(
            id: "poster-manual-selected",
            mediaItemID: context.item.id,
            remotePath: "/manual-selected.jpg",
            isSelected: true,
            selectionSource: .manual
        )
        try context.store.savePosterAsset(manualPoster)
        provider.detailsByID["movie:550"] = movieDetails(id: 550, title: "Omitted Manual Poster")
        provider.imagesByID["movie:550"] = [
            RemoteImage(source: .tmdb, remotePath: "/new-poster.jpg", preferredCacheSize: "w500")
        ]
        posterCache.resultsByRemotePath["/new-poster.jpg"] = PosterCacheResult(
            localPath: "/cache/new-poster.jpg",
            cachedAt: Date(timeIntervalSince1970: 2_000),
            byteCount: 123,
            state: .miss
        )

        _ = try await RefreshMetadataUseCase(
            store: context.store,
            provider: provider,
            posterCache: posterCache
        ).refresh(mediaItemID: context.item.id)

        let posters = try context.store.fetchPosterAssets(mediaItemID: context.item.id)
        let selected = try XCTUnwrap(posters.first { $0.id == manualPoster.id })
        XCTAssertTrue(selected.isSelected)
        XCTAssertEqual(selected.selectionSource, .manual)
        let newPoster = try XCTUnwrap(posters.first { $0.remotePath == "/new-poster.jpg" })
        XCTAssertFalse(newPoster.isSelected)
        XCTAssertEqual(newPoster.localCachePath, "/cache/new-poster.jpg")
    }

    func testRefreshLibraryDoesNotModifyPlaybackHistory() async throws {
        let context = try makeMediaContext()
        let provider = FakeMetadataProvider()
        let history = PlaybackHistory(
            id: "refresh-library-history-existing",
            mediaItemID: context.item.id,
            mediaFileID: context.file.id,
            positionMS: 24_000,
            durationMS: 120_000,
            completed: false,
            playCount: 2,
            lastPlayedAt: Date(timeIntervalSince1970: 500),
            createdAt: Date(timeIntervalSince1970: 500),
            updatedAt: Date(timeIntervalSince1970: 500)
        )
        try context.store.savePlaybackHistory(history)
        try context.store.saveMetadataItem(
            MetadataItem(mediaItemID: context.item.id, title: "Existing")
        )
        try context.store.saveMetadataSourceRecord(
            try sourceRecord(
                mediaItemID: context.item.id,
                providerID: "movie:550",
                refreshedAt: Date(timeIntervalSince1970: 100)
            )
        )
        provider.detailsByID["movie:550"] = movieDetails(id: 550, title: "Batch Refresh")

        _ = try await RefreshLibraryMetadataUseCase(
            store: context.store,
            provider: provider
        ).refresh(
            limit: 1,
            staleThreshold: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(
            try context.store.fetchPlaybackHistory(
                mediaItemID: context.item.id,
                mediaFileID: context.file.id
            ),
            history
        )
    }

    func testSetTitleOverrideCreatesMetadataItemWhenMissing() throws {
        let context = try makeMediaContext()
        let now = Date(timeIntervalSince1970: 1_000)

        let metadata = try SetMetadataOverrideUseCase(
            store: context.store,
            now: { now }
        ).set(
            mediaItemID: context.item.id,
            field: .title,
            value: "Manual Title"
        )

        XCTAssertEqual(metadata, try context.store.fetchMetadataItem(mediaItemID: context.item.id))
        XCTAssertEqual(metadata.mediaItemID, context.item.id)
        XCTAssertEqual(metadata.title, "Manual Title")
        XCTAssertNil(metadata.summary)
        XCTAssertNil(metadata.language)
        XCTAssertTrue(metadata.titleOverrideLocked)
        XCTAssertFalse(metadata.summaryOverrideLocked)
        XCTAssertFalse(metadata.languageOverrideLocked)
        XCTAssertEqual(metadata.createdAt, now)
        XCTAssertEqual(metadata.updatedAt, now)
    }

    func testSetTitleOverridePreservesExistingSummaryLanguageAndMetadataFields() throws {
        let context = try makeMediaContext()
        let createdAt = Date(timeIntervalSince1970: 100)
        let updatedAt = Date(timeIntervalSince1970: 200)
        let now = Date(timeIntervalSince1970: 1_000)
        try context.store.saveMetadataItem(
            MetadataItem(
                id: "override-existing-metadata",
                mediaItemID: context.item.id,
                title: "Provider Title",
                originalTitle: "Original Provider Title",
                summary: "Existing Summary",
                language: "fr",
                releaseDate: "2016-11-11",
                airDate: "2016-11-12",
                summaryOverrideLocked: true,
                languageOverrideLocked: true,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        )

        let metadata = try SetMetadataOverrideUseCase(
            store: context.store,
            now: { now }
        ).set(
            mediaItemID: context.item.id,
            field: .title,
            value: "Manual Title"
        )

        XCTAssertEqual(metadata.id, "override-existing-metadata")
        XCTAssertEqual(metadata.title, "Manual Title")
        XCTAssertEqual(metadata.originalTitle, "Original Provider Title")
        XCTAssertEqual(metadata.summary, "Existing Summary")
        XCTAssertEqual(metadata.language, "fr")
        XCTAssertEqual(metadata.releaseDate, "2016-11-11")
        XCTAssertEqual(metadata.airDate, "2016-11-12")
        XCTAssertTrue(metadata.titleOverrideLocked)
        XCTAssertTrue(metadata.summaryOverrideLocked)
        XCTAssertTrue(metadata.languageOverrideLocked)
        XCTAssertEqual(metadata.createdAt, createdAt)
        XCTAssertEqual(metadata.updatedAt, now)
    }

    func testSetSummaryOverrideLocksOnlySummary() throws {
        let context = try makeMediaContext()
        try context.store.saveMetadataItem(
            MetadataItem(
                mediaItemID: context.item.id,
                title: "Existing Title",
                summary: "Existing Summary",
                language: "en"
            )
        )

        let metadata = try SetMetadataOverrideUseCase(store: context.store).set(
            mediaItemID: context.item.id,
            field: .summary,
            value: "Manual Summary"
        )

        XCTAssertEqual(metadata.title, "Existing Title")
        XCTAssertEqual(metadata.summary, "Manual Summary")
        XCTAssertEqual(metadata.language, "en")
        XCTAssertFalse(metadata.titleOverrideLocked)
        XCTAssertTrue(metadata.summaryOverrideLocked)
        XCTAssertFalse(metadata.languageOverrideLocked)
    }

    func testSetLanguageOverrideLocksOnlyLanguage() throws {
        let context = try makeMediaContext()
        try context.store.saveMetadataItem(
            MetadataItem(
                mediaItemID: context.item.id,
                title: "Existing Title",
                summary: "Existing Summary",
                language: "en"
            )
        )

        let metadata = try SetMetadataOverrideUseCase(store: context.store).set(
            mediaItemID: context.item.id,
            field: .language,
            value: "ja"
        )

        XCTAssertEqual(metadata.title, "Existing Title")
        XCTAssertEqual(metadata.summary, "Existing Summary")
        XCTAssertEqual(metadata.language, "ja")
        XCTAssertFalse(metadata.titleOverrideLocked)
        XCTAssertFalse(metadata.summaryOverrideLocked)
        XCTAssertTrue(metadata.languageOverrideLocked)
    }

    func testSetOverrideStoresEmptyStringAsProvided() throws {
        let context = try makeMediaContext()

        let metadata = try SetMetadataOverrideUseCase(store: context.store).set(
            mediaItemID: context.item.id,
            field: .title,
            value: ""
        )

        XCTAssertEqual(metadata.title, "")
        XCTAssertEqual(
            try context.store.fetchMetadataItem(mediaItemID: context.item.id)?.title,
            ""
        )
    }

    func testClearOverrideUnlocksOnlySelectedFieldKeepsValueAndUpdatesTimestamp() throws {
        let context = try makeMediaContext()
        let createdAt = Date(timeIntervalSince1970: 100)
        let updatedAt = Date(timeIntervalSince1970: 200)
        let now = Date(timeIntervalSince1970: 1_000)
        try context.store.saveMetadataItem(
            MetadataItem(
                id: "clear-override-metadata",
                mediaItemID: context.item.id,
                title: "Manual Title",
                summary: "Manual Summary",
                language: "de",
                titleOverrideLocked: true,
                summaryOverrideLocked: true,
                languageOverrideLocked: true,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        )

        let metadata = try XCTUnwrap(
            ClearMetadataOverrideUseCase(
                store: context.store,
                now: { now }
            ).clear(
                mediaItemID: context.item.id,
                field: .summary
            )
        )

        XCTAssertEqual(metadata.id, "clear-override-metadata")
        XCTAssertEqual(metadata.title, "Manual Title")
        XCTAssertEqual(metadata.summary, "Manual Summary")
        XCTAssertEqual(metadata.language, "de")
        XCTAssertTrue(metadata.titleOverrideLocked)
        XCTAssertFalse(metadata.summaryOverrideLocked)
        XCTAssertTrue(metadata.languageOverrideLocked)
        XCTAssertEqual(metadata.createdAt, createdAt)
        XCTAssertEqual(metadata.updatedAt, now)
    }

    func testClearOverrideDoesNotCreateMetadataItemWhenMissing() throws {
        let context = try makeMediaContext()

        let metadata = try ClearMetadataOverrideUseCase(store: context.store).clear(
            mediaItemID: context.item.id,
            field: .title
        )

        XCTAssertNil(metadata)
        XCTAssertNil(try context.store.fetchMetadataItem(mediaItemID: context.item.id))
    }

    func testSetOverrideDoesNotAlterSourceRecord() throws {
        let context = try makeMediaContext()
        let source = try sourceRecord(
            id: "override-source-existing",
            mediaItemID: context.item.id,
            providerID: "movie:550",
            confidence: 0.77,
            matchSource: .manual,
            manualMatchLocked: true,
            rawPayloadJSON: #"{"source":true}"#
        )
        try context.store.saveMetadataSourceRecord(source)

        _ = try SetMetadataOverrideUseCase(store: context.store).set(
            mediaItemID: context.item.id,
            field: .title,
            value: "Manual Title"
        )

        XCTAssertEqual(
            try context.store.fetchMetadataSourceRecord(
                mediaItemID: context.item.id,
                provider: .tmdb
            ),
            source
        )
    }

    func testSelectPosterVerifiesOwnershipAndLeavesOtherMediaItemPostersUntouched() throws {
        let context = try makeMediaContext()
        let otherItem = MediaItem(mediaType: .movie, title: "Moon", year: 2009)
        let first = try posterAsset(
            id: "poster-owned-first",
            mediaItemID: context.item.id,
            remotePath: "/owned-first.jpg",
            isSelected: true
        )
        let second = try posterAsset(
            id: "poster-owned-second",
            mediaItemID: context.item.id,
            remotePath: "/owned-second.jpg"
        )
        let other = try posterAsset(
            id: "poster-other-selected",
            mediaItemID: otherItem.id,
            remotePath: "/other-selected.jpg",
            isSelected: true,
            selectionSource: .automatic
        )
        try context.store.saveMediaItem(otherItem)
        try context.store.savePosterAsset(first)
        try context.store.savePosterAsset(second)
        try context.store.savePosterAsset(other)

        try SelectPosterAssetUseCase(store: context.store).select(
            mediaItemID: context.item.id,
            posterAssetID: second.id
        )

        let ownedPosters = try context.store.fetchPosterAssets(mediaItemID: context.item.id)
        XCTAssertFalse(try XCTUnwrap(ownedPosters.first { $0.id == first.id }).isSelected)
        let selected = try XCTUnwrap(ownedPosters.first { $0.id == second.id })
        XCTAssertTrue(selected.isSelected)
        XCTAssertEqual(selected.selectionSource, .manual)
        XCTAssertEqual(ownedPosters.count, 2)

        let otherPosters = try context.store.fetchPosterAssets(mediaItemID: otherItem.id)
        let otherSelected = try XCTUnwrap(otherPosters.first { $0.id == other.id })
        XCTAssertTrue(otherSelected.isSelected)
        XCTAssertEqual(otherSelected.selectionSource, .automatic)
    }

    func testSelectPosterSetsManualSelectionAndUnselectsPreviousPoster() throws {
        let context = try makeMediaContext()
        let first = try posterAsset(
            id: "poster-select-first",
            mediaItemID: context.item.id,
            remotePath: "/select-first.jpg",
            isSelected: true,
            selectionSource: .automatic
        )
        let second = try posterAsset(
            id: "poster-select-second",
            mediaItemID: context.item.id,
            remotePath: "/select-second.jpg"
        )
        try context.store.savePosterAsset(first)
        try context.store.savePosterAsset(second)

        try SelectPosterAssetUseCase(store: context.store).select(
            mediaItemID: context.item.id,
            posterAssetID: second.id
        )

        let posters = try context.store.fetchPosterAssets(mediaItemID: context.item.id)
        XCTAssertEqual(posters.count, 2)
        XCTAssertFalse(try XCTUnwrap(posters.first { $0.id == first.id }).isSelected)
        let selected = try XCTUnwrap(posters.first { $0.id == second.id })
        XCTAssertTrue(selected.isSelected)
        XCTAssertEqual(selected.selectionSource, .manual)
        XCTAssertNil(selected.localCachePath)
        XCTAssertNil(selected.cachedAt)
    }

    func testInvalidPosterMediaItemMismatchThrowsClearError() throws {
        let context = try makeMediaContext()
        let otherItem = MediaItem(mediaType: .movie, title: "Moon", year: 2009)
        let otherPoster = try posterAsset(
            id: "poster-mismatched",
            mediaItemID: otherItem.id,
            remotePath: "/mismatched.jpg"
        )
        try context.store.saveMediaItem(otherItem)
        try context.store.savePosterAsset(otherPoster)

        do {
            try SelectPosterAssetUseCase(store: context.store).select(
                mediaItemID: context.item.id,
                posterAssetID: otherPoster.id
            )
            XCTFail("Expected posterAssetMediaItemMismatch.")
        } catch let error as ApplicationMetadataError {
            XCTAssertEqual(
                error,
                .posterAssetMediaItemMismatch(
                    mediaItemID: context.item.id,
                    posterAssetID: otherPoster.id
                )
            )
        } catch {
            XCTFail("Expected posterAssetMediaItemMismatch, got \(error).")
        }

        let posters = try context.store.fetchPosterAssets(mediaItemID: otherItem.id)
        XCTAssertFalse(try XCTUnwrap(posters.first { $0.id == otherPoster.id }).isSelected)
    }

    func testOverrideAndPosterSelectionDoNotModifyPlaybackHistory() throws {
        let context = try makeMediaContext()
        let history = PlaybackHistory(
            id: "override-history-existing",
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
        let first = try posterAsset(
            id: "poster-history-first",
            mediaItemID: context.item.id,
            remotePath: "/history-first.jpg",
            isSelected: true
        )
        let second = try posterAsset(
            id: "poster-history-second",
            mediaItemID: context.item.id,
            remotePath: "/history-second.jpg"
        )
        try context.store.savePlaybackHistory(history)
        try context.store.savePosterAsset(first)
        try context.store.savePosterAsset(second)

        _ = try SetMetadataOverrideUseCase(store: context.store).set(
            mediaItemID: context.item.id,
            field: .title,
            value: "Manual Title"
        )
        _ = try ClearMetadataOverrideUseCase(store: context.store).clear(
            mediaItemID: context.item.id,
            field: .title
        )
        try SelectPosterAssetUseCase(store: context.store).select(
            mediaItemID: context.item.id,
            posterAssetID: second.id
        )

        XCTAssertEqual(
            try context.store.fetchPlaybackHistory(
                mediaItemID: context.item.id,
                mediaFileID: context.file.id
            ),
            history
        )
    }

    private func makeMediaContext(
        item: MediaItem = MediaItem(mediaType: .movie, title: "Arrival", year: 2016),
        relativePath: String? = nil,
        fileName: String? = nil
    ) throws -> MetadataTestContext {
        let store = try CineMindStore(path: databaseURL.path)
        let library = try store.createOrLoadLibrary(name: "Local")
        let folder = LibraryFolder(
            libraryID: library.id,
            displayName: "Movies",
            rootPath: "/media/movies"
        )
        let resolvedRelativePath = relativePath ?? "\(item.id).mkv"
        let resolvedFileName = fileName ?? URL(fileURLWithPath: resolvedRelativePath).lastPathComponent
        let file = MediaFile(
            mediaItemID: item.id,
            libraryFolderID: folder.id,
            relativePath: resolvedRelativePath,
            absolutePathHash: "metadata-test-\(UUID().uuidString)",
            fileName: resolvedFileName,
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

    private func makeRefreshContextWithLockedMetadata(
        title: String? = nil,
        summary: String? = nil,
        language: String? = nil,
        titleLocked: Bool = false,
        summaryLocked: Bool = false,
        languageLocked: Bool = false
    ) throws -> MetadataTestContext {
        let context = try makeMediaContext()
        try context.store.saveMetadataItem(
            MetadataItem(
                mediaItemID: context.item.id,
                title: title,
                summary: summary,
                language: language,
                titleOverrideLocked: titleLocked,
                summaryOverrideLocked: summaryLocked,
                languageOverrideLocked: languageLocked
            )
        )
        try context.store.saveMetadataSourceRecord(
            try sourceRecord(mediaItemID: context.item.id, providerID: "movie:550")
        )
        return context
    }

    @discardableResult
    private func addMediaItem(
        _ item: MediaItem,
        to store: CineMindStore
    ) throws -> MediaFile {
        let library = try XCTUnwrap(try store.fetchLibrary())
        let folder = try XCTUnwrap(try store.fetchLibraryFolders(libraryID: library.id).first)
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

        try store.saveMediaItem(item)
        try store.saveMediaFile(file)
        return file
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

    private func sourceRecord(
        id: MetadataSourceRecordID = DomainID.new(),
        mediaItemID: MediaItemID,
        providerID: String,
        confidence: Double = 0.9,
        matchSource: MetadataMatchSource = .automatic,
        manualMatchLocked: Bool = false,
        rawPayloadJSON: String? = "{}",
        matchedAt: Date = Date(timeIntervalSince1970: 100),
        refreshedAt: Date? = Date(timeIntervalSince1970: 100),
        createdAt: Date = Date(timeIntervalSince1970: 100),
        updatedAt: Date = Date(timeIntervalSince1970: 100)
    ) throws -> MetadataSourceRecord {
        try MetadataSourceRecord.validated(
            id: id,
            mediaItemID: mediaItemID,
            provider: .tmdb,
            providerID: providerID,
            providerMediaType: .movie,
            confidence: confidence,
            matchSource: matchSource,
            manualMatchLocked: manualMatchLocked,
            rawPayloadJSON: rawPayloadJSON,
            matchedAt: matchedAt,
            refreshedAt: refreshedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func posterAsset(
        id: PosterAssetID = DomainID.new(),
        mediaItemID: MediaItemID,
        remotePath: String,
        isSelected: Bool = false,
        selectionSource: PosterSelectionSource = .automatic,
        localCachePath: String? = nil,
        cachedAt: Date? = nil
    ) throws -> PosterAsset {
        try PosterAsset.validated(
            id: id,
            mediaItemID: mediaItemID,
            assetType: .poster,
            source: .tmdb,
            remotePath: remotePath,
            preferredCacheSize: "w500",
            localCachePath: localCachePath,
            cachedAt: cachedAt,
            isSelected: isSelected,
            selectionSource: selectionSource,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
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
    var detailsErrorsByID: [String: Error] = [:]
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
        if let error = detailsErrorsByID[identifier.rawValue] {
            throw error
        }
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

private final class FakePosterCache: ApplicationPosterCaching {
    var resultsByRemotePath: [String: PosterCacheResult] = [:]
    var errorsByRemotePath: [String: Error] = [:]

    private(set) var requests: [RemoteImage] = []

    func cache(_ image: RemoteImage) async throws -> PosterCacheResult {
        requests.append(image)
        if let error = errorsByRemotePath[image.remotePath] {
            throw error
        }
        if let result = resultsByRemotePath[image.remotePath] {
            return result
        }
        throw MetadataError.notFound
    }
}
