import Domain
import Persistence
import Scanner
import XCTest

final class ScannerTests: XCTestCase {
    func testNewMovieScanCreatesMediaItemAndFile() throws {
        let context = try makeContext()
        context.fileSystem.filesByRoot[context.folder.rootPath] = [
            scanned(root: context.folder.rootPath, relative: "Arrival (2016).mkv", size: 100)
        ]

        let result = try context.scanner.scanLibrary(libraryID: context.library.id)

        let items = try context.store.fetchMediaItems()
        let files = try context.store.fetchMediaFiles(libraryFolderID: context.folder.id)
        XCTAssertEqual(result.scanRun.filesSeen, 1)
        XCTAssertEqual(result.scanRun.filesAdded, 1)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Arrival")
        XCTAssertEqual(items[0].year, 2016)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].isAvailable)
    }

    func testEpisodeScanParsesSxxExx() throws {
        let context = try makeContext()
        context.fileSystem.filesByRoot[context.folder.rootPath] = [
            scanned(root: context.folder.rootPath, relative: "Shows/Severance.S01E02.Half Loop.mkv", size: 100)
        ]

        _ = try context.scanner.scanLibrary(libraryID: context.library.id)

        let item = try XCTUnwrap(context.store.fetchMediaItems().first)
        XCTAssertEqual(item.mediaType, .episode)
        XCTAssertEqual(item.normalizedTitle, "severance")
        XCTAssertEqual(item.episodeInfo?.seriesTitle, "Severance")
        XCTAssertEqual(item.episodeInfo?.seasonNumber, 1)
        XCTAssertEqual(item.episodeInfo?.episodeNumber, 2)
        XCTAssertEqual(item.episodeInfo?.episodeTitle, "Half Loop")
    }

    func testRepeatedScanUpdatesExactPathInsteadOfCreatingDuplicate() throws {
        let context = try makeContext()
        context.fileSystem.filesByRoot[context.folder.rootPath] = [
            scanned(root: context.folder.rootPath, relative: "Moon (2009).mkv", size: 100)
        ]

        _ = try context.scanner.scanLibrary(libraryID: context.library.id)
        let second = try context.scanner.scanLibrary(libraryID: context.library.id)

        XCTAssertEqual(second.scanRun.filesAdded, 0)
        XCTAssertEqual(second.scanRun.filesUpdated, 1)
        XCTAssertEqual(try context.store.fetchMediaItems().count, 1)
        XCTAssertEqual(try context.store.fetchMediaFiles(libraryFolderID: context.folder.id).count, 1)
    }

    func testMissingFileIsMarkedUnavailableWithoutDeletingItem() throws {
        let context = try makeContext()
        context.fileSystem.filesByRoot[context.folder.rootPath] = [
            scanned(root: context.folder.rootPath, relative: "Moon (2009).mkv", size: 100)
        ]
        _ = try context.scanner.scanLibrary(libraryID: context.library.id)

        context.fileSystem.filesByRoot[context.folder.rootPath] = []
        let second = try context.scanner.scanLibrary(libraryID: context.library.id)

        let files = try context.store.fetchMediaFiles(libraryFolderID: context.folder.id)
        XCTAssertEqual(second.scanRun.filesMissing, 1)
        XCTAssertEqual(files.count, 1)
        XCTAssertFalse(files[0].isAvailable)
        XCTAssertEqual(try context.store.fetchMediaItems().count, 1)
    }

    func testNewPathCreatesNewFileAndRecordsConservativeRenameCandidate() throws {
        let context = try makeContext()
        context.fileSystem.filesByRoot[context.folder.rootPath] = [
            scanned(root: context.folder.rootPath, relative: "Moon (2009).mkv", size: 100)
        ]
        _ = try context.scanner.scanLibrary(libraryID: context.library.id)

        context.fileSystem.filesByRoot[context.folder.rootPath] = [
            scanned(root: context.folder.rootPath, relative: "Renamed/Moon (2009).mkv", size: 100)
        ]
        let second = try context.scanner.scanLibrary(libraryID: context.library.id)

        let files = try context.store.fetchMediaFiles(libraryFolderID: context.folder.id)
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files.filter(\.isAvailable).count, 1)
        XCTAssertEqual(files.filter { !$0.isAvailable }.count, 1)
        XCTAssertEqual(try context.store.fetchMediaItems().count, 1)
        XCTAssertTrue(second.issues.contains { $0.issueType == .renameCandidate })
    }

    func testDuplicateFilesAttachToSameMediaItemWithoutOverwriting() throws {
        let context = try makeContext()
        context.fileSystem.filesByRoot[context.folder.rootPath] = [
            scanned(root: context.folder.rootPath, relative: "Moon (2009).mkv", size: 100),
            scanned(root: context.folder.rootPath, relative: "Duplicates/Moon (2009).mkv", size: 100)
        ]

        _ = try context.scanner.scanLibrary(libraryID: context.library.id)

        XCTAssertEqual(try context.store.fetchMediaItems().count, 1)
        XCTAssertEqual(try context.store.fetchMediaFiles(libraryFolderID: context.folder.id).count, 2)
    }

    func testUnavailableFolderRecordsIssueWithoutMarkingFilesMissing() throws {
        let context = try makeContext()
        context.fileSystem.filesByRoot[context.folder.rootPath] = [
            scanned(root: context.folder.rootPath, relative: "Arrival (2016).mkv", size: 100)
        ]
        _ = try context.scanner.scanLibrary(libraryID: context.library.id)

        context.fileSystem.existingFolders.remove(context.folder.rootPath)
        let second = try context.scanner.scanLibrary(libraryID: context.library.id)

        let files = try context.store.fetchMediaFiles(libraryFolderID: context.folder.id)
        XCTAssertEqual(second.scanRun.filesMissing, 0)
        XCTAssertTrue(second.issues.contains { $0.issueType == .folderUnavailable })
        XCTAssertTrue(files[0].isAvailable)
    }

    func testPartialScanFailureDoesNotCorruptExistingLibraryState() throws {
        let context = try makeContext()
        context.fileSystem.filesByRoot[context.folder.rootPath] = [
            scanned(root: context.folder.rootPath, relative: "Arrival (2016).mkv", size: 100)
        ]
        _ = try context.scanner.scanLibrary(libraryID: context.library.id)

        context.fileSystem.failingRoots.insert(context.folder.rootPath)
        let second = try context.scanner.scanLibrary(libraryID: context.library.id)

        let files = try context.store.fetchMediaFiles(libraryFolderID: context.folder.id)
        XCTAssertEqual(second.scanRun.filesMissing, 0)
        XCTAssertTrue(second.issues.contains { $0.issueType == .filesystemError })
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].isAvailable)
    }
}

