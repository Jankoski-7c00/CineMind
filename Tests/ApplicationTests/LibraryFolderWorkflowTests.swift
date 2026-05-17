import Application
import Domain
import Foundation
import XCTest

final class LibraryFolderWorkflowTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CineMindLibraryFolderWorkflowTests-\(UUID().uuidString)", isDirectory: true)
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

    func testAddFolderCreatesCurrentLibraryWhenMissing() async throws {
        let folderURL = try makeDirectory("Movies")
        let ensuredLibrary = Library(id: "created-library", name: "CineMind Library")
        let store = FakeLibraryFolderMutationStore(
            library: nil,
            ensuredLibrary: ensuredLibrary
        )
        let useCase = AddLibraryFolderUseCase(store: store)

        let added = try await useCase.addFolder(
            AddLibraryFolderRequest(
                rootPath: folderURL.path,
                displayName: "Movies",
                accessBookmark: nil
            )
        )

        let savedFolder = try XCTUnwrap(store.savedFolders.first)
        XCTAssertEqual(savedFolder.libraryID, ensuredLibrary.id)
        XCTAssertEqual(added.id, savedFolder.id)
        XCTAssertEqual(
            store.calls,
            [
                .fetchLibrary,
                .ensureLibrary(name: "CineMind Library"),
                .fetchLibraryFolders(libraryID: ensuredLibrary.id),
                .addLibraryFolder
            ]
        )
    }

    func testAddFolderUsesExistingCurrentLibrary() async throws {
        let folderURL = try makeDirectory("Movies")
        let library = Library(id: "existing-library", name: "Existing")
        let store = FakeLibraryFolderMutationStore(library: library)
        let useCase = AddLibraryFolderUseCase(store: store)

        _ = try await useCase.addFolder(
            AddLibraryFolderRequest(
                rootPath: folderURL.path,
                displayName: nil,
                accessBookmark: nil
            )
        )

        let savedFolder = try XCTUnwrap(store.savedFolders.first)
        XCTAssertEqual(savedFolder.libraryID, library.id)
        XCTAssertEqual(
            store.calls,
            [
                .fetchLibrary,
                .fetchLibraryFolders(libraryID: library.id),
                .addLibraryFolder
            ]
        )
    }

    func testAddFolderStoresStandardizedPath() async throws {
        let parentURL = try makeDirectory("Parent")
        let folderURL = parentURL.appendingPathComponent("Movies", isDirectory: true)
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        let unstandardizedPath = parentURL
            .appendingPathComponent("..")
            .appendingPathComponent("Parent")
            .appendingPathComponent("Movies")
            .path
        let expectedPath = URL(fileURLWithPath: unstandardizedPath).standardizedFileURL.path
        let store = FakeLibraryFolderMutationStore()
        let useCase = AddLibraryFolderUseCase(store: store)

        let added = try await useCase.addFolder(
            AddLibraryFolderRequest(
                rootPath: unstandardizedPath,
                displayName: nil,
                accessBookmark: nil
            )
        )

        XCTAssertEqual(added.rootPath, expectedPath)
        XCTAssertEqual(store.savedFolders.first?.rootPath, expectedPath)
    }

    func testAddFolderUsesProvidedDisplayName() async throws {
        let folderURL = try makeDirectory("Movies")
        let store = FakeLibraryFolderMutationStore()
        let useCase = AddLibraryFolderUseCase(store: store)

        let added = try await useCase.addFolder(
            AddLibraryFolderRequest(
                rootPath: folderURL.path,
                displayName: "  Curated Movies  ",
                accessBookmark: nil
            )
        )

        XCTAssertEqual(added.displayName, "Curated Movies")
        XCTAssertEqual(store.savedFolders.first?.displayName, "Curated Movies")
    }

    func testAddFolderFallsBackToLastPathComponentForDisplayName() async throws {
        let folderURL = try makeDirectory("Movies")
        let store = FakeLibraryFolderMutationStore()
        let useCase = AddLibraryFolderUseCase(store: store)

        let added = try await useCase.addFolder(
            AddLibraryFolderRequest(
                rootPath: folderURL.path,
                displayName: "   ",
                accessBookmark: nil
            )
        )

        XCTAssertEqual(added.displayName, "Movies")
        XCTAssertEqual(store.savedFolders.first?.displayName, "Movies")
    }

    func testAddFolderStoresBookmarkData() async throws {
        let folderURL = try makeDirectory("Movies")
        let bookmark = Data([0x01, 0x02, 0x03])
        let store = FakeLibraryFolderMutationStore()
        let useCase = AddLibraryFolderUseCase(store: store)

        _ = try await useCase.addFolder(
            AddLibraryFolderRequest(
                rootPath: folderURL.path,
                displayName: nil,
                accessBookmark: bookmark
            )
        )

        XCTAssertEqual(store.savedFolders.first?.accessBookmark, bookmark)
    }

    func testAddFolderRejectsEmptyPathBeforeStoreAccess() async {
        let store = FakeLibraryFolderMutationStore()
        let useCase = AddLibraryFolderUseCase(store: store)

        await assertThrowsWorkflowError(
            {
                try await useCase.addFolder(
                    AddLibraryFolderRequest(
                        rootPath: "  \n  ",
                        displayName: nil,
                        accessBookmark: nil
                    )
                )
            },
            .invalidFolderPath
        )
        XCTAssertEqual(store.calls, [])
    }

    func testAddFolderRejectsRelativePathBeforeStoreAccess() async {
        let store = FakeLibraryFolderMutationStore()
        let useCase = AddLibraryFolderUseCase(store: store)

        await assertThrowsWorkflowError(
            {
                try await useCase.addFolder(
                    AddLibraryFolderRequest(
                        rootPath: "../Movies",
                        displayName: nil,
                        accessBookmark: nil
                    )
                )
            },
            .invalidFolderPath
        )
        XCTAssertEqual(store.calls, [])
    }

    func testAddFolderRejectsMissingPathBeforeStoreAccess() async {
        let missingPath = temporaryDirectory
            .appendingPathComponent("Missing", isDirectory: true)
            .path
        let standardizedPath = URL(fileURLWithPath: missingPath).standardizedFileURL.path
        let store = FakeLibraryFolderMutationStore()
        let useCase = AddLibraryFolderUseCase(store: store)

        await assertThrowsWorkflowError(
            {
                try await useCase.addFolder(
                    AddLibraryFolderRequest(
                        rootPath: missingPath,
                        displayName: nil,
                        accessBookmark: nil
                    )
                )
            },
            .folderUnavailable(standardizedPath)
        )
        XCTAssertEqual(store.calls, [])
    }

    func testAddFolderRejectsFilePathBeforeStoreAccess() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("Movie.mkv", isDirectory: false)
        try Data().write(to: fileURL)
        let standardizedPath = fileURL.standardizedFileURL.path
        let store = FakeLibraryFolderMutationStore()
        let useCase = AddLibraryFolderUseCase(store: store)

        await assertThrowsWorkflowError(
            {
                try await useCase.addFolder(
                    AddLibraryFolderRequest(
                        rootPath: fileURL.path,
                        displayName: nil,
                        accessBookmark: nil
                    )
                )
            },
            .folderUnavailable(standardizedPath)
        )
        XCTAssertEqual(store.calls, [])
    }

    func testAddFolderRejectsDuplicateStandardizedPath() async throws {
        let parentURL = try makeDirectory("Parent")
        let folderURL = parentURL.appendingPathComponent("Movies", isDirectory: true)
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        let unstandardizedExistingPath = parentURL
            .appendingPathComponent("..")
            .appendingPathComponent("Parent")
            .appendingPathComponent("Movies")
            .path
        let standardizedPath = folderURL.standardizedFileURL.path
        let library = Library(id: "existing-library", name: "Existing")
        let store = FakeLibraryFolderMutationStore(
            library: library,
            existingFolders: [
                LibraryFolder(
                    libraryID: library.id,
                    displayName: "Existing",
                    rootPath: unstandardizedExistingPath
                )
            ]
        )
        let useCase = AddLibraryFolderUseCase(store: store)

        await assertThrowsWorkflowError(
            {
                try await useCase.addFolder(
                    AddLibraryFolderRequest(
                        rootPath: folderURL.path,
                        displayName: nil,
                        accessBookmark: nil
                    )
                )
            },
            .duplicateFolder(standardizedPath)
        )
        XCTAssertEqual(store.savedFolders, [])
        XCTAssertEqual(
            store.calls,
            [
                .fetchLibrary,
                .fetchLibraryFolders(libraryID: library.id)
            ]
        )
    }

    func testLibraryFetchFailureMapsToLibraryUnavailable() async throws {
        let folderURL = try makeDirectory("Movies")
        let store = FakeLibraryFolderMutationStore(fetchLibraryError: StoreFailure.fetchLibrary)
        let useCase = AddLibraryFolderUseCase(store: store)

        await assertThrowsWorkflowError(
            {
                try await useCase.addFolder(
                    AddLibraryFolderRequest(
                        rootPath: folderURL.path,
                        displayName: nil,
                        accessBookmark: nil
                    )
                )
            },
            .libraryUnavailable
        )
    }

    func testAddLibraryFolderWriteFailurePropagatesWithoutLibraryUnavailableMapping() async throws {
        let folderURL = try makeDirectory("Movies")
        let store = FakeLibraryFolderMutationStore(addLibraryFolderError: StoreFailure.addLibraryFolder)
        let useCase = AddLibraryFolderUseCase(store: store)

        do {
            _ = try await useCase.addFolder(
                AddLibraryFolderRequest(
                    rootPath: folderURL.path,
                    displayName: nil,
                    accessBookmark: nil
                )
            )
            XCTFail("Expected addLibraryFolder failure")
        } catch let error as StoreFailure {
            XCTAssertEqual(error, .addLibraryFolder)
        } catch {
            XCTFail("Expected StoreFailure.addLibraryFolder, got \(error)")
        }
    }

    func testWorkflowErrorDescriptionsAreHumanReadable() {
        XCTAssertEqual(
            LibraryFolderWorkflowError.invalidFolderPath.errorDescription,
            "Choose a valid folder path."
        )
        XCTAssertEqual(
            LibraryFolderWorkflowError.folderUnavailable("/tmp/Movies").errorDescription,
            "The folder is unavailable: /tmp/Movies"
        )
        XCTAssertEqual(
            LibraryFolderWorkflowError.duplicateFolder("/tmp/Movies").errorDescription,
            "This folder is already in the library: /tmp/Movies"
        )
        XCTAssertEqual(
            LibraryFolderWorkflowError.libraryUnavailable.errorDescription,
            "The library could not be loaded."
        )
    }

    private func makeDirectory(_ name: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }
}

