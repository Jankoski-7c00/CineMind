import Application
import Domain
import Foundation
import XCTest

final class LibraryScanWorkflowTests: XCTestCase {
    func testNoLibraryThrowsLibraryUnavailableAndDoesNotRunScan() async {
        let store = FakeLibraryScanStore(library: nil)
        let runner = FakeLibraryScanRunner()
        let useCase = RunLibraryScanUseCase(
            store: store,
            runner: runner,
            queueLabel: "CineMind.LibraryScanWorkflowTests.noLibrary"
        )

        await assertThrowsScanWorkflowError(
            {
                try await useCase.scanLibrary()
            },
            .libraryUnavailable
        )

        XCTAssertEqual(store.calls, [.fetchLibrary])
        XCTAssertEqual(runner.libraryIDs, [])
    }

    func testZeroFoldersThrowsNoLibraryFoldersAndDoesNotRunScan() async {
        let library = Library(id: "library", name: "CineMind Library")
        let store = FakeLibraryScanStore(library: library, folders: [])
        let runner = FakeLibraryScanRunner()
        let useCase = RunLibraryScanUseCase(
            store: store,
            runner: runner,
            queueLabel: "CineMind.LibraryScanWorkflowTests.zeroFolders"
        )

        await assertThrowsScanWorkflowError(
            {
                try await useCase.scanLibrary()
            },
            .noLibraryFolders
        )

        XCTAssertEqual(
            store.calls,
            [
                .fetchLibrary,
                .fetchLibraryFolders(libraryID: library.id)
            ]
        )
        XCTAssertEqual(runner.libraryIDs, [])
    }

    func testStoreReadFailureThrowsLibraryUnavailableAndDoesNotRunScan() async {
        let library = Library(id: "library", name: "CineMind Library")
        let store = FakeLibraryScanStore(
            library: library,
            folders: [LibraryFolder(libraryID: library.id, displayName: "Movies", rootPath: "/Movies")],
            fetchLibraryFoldersError: StoreFailure.fetchLibraryFolders
        )
        let runner = FakeLibraryScanRunner()
        let useCase = RunLibraryScanUseCase(
            store: store,
            runner: runner,
            queueLabel: "CineMind.LibraryScanWorkflowTests.storeFailure"
        )

        await assertThrowsScanWorkflowError(
            {
                try await useCase.scanLibrary()
            },
            .libraryUnavailable
        )

        XCTAssertEqual(runner.libraryIDs, [])
    }

    func testSuccessfulRunnerResultIsReturned() async throws {
        let library = Library(id: "library", name: "CineMind Library")
        let expectedResult = LibraryScanResultSummary(
            scanRunID: "scan-run",
            statusLabel: "completed",
            counts: LibraryScanCountSummary(
                foldersScanned: 1,
                filesDiscovered: 2,
                mediaItemsCreated: 3,
                mediaItemsUpdated: 4,
                mediaFilesCreated: 5,
                mediaFilesUpdated: 6,
                filesMarkedUnavailable: 7,
                issuesRecorded: 8
            ),
            issues: [
                LibraryScanIssueSummary(typeLabel: "filesystem", message: "Issue A"),
                LibraryScanIssueSummary(typeLabel: "rename", message: "Issue B")
            ]
        )
        let store = FakeLibraryScanStore(
            library: library,
            folders: [LibraryFolder(libraryID: library.id, displayName: "Movies", rootPath: "/Movies")]
        )
        let runner = FakeLibraryScanRunner(result: expectedResult)
        let useCase = RunLibraryScanUseCase(
            store: store,
            runner: runner,
            queueLabel: "CineMind.LibraryScanWorkflowTests.success"
        )

        let result = try await useCase.scanLibrary()

        XCTAssertEqual(result, expectedResult)
        XCTAssertEqual(runner.libraryIDs, [library.id])
        XCTAssertEqual(
            store.calls,
            [
                .fetchLibrary,
                .fetchLibraryFolders(libraryID: library.id)
            ]
        )
    }

    func testRunnerFailureMapsToSanitizedScanFailedError() async {
        let library = Library(id: "library", name: "CineMind Library")
        let store = FakeLibraryScanStore(
            library: library,
            folders: [LibraryFolder(libraryID: library.id, displayName: "Movies", rootPath: "/Movies")]
        )
        let runner = FakeLibraryScanRunner(error: StoreFailure.runner)
        let useCase = RunLibraryScanUseCase(
            store: store,
            runner: runner,
            queueLabel: "CineMind.LibraryScanWorkflowTests.runnerFailure"
        )

        await assertThrowsScanWorkflowError(
            {
                try await useCase.scanLibrary()
            },
            .scanFailed("The library scan could not be completed.")
        )

        XCTAssertEqual(runner.libraryIDs, [library.id])
    }

