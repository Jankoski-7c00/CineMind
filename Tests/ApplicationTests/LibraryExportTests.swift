@testable import Application
import Domain
import Foundation
import Persistence
import XCTest

final class LibraryExportTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CineMindLibraryExportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testExportWritesDeterministicVersionOneJSONWithPrivacyProjection() async throws {
        let fixedDate = date(1_000)
        let store = FakeExportStore(snapshot: completeSnapshot())
        let firstURL = temporaryDirectory.appendingPathComponent("first.json")
        let secondURL = temporaryDirectory.appendingPathComponent("second.json")
        let useCase = LibraryExportUseCase(store: store, now: { fixedDate })

        let firstResult = try await useCase.exportLibrary(to: firstURL.path)
        _ = try await useCase.exportLibrary(to: secondURL.path)
        let firstData = try Data(contentsOf: firstURL)
        let secondData = try Data(contentsOf: secondURL)

        XCTAssertEqual(firstData, secondData)
        XCTAssertEqual(firstResult.destinationPath, firstURL.path)
        XCTAssertEqual(firstResult.exportedAt, fixedDate)
        XCTAssertEqual(firstResult.mediaItemCount, 2)
        XCTAssertEqual(firstResult.byteCount, firstData.count)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(LibraryExportDocumentV1.self, from: firstData)
        XCTAssertEqual(document.format, "cinemind-library-export")
        XCTAssertEqual(document.formatVersion, 1)
        XCTAssertEqual(document.exportedAt, fixedDate)
        XCTAssertEqual(document.mediaItems.map(\.id), ["item-a", "item-z"])
        XCTAssertEqual(document.mediaFiles.map(\.relativePath), ["Movies/Zulu.m4v"])
        XCTAssertEqual(document.subtitleAssets.map(\.relativePath), ["Movies/Zulu.en.srt"])
        XCTAssertEqual(document.tags.map(\.id), ["tag-z"])
        XCTAssertEqual(document.mediaItemTags.map(\.tagID), ["tag-z"])
        XCTAssertEqual(document.favorites.map(\.mediaItemID), ["item-z"])
        XCTAssertEqual(document.collections.map(\.id), ["collection-z"])
        XCTAssertEqual(document.collectionItems.map(\.collectionID), ["collection-z"])

