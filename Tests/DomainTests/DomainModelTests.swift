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

    func testEpisodeInfoStaysMinimal() {
        let episode = EpisodeInfo(
            seriesTitle: "Severance",
            seasonNumber: 1,
            episodeNumber: 2,
            episodeTitle: "Half Loop"
        )
        let item = MediaItem(
            mediaType: .episode,
            title: "Half Loop",
            normalizedTitle: MediaTitleNormalizer.normalize(episode.seriesTitle),
            episodeInfo: episode
        )

        XCTAssertEqual(item.episodeInfo?.seriesTitle, "Severance")
        XCTAssertEqual(item.episodeInfo?.seasonNumber, 1)
        XCTAssertEqual(item.episodeInfo?.episodeNumber, 2)
        XCTAssertEqual(item.episodeInfo?.episodeTitle, "Half Loop")
    }

    func testTitleNormalizationRemovesCommonFilenameSeparators() {
        XCTAssertEqual(
            MediaTitleNormalizer.normalize("The.Matrix_Reloaded-2003"),
            "the matrix reloaded 2003"
        )
    }

    func testScanRunDefaultsToRunningAndTracksAvailabilitySeparately() {
        let run = ScanRun(libraryID: "library-1")
        let item = MediaItem(mediaType: .movie, title: "Moon", year: 2009)
        let unavailableFile = MediaFile(
            mediaItemID: item.id,
            libraryFolderID: "folder-1",
            relativePath: "Moon (2009).mkv",
            absolutePathHash: "diagnostic-hash",
            fileName: "Moon (2009).mkv",
            fileExtension: "mkv",
            fileSizeBytes: 512,
            isAvailable: false
        )

        XCTAssertEqual(run.status, .running)
        XCTAssertFalse(unavailableFile.isAvailable)
    }
}
