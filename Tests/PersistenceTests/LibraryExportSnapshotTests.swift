import Domain
@testable import Persistence
import XCTest

final class LibraryExportSnapshotTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var databaseURL: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CineMindLibraryExportSnapshotTests-\(UUID().uuidString)", isDirectory: true)
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
        databaseURL = nil
        temporaryDirectory = nil
    }

    func testMinimalLibraryExportsFromReadWriteAndReadOnlyStoresWithoutSchemaChange() throws {
        let store = try CineMindStore(path: databaseURL.path)
        let library = Library(
            id: "library-export",
            name: "Export Library",
            createdAt: date(1),
            updatedAt: date(2)
        )
        try store.saveLibrary(library)

        let snapshot = try store.fetchLibraryExportSnapshot()
        XCTAssertEqual(snapshot, PersistedLibraryExportSnapshot(library: library))
        XCTAssertEqual(try store.appliedMigrationVersions(), [1, 2, 3, 4, 5, 6])

        let readOnly = try CineMindStore(readOnlyPath: databaseURL.path)
        XCTAssertEqual(try readOnly.fetchLibraryExportSnapshot(), snapshot)
    }

    func testCompleteSnapshotExportsEveryVersionOneCategoryInStableIDOrder() throws {
        let store = try CineMindStore(path: databaseURL.path)
        let library = Library(
            id: "library-export",
            name: "Export Library",
            createdAt: date(1),
            updatedAt: date(2)
        )
        let folder = LibraryFolder(
            id: "folder-z",
            libraryID: library.id,
            displayName: "Movies",
            rootPath: "/private/secret/movies",
            accessBookmark: Data("secret-bookmark".utf8),
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
        let file = MediaFile(
            id: "file-z",
            mediaItemID: itemZ.id,
            libraryFolderID: folder.id,
            relativePath: "Zulu.m4v",
            absolutePathHash: "secret-absolute-path-hash",
            fileName: "Zulu.m4v",
            fileExtension: "m4v",
            fileSizeBytes: 100,
            modifiedAt: date(11),
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
            title: "Zulu Metadata",
            summary: "Summary",
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
        let source = MetadataSourceRecord(
            id: "source-z",
            mediaItemID: itemZ.id,
            provider: .tmdb,
            providerID: "100",
            providerMediaType: .movie,
            confidence: 0.9,
            matchSource: .manual,
            manualMatchLocked: true,
            rawPayloadJSON: #"{"secret":true}"#,
            matchedAt: date(22),
            refreshedAt: date(23),
            createdAt: date(24),
            updatedAt: date(25)
        )
        let poster = PosterAsset(
            id: "poster-z",
            mediaItemID: itemZ.id,
            assetType: .poster,
            source: .tmdb,
            remotePath: "/poster.jpg",
            width: 500,
            height: 750,
            preferredCacheSize: "w500",
            localCachePath: "/private/secret/poster.jpg",
            cachedAt: date(26),
            isSelected: true,
            selectionSource: .manual,
            createdAt: date(27),
            updatedAt: date(28)
        )
        let subtitle = SubtitleAsset(
            id: "subtitle-z",
            mediaItemID: itemZ.id,
            mediaFileID: file.id,
            libraryFolderID: folder.id,
            relativePath: "Zulu.en.srt",
            fileName: "Zulu.en.srt",
            fileExtension: "srt",
            format: .srt,
            languageCode: "en",
            displayName: "English",
            source: .external,
            lastSeenAt: date(29),
            createdAt: date(30),
            updatedAt: date(31)
        )
        let tag = Tag(
            id: "tag-z",
            name: "Favorite Director",
            source: .manual,
            createdAt: date(32),
            updatedAt: date(33)
        )
        let collection = MediaCollection(
            id: "collection-z",
            name: "Weekend",
            description: "Weekend movies",
            createdAt: date(34),
            updatedAt: date(35)
        )

        try store.saveLibrary(library)
        try store.saveLibraryFolder(folder)
        try store.saveMediaItem(itemZ)
        try store.saveMediaItem(itemA)
        try store.saveMediaFile(file)
        try store.savePlaybackHistory(history)
        try store.saveMetadataItem(metadata)
        try store.upsertMetadataExternalIDs([externalID])
        try store.saveMetadataSourceRecord(source)
        try store.savePosterAsset(poster)
        try store.saveSubtitleAsset(subtitle)
        try store.saveTag(tag)
        try store.assignTag(tagID: tag.id, to: itemZ.id, assignedAt: date(36))
        try store.setFavorite(mediaItemID: itemZ.id, isFavorite: true, updatedAt: date(37))
        try store.saveCollection(collection)
        try store.addMediaItem(itemZ.id, toCollection: collection.id, addedAt: date(38))

        let snapshot = try store.fetchLibraryExportSnapshot()

        XCTAssertEqual(snapshot.library, library)
        XCTAssertEqual(snapshot.folders.map(\.id), [folder.id])
        XCTAssertEqual(snapshot.mediaItems.map(\.id), [itemA.id, itemZ.id])
        XCTAssertEqual(snapshot.mediaFiles.map(\.id), [file.id])
        XCTAssertEqual(snapshot.playbackHistory.map(\.id), [history.id])
        XCTAssertEqual(snapshot.metadataItems.map(\.id), [metadata.id])
        XCTAssertEqual(snapshot.metadataExternalIDs.map(\.id), [externalID.id])
        XCTAssertEqual(snapshot.metadataSourceRecords.map(\.id), [source.id])
        XCTAssertEqual(snapshot.posterAssets.map(\.id), [poster.id])
        XCTAssertEqual(snapshot.subtitleAssets.map(\.id), [subtitle.id])
        XCTAssertEqual(snapshot.tags.map(\.id), [tag.id])
        XCTAssertEqual(snapshot.mediaItemTags.map(\.tagID), [tag.id])
        XCTAssertEqual(snapshot.favorites.map(\.mediaItemID), [itemZ.id])
        XCTAssertEqual(snapshot.collections.map(\.id), [collection.id])
        XCTAssertEqual(snapshot.collectionItems.map(\.collectionID), [collection.id])

        XCTAssertFalse(childLabels(of: snapshot.folders[0]).contains("rootPath"))
        XCTAssertFalse(childLabels(of: snapshot.folders[0]).contains("accessBookmark"))
        XCTAssertFalse(childLabels(of: snapshot.mediaFiles[0]).contains("absolutePathHash"))
        XCTAssertFalse(childLabels(of: snapshot.metadataSourceRecords[0]).contains("rawPayloadJSON"))
        XCTAssertFalse(childLabels(of: snapshot.posterAssets[0]).contains("localCachePath"))
    }

    func testMissingLibraryProducesFocusedExportError() throws {
        let store = try CineMindStore(path: databaseURL.path)

        XCTAssertThrowsError(try store.fetchLibraryExportSnapshot()) { error in
            XCTAssertEqual(error as? PersistenceError, .libraryExportUnavailable)
        }
    }

    func testReadTransactionPreventsConcurrentStoreWritesFromInterleaving() throws {
        let store = try CineMindStore(path: databaseURL.path)
        let original = Library(id: "library", name: "Original", createdAt: date(1), updatedAt: date(1))
        let updated = Library(id: original.id, name: "Updated", createdAt: date(1), updatedAt: date(2))
        try store.saveLibrary(original)

        let transactionEntered = DispatchSemaphore(value: 0)
        let allowTransactionToFinish = DispatchSemaphore(value: 0)
        let transactionFinished = DispatchSemaphore(value: 0)
        let writerFinished = DispatchSemaphore(value: 0)
        let observations = LockedLibraryNames()

        DispatchQueue.global().async {
            defer {
                transactionFinished.signal()
            }
            do {
                try store.withReadTransaction {
                    observations.first = try store.fetchLibrary()?.name
                    transactionEntered.signal()
                    allowTransactionToFinish.wait()
                    observations.second = try store.fetchLibrary()?.name
                }
            } catch {
                observations.error = error
            }
        }

        XCTAssertEqual(transactionEntered.wait(timeout: .now() + 1), .success)
        DispatchQueue.global().async {
            defer {
                writerFinished.signal()
            }
            do {
                try store.saveLibrary(updated)
            } catch {
                observations.error = error
            }
        }

        XCTAssertEqual(writerFinished.wait(timeout: .now() + 0.1), .timedOut)
        allowTransactionToFinish.signal()
        XCTAssertEqual(transactionFinished.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(writerFinished.wait(timeout: .now() + 1), .success)
        XCTAssertNil(observations.error)
        XCTAssertEqual(observations.first, original.name)
        XCTAssertEqual(observations.second, original.name)
        XCTAssertEqual(try store.fetchLibrary()?.name, updated.name)
    }

    private func date(_ value: TimeInterval) -> Date {
        Date(timeIntervalSince1970: value)
    }

    private func childLabels<T>(of value: T) -> Set<String> {
        Set(Mirror(reflecting: value).children.compactMap(\.label))
    }
}

private final class LockedLibraryNames: @unchecked Sendable {
    private let lock = NSLock()
    private var storedFirst: String?
    private var storedSecond: String?
    private var storedError: Error?

    var first: String? {
        get {
            lock.withLock { storedFirst }
        }
        set {
            lock.withLock { storedFirst = newValue }
        }
    }

    var second: String? {
        get {
            lock.withLock { storedSecond }
        }
        set {
            lock.withLock { storedSecond = newValue }
        }
    }

    var error: Error? {
        get {
            lock.withLock { storedError }
        }
        set {
            lock.withLock { storedError = newValue }
        }
    }
}
