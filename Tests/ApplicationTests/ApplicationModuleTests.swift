import Application
import Domain
import Foundation
import Persistence
import XCTest

final class ApplicationModuleTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var databaseURL: URL!
    private var mediaRootURL: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CineMindApplicationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        databaseURL = temporaryDirectory.appendingPathComponent("test.sqlite")
        mediaRootURL = temporaryDirectory.appendingPathComponent("Movies", isDirectory: true)
        try FileManager.default.createDirectory(
            at: mediaRootURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        databaseURL = nil
        mediaRootURL = nil
    }

    func testApplicationTargetImportsAndBuilds() {
        XCTAssertEqual(ApplicationModule.name, "Application")
    }

    func testOpenMediaUseCaseResolvesPlayableFileForAvailableFile() throws {
        let context = try makePlaybackContext(relativePath: "Arrival (2016).mkv")
        let playableFile = try OpenMediaUseCase(store: context.store).open(mediaFileID: context.file.id)

        XCTAssertEqual(playableFile.mediaItemID, context.item.id)
        XCTAssertEqual(playableFile.mediaFileID, context.file.id)
        XCTAssertEqual(playableFile.url, mediaRootURL.appendingPathComponent("Arrival (2016).mkv"))
        XCTAssertEqual(playableFile.displayName, "Arrival")
        XCTAssertNil(playableFile.resumePositionMS)
    }

    func testOpenMediaUseCaseRejectsUnavailableMediaFile() throws {
        let context = try makePlaybackContext(
            relativePath: "Arrival (2016).mkv",
            mediaFileIsAvailable: false
        )

        assertThrowsApplicationError(
            try OpenMediaUseCase(store: context.store).open(mediaFileID: context.file.id),
            .mediaFileUnavailable
        )
    }

    func testOpenMediaUseCaseRejectsUnavailableLibraryFolder() throws {
        let context = try makePlaybackContext(
            relativePath: "Arrival (2016).mkv",
            libraryFolderIsAvailable: false
        )

        assertThrowsApplicationError(
            try OpenMediaUseCase(store: context.store).open(mediaFileID: context.file.id),
            .libraryFolderUnavailable
        )
    }

    func testOpenMediaUseCaseRejectsMissingResolvedFile() throws {
        let context = try makePlaybackContext(
            relativePath: "Missing (2016).mkv",
            createResolvedFile: false
        )

        assertThrowsApplicationError(
            try OpenMediaUseCase(store: context.store).open(mediaFileID: context.file.id),
            .resolvedFileMissing
        )
    }

    func testOpenMediaUseCaseRejectsEscapingRelativePath() throws {
        let outsideURL = temporaryDirectory.appendingPathComponent("Outside.mkv")
        try Data().write(to: outsideURL)
        let context = try makePlaybackContext(
            relativePath: "../Outside.mkv",
            createResolvedFile: false
        )

        assertThrowsApplicationError(
            try OpenMediaUseCase(store: context.store).open(mediaFileID: context.file.id),
            .invalidResolvedURL
        )
    }

    func testNoHistoryResumeStartsAtBeginning() throws {
        let context = try makePlaybackContext(relativePath: "Arrival (2016).mkv")

        let playableFile = try OpenMediaUseCase(store: context.store).open(mediaFileID: context.file.id)

        XCTAssertNil(playableFile.resumePositionMS)
    }

    func testCompletedHistoryResumeStartsAtBeginning() throws {
        let context = try makePlaybackContext(relativePath: "Arrival (2016).mkv")
        try context.store.savePlaybackHistory(
            playbackHistory(
                context: context,
                positionMS: 120_000,
                durationMS: 600_000,
                completed: true
            )
        )

        let playableFile = try OpenMediaUseCase(store: context.store).open(mediaFileID: context.file.id)

        XCTAssertNil(playableFile.resumePositionMS)
    }

    func testNearBeginningHistoryStartsAtBeginning() throws {
        let context = try makePlaybackContext(relativePath: "Arrival (2016).mkv")
        try context.store.savePlaybackHistory(
            playbackHistory(
                context: context,
                positionMS: 9_999,
                durationMS: 600_000
            )
        )

        let playableFile = try OpenMediaUseCase(store: context.store).open(mediaFileID: context.file.id)

        XCTAssertNil(playableFile.resumePositionMS)
    }

    func testNearEndHistoryStartsAtBeginning() throws {
        let context = try makePlaybackContext(relativePath: "Arrival (2016).mkv")
        try context.store.savePlaybackHistory(
            playbackHistory(
                context: context,
                positionMS: 240_000,
                durationMS: 300_000
            )
        )

        let playableFile = try OpenMediaUseCase(store: context.store).open(mediaFileID: context.file.id)

        XCTAssertNil(playableFile.resumePositionMS)
    }

    func testValidInProgressHistoryResumes() throws {
        let context = try makePlaybackContext(relativePath: "Arrival (2016).mkv")
        try context.store.savePlaybackHistory(
            playbackHistory(
                context: context,
                positionMS: 60_000,
                durationMS: 600_000
            )
        )

        let playableFile = try OpenMediaUseCase(store: context.store).open(mediaFileID: context.file.id)

        XCTAssertEqual(playableFile.resumePositionMS, 60_000)
    }

    func testUnknownDurationHistoryResumesWhenPastMinimum() throws {
        let context = try makePlaybackContext(relativePath: "Arrival (2016).mkv")
        try context.store.savePlaybackHistory(
            playbackHistory(
                context: context,
                positionMS: 600_000,
                durationMS: nil
            )
        )

        let playableFile = try OpenMediaUseCase(store: context.store).open(mediaFileID: context.file.id)

        XCTAssertEqual(playableFile.resumePositionMS, 600_000)
    }

    func testCompletionPolicyNearEndThreshold() {
        XCTAssertTrue(
            PlaybackCompletionPolicy.isCompleted(
                reliableEndEventReceived: false,
                positionMS: 180_000,
                durationMS: 300_000
            )
        )
        XCTAssertFalse(
            PlaybackCompletionPolicy.isCompleted(
                reliableEndEventReceived: false,
                positionMS: 179_999,
                durationMS: 300_000
            )
        )
        XCTAssertTrue(
            PlaybackCompletionPolicy.isCompleted(
                reliableEndEventReceived: false,
                positionMS: 570_000,
                durationMS: 600_000
            )
        )
        XCTAssertTrue(
            PlaybackCompletionPolicy.isCompleted(
                reliableEndEventReceived: true,
                positionMS: 1,
                durationMS: nil
            )
        )
    }

    func testProgressSaveDelegatesToPersistence() throws {
        let context = try makePlaybackContext(relativePath: "Arrival (2016).mkv")
        let playedAt = Date(timeIntervalSince1970: 1_000)

        try PlaybackProgressUseCase(store: context.store).saveProgress(
            mediaItemID: context.item.id,
            mediaFileID: context.file.id,
            positionMS: 45_000,
            durationMS: 600_000,
            completed: false,
            playedAt: playedAt
        )

        let history = try XCTUnwrap(
            context.store.fetchPlaybackHistory(
                mediaItemID: context.item.id,
                mediaFileID: context.file.id
            )
        )
        XCTAssertEqual(history.positionMS, 45_000)
        XCTAssertEqual(history.durationMS, 600_000)
        XCTAssertFalse(history.completed)
        XCTAssertEqual(history.lastPlayedAt, playedAt)
    }

    func testPlayCountIncrementsOncePerCall() throws {
        let context = try makePlaybackContext(relativePath: "Arrival (2016).mkv")
        let useCase = PlaybackProgressUseCase(store: context.store)
        let firstPlayedAt = Date(timeIntervalSince1970: 1_000)
        let secondPlayedAt = Date(timeIntervalSince1970: 2_000)

        try useCase.incrementPlayCount(
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
        XCTAssertEqual(history.lastPlayedAt, firstPlayedAt)

        try useCase.incrementPlayCount(
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
        XCTAssertEqual(history.lastPlayedAt, secondPlayedAt)
    }

    private func makePlaybackContext(
        relativePath: String,
        mediaFileIsAvailable: Bool = true,
        libraryFolderIsAvailable: Bool = true,
        createResolvedFile: Bool = true
    ) throws -> PlaybackContext {
        let store = try CineMindStore(path: databaseURL.path)
        let library = try store.createOrLoadLibrary(name: "Local")
        let folder = LibraryFolder(
            libraryID: library.id,
            displayName: "Movies",
            rootPath: mediaRootURL.path,
            isAvailable: libraryFolderIsAvailable
        )
        let item = MediaItem(mediaType: .movie, title: "Arrival", year: 2016)
        let file = mediaFile(
            itemID: item.id,
            folderID: folder.id,
            relativePath: relativePath,
            isAvailable: mediaFileIsAvailable
        )

        if createResolvedFile {
            let fileURL = mediaRootURL.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: fileURL)
        }

        try store.addLibraryFolder(folder)
        try store.saveMediaItem(item)
        try store.saveMediaFile(file)

        return PlaybackContext(
            store: store,
            library: library,
            folder: folder,
            item: item,
            file: file
        )
    }

    private func mediaFile(
        itemID: MediaItemID,
        folderID: LibraryFolderID,
        relativePath: String,
        isAvailable: Bool = true
    ) -> MediaFile {
        let url = URL(fileURLWithPath: relativePath)
        return MediaFile(
            mediaItemID: itemID,
            libraryFolderID: folderID,
            relativePath: relativePath,
            absolutePathHash: "application-test-path-hash-\(UUID().uuidString)",
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension,
            fileSizeBytes: 1,
            modifiedAt: Date(timeIntervalSince1970: 100),
            isAvailable: isAvailable,
            lastSeenAt: Date(timeIntervalSince1970: 100),
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func playbackHistory(
        context: PlaybackContext,
        positionMS: Int,
        durationMS: Int?,
        completed: Bool = false
    ) -> PlaybackHistory {
        PlaybackHistory(
            mediaItemID: context.item.id,
            mediaFileID: context.file.id,
            positionMS: positionMS,
            durationMS: durationMS,
            completed: completed,
            playCount: 0,
            lastPlayedAt: Date(timeIntervalSince1970: 200),
            createdAt: Date(timeIntervalSince1970: 200),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
    }

    private func assertThrowsApplicationError<T>(
        _ expression: @autoclosure () throws -> T,
        _ expected: ApplicationPlaybackError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? ApplicationPlaybackError, expected, file: file, line: line)
        }
    }
}

private struct PlaybackContext {
    let store: CineMindStore
    let library: Library
    let folder: LibraryFolder
    let item: MediaItem
    let file: MediaFile
}