    func testErrorDescriptionsAreHumanReadableAndSanitized() {
        XCTAssertEqual(
            LibraryScanWorkflowError.libraryUnavailable.errorDescription,
            "The library could not be loaded."
        )
        XCTAssertEqual(
            LibraryScanWorkflowError.noLibraryFolders.errorDescription,
            "Add a library folder before scanning."
        )
        XCTAssertEqual(
            LibraryScanWorkflowError.scanFailed("The library scan could not be completed.").errorDescription,
            "The library scan could not be completed."
        )
    }

    func testApplicationSourcesDoNotImportScanner() throws {
        let applicationSourcesURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
            .appendingPathComponent("Application", isDirectory: true)

        let swiftFiles = try XCTUnwrap(
            FileManager.default.enumerator(
                at: applicationSourcesURL,
                includingPropertiesForKeys: nil
            )?.compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" }
        )

        for fileURL in swiftFiles {
            let contents = try String(contentsOf: fileURL)
            XCTAssertFalse(
                contents.contains("import Scanner"),
                "\(fileURL.path) must not import Scanner"
            )
        }
    }
}

private final class FakeLibraryScanStore: ApplicationLibraryScanStore, @unchecked Sendable {
    private let lock = NSLock()
    private let storedLibrary: Library?
    private let storedFolders: [LibraryFolder]
    private var recordedCalls: [LibraryScanStoreCall] = []
    private let fetchLibraryError: Error?
    private let fetchLibraryFoldersError: Error?

    init(
        library: Library? = Library(id: "library", name: "CineMind Library"),
        folders: [LibraryFolder] = [LibraryFolder(libraryID: "library", displayName: "Movies", rootPath: "/Movies")],
        fetchLibraryError: Error? = nil,
        fetchLibraryFoldersError: Error? = nil
    ) {
        self.storedLibrary = library
        self.storedFolders = folders
        self.fetchLibraryError = fetchLibraryError
        self.fetchLibraryFoldersError = fetchLibraryFoldersError
    }

    var calls: [LibraryScanStoreCall] {
        lock.withLock {
            recordedCalls
        }
    }

    func fetchLibrary() throws -> Library? {
        try lock.withLock {
            recordedCalls.append(.fetchLibrary)
            if let fetchLibraryError {
                throw fetchLibraryError
            }
            return storedLibrary
        }
    }

    func fetchLibraryFolders(libraryID: LibraryID) throws -> [LibraryFolder] {
        try lock.withLock {
            recordedCalls.append(.fetchLibraryFolders(libraryID: libraryID))
            if let fetchLibraryFoldersError {
                throw fetchLibraryFoldersError
            }
            return storedFolders.filter { $0.libraryID == libraryID }
        }
    }
}

private final class FakeLibraryScanRunner: LibraryScanRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let result: LibraryScanResultSummary
    private let error: Error?
    private var recordedLibraryIDs: [LibraryID] = []

    init(
        result: LibraryScanResultSummary = LibraryScanResultSummary(
            scanRunID: "scan-run",
            statusLabel: "completed",
            counts: LibraryScanCountSummary(
                foldersScanned: 1,
                filesDiscovered: 0,
                mediaItemsCreated: 0,
                mediaItemsUpdated: 0,
                mediaFilesCreated: 0,
                mediaFilesUpdated: 0,
                filesMarkedUnavailable: 0,
                issuesRecorded: 0
            ),
            issues: []
        ),
        error: Error? = nil
    ) {
        self.result = result
        self.error = error
    }

    var libraryIDs: [LibraryID] {
        lock.withLock {
            recordedLibraryIDs
        }
    }

    func runScan(libraryID: LibraryID) throws -> LibraryScanResultSummary {
        try lock.withLock {
            recordedLibraryIDs.append(libraryID)
            if let error {
                throw error
            }
            return result
        }
    }
}

private enum LibraryScanStoreCall: Equatable {
    case fetchLibrary
    case fetchLibraryFolders(libraryID: LibraryID)
}

private enum StoreFailure: Error {
    case fetchLibrary
    case fetchLibraryFolders
    case runner
}

private func assertThrowsScanWorkflowError<T>(
    _ operation: () async throws -> T,
    _ expectedError: LibraryScanWorkflowError,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await operation()
        XCTFail("Expected \(expectedError)", file: file, line: line)
    } catch let error as LibraryScanWorkflowError {
        XCTAssertEqual(error, expectedError, file: file, line: line)
    } catch {
        XCTFail("Expected \(expectedError), got \(error)", file: file, line: line)
    }
}
