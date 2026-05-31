@testable import Application
import Domain
import Foundation
import Persistence
import Subtitle
import XCTest

final class LibrarySubtitleActionTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var databaseURL: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CineMindLibrarySubtitleActionTests-\(UUID().uuidString)", isDirectory: true)
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

    func testSearchMapsProviderResultsForAppUI() async throws {
        let context = try makeMediaContext()
        let provider = FakeSubtitleProvider()
        provider.searchResults = [
            SubtitleSearchResult(
                id: "provider-en",
                title: "Arrival English",
                languageCode: "en",
                format: .srt
            ),
            SubtitleSearchResult(
                id: "provider-styled",
                title: "Arrival Styled",
                languageCode: nil,
                format: .ass
            )
        ]

        let candidates = try await LibrarySubtitleActionService(
            store: context.store,
            provider: provider
        ).searchSubtitles(
            mediaItemID: context.item.id,
            mediaFileID: context.file.id,
            languageCode: "en"
        )

        XCTAssertEqual(
            candidates,
            [
                LibrarySubtitleCandidate(
                    resultID: "provider-en",
                    title: "Arrival English",
                    languageLabel: "EN",
                    formatLabel: "SRT",
                    isDownloadable: true
                ),
                LibrarySubtitleCandidate(
                    resultID: "provider-styled",
                    title: "Arrival Styled",
                    languageLabel: "Unknown language",
                    formatLabel: "ASS",
                    isDownloadable: false,
                    unavailableReason: "Only SRT and WebVTT subtitles can be downloaded for playback."
                )
            ]
        )
        XCTAssertEqual(
            provider.searchQueries,
            [
                SubtitleSearchQuery(
                    mediaItemID: context.item.id,
                    mediaFileID: context.file.id,
                    title: "Arrival",
                    languageCode: "en"
                )
            ]
        )
    }

    func testSearchRequiresMatchingMediaItemAndFile() async throws {
        let context = try makeMediaContext()
        let other = MediaItem(
            id: "subtitle-actions-other-item",
            mediaType: .movie,
            title: "Moon"
        )
        try context.store.saveMediaItem(other)

        do {
            _ = try await LibrarySubtitleActionService(
                store: context.store,
                provider: FakeSubtitleProvider()
            ).searchSubtitles(
                mediaItemID: other.id,
                mediaFileID: context.file.id,
                languageCode: nil
            )
            XCTFail("Expected matching media item/file validation failure.")
        } catch let error as LibrarySubtitleActionError {
            XCTAssertEqual(error.message, "That file is not available for this item.")
        } catch {
            XCTFail("Expected LibrarySubtitleActionError, got \(error).")
        }
    }

    func testDownloadWritesSubtitleAndPersistsDownloadedAsset() async throws {
        let context = try makeMediaContext()
        let provider = FakeSubtitleProvider()
        provider.downloadResultsByID["provider-en"] = srtDownloadResult()

        let result = try await LibrarySubtitleActionService(
            store: context.store,
            provider: provider,
            now: { Date(timeIntervalSince1970: 1_000) }
        ).downloadSubtitle(
            mediaItemID: context.item.id,
            mediaFileID: context.file.id,
            resultID: "provider-en"
        )

        XCTAssertEqual(result.message, "Subtitle downloaded.")
        XCTAssertEqual(result.resultID, "provider-en")

        let asset = try XCTUnwrap(try context.store.fetchSubtitleAssets(mediaFileID: context.file.id).first)
        XCTAssertEqual(asset.id, result.subtitleAssetID)
        XCTAssertEqual(asset.mediaItemID, context.item.id)
        XCTAssertEqual(asset.mediaFileID, context.file.id)
        XCTAssertEqual(asset.libraryFolderID, context.folder.id)
        XCTAssertEqual(asset.relativePath, ".cinemind/subtitles/subtitle-actions-file/provider-en.srt")
        XCTAssertEqual(asset.fileName, "provider-en.srt")
        XCTAssertEqual(asset.fileExtension, "srt")
        XCTAssertEqual(asset.format, .srt)
        XCTAssertEqual(asset.languageCode, "en")
        XCTAssertEqual(asset.displayName, "Arrival.en.srt")
        XCTAssertEqual(asset.source, .downloaded)
        XCTAssertTrue(asset.isAvailable)

        let downloadedURL = context.rootURL.appendingPathComponent(asset.relativePath, isDirectory: false)
        XCTAssertEqual(try String(contentsOf: downloadedURL, encoding: .utf8), srtContent)

        let playbackAsset = try XCTUnwrap(
            try context.store.fetchPlaybackSubtitleAssets(mediaFileID: context.file.id).first
        )
        XCTAssertEqual(playbackAsset.folderRootPath, context.rootURL.path)
        XCTAssertTrue(playbackAsset.isSelectable)
    }

    func testDownloadUpdatesExistingGeneratedAsset() async throws {
        let context = try makeMediaContext()
        let provider = FakeSubtitleProvider()
        provider.downloadResultsByID["provider-en"] = srtDownloadResult(content: srtContent)
        let service = LibrarySubtitleActionService(
            store: context.store,
            provider: provider,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        _ = try await service.downloadSubtitle(
            mediaItemID: context.item.id,
            mediaFileID: context.file.id,
            resultID: "provider-en"
        )
        provider.downloadResultsByID["provider-en"] = srtDownloadResult(content: updatedSRTContent)
        _ = try await service.downloadSubtitle(
            mediaItemID: context.item.id,
            mediaFileID: context.file.id,
            resultID: "provider-en"
        )

        let assets = try context.store.fetchSubtitleAssets(mediaFileID: context.file.id)
        XCTAssertEqual(assets.count, 1)
        let downloadedURL = context.rootURL.appendingPathComponent(assets[0].relativePath, isDirectory: false)
        XCTAssertEqual(try String(contentsOf: downloadedURL, encoding: .utf8), updatedSRTContent)
    }

    func testDownloadSanitizesTraversalInProviderIdentifiers() async throws {
        let context = try makeMediaContext()
        let provider = FakeSubtitleProvider()
        provider.downloadResultsByID["../evil/sub"] = SubtitleDownloadResult(
            resultID: "../evil/sub",
            suggestedFileName: "../../evil.vtt",
            languageCode: "en",
            format: .webVTT,
            content: webVTTContent
        )

        _ = try await LibrarySubtitleActionService(
            store: context.store,
            provider: provider
        ).downloadSubtitle(
            mediaItemID: context.item.id,
            mediaFileID: context.file.id,
            resultID: "../evil/sub"
        )

        let asset = try XCTUnwrap(try context.store.fetchSubtitleAssets(mediaFileID: context.file.id).first)
        XCTAssertEqual(asset.relativePath, ".cinemind/subtitles/subtitle-actions-file/evil-sub.vtt")
        XCTAssertFalse(asset.relativePath.contains(".."))
        XCTAssertEqual(asset.displayName, "evil.vtt")
    }

    func testProviderFailureDoesNotWritePartialAsset() async throws {
        let context = try makeMediaContext()
        let provider = FakeSubtitleProvider()
        provider.downloadError = SubtitleProviderTestError.failure

        do {
            _ = try await LibrarySubtitleActionService(
                store: context.store,
                provider: provider
            ).downloadSubtitle(
                mediaItemID: context.item.id,
                mediaFileID: context.file.id,
                resultID: "provider-en"
            )
            XCTFail("Expected provider failure.")
        } catch let error as LibrarySubtitleActionError {
            XCTAssertEqual(error.message, "Subtitle download failed.")
        } catch {
            XCTFail("Expected LibrarySubtitleActionError, got \(error).")
        }

        XCTAssertEqual(try context.store.fetchSubtitleAssets(mediaFileID: context.file.id), [])
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: context.rootURL.appendingPathComponent(".cinemind", isDirectory: true).path
            )
        )
    }

    func testFileWriteFailureDoesNotSaveAsset() async throws {
        let context = try makeMediaContext()
        let provider = FakeSubtitleProvider()
        provider.downloadResultsByID["provider-en"] = srtDownloadResult()

        do {
            _ = try await LibrarySubtitleActionService(
                store: context.store,
                provider: provider,
                fileWriter: FailingSubtitleFileWriter()
            ).downloadSubtitle(
                mediaItemID: context.item.id,
                mediaFileID: context.file.id,
                resultID: "provider-en"
            )
            XCTFail("Expected file writer failure.")
        } catch let error as LibrarySubtitleActionError {
            XCTAssertEqual(error.message, "Could not save the downloaded subtitle file.")
        } catch {
            XCTFail("Expected LibrarySubtitleActionError, got \(error).")
        }

        XCTAssertEqual(try context.store.fetchSubtitleAssets(mediaFileID: context.file.id), [])
    }

    func testUnsupportedDownloadedFormatReturnsUISafeError() async throws {
        let context = try makeMediaContext()
        let provider = FakeSubtitleProvider()
        provider.downloadResultsByID["provider-ass"] = SubtitleDownloadResult(
            resultID: "provider-ass",
            suggestedFileName: "Arrival.ass",
            languageCode: "en",
            format: .ass,
            content: "[Script Info]"
        )

        do {
            _ = try await LibrarySubtitleActionService(
                store: context.store,
                provider: provider
            ).downloadSubtitle(
                mediaItemID: context.item.id,
                mediaFileID: context.file.id,
                resultID: "provider-ass"
            )
            XCTFail("Expected unsupported format failure.")
        } catch let error as LibrarySubtitleActionError {
            XCTAssertEqual(
                error.message,
                "Only SRT and WebVTT subtitles can be downloaded for playback."
            )
        } catch {
            XCTFail("Expected LibrarySubtitleActionError, got \(error).")
        }

        XCTAssertEqual(try context.store.fetchSubtitleAssets(mediaFileID: context.file.id), [])
    }

    func testDownloadRefreshesActivePlaybackSubtitleOptions() async throws {
        let context = try makeMediaContext()
        let provider = FakeSubtitleProvider()
        provider.downloadResultsByID["provider-en"] = srtDownloadResult()
        let refresher = RecordingSubtitleRefresher()

        _ = try await LibrarySubtitleActionService(
            store: context.store,
            provider: provider,
            playbackSubtitleRefresher: refresher
        ).downloadSubtitle(
            mediaItemID: context.item.id,
            mediaFileID: context.file.id,
            resultID: "provider-en"
        )

        let refreshedMediaFileIDs = await refresher.mediaFileIDs()
        XCTAssertEqual(refreshedMediaFileIDs, [context.file.id])
    }

    private func makeMediaContext(
        folderIsAvailable: Bool = true,
        fileIsAvailable: Bool = true
    ) throws -> SubtitleActionMediaContext {
        let store = try CineMindStore(path: databaseURL.path)
        let library = try store.ensureLibrary(name: "CineMind Library")
        let rootURL = temporaryDirectory.appendingPathComponent("library", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        let folder = LibraryFolder(
            id: "subtitle-actions-folder",
            libraryID: library.id,
            displayName: "Movies",
            rootPath: rootURL.path,
            isAvailable: folderIsAvailable
        )
        let item = MediaItem(
            id: "subtitle-actions-item",
            mediaType: .movie,
            title: "Arrival",
            year: 2016
        )
        let file = MediaFile(
            id: "subtitle-actions-file",
            mediaItemID: item.id,
            libraryFolderID: folder.id,
            relativePath: "Arrival.m4v",
            absolutePathHash: "arrival-hash",
            fileName: "Arrival.m4v",
            fileExtension: "m4v",
            fileSizeBytes: 1_024,
            isAvailable: fileIsAvailable
        )
        try store.saveLibraryFolder(folder)
        try store.saveMediaItem(item)
        try store.saveMediaFile(file)
        return SubtitleActionMediaContext(
            store: store,
            rootURL: rootURL,
            folder: folder,
            item: item,
            file: file
        )
    }
}

