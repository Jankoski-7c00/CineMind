import Domain
import XCTest

final class DomainMetadataModelTests: XCTestCase {
    func testMetadataItemDefaultsAndOverrideLocks() {
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let updatedAt = Date(timeIntervalSince1970: 2_000)
        let defaultItem = MetadataItem(
            id: "metadata-item-1",
            mediaItemID: "media-item-1",
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        let lockedItem = MetadataItem(
            id: "metadata-item-2",
            mediaItemID: "media-item-1",
            title: "Manual Title",
            summary: "Manual summary",
            language: "en",
            titleOverrideLocked: true,
            summaryOverrideLocked: true,
            languageOverrideLocked: true,
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        XCTAssertEqual(defaultItem.id, "metadata-item-1")
        XCTAssertEqual(defaultItem.mediaItemID, "media-item-1")
        XCTAssertNil(defaultItem.title)
        XCTAssertNil(defaultItem.originalTitle)
        XCTAssertNil(defaultItem.summary)
        XCTAssertNil(defaultItem.language)
        XCTAssertNil(defaultItem.releaseDate)
        XCTAssertNil(defaultItem.airDate)
        XCTAssertFalse(defaultItem.titleOverrideLocked)
        XCTAssertFalse(defaultItem.summaryOverrideLocked)
        XCTAssertFalse(defaultItem.languageOverrideLocked)
        XCTAssertEqual(defaultItem.createdAt, createdAt)
        XCTAssertEqual(defaultItem.updatedAt, updatedAt)
        XCTAssertEqual(lockedItem.title, "Manual Title")
        XCTAssertEqual(lockedItem.summary, "Manual summary")
        XCTAssertEqual(lockedItem.language, "en")
        XCTAssertTrue(lockedItem.titleOverrideLocked)
        XCTAssertTrue(lockedItem.summaryOverrideLocked)
        XCTAssertTrue(lockedItem.languageOverrideLocked)
    }

    func testMetadataExternalIDStoresIDsWithoutTouchingMediaItem() throws {
        let item = MediaItem(id: "media-item-1", mediaType: .movie, title: "Arrival", year: 2016)
        let externalID = try MetadataExternalID.validated(
            id: "external-id-1",
            mediaItemID: item.id,
            provider: .tmdb,
            externalIDType: .tmdbMovie,
            externalIDValue: "329865"
        )

        XCTAssertEqual(externalID.mediaItemID, item.id)
        XCTAssertEqual(externalID.provider, .tmdb)
        XCTAssertEqual(externalID.externalIDType, .tmdbMovie)
        XCTAssertEqual(externalID.externalIDValue, "329865")
        assertMediaItemDoesNotExposeProviderMetadata(item)
    }

    func testMetadataExternalIDRejectsEmptyExternalIDValue() {
        XCTAssertThrowsError(
            try MetadataExternalID.validated(
                mediaItemID: "media-item-1",
                provider: .tmdb,
                externalIDType: .imdb,
                externalIDValue: ""
            )
        ) { error in
            XCTAssertEqual(error as? DomainValidationError, .emptyMetadataExternalIDValue)
        }
    }

    func testMetadataSourceRecordAcceptsConfidenceBoundaries() throws {
        let zeroConfidence = try MetadataSourceRecord.validated(
            id: "source-record-1",
            mediaItemID: "media-item-1",
            provider: .tmdb,
            providerID: "movie:1",
            providerMediaType: .movie,
            confidence: 0.0,
            matchSource: .automatic
        )
        let fullConfidence = try MetadataSourceRecord.validated(
            id: "source-record-2",
            mediaItemID: "media-item-1",
            provider: .tmdb,
            providerID: "movie:2",
            providerMediaType: .movie,
            confidence: 1.0,
            matchSource: .manual,
            manualMatchLocked: true
        )

        XCTAssertEqual(zeroConfidence.confidence, 0.0)
        XCTAssertEqual(zeroConfidence.matchSource, .automatic)
        XCTAssertFalse(zeroConfidence.manualMatchLocked)
        XCTAssertEqual(fullConfidence.confidence, 1.0)
        XCTAssertEqual(fullConfidence.matchSource, .manual)
        XCTAssertTrue(fullConfidence.manualMatchLocked)
    }

    func testMetadataSourceRecordRejectsConfidenceBelowZeroOrAboveOne() {
        XCTAssertThrowsError(
            try MetadataSourceRecord.validated(
                mediaItemID: "media-item-1",
                provider: .tmdb,
                providerID: "movie:1",
                providerMediaType: .movie,
                confidence: -0.1,
                matchSource: .automatic
            )
        ) { error in
            XCTAssertEqual(error as? DomainValidationError, .invalidMetadataSourceConfidence(-0.1))
        }
        XCTAssertThrowsError(
            try MetadataSourceRecord.validated(
                mediaItemID: "media-item-1",
                provider: .tmdb,
                providerID: "movie:1",
                providerMediaType: .movie,
                confidence: 1.1,
                matchSource: .automatic
            )
        ) { error in
            XCTAssertEqual(error as? DomainValidationError, .invalidMetadataSourceConfidence(1.1))
        }
    }

    func testMetadataSourceRecordRejectsEmptyProviderID() {
        XCTAssertThrowsError(
            try MetadataSourceRecord.validated(
                mediaItemID: "media-item-1",
                provider: .tmdb,
                providerID: "",
                providerMediaType: .movie,
                confidence: 0.8,
                matchSource: .automatic
            )
        ) { error in
            XCTAssertEqual(error as? DomainValidationError, .emptyMetadataSourceProviderID)
        }
    }

    func testPosterAssetStoresRemotePathAndCacheMetadata() throws {
        let cachedAt = Date(timeIntervalSince1970: 3_000)
        let asset = try PosterAsset.validated(
            id: "poster-asset-1",
            mediaItemID: "media-item-1",
            assetType: .poster,
            source: .tmdb,
            remotePath: "/poster.jpg",
            width: 500,
            height: 750,
            preferredCacheSize: "w500",
            localCachePath: "posters/media-item-1/poster.jpg",
            cachedAt: cachedAt,
            isSelected: true,
            selectionSource: .manual
        )

        XCTAssertEqual(asset.id, "poster-asset-1")
        XCTAssertEqual(asset.mediaItemID, "media-item-1")
        XCTAssertEqual(asset.assetType, .poster)
        XCTAssertEqual(asset.source, .tmdb)
        XCTAssertEqual(asset.remotePath, "/poster.jpg")
        XCTAssertEqual(asset.width, 500)
        XCTAssertEqual(asset.height, 750)
        XCTAssertEqual(asset.preferredCacheSize, "w500")
        XCTAssertEqual(asset.localCachePath, "posters/media-item-1/poster.jpg")
        XCTAssertEqual(asset.cachedAt, cachedAt)
        XCTAssertTrue(asset.isSelected)
        XCTAssertEqual(asset.selectionSource, .manual)
    }

    func testPosterAssetRejectsEmptyRemotePath() {
        XCTAssertThrowsError(
            try PosterAsset.validated(
                mediaItemID: "media-item-1",
                assetType: .poster,
                source: .tmdb,
                remotePath: "",
                preferredCacheSize: "w500"
            )
        ) { error in
            XCTAssertEqual(error as? DomainValidationError, .emptyPosterRemotePath)
        }
    }

    func testPosterAssetRejectsEmptyPreferredCacheSize() {
        XCTAssertThrowsError(
            try PosterAsset.validated(
                mediaItemID: "media-item-1",
                assetType: .poster,
                source: .tmdb,
                remotePath: "/poster.jpg",
                preferredCacheSize: ""
            )
        ) { error in
            XCTAssertEqual(error as? DomainValidationError, .emptyPosterPreferredCacheSize)
        }
    }

    func testPosterAssetRejectsNonPositiveWidthAndHeightWhenPresent() {
        XCTAssertThrowsError(
            try PosterAsset.validated(
                mediaItemID: "media-item-1",
                assetType: .poster,
                source: .tmdb,
                remotePath: "/poster.jpg",
                width: 0,
                preferredCacheSize: "w500"
            )
        ) { error in
            XCTAssertEqual(error as? DomainValidationError, .invalidPosterWidth(0))
        }
        XCTAssertThrowsError(
            try PosterAsset.validated(
                mediaItemID: "media-item-1",
                assetType: .poster,
                source: .tmdb,
                remotePath: "/poster.jpg",
                height: -1,
                preferredCacheSize: "w500"
            )
        ) { error in
            XCTAssertEqual(error as? DomainValidationError, .invalidPosterHeight(-1))
        }
    }

    func testPhase3MetadataEnumCoverage() {
        XCTAssertEqual(MetadataProviderName.allCases.map(\.rawValue), ["tmdb"])
        XCTAssertEqual(MetadataProviderMediaType.allCases.map(\.rawValue), ["movie", "episode"])
        XCTAssertEqual(MetadataMatchSource.allCases.map(\.rawValue), ["automatic", "manual"])
        XCTAssertEqual(
            MetadataExternalIDType.allCases.map(\.rawValue),
            ["tmdb_movie", "tmdb_tv_series", "tmdb_episode", "imdb"]
        )
        XCTAssertEqual(PosterAssetType.allCases.map(\.rawValue), ["poster"])
        XCTAssertEqual(PosterAssetSource.allCases.map(\.rawValue), ["tmdb"])
        XCTAssertEqual(PosterSelectionSource.allCases.map(\.rawValue), ["automatic", "manual"])
    }

    func testMediaItemRemainsScannerCompatibleAndDoesNotExposeProviderMetadata() throws {
        let episodeInfo = try EpisodeInfo.validated(
            seriesTitle: "Severance",
            seasonNumber: 1,
            episodeNumber: 2,
            episodeTitle: "Half Loop"
        )
        let movie = MediaItem(mediaType: .movie, title: "Arrival", year: 2016)
        let episode = MediaItem(
            mediaType: .episode,
            title: "Half Loop",
            normalizedTitle: MediaTitleNormalizer.normalize(episodeInfo.seriesTitle),
            episodeInfo: episodeInfo
        )

        XCTAssertEqual(movie.title, "Arrival")
        XCTAssertEqual(movie.normalizedTitle, "arrival")
        XCTAssertEqual(movie.year, 2016)
        XCTAssertEqual(episode.mediaType, .episode)
        XCTAssertEqual(episode.episodeInfo?.seriesTitle, "Severance")
        XCTAssertEqual(episode.episodeInfo?.seasonNumber, 1)
        XCTAssertEqual(episode.episodeInfo?.episodeNumber, 2)
        assertMediaItemDoesNotExposeProviderMetadata(movie)
        assertMediaItemDoesNotExposeProviderMetadata(episode)
    }

    private func assertMediaItemDoesNotExposeProviderMetadata(
        _ item: MediaItem,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let labels = Set(Mirror(reflecting: item).children.compactMap(\.label))
        let providerSpecificLabels: Set<String> = [
            "tmdbID",
            "tmdbId",
            "imdbID",
            "imdbId",
            "provider",
            "providerID",
            "providerId",
            "providerSummary",
            "providerLanguage",
            "originalTitle",
            "summary",
            "language",
            "posterPath",
            "posterRemotePath",
            "manualMatchLocked",
            "titleOverrideLocked",
            "summaryOverrideLocked",
            "languageOverrideLocked"
        ]

        XCTAssertTrue(
            labels.isDisjoint(with: providerSpecificLabels),
            "MediaItem should not expose provider metadata fields: \(labels.intersection(providerSpecificLabels))",
            file: file,
            line: line
        )
    }
}
