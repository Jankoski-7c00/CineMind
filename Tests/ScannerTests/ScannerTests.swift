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
        XCTAssertScanCounts(
            result.counts,
            foldersScanned: 1,
            filesDiscovered: 1,
            mediaItemsCreated: 1,
            mediaItemsUpdated: 0,
            mediaFilesCreated: 1,
            mediaFilesUpdated: 0,
            filesMarkedUnavailable: 0,
            issuesRecorded: 0
        )
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

    func testEpisodeScanParsesLowercaseSxxExx() throws {
        let context = try makeContext()
        context.fileSystem.filesByRoot[context.folder.rootPath] = [
            scanned(root: context.folder.rootPath, relative: "Shows/Severance.s01e02.Half Loop.mkv", size: 100)
        ]

        _ = try context.scanner.scanLibrary(libraryID: context.library.id)

        let item = try XCTUnwrap(context.store.fetchMediaItems().first)
        XCTAssertEqual(item.mediaType, .episode)
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
        XCTAssertScanCounts(
            second.counts,
            foldersScanned: 1,
            filesDiscovered: 1,
            mediaItemsCreated: 0,
            mediaItemsUpdated: 0,
            mediaFilesCreated: 0,
            mediaFilesUpdated: 1,
            filesMarkedUnavailable: 0,
            issuesRecorded: 0
        )
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
        XCTAssertScanCounts(
            second.counts,
            foldersScanned: 1,
            filesDiscovered: 0,
            mediaItemsCreated: 0,
            mediaItemsUpdated: 0,
            mediaFilesCreated: 0,
            mediaFilesUpdated: 0,
            filesMarkedUnavailable: 1,
            issuesRecorded: 0
        )
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
        XCTAssertScanCounts(
            second.counts,
            foldersScanned: 1,
            filesDiscovered: 1,
            mediaItemsCreated: 0,
            mediaItemsUpdated: 0,
            mediaFilesCreated: 1,
            mediaFilesUpdated: 0,
            filesMarkedUnavailable: 1,
            issuesRecorded: 1
        )
        XCTAssertTrue(second.issues.contains { $0.issueType == .renameCandidate })
    }

    func testDuplicateFilesAttachToSameMediaItemWithoutOverwriting() throws {
        let context = try makeContext()
        context.fileSystem.filesByRoot[context.folder.rootPath] = [
            scanned(root: context.folder.rootPath, relative: "Moon (2009).mkv", size: 100),
            scanned(root: context.folder.rootPath, relative: "Duplicates/Moon (2009).mkv", size: 100)
        ]

        let result = try context.scanner.scanLibrary(libraryID: context.library.id)

        XCTAssertScanCounts(
            result.counts,
            foldersScanned: 1,
            filesDiscovered: 2,
            mediaItemsCreated: 1,
            mediaItemsUpdated: 0,
            mediaFilesCreated: 2,
            mediaFilesUpdated: 0,
            filesMarkedUnavailable: 0,
            issuesRecorded: 0
        )
        XCTAssertEqual(try context.store.fetchMediaItems().count, 1)
        XCTAssertEqual(try context.store.fetchMediaFiles(libraryFolderID: context.folder.id).count, 2)
    }

    func testReusedMovieAndEpisodeItemsDoNotIncrementMediaItemsCreated() throws {
        let context = try makeContext()
        context.fileSystem.filesByRoot[context.folder.rootPath] = [
            scanned(root: context.folder.rootPath, relative: "Moon (2009).mkv", size: 100),
            scanned(root: context.folder.rootPath, relative: "Shows/Severance.S01E02.Half Loop.mkv", size: 200)
        ]
        _ = try context.scanner.scanLibrary(libraryID: context.library.id)

        context.fileSystem.filesByRoot[context.folder.rootPath] = [
            scanned(root: context.folder.rootPath, relative: "Copies/Moon (2009).mkv", size: 100),
            scanned(root: context.folder.rootPath, relative: "Copies/Severance.S01E02.Half Loop.mkv", size: 200)
        ]
        let second = try context.scanner.scanLibrary(libraryID: context.library.id)

        XCTAssertScanCounts(
            second.counts,
            foldersScanned: 1,
            filesDiscovered: 2,
            mediaItemsCreated: 0,
            mediaItemsUpdated: 0,
            mediaFilesCreated: 2,
            mediaFilesUpdated: 0,
            filesMarkedUnavailable: 2,
            issuesRecorded: 2
        )
        XCTAssertEqual(try context.store.fetchMediaItems().count, 2)
        XCTAssertEqual(try context.store.fetchMediaFiles(libraryFolderID: context.folder.id).count, 4)
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
        XCTAssertEqual(second.scanRun.status, .completed)
        XCTAssertEqual(second.scanRun.filesMissing, 0)
        XCTAssertScanCounts(
            second.counts,
            foldersScanned: 0,
            filesDiscovered: 0,
            mediaItemsCreated: 0,
            mediaItemsUpdated: 0,
            mediaFilesCreated: 0,
            mediaFilesUpdated: 0,
            filesMarkedUnavailable: 0,
            issuesRecorded: 1
        )
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
        XCTAssertEqual(second.scanRun.status, .completed)
        XCTAssertEqual(second.scanRun.filesMissing, 0)
        XCTAssertScanCounts(
            second.counts,
            foldersScanned: 0,
            filesDiscovered: 0,
            mediaItemsCreated: 0,
            mediaItemsUpdated: 0,
            mediaFilesCreated: 0,
            mediaFilesUpdated: 0,
            filesMarkedUnavailable: 0,
            issuesRecorded: 1
        )
        XCTAssertTrue(second.issues.contains { $0.issueType == .filesystemError })
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].isAvailable)
    }

    func testUnexpectedScanFailureFinishesScanRunAsFailed() throws {
        let context = try makeContext()
        context.fileSystem.unexpectedFailureRoots.insert(context.folder.rootPath)

        XCTAssertThrowsError(
            try context.scanner.scanLibrary(libraryID: context.library.id)
        ) { error in
            XCTAssertEqual(error as? UnexpectedScanError, .injected)
        }

        let runs = try context.store.fetchScanRuns(libraryID: context.library.id)
        let run = try XCTUnwrap(runs.first)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(run.status, .failed)
        XCTAssertNotEqual(run.status, .running)
        XCTAssertNotNil(run.finishedAt)
        XCTAssertEqual(run.issuesCount, 0)
        XCTAssertTrue(try context.store.fetchScanIssues(scanRunID: run.id).isEmpty)
    }

    func testPersistenceErrorDuringScanIsNotRecordedAsFilesystemIssue() throws {
        let context = try makeContext()
        context.fileSystem.persistenceFailureRoots.insert(context.folder.rootPath)

        XCTAssertThrowsError(
            try context.scanner.scanLibrary(libraryID: context.library.id)
        ) { error in
            XCTAssertEqual(error as? PersistenceError, .stepFailed("injected persistence failure"))
        }

        let runs = try context.store.fetchScanRuns(libraryID: context.library.id)
        let run = try XCTUnwrap(runs.first)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(run.status, .failed)
        XCTAssertTrue(try context.store.fetchScanIssues(scanRunID: run.id).isEmpty)
    }

    func testUnsupportedExtensionsAreIgnored() throws {
        let context = try makeContext()
        context.fileSystem.filesByRoot[context.folder.rootPath] = [
            scanned(root: context.folder.rootPath, relative: "Notes/Arrival.txt", size: 100),
            scanned(root: context.folder.rootPath, relative: "Audio/Arrival.mp3", size: 100)
        ]

        let result = try context.scanner.scanLibrary(libraryID: context.library.id)

        XCTAssertScanCounts(
            result.counts,
            foldersScanned: 1,
            filesDiscovered: 0,
            mediaItemsCreated: 0,
            mediaItemsUpdated: 0,
            mediaFilesCreated: 0,
            mediaFilesUpdated: 0,
            filesMarkedUnavailable: 0,
            issuesRecorded: 0
        )
        XCTAssertEqual(try context.store.fetchMediaItems().count, 0)
        XCTAssertEqual(try context.store.fetchMediaFiles(libraryFolderID: context.folder.id).count, 0)
    }

    func testSidecarSubtitlesAreDiscoveredWithoutCountingAsMediaFiles() throws {
        let context = try makeContext()
        context.fileSystem.filesByRoot[context.folder.rootPath] = [
            scanned(root: context.folder.rootPath, relative: "Arrival (2016).mkv", size: 100),
            scanned(root: context.folder.rootPath, relative: "Arrival (2016).en.srt", size: 10),
            scanned(root: context.folder.rootPath, relative: "Arrival (2016).zh-Hans.vtt", size: 11),
            scanned(root: context.folder.rootPath, relative: "Arrival (2016).commentary.ass", size: 12),
            scanned(root: context.folder.rootPath, relative: "Unmatched.en.srt", size: 13)
        ]

        let result = try context.scanner.scanLibrary(libraryID: context.library.id)

        let mediaFiles = try context.store.fetchMediaFiles(libraryFolderID: context.folder.id)
        let subtitleAssets = try context.store.fetchSubtitleAssets(libraryFolderID: context.folder.id)
        XCTAssertEqual(result.scanRun.filesSeen, 1)
        XCTAssertScanCounts(
            result.counts,
            foldersScanned: 1,
            filesDiscovered: 1,
            mediaItemsCreated: 1,
            mediaItemsUpdated: 0,
            mediaFilesCreated: 1,
            mediaFilesUpdated: 0,
            filesMarkedUnavailable: 0,
            subtitlesDiscovered: 4,
            subtitlesCreated: 3,
            subtitlesUpdated: 0,
            subtitlesMarkedUnavailable: 0,
            issuesRecorded: 0
        )
        XCTAssertEqual(mediaFiles.map(\.relativePath), ["Arrival (2016).mkv"])
        XCTAssertEqual(subtitleAssets.count, 3)
        XCTAssertEqual(Set(subtitleAssets.map(\.format)), [.srt, .webVTT, .ass])
        XCTAssertTrue(subtitleAssets.contains { $0.relativePath == "Arrival (2016).en.srt" && $0.languageCode == "en" })
        XCTAssertTrue(subtitleAssets.contains { $0.relativePath == "Arrival (2016).zh-Hans.vtt" && $0.languageCode == "zh-Hans" })
        XCTAssertFalse(subtitleAssets.contains { $0.relativePath == "Unmatched.en.srt" })
    }

    func testRepeatedScanUpdatesExistingSubtitleAsset() throws {
        let context = try makeContext()
        context.fileSystem.filesByRoot[context.folder.rootPath] = [
            scanned(root: context.folder.rootPath, relative: "Moon (2009).mkv", size: 100),
            scanned(root: context.folder.rootPath, relative: "Moon (2009).en.srt", size: 10)
        ]
        _ = try context.scanner.scanLibrary(libraryID: context.library.id)

        let second = try context.scanner.scanLibrary(libraryID: context.library.id)

        XCTAssertScanCounts(
            second.counts,
            foldersScanned: 1,
            filesDiscovered: 1,
            mediaItemsCreated: 0,
            mediaItemsUpdated: 0,
            mediaFilesCreated: 0,
            mediaFilesUpdated: 1,
            filesMarkedUnavailable: 0,
            subtitlesDiscovered: 1,
            subtitlesCreated: 0,
            subtitlesUpdated: 1,
            subtitlesMarkedUnavailable: 0,
            issuesRecorded: 0
        )
        XCTAssertEqual(try context.store.fetchSubtitleAssets(libraryFolderID: context.folder.id).count, 1)
    }

    func testMissingSubtitleSidecarIsMarkedUnavailable() throws {
        let context = try makeContext()
        context.fileSystem.filesByRoot[context.folder.rootPath] = [
            scanned(root: context.folder.rootPath, relative: "Moon (2009).mkv", size: 100),
            scanned(root: context.folder.rootPath, relative: "Moon (2009).en.srt", size: 10)
        ]
        _ = try context.scanner.scanLibrary(libraryID: context.library.id)

        context.fileSystem.filesByRoot[context.folder.rootPath] = [
            scanned(root: context.folder.rootPath, relative: "Moon (2009).mkv", size: 100)
        ]
        let second = try context.scanner.scanLibrary(libraryID: context.library.id)

        let subtitle = try XCTUnwrap(context.store.fetchSubtitleAssets(libraryFolderID: context.folder.id).first)
        XCTAssertScanCounts(
            second.counts,
            foldersScanned: 1,
            filesDiscovered: 1,
            mediaItemsCreated: 0,
            mediaItemsUpdated: 0,
            mediaFilesCreated: 0,
            mediaFilesUpdated: 1,
            filesMarkedUnavailable: 0,
            subtitlesDiscovered: 0,
            subtitlesCreated: 0,
            subtitlesUpdated: 0,
            subtitlesMarkedUnavailable: 1,
            issuesRecorded: 0
        )
        XCTAssertFalse(subtitle.isAvailable)
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
    var unexpectedFailureRoots = Set<String>()
    var persistenceFailureRoots = Set<String>()

    func folderExists(at path: String) -> Bool {
        existingFolders.contains(path)
    }

    func enumerateFiles(rootPath: String) throws -> [ScannedFile] {
        if persistenceFailureRoots.contains(rootPath) {
            throw PersistenceError.stepFailed("injected persistence failure")
        }
        if unexpectedFailureRoots.contains(rootPath) {
            throw UnexpectedScanError.injected
        }
        if failingRoots.contains(rootPath) {
            throw ScannerError.enumerationFailed(rootPath)
        }
        return filesByRoot[rootPath] ?? []
    }
}

