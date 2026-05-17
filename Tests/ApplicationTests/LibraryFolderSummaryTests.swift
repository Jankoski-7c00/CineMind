import Application
import Domain
import Foundation
@testable import Persistence
import XCTest

final class LibraryFolderSummaryTests: XCTestCase {
    func testBrowseFoldersFetchesCurrentLibraryAndMapsSummaries() async throws {
        let library = Library(id: "folder-use-library", name: "Local")
        let store = RecordingLibraryFolderSummaryStore(
            library: library,
            summaries: [
                PersistedLibraryFolderSummary(
                    id: "folder-a",
                    displayName: "Movies",
                    rootPath: "/media/movies",
                    isAvailable: true,
                    lastSeenAt: Date(timeIntervalSince1970: 1_000),
                    lastScanAt: Date(timeIntervalSince1970: 2_000),
                    mediaFileCount: 2,
                    unavailableMediaFileCount: 1
                ),
                PersistedLibraryFolderSummary(
                    id: "folder-b",
                    displayName: "Offline",
                    rootPath: "/media/offline",
                    isAvailable: false,
                    lastSeenAt: nil,
                    lastScanAt: nil,
                    mediaFileCount: 1,
                    unavailableMediaFileCount: 1
                )
            ]
        )
        let useCase = LibraryFolderSummaryUseCase(store: store)

        let snapshot = try await useCase.browseFolders(
            page: LibraryBrowserPage(limit: 10, offset: -5)
        )

        XCTAssertEqual(snapshot.page, LibraryBrowserPage(limit: 10, offset: 0))
        XCTAssertEqual(
            store.calls,
            [FolderStoreCall(libraryID: library.id, limit: 10, offset: 0)]
        )
        XCTAssertEqual(store.fetchLibraryCallCount, 1)
        XCTAssertEqual(
            snapshot.folders,
            [
                LibraryFolderSummary(
                    id: "folder-a",
                    displayName: "Movies",
                    rootPath: "/media/movies",
                    availabilityLabel: "available",
                    fileCountLabel: "2 files, 1 unavailable",
                    lastSeenLabel: "1970-01-01T00:16:40Z",
                    lastScanLabel: "1970-01-01T00:33:20Z"
                ),
                LibraryFolderSummary(
                    id: "folder-b",
                    displayName: "Offline",
                    rootPath: "/media/offline",
                    availabilityLabel: "unavailable",
                    fileCountLabel: "1 file, 1 unavailable",
                    lastSeenLabel: nil,
                    lastScanLabel: nil
                )
            ]
        )
    }

    func testBrowseFoldersReturnsEmptySnapshotWhenLibraryIsMissing() async throws {
        let store = RecordingLibraryFolderSummaryStore(library: nil)
        let useCase = LibraryFolderSummaryUseCase(store: store)

        let snapshot = try await useCase.browseFolders(page: LibraryBrowserPage(limit: 10))

        XCTAssertEqual(snapshot, LibraryFolderSummarySnapshot(page: LibraryBrowserPage(limit: 10), folders: []))
        XCTAssertEqual(store.fetchLibraryCallCount, 1)
        XCTAssertEqual(store.calls, [])
    }

    func testLimitLessThanOrEqualToZeroReturnsEmptySnapshotWithoutStoreCall() async throws {
        let store = RecordingLibraryFolderSummaryStore(
            library: Library(id: "folder-use-library", name: "Local")
        )
        let useCase = LibraryFolderSummaryUseCase(store: store)

        let zeroSnapshot = try await useCase.browseFolders(
            page: LibraryBrowserPage(limit: 0, offset: 4)
        )
        let negativeSnapshot = try await useCase.browseFolders(
            page: LibraryBrowserPage(limit: -1, offset: -10)
        )

        XCTAssertEqual(
            zeroSnapshot,
            LibraryFolderSummarySnapshot(page: LibraryBrowserPage(limit: 0, offset: 4), folders: [])
        )
        XCTAssertEqual(
            negativeSnapshot,
            LibraryFolderSummarySnapshot(page: LibraryBrowserPage(limit: -1, offset: 0), folders: [])
        )
        XCTAssertEqual(store.fetchLibraryCallCount, 0)
        XCTAssertEqual(store.calls, [])
    }

    func testFileCountLabelOmitsUnavailableCountWhenEverythingIsAvailable() async throws {
        let library = Library(id: "folder-use-library", name: "Local")
        let store = RecordingLibraryFolderSummaryStore(
            library: library,
            summaries: [
                PersistedLibraryFolderSummary(
                    id: "folder-empty",
                    displayName: "Empty",
                    rootPath: "/media/empty",
                    isAvailable: true,
                    lastSeenAt: nil,
                    lastScanAt: nil,
                    mediaFileCount: 0,
                    unavailableMediaFileCount: 0
                ),
                PersistedLibraryFolderSummary(
                    id: "folder-one",
                    displayName: "One",
                    rootPath: "/media/one",
                    isAvailable: true,
                    lastSeenAt: nil,
                    lastScanAt: nil,
                    mediaFileCount: 1,
                    unavailableMediaFileCount: 0
                )
            ]
        )
        let useCase = LibraryFolderSummaryUseCase(store: store)

        let folders = try await useCase.browseFolders(page: LibraryBrowserPage(limit: 10)).folders

        XCTAssertEqual(folders.map(\.fileCountLabel), ["0 files", "1 file"])
    }
}

private final class RecordingLibraryFolderSummaryStore: ApplicationLibraryFolderSummaryStore,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let storedLibrary: Library?
    private let storedSummaries: [PersistedLibraryFolderSummary]
    private var recordedFetchLibraryCallCount = 0
    private var recordedCalls: [FolderStoreCall] = []

    init(
        library: Library?,
        summaries: [PersistedLibraryFolderSummary] = []
    ) {
        self.storedLibrary = library
        self.storedSummaries = summaries
    }

    var fetchLibraryCallCount: Int {
        lock.withLock {
            recordedFetchLibraryCallCount
        }
    }

    var calls: [FolderStoreCall] {
        lock.withLock {
            recordedCalls
        }
    }

    func fetchLibrary() throws -> Library? {
        lock.withLock {
            recordedFetchLibraryCallCount += 1
            return storedLibrary
        }
    }

    func fetchLibraryFolderSummaries(
        libraryID: LibraryID,
        limit: Int,
        offset: Int
    ) throws -> [PersistedLibraryFolderSummary] {
        lock.withLock {
            recordedCalls.append(FolderStoreCall(libraryID: libraryID, limit: limit, offset: offset))
            return storedSummaries
        }
    }
}

private struct FolderStoreCall: Equatable {
    let libraryID: LibraryID
    let limit: Int
    let offset: Int
}
