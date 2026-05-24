import Domain
import XCTest

final class DomainModelTests: XCTestCase {
    func testMediaItemAndMediaFileHaveSeparateIdentities() {
        let item = MediaItem(mediaType: .movie, title: "Arrival", year: 2016)
        let file = MediaFile(
            mediaItemID: item.id,
            libraryFolderID: "folder-1",
            relativePath: "Arrival (2016).mkv",
            absolutePathHash: "diagnostic-hash",
            fileName: "Arrival (2016).mkv",
            fileExtension: "mkv",
            fileSizeBytes: 1024
        )

        XCTAssertNotEqual(item.id, file.id)
        XCTAssertEqual(file.mediaItemID, item.id)
        XCTAssertEqual(item.mediaType, .movie)
    }

    func testMediaFileBelongsToMediaItemAndSupportsMultipleFiles() {
        let item = MediaItem(mediaType: .movie, title: "Moon", year: 2009)
        let primaryFile = MediaFile(
            mediaItemID: item.id,
            libraryFolderID: "folder-1",
            relativePath: "Moon (2009).mkv",
            absolutePathHash: "hash-1",
            fileName: "Moon (2009).mkv",
            fileExtension: "mkv",
            fileSizeBytes: 1024
        )
        let backupFile = MediaFile(
            mediaItemID: item.id,
            libraryFolderID: "folder-1",
            relativePath: "Backups/Moon (2009).mp4",
            absolutePathHash: "hash-2",
            fileName: "Moon (2009).mp4",
            fileExtension: "MP4",
            fileSizeBytes: 2048
        )

        XCTAssertEqual(primaryFile.mediaItemID, item.id)
        XCTAssertEqual(backupFile.mediaItemID, item.id)
        XCTAssertNotEqual(primaryFile.id, backupFile.id)
        XCTAssertEqual(backupFile.fileExtension, "mp4")
    }

    func testMediaTypeMovieVsEpisodeBehavior() throws {
        let episode = try EpisodeInfo.validated(
            seriesTitle: "Severance",
            seasonNumber: 1,
            episodeNumber: 2,
            episodeTitle: "Half Loop"
        )
        let movie = MediaItem(mediaType: .movie, title: "Arrival", year: 2016)
        let item = MediaItem(
            mediaType: .episode,
            title: "Half Loop",
            normalizedTitle: MediaTitleNormalizer.normalize(episode.seriesTitle),
            episodeInfo: episode
        )

        XCTAssertFalse(MediaType.movie.requiresEpisodeInfo)
        XCTAssertTrue(MediaType.episode.requiresEpisodeInfo)
        XCTAssertNil(movie.episodeInfo)
        XCTAssertEqual(item.mediaType, .episode)
        XCTAssertEqual(item.episodeInfo?.seriesTitle, "Severance")
        XCTAssertEqual(item.episodeInfo?.seasonNumber, 1)
        XCTAssertEqual(item.episodeInfo?.episodeNumber, 2)
        XCTAssertEqual(item.episodeInfo?.episodeTitle, "Half Loop")
    }

    func testEpisodeInfoValidationRequiresPositiveSeasonAndEpisodeNumbers() throws {
        let episode = try EpisodeInfo.validated(
            seriesTitle: "Severance",
            seasonNumber: 1,
            episodeNumber: 2
        )

        XCTAssertEqual(episode.seriesTitle, "Severance")
        XCTAssertEqual(episode.seasonNumber, 1)
        XCTAssertEqual(episode.episodeNumber, 2)
        XCTAssertThrowsError(
            try EpisodeInfo.validated(seriesTitle: "Severance", seasonNumber: 0, episodeNumber: 2)
        ) { error in
            XCTAssertEqual(error as? DomainValidationError, .invalidSeasonNumber(0))
        }
        XCTAssertThrowsError(
            try EpisodeInfo.validated(seriesTitle: "Severance", seasonNumber: 1, episodeNumber: -1)
        ) { error in
            XCTAssertEqual(error as? DomainValidationError, .invalidEpisodeNumber(-1))
        }
    }

    func testTitleNormalizationRemovesCommonFilenameSeparators() {
        XCTAssertEqual(
            MediaTitleNormalizer.normalize("The.Matrix_Reloaded-2003"),
            "the matrix reloaded 2003"
        )
    }

    func testMediaFileAvailabilityAvailableAndUnavailableBehavior() {
        let item = MediaItem(mediaType: .movie, title: "Moon", year: 2009)
        let availableFile = MediaFile(
            mediaItemID: item.id,
            libraryFolderID: "folder-1",
            relativePath: "Moon (2009).mkv",
            absolutePathHash: "diagnostic-hash",
            fileName: "Moon (2009).mkv",
            fileExtension: "mkv",
            fileSizeBytes: 512,
            availability: .available
        )
        let unavailableFile = MediaFile(
            mediaItemID: item.id,
            libraryFolderID: "folder-1",
            relativePath: "Missing/Moon (2009).mkv",
            absolutePathHash: "missing-hash",
            fileName: "Moon (2009).mkv",
            fileExtension: "mkv",
            fileSizeBytes: 512,
            availability: .unavailable
        )

        XCTAssertTrue(MediaFileAvailability.available.isAvailable)
        XCTAssertFalse(MediaFileAvailability.unavailable.isAvailable)
        XCTAssertEqual(MediaFileAvailability(isAvailable: true), .available)
        XCTAssertEqual(MediaFileAvailability(isAvailable: false), .unavailable)
        XCTAssertEqual(availableFile.availability, .available)
        XCTAssertEqual(unavailableFile.availability, .unavailable)
    }