        let json = try XCTUnwrap(String(data: firstData, encoding: .utf8))
        XCTAssertTrue(json.contains(#""exportedAt" : "1970-01-01T00:16:40Z""#))
        XCTAssertFalse(json.contains("rootPath"))
        XCTAssertFalse(json.contains("accessBookmark"))
        XCTAssertFalse(json.contains("absolutePathHash"))
        XCTAssertFalse(json.contains("rawPayloadJSON"))
        XCTAssertFalse(json.contains("localCachePath"))
        XCTAssertFalse(json.contains("preferredCacheSize"))
        XCTAssertFalse(json.contains("cachedAt"))
        XCTAssertFalse(json.contains(#""content""#))
    }

    func testInvalidDestinationIsRejectedBeforeReadingStore() async throws {
        let store = FakeExportStore(snapshot: completeSnapshot())

        do {
            _ = try await LibraryExportUseCase(store: store).exportLibrary(to: "relative.json")
            XCTFail("Expected invalid destination.")
        } catch {
            XCTAssertEqual(error as? LibraryExportError, .invalidDestination)
        }

        XCTAssertEqual(store.fetchCount, 0)
    }

    func testRelationshipValidationRejectsInconsistentSnapshotBeforeEncodingOrWriting() async throws {
        let library = Library(id: "library", name: "Library")
        let snapshot = PersistedLibraryExportSnapshot(
            library: library,
            mediaFiles: [
                PersistedExportMediaFile(
                    id: "orphan-file",
                    mediaItemID: "missing-item",
                    libraryFolderID: "missing-folder",
                    relativePath: "orphan.m4v",
                    fileName: "orphan.m4v",
                    fileExtension: "m4v",
                    fileSizeBytes: 1,
                    modifiedAt: nil,
                    isAvailable: true,
                    lastSeenAt: nil,
                    createdAt: date(1),
                    updatedAt: date(1)
                )
            ]
        )
        let encoder = RecordingExportEncoder()
        let writer = RecordingExportWriter()
        let destination = temporaryDirectory.appendingPathComponent("invalid.json")

        do {
            _ = try await LibraryExportUseCase(
                store: FakeExportStore(snapshot: snapshot),
                encoder: encoder,
                fileWriter: writer
            ).exportLibrary(to: destination.path)
            XCTFail("Expected inconsistent snapshot.")
        } catch {
            XCTAssertEqual(error as? LibraryExportError, .inconsistentSnapshot)
        }

        XCTAssertEqual(encoder.encodeCount, 0)
        XCTAssertEqual(writer.writeCount, 0)
    }

    func testStoreEncodingAndWriterFailuresMapToFocusedErrors() async throws {
        let destination = temporaryDirectory.appendingPathComponent("failure.json")

        do {
            _ = try await LibraryExportUseCase(
                store: FakeExportStore(snapshot: completeSnapshot(), error: ExportTestError.failure)
            ).exportLibrary(to: destination.path)
            XCTFail("Expected store failure.")
        } catch {
            XCTAssertEqual(error as? LibraryExportError, .snapshotUnavailable)
        }

        do {
            _ = try await LibraryExportUseCase(
                store: FakeExportStore(snapshot: completeSnapshot()),
                encoder: RecordingExportEncoder(error: ExportTestError.failure)
            ).exportLibrary(to: destination.path)
            XCTFail("Expected encoding failure.")
        } catch {
            XCTAssertEqual(error as? LibraryExportError, .encodingFailed)
        }

        do {
            _ = try await LibraryExportUseCase(
                store: FakeExportStore(snapshot: completeSnapshot()),
                fileWriter: RecordingExportWriter(error: ExportTestError.failure)
            ).exportLibrary(to: destination.path)
            XCTFail("Expected writer failure.")
        } catch {
            XCTAssertEqual(error as? LibraryExportError, .writeFailed)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testFoundationWriterAtomicallyReplacesExistingFile() throws {
        let destination = temporaryDirectory.appendingPathComponent("replace.json")
        try Data("old".utf8).write(to: destination)

        try FoundationLibraryExportFileWriter().write(Data("new complete value".utf8), to: destination)

        XCTAssertEqual(try Data(contentsOf: destination), Data("new complete value".utf8))
    }

    private func completeSnapshot() -> PersistedLibraryExportSnapshot {
        let library = Library(
            id: "library-z",
            name: "Library",
            createdAt: date(1),
            updatedAt: date(2)
        )
        let folder = PersistedExportLibraryFolder(
            id: "folder-z",
            libraryID: library.id,
            displayName: "Movies",
            isAvailable: true,
            lastSeenAt: date(3),
            lastScanAt: date(4),
            createdAt: date(5),
            updatedAt: date(6)
        )
        let itemZ = MediaItem(
            id: "item-z",
            mediaType: .movie,
            title: "Zulu",
            year: 2020,
            createdAt: date(7),
            updatedAt: date(8)
        )
        let itemA = MediaItem(
            id: "item-a",
            mediaType: .movie,
            title: "Alpha",
            year: 2010,
            createdAt: date(9),
            updatedAt: date(10)
        )
        let file = PersistedExportMediaFile(
            id: "file-z",
            mediaItemID: itemZ.id,
            libraryFolderID: folder.id,
            relativePath: "Movies/Zulu.m4v",
            fileName: "Zulu.m4v",
            fileExtension: "m4v",
            fileSizeBytes: 100,
            modifiedAt: date(11),
            isAvailable: true,
            lastSeenAt: date(12),
            createdAt: date(13),
            updatedAt: date(14)
        )
        let history = PlaybackHistory(
            id: "history-z",
            mediaItemID: itemZ.id,
            mediaFileID: file.id,
            positionMS: 1_000,
            durationMS: 2_000,
            completed: false,
            playCount: 2,
            lastPlayedAt: date(15),
            createdAt: date(16),
            updatedAt: date(17)
        )
        let metadata = MetadataItem(
            id: "metadata-z",
            mediaItemID: itemZ.id,
            title: "Metadata",
            titleOverrideLocked: true,
            createdAt: date(18),
            updatedAt: date(19)
        )
        let externalID = MetadataExternalID(
            id: "external-z",
            mediaItemID: itemZ.id,
            provider: .tmdb,
            externalIDType: .tmdbMovie,
            externalIDValue: "100",
            createdAt: date(20),
            updatedAt: date(21)
        )
        let source = PersistedExportMetadataSourceRecord(
            id: "source-z",
            mediaItemID: itemZ.id,
            provider: .tmdb,
            providerID: "100",
            providerMediaType: .movie,
            confidence: 0.9,
            matchSource: .manual,
            manualMatchLocked: true,
            matchedAt: date(22),
            refreshedAt: date(23),
            createdAt: date(24),
            updatedAt: date(25)
        )
        let poster = PersistedExportPosterAsset(
            id: "poster-z",
            mediaItemID: itemZ.id,
            assetType: .poster,
            source: .tmdb,
            remotePath: "/poster.jpg",
            width: 500,
            height: 750,
            isSelected: true,
            selectionSource: .manual,
            createdAt: date(26),
            updatedAt: date(27)
        )
        let subtitle = SubtitleAsset(
            id: "subtitle-z",
            mediaItemID: itemZ.id,
            mediaFileID: file.id,
            libraryFolderID: folder.id,
            relativePath: "Movies/Zulu.en.srt",
            fileName: "Zulu.en.srt",
            fileExtension: "srt",
            format: .srt,
            languageCode: "en",
            source: .external,
            createdAt: date(28),
            updatedAt: date(29)
        )
        let tag = Tag(
            id: "tag-z",
            name: "Favorite Director",
            createdAt: date(30),
            updatedAt: date(31)
        )
        let collection = MediaCollection(
            id: "collection-z",
            name: "Weekend",
            createdAt: date(32),
            updatedAt: date(33)
        )

        return PersistedLibraryExportSnapshot(
            library: library,
            folders: [folder],
            mediaItems: [itemZ, itemA],
            mediaFiles: [file],
            playbackHistory: [history],
            metadataItems: [metadata],
            metadataExternalIDs: [externalID],
            metadataSourceRecords: [source],
            posterAssets: [poster],
            subtitleAssets: [subtitle],
            tags: [tag],
            mediaItemTags: [
                MediaItemTag(
                    mediaItemID: itemZ.id,
                    tagID: tag.id,
                    assignedAt: date(34),
                    updatedAt: date(35)
                )
            ],
            favorites: [
                FavoriteMediaItem(
                    mediaItemID: itemZ.id,
                    createdAt: date(36),
                    updatedAt: date(37)
                )
            ],
            collections: [collection],
            collectionItems: [
                CollectionItem(
                    collectionID: collection.id,
                    mediaItemID: itemZ.id,
                    addedAt: date(38),
                    updatedAt: date(39)
                )
            ]
        )
    }

    private func date(_ value: TimeInterval) -> Date {
        Date(timeIntervalSince1970: value)
    }
}

private final class FakeExportStore: ApplicationLibraryExportStore, @unchecked Sendable {
    let snapshot: PersistedLibraryExportSnapshot
    let error: Error?
    private(set) var fetchCount = 0

    init(snapshot: PersistedLibraryExportSnapshot, error: Error? = nil) {
        self.snapshot = snapshot
        self.error = error
    }

    func fetchLibraryExportSnapshot() throws -> PersistedLibraryExportSnapshot {
        fetchCount += 1
        if let error {
            throw error
        }
        return snapshot
    }
}

private final class RecordingExportEncoder: LibraryExportEncoding, @unchecked Sendable {
    let error: Error?
    private(set) var encodeCount = 0

    init(error: Error? = nil) {
        self.error = error
    }

    func encode(_ document: LibraryExportDocumentV1) throws -> Data {
        encodeCount += 1
        if let error {
            throw error
        }
        return Data("encoded".utf8)
    }
}

private final class RecordingExportWriter: LibraryExportFileWriting, @unchecked Sendable {
    let error: Error?
    private(set) var writeCount = 0

    init(error: Error? = nil) {
        self.error = error
    }

    func write(_ data: Data, to destinationURL: URL) throws {
        writeCount += 1
        if let error {
            throw error
        }
    }
}

private enum ExportTestError: Error {
    case failure
}