private final class FakeLibraryFolderMutationStore: ApplicationLibraryFolderMutationStore,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storedLibrary: Library?
    private let ensuredLibrary: Library
    private var existingFolders: [LibraryFolder]
    private var recordedSavedFolders: [LibraryFolder] = []
    private var recordedCalls: [LibraryFolderMutationStoreCall] = []
    private let fetchLibraryError: Error?
    private let ensureLibraryError: Error?
    private let fetchLibraryFoldersError: Error?
    private let addLibraryFolderError: Error?

    init(
        library: Library? = Library(id: "library", name: "CineMind Library"),
        ensuredLibrary: Library = Library(id: "ensured-library", name: "CineMind Library"),
        existingFolders: [LibraryFolder] = [],
        fetchLibraryError: Error? = nil,
        ensureLibraryError: Error? = nil,
        fetchLibraryFoldersError: Error? = nil,
        addLibraryFolderError: Error? = nil
    ) {
        self.storedLibrary = library
        self.ensuredLibrary = ensuredLibrary
        self.existingFolders = existingFolders
        self.fetchLibraryError = fetchLibraryError
        self.ensureLibraryError = ensureLibraryError
        self.fetchLibraryFoldersError = fetchLibraryFoldersError
        self.addLibraryFolderError = addLibraryFolderError
    }

    var savedFolders: [LibraryFolder] {
        lock.withLock {
            recordedSavedFolders
        }
    }

    var calls: [LibraryFolderMutationStoreCall] {
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

    func ensureLibrary(name: String) throws -> Library {
        try lock.withLock {
            recordedCalls.append(.ensureLibrary(name: name))
            if let ensureLibraryError {
                throw ensureLibraryError
            }
            storedLibrary = ensuredLibrary
            return ensuredLibrary
        }
    }

    func fetchLibraryFolders(libraryID: LibraryID) throws -> [LibraryFolder] {
        try lock.withLock {
            recordedCalls.append(.fetchLibraryFolders(libraryID: libraryID))
            if let fetchLibraryFoldersError {
                throw fetchLibraryFoldersError
            }
            return existingFolders.filter { $0.libraryID == libraryID }
        }
    }

    func addLibraryFolder(_ folder: LibraryFolder) throws {
        try lock.withLock {
            recordedCalls.append(.addLibraryFolder)
            if let addLibraryFolderError {
                throw addLibraryFolderError
            }
            existingFolders.append(folder)
            recordedSavedFolders.append(folder)
        }
    }
}

private enum LibraryFolderMutationStoreCall: Equatable {
    case fetchLibrary
    case ensureLibrary(name: String)
    case fetchLibraryFolders(libraryID: LibraryID)
    case addLibraryFolder
}

private enum StoreFailure: Error, Equatable {
    case fetchLibrary
    case addLibraryFolder
}

private func assertThrowsWorkflowError<T>(
    _ operation: () async throws -> T,
    _ expectedError: LibraryFolderWorkflowError,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await operation()
        XCTFail("Expected \(expectedError)", file: file, line: line)
    } catch let error as LibraryFolderWorkflowError {
        XCTAssertEqual(error, expectedError, file: file, line: line)
    } catch {
        XCTFail("Expected \(expectedError), got \(error)", file: file, line: line)
    }
}