private enum UnexpectedScanError: Error, Equatable {
    case injected
}

private func XCTAssertScanCounts(
    _ counts: ScanCounts,
    foldersScanned: Int,
    filesDiscovered: Int,
    mediaItemsCreated: Int,
    mediaItemsUpdated: Int,
    mediaFilesCreated: Int,
    mediaFilesUpdated: Int,
    filesMarkedUnavailable: Int,
    subtitlesDiscovered: Int = 0,
    subtitlesCreated: Int = 0,
    subtitlesUpdated: Int = 0,
    subtitlesMarkedUnavailable: Int = 0,
    issuesRecorded: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(counts.foldersScanned, foldersScanned, "foldersScanned", file: file, line: line)
    XCTAssertEqual(counts.filesDiscovered, filesDiscovered, "filesDiscovered", file: file, line: line)
    XCTAssertEqual(counts.mediaItemsCreated, mediaItemsCreated, "mediaItemsCreated", file: file, line: line)
    XCTAssertEqual(counts.mediaItemsUpdated, mediaItemsUpdated, "mediaItemsUpdated", file: file, line: line)
    XCTAssertEqual(counts.mediaFilesCreated, mediaFilesCreated, "mediaFilesCreated", file: file, line: line)
    XCTAssertEqual(counts.mediaFilesUpdated, mediaFilesUpdated, "mediaFilesUpdated", file: file, line: line)
    XCTAssertEqual(counts.filesMarkedUnavailable, filesMarkedUnavailable, "filesMarkedUnavailable", file: file, line: line)
    XCTAssertEqual(counts.subtitlesDiscovered, subtitlesDiscovered, "subtitlesDiscovered", file: file, line: line)
    XCTAssertEqual(counts.subtitlesCreated, subtitlesCreated, "subtitlesCreated", file: file, line: line)
    XCTAssertEqual(counts.subtitlesUpdated, subtitlesUpdated, "subtitlesUpdated", file: file, line: line)
    XCTAssertEqual(
        counts.subtitlesMarkedUnavailable,
        subtitlesMarkedUnavailable,
        "subtitlesMarkedUnavailable",
        file: file,
        line: line
    )
    XCTAssertEqual(counts.issuesRecorded, issuesRecorded, "issuesRecorded", file: file, line: line)
}
