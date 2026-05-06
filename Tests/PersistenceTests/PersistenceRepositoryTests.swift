import Domain
@testable import Persistence
import SQLite3
import XCTest

final class PersistenceRepositoryTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var databaseURL: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CineMindPersistenceTests-\(UUID().uuidString)", isDirectory: true)
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

    func testMigrationCreatesExpectedTables() throws {
        let store = try makeStore()

        XCTAssertEqual(
            Set(try store.schemaTableNames()),
            [
                "libraries",
                "library_folders",
                "media_items",
                "media_files",
                "playback_history",
                "scan_runs",
                "scan_issues",
                "schema_migrations"
            ]
        )
        XCTAssertEqual(try store.appliedMigrationVersions(), [1, 2])
    }

    func testMigrationIsIdempotentAcrossReopen() throws {
        let firstTables: [String]
        do {
            let store = try makeStore()
            firstTables = try store.schemaTableNames()
            XCTAssertEqual(try store.appliedMigrationVersions(), [1, 2])
        }

        let reopened = try makeStore()
        XCTAssertEqual(try reopened.schemaTableNames(), firstTables)
        XCTAssertEqual(try reopened.appliedMigrationVersions(), [1, 2])
    }

    func testV1DatabaseUpgradesToV2WithoutDataLoss() throws {
        let libraryID: LibraryID
        let folderID: LibraryFolderID
        let itemID: MediaItemID
        let fileID: MediaFileID
        let relativePath = "Arrival (2016).mkv"

        do {
            let store = try makeStore()
            let library = try store.createOrLoadLibrary(name: "Local")
            let folder = LibraryFolder(
                libraryID: library.id,
                displayName: "Movies",
                rootPath: "/media/movies"
            )
            let item = MediaItem(mediaType: .movie, title: "Arrival", year: 2016)
            let file = mediaFile(
                itemID: item.id,
                folderID: folder.id,
                relativePath: relativePath,
                absolutePathHash: "arrival-path-hash",
                fileSizeBytes: 1024
            )

            try store.addLibraryFolder(folder)
            try store.saveMediaItem(item)
            try store.saveMediaFile(file)

            libraryID = library.id
            folderID = folder.id
            itemID = item.id
            fileID = file.id
        }

        try removeV2SchemaObjects()
        XCTAssertEqual(try RawSQLiteFixture.migrationVersions(path: databaseURL.path), [1])
        XCTAssertFalse(try RawSQLiteFixture.tableNames(path: databaseURL.path).contains("playback_history"))

        let upgraded = try makeStore()
        XCTAssertEqual(try upgraded.appliedMigrationVersions(), [1, 2])
        XCTAssertTrue(try upgraded.schemaTableNames().contains("playback_history"))
        XCTAssertEqual(try upgraded.fetchLibrary(id: libraryID)?.name, "Local")
        XCTAssertEqual(try upgraded.fetchLibraryFolders(libraryID: libraryID).map(\.id), [folderID])
        XCTAssertEqual(try upgraded.fetchMediaItem(id: itemID)?.title, "Arrival")
        XCTAssertEqual(
            try upgraded.fetchMediaFile(
                libraryFolderID: folderID,
                relativePath: relativePath
            )?.id,
            fileID
        )
    }

    func testMigrationV2RollbackPreventsPartialPlaybackHistorySchema() throws {
        do {
            _ = try makeStore()
        }
        try removeV2SchemaObjects()
        try RawSQLiteFixture.execute(
            path: databaseURL.path,
            sql: "CREATE TABLE idx_playback_history_media_item_id (id TEXT PRIMARY KEY)"
        )

        XCTAssertThrowsError(try makeStore()) { error in
            guard let persistenceError = error as? PersistenceError,
                  case .migrationFailed = persistenceError else {
                return XCTFail("Expected migrationFailed, got \(error)")
            }
        }

        let tableNames = try RawSQLiteFixture.tableNames(path: databaseURL.path)
        XCTAssertFalse(tableNames.contains("playback_history"))
        XCTAssertTrue(tableNames.contains("idx_playback_history_media_item_id"))
        XCTAssertEqual(try RawSQLiteFixture.migrationVersions(path: databaseURL.path), [1])
    }

    func testLibraryCoreRecordsPersistAcrossStoreReopen() throws {
        let libraryID: LibraryID
        let folderID: LibraryFolderID
        let itemID: MediaItemID
        let fileID: MediaFileID
        let scanRunID: ScanRunID
        let relativePath = "Arrival (2016).mkv"

        do {
            let store = try makeStore()
            let library = try store.createOrLoadLibrary(name: "Local")
            let folder = LibraryFolder(
                libraryID: library.id,
                displayName: "Movies",
                rootPath: "/media/movies"
            )
            let item = MediaItem(mediaType: .movie, title: "Arrival", year: 2016)
            let file = mediaFile(
                itemID: item.id,
                folderID: folder.id,
                relativePath: relativePath,
                absolutePathHash: "arrival-path-hash",
                fileSizeBytes: 1024
            )
            let scanRun = try store.createScanRun(
                libraryID: library.id,
                startedAt: Date(timeIntervalSince1970: 700)
            )

            try store.addLibraryFolder(folder)
            try store.saveMediaItem(item)
            try store.saveMediaFile(file)
            try store.finishScanRun(
                id: scanRun.id,
                finishedAt: Date(timeIntervalSince1970: 800),
                status: .completed,
                filesSeen: 1,
                filesAdded: 1,
                filesUpdated: 0,
                filesMissing: 0,
                issuesCount: 0
            )

            libraryID = library.id
            folderID = folder.id
            itemID = item.id
            fileID = file.id
            scanRunID = scanRun.id
        }

        let reopened = try makeStore()
        let library = try XCTUnwrap(reopened.fetchLibrary(id: libraryID))
        let folders = try reopened.fetchLibraryFolders(libraryID: libraryID)
        let item = try XCTUnwrap(reopened.fetchMediaItem(id: itemID))
        let file = try XCTUnwrap(
            reopened.fetchMediaFile(
                libraryFolderID: folderID,
                relativePath: relativePath
            )
        )
        let scanRun = try XCTUnwrap(reopened.fetchScanRun(id: scanRunID))

        XCTAssertEqual(library.id, libraryID)
        XCTAssertEqual(library.name, "Local")
        XCTAssertEqual(folders.map(\.id), [folderID])
        XCTAssertEqual(folders[0].rootPath, "/media/movies")
        XCTAssertEqual(item.id, itemID)
        XCTAssertEqual(item.title, "Arrival")
        XCTAssertEqual(file.id, fileID)
        XCTAssertEqual(file.mediaItemID, itemID)
        XCTAssertTrue(file.isAvailable)
        XCTAssertEqual(scanRun.id, scanRunID)
        XCTAssertEqual(scanRun.status, .completed)
        XCTAssertEqual(scanRun.filesSeen, 1)
        XCTAssertEqual(scanRun.filesAdded, 1)
    }

    func testReadOnlyStoreCanReadExistingRecordsButCannotWrite() throws {
        let libraryID: LibraryID
        let itemID: MediaItemID

        do {
            let store = try makeStore()
            let library = try store.createOrLoadLibrary(name: "Local")
            let folder = LibraryFolder(
                libraryID: library.id,
                displayName: "Movies",
                rootPath: "/media/movies"
            )
            let item = MediaItem(mediaType: .movie, title: "Arrival", year: 2016)
            let file = mediaFile(
                itemID: item.id,
                folderID: folder.id,
                relativePath: "Arrival (2016).mkv",
                absolutePathHash: "arrival-path-hash",
                fileSizeBytes: 1024
            )

            try store.addLibraryFolder(folder)
            try store.saveMediaItem(item)
            try store.saveMediaFile(file)

            libraryID = library.id
            itemID = item.id
        }

        let readOnly = try CineMindStore(readOnlyPath: databaseURL.path)
        XCTAssertEqual(try readOnly.fetchLibrary(id: libraryID)?.name, "Local")
        XCTAssertEqual(try readOnly.fetchMediaItem(id: itemID)?.title, "Arrival")
        XCTAssertEqual(try readOnly.fetchMediaFiles(mediaItemID: itemID).count, 1)
        XCTAssertThrowsError(
            try readOnly.saveMediaItem(MediaItem(mediaType: .movie, title: "Moon", year: 2009))
        )
    }

    func testSingleMVPLibraryCanBeCreatedAndLoaded() throws {
        let store = try makeStore()

        let created = try store.createOrLoadLibrary(name: "Local")
        let loaded = try store.createOrLoadLibrary(name: "Ignored")

        XCTAssertEqual(loaded.id, created.id)
        XCTAssertEqual(loaded.name, "Local")
        let fetched = try XCTUnwrap(store.fetchLibrary(id: created.id))
        XCTAssertEqual(fetched.id, created.id)
        XCTAssertEqual(fetched.name, created.name)
    }

    func testLibraryFolderCRUD() throws {
        let store = try makeStore()
        let library = try store.createOrLoadLibrary()
        var folder = LibraryFolder(
            libraryID: library.id,
            displayName: "Movies",
            rootPath: "/Volumes/Movies"
        )

        try store.addLibraryFolder(folder)
        folder.displayName = "Films"
        folder.rootPath = "/Volumes/Films"
        folder.isAvailable = false
        folder.updatedAt = Date(timeIntervalSince1970: 200)
        try store.saveLibraryFolder(folder)

        var folders = try store.fetchLibraryFolders(libraryID: library.id)
        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(folders[0].displayName, "Films")
        XCTAssertEqual(folders[0].rootPath, "/Volumes/Films")
        XCTAssertFalse(folders[0].isAvailable)

        let lastSeenAt = Date(timeIntervalSince1970: 300)
        let lastScanAt = Date(timeIntervalSince1970: 400)
        try store.updateLibraryFolderAvailability(
            id: folder.id,
            isAvailable: true,
            lastSeenAt: lastSeenAt,
            lastScanAt: lastScanAt
        )

        folders = try store.fetchLibraryFolders(libraryID: library.id)
        XCTAssertTrue(folders[0].isAvailable)
        XCTAssertEqual(folders[0].lastSeenAt, lastSeenAt)
        XCTAssertEqual(folders[0].lastScanAt, lastScanAt)
    }

    func testMediaItemCRUD() throws {
        let store = try makeStore()
        var item = MediaItem(mediaType: .movie, title: "Arrival", year: 2016)

        try store.saveMediaItem(item)
        item.title = "Arrival Director Cut"
        item.normalizedTitle = MediaTitleNormalizer.normalize(item.title)
        item.year = 2017
        item.updatedAt = Date(timeIntervalSince1970: 500)
        try store.saveMediaItem(item)

        let fetched = try XCTUnwrap(store.fetchMediaItem(id: item.id))
        XCTAssertEqual(fetched.title, "Arrival Director Cut")
        XCTAssertEqual(fetched.normalizedTitle, "arrival director cut")
        XCTAssertEqual(fetched.year, 2017)
        XCTAssertEqual(try store.fetchMediaItems().map(\.id), [item.id])
    }

    func testMediaFileCRUD() throws {
        let context = try makeMediaContext()
        var file = mediaFile(
            itemID: context.item.id,
            folderID: context.folder.id,
            relativePath: "Arrival (2016).mkv",
            absolutePathHash: "same-diagnostic-hash",
            fileSizeBytes: 100
        )

        try context.store.saveMediaFile(file)
        file.fileSizeBytes = 200
        file.isAvailable = false
        file.updatedAt = Date(timeIntervalSince1970: 600)
        try context.store.saveMediaFile(file)

        let secondFile = mediaFile(
            itemID: context.item.id,
            folderID: context.folder.id,
            relativePath: "Extras/Arrival (2016).mkv",
            absolutePathHash: "same-diagnostic-hash",
            fileSizeBytes: 300
        )
        try context.store.saveMediaFile(secondFile)

        let files = try context.store.fetchMediaFiles(mediaItemID: context.item.id)
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files.first { $0.id == file.id }?.fileSizeBytes, 200)
        XCTAssertEqual(files.first { $0.id == file.id }?.absolutePathHash, "same-diagnostic-hash")
        XCTAssertEqual(files.first { $0.id == secondFile.id }?.absolutePathHash, "same-diagnostic-hash")
    }

    func testMediaFileLookupUsesLibraryFolderIDAndRelativePath() throws {
        let context = try makeMediaContext()
        let secondFolder = LibraryFolder(
            libraryID: context.library.id,
            displayName: "NAS",
            rootPath: "/Volumes/NAS"
        )
        try context.store.addLibraryFolder(secondFolder)

        let relativePath = "Arrival (2016).mkv"
        let localFile = mediaFile(
            itemID: context.item.id,
            folderID: context.folder.id,
            relativePath: relativePath,
            absolutePathHash: "local-hash",
            fileSizeBytes: 100
        )
        let nasFile = mediaFile(
            itemID: context.item.id,
            folderID: secondFolder.id,
            relativePath: relativePath,
            absolutePathHash: "nas-hash",
            fileSizeBytes: 100
        )
        try context.store.saveMediaFile(localFile)
        try context.store.saveMediaFile(nasFile)

        XCTAssertEqual(
            try context.store.fetchMediaFile(
                libraryFolderID: context.folder.id,
                relativePath: relativePath
            )?.id,
            localFile.id
        )
        XCTAssertEqual(
            try context.store.fetchMediaFile(
                libraryFolderID: secondFolder.id,
                relativePath: relativePath
            )?.id,
            nasFile.id
        )
    }

    func testMarkMediaFileUnavailablePreservesMediaItemAndFileRecord() throws {
        let context = try makeMediaContext()
        let file = mediaFile(
            itemID: context.item.id,
            folderID: context.folder.id,
            relativePath: "Moon (2009).mkv",
            absolutePathHash: "hash",
            fileSizeBytes: 1024
        )
        try context.store.saveMediaFile(file)

        try context.store.markMediaFileUnavailable(id: file.id)

        let files = try context.store.fetchMediaFiles(mediaItemID: context.item.id)
        XCTAssertEqual(files.count, 1)
        XCTAssertFalse(files[0].isAvailable)
        XCTAssertEqual(try context.store.fetchMediaItem(id: context.item.id)?.id, context.item.id)
    }

    func testPlaybackHistorySaveAndFetchWorks() throws {
        let context = try makePlaybackContext()
        let playedAt = Date(timeIntervalSince1970: 1_000)
        let history = PlaybackHistory(
            id: "history-1",
            mediaItemID: context.item.id,
            mediaFileID: context.file.id,
            positionMS: 45_000,
            durationMS: 120_000,
            completed: true,
            playCount: 3,
            lastPlayedAt: playedAt,
            createdAt: playedAt,
            updatedAt: playedAt
        )

        try context.store.savePlaybackHistory(history)

        XCTAssertEqual(
            try context.store.fetchPlaybackHistory(
                mediaItemID: context.item.id,
                mediaFileID: context.file.id
            ),
            history
        )
        XCTAssertEqual(
            try RawSQLiteFixture.singleInt(
                path: databaseURL.path,
                sql: "SELECT completed FROM playback_history WHERE id = 'history-1'"
            ),
            1
        )
    }

    func testPlaybackHistoryUpsertUpdatesSameMediaItemAndMediaFileRow() throws {
        let context = try makePlaybackContext()
        let firstPlayedAt = Date(timeIntervalSince1970: 1_000)
        let secondPlayedAt = Date(timeIntervalSince1970: 2_000)

        try context.store.savePlaybackProgress(
            mediaItemID: context.item.id,
            mediaFileID: context.file.id,
            positionMS: 10_000,
            durationMS: 120_000,
            completed: false,
            playedAt: firstPlayedAt
        )
        let first = try XCTUnwrap(
            context.store.fetchPlaybackHistory(
                mediaItemID: context.item.id,
                mediaFileID: context.file.id
            )
        )

        try context.store.savePlaybackProgress(
            mediaItemID: context.item.id,
            mediaFileID: context.file.id,
            positionMS: 20_000,
            durationMS: 130_000,
            completed: true,
            playedAt: secondPlayedAt
        )
        let second = try XCTUnwrap(
            context.store.fetchPlaybackHistory(
                mediaItemID: context.item.id,
                mediaFileID: context.file.id
            )
        )

        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(second.positionMS, 20_000)
        XCTAssertEqual(second.durationMS, 130_000)
        XCTAssertTrue(second.completed)
        XCTAssertEqual(second.playCount, 0)
        XCTAssertEqual(second.createdAt, firstPlayedAt)
        XCTAssertEqual(second.lastPlayedAt, secondPlayedAt)
        XCTAssertEqual(second.updatedAt, secondPlayedAt)
        XCTAssertEqual(
            try RawSQLiteFixture.singleInt(
                path: databaseURL.path,
                sql: "SELECT COUNT(*) FROM playback_history"
            ),
            1
        )
        XCTAssertEqual(
            try RawSQLiteFixture.singleInt(
                path: databaseURL.path,
                sql: "SELECT completed FROM playback_history WHERE id = '\(first.id)'"
            ),
            1
        )
    }

    func testFetchMostRecentPlaybackHistoryReturnsNewestForMediaItem() throws {
        let context = try makePlaybackContext()
        let olderPlayedAt = Date(timeIntervalSince1970: 1_000)
        let newerPlayedAt = Date(timeIntervalSince1970: 2_000)
        let secondFile = mediaFile(
            itemID: context.item.id,
            folderID: context.folder.id,
            relativePath: "Extras/Arrival (2016).mkv",
            absolutePathHash: "arrival-extra-hash",
            fileSizeBytes: 2048
        )
        try context.store.saveMediaFile(secondFile)

        try context.store.savePlaybackProgress(
            mediaItemID: context.item.id,
            mediaFileID: context.file.id,
            positionMS: 1_000,
            durationMS: nil,
            completed: false,
            playedAt: olderPlayedAt
        )
        try context.store.savePlaybackProgress(
            mediaItemID: context.item.id,
            mediaFileID: secondFile.id,
            positionMS: 2_000,
            durationMS: nil,
            completed: false,
            playedAt: newerPlayedAt
        )

        let newest = try XCTUnwrap(
            context.store.fetchMostRecentPlaybackHistory(mediaItemID: context.item.id)
        )
        XCTAssertEqual(newest.mediaFileID, secondFile.id)
        XCTAssertEqual(newest.lastPlayedAt, newerPlayedAt)
    }

    func testIncrementPlaybackCountIncrementsOncePerCall() throws {
        let context = try makePlaybackContext()
        let firstPlayedAt = Date(timeIntervalSince1970: 1_000)
        let secondPlayedAt = Date(timeIntervalSince1970: 2_000)

        try context.store.incrementPlaybackCount(
            mediaItemID: context.item.id,
            mediaFileID: context.file.id,
            playedAt: firstPlayedAt
        )
        var history = try XCTUnwrap(
            context.store.fetchPlaybackHistory(
                mediaItemID: context.item.id,
                mediaFileID: context.file.id
            )
        )
        XCTAssertEqual(history.playCount, 1)
        XCTAssertEqual(history.positionMS, 0)
        XCTAssertNil(history.durationMS)
        XCTAssertFalse(history.completed)
        XCTAssertEqual(history.createdAt, firstPlayedAt)
        XCTAssertEqual(history.updatedAt, firstPlayedAt)
        XCTAssertEqual(history.lastPlayedAt, firstPlayedAt)

        try context.store.incrementPlaybackCount(
            mediaItemID: context.item.id,
            mediaFileID: context.file.id,
            playedAt: secondPlayedAt
        )
        history = try XCTUnwrap(
            context.store.fetchPlaybackHistory(
                mediaItemID: context.item.id,
                mediaFileID: context.file.id
            )
        )
        XCTAssertEqual(history.playCount, 2)
        XCTAssertEqual(history.createdAt, firstPlayedAt)
        XCTAssertEqual(history.updatedAt, secondPlayedAt)
        XCTAssertEqual(history.lastPlayedAt, secondPlayedAt)
    }

    func testPlaybackHistorySurvivesMediaFileUnavailable() throws {
        let context = try makePlaybackContext()
        try context.store.savePlaybackProgress(
            mediaItemID: context.item.id,
            mediaFileID: context.file.id,
            positionMS: 10_000,
            durationMS: nil,
            completed: false,
            playedAt: Date(timeIntervalSince1970: 1_000)
        )

        try context.store.markMediaFileUnavailable(id: context.file.id)

        let files = try context.store.fetchMediaFiles(mediaItemID: context.item.id)
        let history = try context.store.fetchPlaybackHistory(
            mediaItemID: context.item.id,
            mediaFileID: context.file.id
        )
        XCTAssertEqual(files.count, 1)
        XCTAssertFalse(files[0].isAvailable)
        XCTAssertEqual(history?.mediaFileID, context.file.id)
    }

    func testPlaybackHistoryForeignKeysRejectInvalidMediaItemAndFileIDs() throws {
        let store = try makeStore()
        let history = PlaybackHistory(
            mediaItemID: "missing-item",
            mediaFileID: "missing-file",
            positionMS: 0,
            completed: false,
            playCount: 0
        )

        XCTAssertThrowsError(try store.savePlaybackHistory(history)) { error in
            guard let persistenceError = error as? PersistenceError,
                  case .stepFailed(let message) = persistenceError else {
                return XCTFail("Expected stepFailed, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("foreign key"))
        }
    }

    func testPlaybackHistoryWritesRejectMediaItemAndMediaFileMismatch() throws {
        let context = try makePlaybackContext()
        let otherItem = MediaItem(mediaType: .movie, title: "Moon", year: 2009)
        try context.store.saveMediaItem(otherItem)

        XCTAssertThrowsError(
            try context.store.savePlaybackHistory(
                PlaybackHistory(
                    mediaItemID: otherItem.id,
                    mediaFileID: context.file.id,
                    positionMS: 0,
                    completed: false,
                    playCount: 0
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? PersistenceError,
                .mediaFileMediaItemMismatch(
                    mediaItemID: otherItem.id,
                    mediaFileID: context.file.id,
                    actualMediaItemID: context.item.id
                )
            )
        }
        XCTAssertThrowsError(
            try context.store.savePlaybackProgress(
                mediaItemID: otherItem.id,
                mediaFileID: context.file.id,
                positionMS: 0,
                durationMS: nil,
                completed: false,
                playedAt: Date(timeIntervalSince1970: 1_000)
            )
        ) { error in
            XCTAssertEqual(
                error as? PersistenceError,
                .mediaFileMediaItemMismatch(
                    mediaItemID: otherItem.id,
                    mediaFileID: context.file.id,
                    actualMediaItemID: context.item.id
                )
            )
        }
        XCTAssertThrowsError(
            try context.store.incrementPlaybackCount(
                mediaItemID: otherItem.id,
                mediaFileID: context.file.id,
                playedAt: Date(timeIntervalSince1970: 1_000)
            )
        ) { error in
            XCTAssertEqual(
                error as? PersistenceError,
                .mediaFileMediaItemMismatch(
                    mediaItemID: otherItem.id,
                    mediaFileID: context.file.id,
                    actualMediaItemID: context.item.id
                )
            )
        }
    }

    func testSavePlaybackHistoryRejectsDuplicatePairWithDifferentID() throws {
        let context = try makePlaybackContext()
        let playedAt = Date(timeIntervalSince1970: 1_000)
        let first = PlaybackHistory(
            id: "history-1",
            mediaItemID: context.item.id,
            mediaFileID: context.file.id,
            positionMS: 1_000,
            completed: false,
            playCount: 0,
            lastPlayedAt: playedAt,
            createdAt: playedAt,
            updatedAt: playedAt
        )
        let second = PlaybackHistory(
            id: "history-2",
            mediaItemID: context.item.id,
            mediaFileID: context.file.id,
            positionMS: 2_000,
            completed: false,
            playCount: 0,
            lastPlayedAt: playedAt,
            createdAt: playedAt,
            updatedAt: playedAt
        )

        try context.store.savePlaybackHistory(first)

        XCTAssertThrowsError(try context.store.savePlaybackHistory(second)) { error in
            XCTAssertEqual(
                error as? PersistenceError,
                .duplicatePlaybackHistoryPair(existingID: first.id, attemptedID: second.id)
            )
        }
    }

    func testScanRunPersistence() throws {
        let store = try makeStore()
        let library = try store.createOrLoadLibrary()

        let run = try store.createScanRun(
            libraryID: library.id,
            startedAt: Date(timeIntervalSince1970: 700)
        )
        XCTAssertEqual(try store.fetchScanRun(id: run.id)?.status, .running)

        let finishedAt = Date(timeIntervalSince1970: 800)
        try store.finishScanRun(
            id: run.id,
            finishedAt: finishedAt,
            status: .completed,
            filesSeen: 5,
            filesAdded: 2,
            filesUpdated: 1,
            filesMissing: 1,
            issuesCount: 1
        )

        let finished = try XCTUnwrap(store.fetchScanRun(id: run.id))
        XCTAssertEqual(finished.status, .completed)
        XCTAssertEqual(finished.finishedAt, finishedAt)
        XCTAssertEqual(finished.filesSeen, 5)
        XCTAssertEqual(finished.filesAdded, 2)
        XCTAssertEqual(finished.filesUpdated, 1)
        XCTAssertEqual(finished.filesMissing, 1)
        XCTAssertEqual(finished.issuesCount, 1)
    }

    func testScanIssuePersistence() throws {
        let context = try makeMediaContext()
        let run = try context.store.createScanRun(libraryID: context.library.id)
        let issue = ScanIssue(
            scanRunID: run.id,
            libraryFolderID: context.folder.id,
            pathHash: "path-hash",
            issueType: .folderUnavailable,
            message: "Unavailable",
            createdAt: Date(timeIntervalSince1970: 900)
        )

        try context.store.recordScanIssue(issue)

        let issues = try context.store.fetchScanIssues(scanRunID: run.id)
        XCTAssertEqual(issues, [issue])
    }

    func testTransactionRollbackPreventsPartialRepositoryWrites() throws {
        let store = try makeStore()
        let library = Library(name: "Rollback")
        let folder = LibraryFolder(
            libraryID: library.id,
            displayName: "Movies",
            rootPath: "/media"
        )
        let item = MediaItem(mediaType: .movie, title: "Moon", year: 2009)

        XCTAssertThrowsError(
            try store.withTransaction {
                try store.saveLibrary(library)
                try store.addLibraryFolder(folder)
                try store.saveMediaItem(item)
                throw RollbackProbeError.intentional
            }
        )

        XCTAssertNil(try store.fetchLibrary(id: library.id))
        XCTAssertTrue(try store.fetchLibraryFolders(libraryID: library.id).isEmpty)
        XCTAssertTrue(try store.fetchMediaItems().isEmpty)
    }

    private func makeStore() throws -> CineMindStore {
        try CineMindStore(path: databaseURL.path)
    }

    private func makeMediaContext() throws -> MediaContext {
        let store = try makeStore()
        let library = try store.createOrLoadLibrary()
        let folder = LibraryFolder(libraryID: library.id, displayName: "Movies", rootPath: "/media")
        let item = MediaItem(mediaType: .movie, title: "Arrival", year: 2016)
        try store.addLibraryFolder(folder)
        try store.saveMediaItem(item)
        return MediaContext(store: store, library: library, folder: folder, item: item)
    }

    private func makePlaybackContext() throws -> PlaybackContext {
        let context = try makeMediaContext()
        let file = mediaFile(
            itemID: context.item.id,
            folderID: context.folder.id,
            relativePath: "Arrival (2016).mkv",
            absolutePathHash: "arrival-path-hash",
            fileSizeBytes: 1024
        )
        try context.store.saveMediaFile(file)
        return PlaybackContext(
            store: context.store,
            library: context.library,
            folder: context.folder,
            item: context.item,
            file: file
        )
    }

    private func removeV2SchemaObjects() throws {
        try RawSQLiteFixture.execute(
            path: databaseURL.path,
            sql: """
                DROP INDEX IF EXISTS idx_playback_history_last_played_at;
                DROP INDEX IF EXISTS idx_playback_history_media_file_id;
                DROP INDEX IF EXISTS idx_playback_history_media_item_id;
                DROP TABLE IF EXISTS playback_history;
                DELETE FROM schema_migrations WHERE version = 2;
                """
        )
    }

    private func mediaFile(
        itemID: MediaItemID,
        folderID: LibraryFolderID,
        relativePath: String,
        absolutePathHash: String,
        fileSizeBytes: Int64,
        isAvailable: Bool = true
    ) -> MediaFile {
        let url = URL(fileURLWithPath: relativePath)
        return MediaFile(
            mediaItemID: itemID,
            libraryFolderID: folderID,
            relativePath: relativePath,
            absolutePathHash: absolutePathHash,
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension,
            fileSizeBytes: fileSizeBytes,
            modifiedAt: Date(timeIntervalSince1970: 100),
            isAvailable: isAvailable,
            lastSeenAt: Date(timeIntervalSince1970: 100),
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }
}

private struct MediaContext {
    let store: CineMindStore
    let library: Library
    let folder: LibraryFolder
    let item: MediaItem
}

private struct PlaybackContext {
    let store: CineMindStore
    let library: Library
    let folder: LibraryFolder
    let item: MediaItem
    let file: MediaFile
}

private enum RollbackProbeError: Error {
    case intentional
}

private enum SQLiteFixtureError: Error {
    case openFailed(String)
    case execFailed(String)
    case prepareFailed(String)
}

private enum RawSQLiteFixture {
    static func execute(path: String, sql: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown open error"
            if let handle {
                sqlite3_close(handle)
            }
            throw SQLiteFixtureError.openFailed(message)
        }
        defer {
            sqlite3_close(handle)
        }

        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(handle))
            sqlite3_free(errorMessage)
            throw SQLiteFixtureError.execFailed(message)
        }
    }

    static func tableNames(path: String) throws -> [String] {
        try queryStrings(
            path: path,
            sql: """
                SELECT name
                FROM sqlite_master
                WHERE type = 'table'
                  AND name NOT LIKE 'sqlite_%'
                ORDER BY name ASC
                """
        )
    }

    static func migrationVersions(path: String) throws -> [Int] {
        try queryInts(
            path: path,
            sql: """
                SELECT version
                FROM schema_migrations
                ORDER BY version ASC
                """
        )
    }

    static func singleInt(path: String, sql: String) throws -> Int? {
        try queryInts(path: path, sql: sql).first
    }

    private static func queryStrings(path: String, sql: String) throws -> [String] {
        try query(path: path, sql: sql) { statement in
            guard let text = sqlite3_column_text(statement, 0) else {
                return nil
            }
            return String(cString: text)
        }
    }

    private static func queryInts(path: String, sql: String) throws -> [Int] {
        try query(path: path, sql: sql) { statement in
            Int(sqlite3_column_int64(statement, 0))
        }
    }

    private static func query<T>(
        path: String,
        sql: String,
        map: (OpaquePointer) throws -> T?
    ) throws -> [T] {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown open error"
            if let handle {
                sqlite3_close(handle)
            }
            throw SQLiteFixtureError.openFailed(message)
        }
        defer {
            sqlite3_close(handle)
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw SQLiteFixtureError.prepareFailed(String(cString: sqlite3_errmsg(handle)))
        }
        defer {
            sqlite3_finalize(statement)
        }

        var values: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let value = try map(statement) {
                values.append(value)
            }
        }
        return values
    }
}