private let srtContent = """
1
00:00:00,000 --> 00:00:01,000
Hello
"""

private let updatedSRTContent = """
1
00:00:00,000 --> 00:00:01,000
Updated
"""

private let webVTTContent = """
WEBVTT

00:00.000 --> 00:01.000
Hello
"""

private func srtDownloadResult(content: String = srtContent) -> SubtitleDownloadResult {
    SubtitleDownloadResult(
        resultID: "provider-en",
        suggestedFileName: "Arrival.en.srt",
        languageCode: "en",
        format: .srt,
        content: content
    )
}

private struct SubtitleActionMediaContext {
    let store: CineMindStore
    let rootURL: URL
    let folder: LibraryFolder
    let item: MediaItem
    let file: MediaFile
}

private final class FakeSubtitleProvider: SubtitleSearchProviding, @unchecked Sendable {
    private let lock = NSLock()
    var searchResults: [SubtitleSearchResult] = []
    var searchError: (any Error)?
    var downloadResultsByID: [String: SubtitleDownloadResult] = [:]
    var downloadError: (any Error)?
    private var recordedSearchQueries: [SubtitleSearchQuery] = []
    private var recordedDownloadRequests: [SubtitleDownloadRequest] = []

    var searchQueries: [SubtitleSearchQuery] {
        withLock { recordedSearchQueries }
    }

