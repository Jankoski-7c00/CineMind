import Domain
@testable import Persistence
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
                "scan_runs",
                "scan_issues",
                "schema_migrations"
            ]
        )
        XCTAssertEqual(try store.appliedMigrationVersions(), [1])
    }

    func testMigrationIsIdempotentAcrossReopen() throws {
        let firstTables: [String]
        do {
            let store = try makeStore()
            firstTables = try store.schemaTableNames()
            XCTAssertEqual(try store.appliedMigrationVersions(), [1])
        }

        let reopened = try makeStore()
        XCTAssertEqual(try reopened.schemaTableNames(), firstTables)
        XCTAssertEqual(try reopened.appliedMigrationVersions(), [1])
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

    private func mediaFile(
        itemID: MediaItemID,
        folderID: LibraryFolderID,
        relativePath: String,
        absolutePathHash: String,
        fileSizeBytes: Int64
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

private enum RollbackProbeError: Error {
    case intentional
}
