import Domain
import Persistence
import XCTest

final class PersistenceRepositoryTests: XCTestCase {
    func testDatabaseInitializesAndPersistsLibraryFolder() throws {
        let store = try CineMindStore.inMemory()
        let library = try store.ensureLibrary(name: "Local")
        let folder = LibraryFolder(
            libraryID: library.id,
            displayName: "Movies",
            rootPath: "/Volumes/Movies"
        )

        try store.saveLibraryFolder(folder)

        let folders = try store.fetchLibraryFolders(libraryID: library.id)
        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(folders[0].rootPath, "/Volumes/Movies")
        XCTAssertTrue(folders[0].isAvailable)
    }

    func testMediaItemAndFileCRUD() throws {
        let store = try CineMindStore.inMemory()
        let library = try store.ensureLibrary()
        let folder = LibraryFolder(libraryID: library.id, displayName: "Movies", rootPath: "/media")
        try store.saveLibraryFolder(folder)

        let item = MediaItem(mediaType: .movie, title: "Arrival", year: 2016)
        try store.saveMediaItem(item)

        let file = MediaFile(
            mediaItemID: item.id,
            libraryFolderID: folder.id,
            relativePath: "Arrival (2016).mkv",
            absolutePathHash: "hash",
            fileName: "Arrival (2016).mkv",
            fileExtension: "mkv",
            fileSizeBytes: 2048
        )
        try store.saveMediaFile(file)

        let fetchedItem = try XCTUnwrap(store.fetchMediaItems().first)
        let fetchedFile = try XCTUnwrap(
            store.fetchMediaFile(libraryFolderID: folder.id, relativePath: file.relativePath)
        )
        XCTAssertEqual(fetchedItem.id, item.id)
        XCTAssertEqual(fetchedItem.title, "Arrival")
        XCTAssertEqual(fetchedFile.id, file.id)
        XCTAssertEqual(fetchedFile.mediaItemID, item.id)
        XCTAssertEqual(fetchedFile.relativePath, file.relativePath)
        XCTAssertEqual(fetchedFile.absolutePathHash, "hash")
    }

    func testMarkUnavailablePreservesMediaItemAndFileRecord() throws {
        let store = try CineMindStore.inMemory()
        let library = try store.ensureLibrary()
        let folder = LibraryFolder(libraryID: library.id, displayName: "Movies", rootPath: "/media")
        try store.saveLibraryFolder(folder)

        let item = MediaItem(mediaType: .movie, title: "Moon", year: 2009)
        try store.saveMediaItem(item)
        let file = MediaFile(
            mediaItemID: item.id,
            libraryFolderID: folder.id,
            relativePath: "Moon (2009).mkv",
            absolutePathHash: "hash",
            fileName: "Moon (2009).mkv",
            fileExtension: "mkv",
            fileSizeBytes: 1024
        )
        try store.saveMediaFile(file)

        try store.markMediaFileUnavailable(id: file.id)

        let files = try store.fetchMediaFiles(mediaItemID: item.id)
        XCTAssertEqual(files.count, 1)
        XCTAssertFalse(files[0].isAvailable)
        XCTAssertEqual(try store.fetchMediaItems().count, 1)
    }

    func testScanRunAndIssuePersistence() throws {
        let store = try CineMindStore.inMemory()
        let library = try store.ensureLibrary()
        var run = ScanRun(libraryID: library.id)
        try store.saveScanRun(run)

        let issue = ScanIssue(
            scanRunID: run.id,
            libraryFolderID: nil,
            pathHash: "path-hash",
            issueType: .folderUnavailable,
            message: "Unavailable"
        )
        try store.saveScanIssue(issue)

        run.status = .completed
        run.finishedAt = Date()
        run.issuesCount = 1
        try store.saveScanRun(run)

        let fetchedIssue = try XCTUnwrap(store.fetchScanIssues(scanRunID: run.id).first)
        XCTAssertEqual(try store.fetchScanRun(id: run.id)?.status, .completed)
        XCTAssertEqual(fetchedIssue.id, issue.id)
        XCTAssertEqual(fetchedIssue.scanRunID, run.id)
        XCTAssertEqual(fetchedIssue.pathHash, "path-hash")
        XCTAssertEqual(fetchedIssue.issueType, .folderUnavailable)
        XCTAssertEqual(fetchedIssue.message, "Unavailable")
    }

    func testTransactionRollbackIsObservableThroughRepositoryBehavior() throws {
        let store = try CineMindStore.inMemory()
        let library = try store.ensureLibrary()
        let folder = LibraryFolder(libraryID: library.id, displayName: "Movies", rootPath: "/media")

        XCTAssertThrowsError(
            try store.withTransaction {
                try store.saveLibraryFolder(folder)
                throw RollbackProbeError.intentional
            }
        )

        XCTAssertTrue(try store.fetchLibraryFolders(libraryID: library.id).isEmpty)
    }

    func testDataPersistsAcrossStoreReopen() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")

        do {
            let store = try CineMindStore(path: url.path)
            let library = try store.ensureLibrary(name: "Persistent")
            try store.saveLibraryFolder(
                LibraryFolder(libraryID: library.id, displayName: "Movies", rootPath: "/media")
            )
        }

        let reopened = try CineMindStore(path: url.path)
        let library = try XCTUnwrap(reopened.fetchLibrary())
        XCTAssertEqual(library.name, "Persistent")
        XCTAssertEqual(try reopened.fetchLibraryFolders(libraryID: library.id).count, 1)
    }
}

private enum RollbackProbeError: Error {
    case intentional
}