    var downloadRequests: [SubtitleDownloadRequest] {
        withLock { recordedDownloadRequests }
    }

    func searchSubtitles(query: SubtitleSearchQuery) async throws -> [SubtitleSearchResult] {
        try withLock {
            recordedSearchQueries.append(query)
            if let searchError {
                throw searchError
            }
            return searchResults
        }
    }

    func downloadSubtitle(
        resultID: String,
        for query: SubtitleSearchQuery
    ) async throws -> SubtitleDownloadResult {
        try withLock {
            recordedDownloadRequests.append(
                SubtitleDownloadRequest(resultID: resultID, query: query)
            )
            if let downloadError {
                throw downloadError
            }
            guard let result = downloadResultsByID[resultID] else {
                throw SubtitleProviderTestError.missingDownload
            }
            return result
        }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

private struct SubtitleDownloadRequest: Equatable {
    let resultID: String
    let query: SubtitleSearchQuery
}

private struct FailingSubtitleFileWriter: SubtitleDownloadFileWriting {
    func writeSubtitle(_ content: String, to url: URL) throws {
        throw SubtitleProviderTestError.fileWrite
    }
}

private actor RecordingSubtitleRefresher: PlaybackExternalSubtitleRefreshing {
    private var recordedMediaFileIDs: [MediaFileID] = []

    func reloadExternalSubtitleOptions(mediaFileID: MediaFileID) async {
        recordedMediaFileIDs.append(mediaFileID)
    }

    func mediaFileIDs() -> [MediaFileID] {
        recordedMediaFileIDs
    }
}

private enum SubtitleProviderTestError: Error {
    case failure
    case missingDownload
    case fileWrite
}