    func testMediaFileAvailabilityAndLegacyIsAvailableStayBidirectionallyConsistent() {
        let item = MediaItem(mediaType: .movie, title: "Moon", year: 2009)
        var file = MediaFile(
            mediaItemID: item.id,
            libraryFolderID: "folder-1",
            relativePath: "Moon (2009).mkv",
            absolutePathHash: "diagnostic-hash",
            fileName: "Moon (2009).mkv",
            fileExtension: "mkv",
            fileSizeBytes: 512,
            isAvailable: true
        )

        XCTAssertEqual(file.availability, .available)
        file.availability = .unavailable
        XCTAssertFalse(file.isAvailable)
        file.isAvailable = true
        XCTAssertEqual(file.availability, .available)
    }

    func testScanStatusBehavior() {
        let run = ScanRun(libraryID: "library-1")

        XCTAssertEqual(run.status, .running)
        XCTAssertFalse(ScanStatus.running.isTerminal)
        XCTAssertTrue(ScanStatus.completed.isTerminal)
        XCTAssertTrue(ScanStatus.failed.isTerminal)
    }

    func testScanIssueTypeCoverage() {
        XCTAssertEqual(
            Set(ScanIssueType.allCases),
            [
                .folderUnavailable,
                .unsupportedFile,
                .metadataParseFailed,
                .duplicateCandidate,
                .renameCandidate,
                .filesystemError
            ]
        )
    }

    func testFilePathIsNotUsedAsMediaItemIdentity() {
        let item = MediaItem(id: "media-item-1", mediaType: .movie, title: "Arrival", year: 2016)
        let originalFile = MediaFile(
            mediaItemID: item.id,
            libraryFolderID: "folder-1",
            relativePath: "Arrival (2016).mkv",
            absolutePathHash: "hash-1",
            fileName: "Arrival (2016).mkv",
            fileExtension: "mkv",
            fileSizeBytes: 1024
        )
        let renamedFile = MediaFile(
            mediaItemID: item.id,
            libraryFolderID: "folder-1",
            relativePath: "Renamed/Arrival (2016).mkv",
            absolutePathHash: "hash-2",
            fileName: "Arrival (2016).mkv",
            fileExtension: "mkv",
            fileSizeBytes: 1024
        )

        XCTAssertEqual(item.id, "media-item-1")
        XCTAssertEqual(originalFile.mediaItemID, item.id)
        XCTAssertEqual(renamedFile.mediaItemID, item.id)
        XCTAssertNotEqual(originalFile.relativePath, renamedFile.relativePath)
        XCTAssertNotEqual(originalFile.id, renamedFile.id)
    }

    func testPlaybackHistoryAllowsValidNonNegativeValues() throws {
        let playedAt = Date(timeIntervalSince1970: 1_000)
        let history = try PlaybackHistory.validated(
            id: "history-1",
            mediaItemID: "item-1",
            mediaFileID: "file-1",
            positionMS: 1_000,
            durationMS: 7_000,
            completed: false,
            playCount: 2,
            lastPlayedAt: playedAt,
            createdAt: playedAt,
            updatedAt: playedAt
        )

        XCTAssertEqual(history.id, "history-1")
        XCTAssertEqual(history.positionMS, 1_000)
        XCTAssertEqual(history.durationMS, 7_000)
        XCTAssertFalse(history.completed)
        XCTAssertEqual(history.playCount, 2)
        XCTAssertEqual(history.lastPlayedAt, playedAt)
    }

    func testPlaybackHistoryValidationRejectsNegativeValues() {
        XCTAssertThrowsError(
            try PlaybackHistory.validate(positionMS: -1, durationMS: 1, playCount: 0)
        ) { error in
            XCTAssertEqual(error as? DomainValidationError, .invalidPlaybackPositionMS(-1))
        }
        XCTAssertThrowsError(
            try PlaybackHistory.validate(positionMS: 0, durationMS: -1, playCount: 0)
        ) { error in
            XCTAssertEqual(error as? DomainValidationError, .invalidPlaybackDurationMS(-1))
        }
        XCTAssertThrowsError(
            try PlaybackHistory.validate(positionMS: 0, durationMS: nil, playCount: -1)
        ) { error in
            XCTAssertEqual(error as? DomainValidationError, .invalidPlaybackPlayCount(-1))
        }
    }

    func testPlaybackHistoryStoresMediaItemAndMediaFileIDsSeparately() {
        let history = PlaybackHistory(
            mediaItemID: "media-item-1",
            mediaFileID: "media-file-1",
            positionMS: 0,
            completed: false,
            playCount: 0
        )

        XCTAssertEqual(history.mediaItemID, "media-item-1")
        XCTAssertEqual(history.mediaFileID, "media-file-1")
        XCTAssertNotEqual(history.mediaItemID, history.mediaFileID)
    }

    func testSubtitleAssetStoresExternalSidecarMetadata() {
        let asset = SubtitleAsset(
            id: "subtitle-1",
            mediaItemID: "media-item-1",
            mediaFileID: "media-file-1",
            libraryFolderID: "folder-1",
            relativePath: "Arrival.en.srt",
            fileName: "Arrival.en.srt",
            fileExtension: "SRT",
            format: .srt,
            languageCode: "en",
            displayName: "English",
            source: .external,
            isAvailable: true
        )

        XCTAssertEqual(asset.fileExtension, "srt")
        XCTAssertEqual(asset.format, .srt)
        XCTAssertEqual(asset.languageCode, "en")
        XCTAssertEqual(asset.source, .external)
        XCTAssertTrue(asset.isAvailable)
    }
}