private func makeContext() throws -> ScannerTestContext {
    let store = try CineMindStore.inMemory()
    let library = try store.ensureLibrary()
    let folder = LibraryFolder(libraryID: library.id, displayName: "Movies", rootPath: "/media")
    try store.saveLibraryFolder(folder)

    let fileSystem = FakeFileSystem()
    fileSystem.existingFolders.insert(folder.rootPath)
    let scanner = LibraryScanner(store: store, fileSystem: fileSystem)

    return ScannerTestContext(
        store: store,
        library: library,
        folder: folder,
        fileSystem: fileSystem,
        scanner: scanner
    )
}

private func scanned(root: String, relative: String, size: Int64) -> ScannedFile {
    let relativeURL = URL(fileURLWithPath: relative)
    return ScannedFile(
        relativePath: relative,
        absolutePath: root + "/" + relative,
        fileName: relativeURL.lastPathComponent,
        fileExtension: relativeURL.pathExtension,
        fileSizeBytes: size,
        modifiedAt: Date(timeIntervalSince1970: 100)
    )
}

private struct ScannerTestContext {
    let store: CineMindStore
    let library: Library
    let folder: LibraryFolder
    let fileSystem: FakeFileSystem
    let scanner: LibraryScanner
}

private final class FakeFileSystem: ScannerFileSystem {
    var existingFolders = Set<String>()
    var filesByRoot: [String: [ScannedFile]] = [:]
    var failingRoots = Set<String>()

    func folderExists(at path: String) -> Bool {
        existingFolders.contains(path)
    }

    func enumerateFiles(rootPath: String) throws -> [ScannedFile] {
        if failingRoots.contains(rootPath) {
            throw FakeFileSystemError.enumerationFailed
        }
        return filesByRoot[rootPath] ?? []
    }
}

private enum FakeFileSystemError: Error {
    case enumerationFailed
}
