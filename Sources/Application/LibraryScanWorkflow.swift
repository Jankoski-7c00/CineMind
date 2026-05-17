import Domain
import Foundation
import Persistence

public struct LibraryScanCountSummary: Sendable, Equatable {
    public let foldersScanned: Int
    public let filesDiscovered: Int
    public let mediaItemsCreated: Int
    public let mediaItemsUpdated: Int
    public let mediaFilesCreated: Int
    public let mediaFilesUpdated: Int
    public let filesMarkedUnavailable: Int
    public let issuesRecorded: Int

    public init(
        foldersScanned: Int,
        filesDiscovered: Int,
        mediaItemsCreated: Int,
        mediaItemsUpdated: Int,
        mediaFilesCreated: Int,
        mediaFilesUpdated: Int,
        filesMarkedUnavailable: Int,
        issuesRecorded: Int
    ) {
        self.foldersScanned = foldersScanned
        self.filesDiscovered = filesDiscovered
        self.mediaItemsCreated = mediaItemsCreated
        self.mediaItemsUpdated = mediaItemsUpdated
        self.mediaFilesCreated = mediaFilesCreated
        self.mediaFilesUpdated = mediaFilesUpdated
        self.filesMarkedUnavailable = filesMarkedUnavailable
        self.issuesRecorded = issuesRecorded
    }
}

public struct LibraryScanIssueSummary: Sendable, Equatable {
    public let typeLabel: String
    public let message: String

    public init(
        typeLabel: String,
        message: String
    ) {
        self.typeLabel = typeLabel
        self.message = message
    }
}

public struct LibraryScanResultSummary: Sendable, Equatable {
    public let scanRunID: ScanRunID
    public let statusLabel: String
    public let counts: LibraryScanCountSummary
    public let issues: [LibraryScanIssueSummary]

    public init(
        scanRunID: ScanRunID,
        statusLabel: String,
        counts: LibraryScanCountSummary,
        issues: [LibraryScanIssueSummary]
    ) {
        self.scanRunID = scanRunID
        self.statusLabel = statusLabel
        self.counts = counts
        self.issues = issues
    }
}

public protocol LibraryScanRunning: Sendable {
    func runScan(libraryID: LibraryID) throws -> LibraryScanResultSummary
}

public protocol LibraryScanning: Sendable {
    func scanLibrary() async throws -> LibraryScanResultSummary
}

public enum LibraryScanWorkflowError: Error, Sendable, Equatable, LocalizedError {
    case libraryUnavailable
    case noLibraryFolders
    case scanFailed(String)

    public var errorDescription: String? {
        switch self {
        case .libraryUnavailable:
            "The library could not be loaded."
        case .noLibraryFolders:
            "Add a library folder before scanning."
        case .scanFailed(let message):
            message
        }
    }
}

public protocol ApplicationLibraryScanStore: Sendable {
    func fetchLibrary() throws -> Library?
    func fetchLibraryFolders(libraryID: LibraryID) throws -> [LibraryFolder]
}

extension CineMindStore: ApplicationLibraryScanStore {}

public struct RunLibraryScanUseCase: LibraryScanning, Sendable {
    private static let sanitizedRunnerFailureMessage = "The library scan could not be completed."

    private let store: any ApplicationLibraryScanStore
    private let runner: any LibraryScanRunning
    private let queue: DispatchQueue

    public init(
        store: any ApplicationLibraryScanStore,
        runner: any LibraryScanRunning,
        queueLabel: String = "CineMind.RunLibraryScanUseCase"
    ) {
        self.store = store
        self.runner = runner
        self.queue = DispatchQueue(label: queueLabel)
    }

    public func scanLibrary() async throws -> LibraryScanResultSummary {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let result = try Self.scanLibrary(store: store, runner: runner)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func scanLibrary(
        store: any ApplicationLibraryScanStore,
        runner: any LibraryScanRunning
    ) throws -> LibraryScanResultSummary {
        let library = try currentLibrary(from: store)
        let folders = try libraryFolders(libraryID: library.id, from: store)

        guard !folders.isEmpty else {
            throw LibraryScanWorkflowError.noLibraryFolders
        }

        do {
            return try runner.runScan(libraryID: library.id)
        } catch {
            throw LibraryScanWorkflowError.scanFailed(sanitizedRunnerFailureMessage)
        }
    }

    private static func currentLibrary(
        from store: any ApplicationLibraryScanStore
    ) throws -> Library {
        do {
            guard let library = try store.fetchLibrary() else {
                throw LibraryScanWorkflowError.libraryUnavailable
            }
            return library
        } catch let error as LibraryScanWorkflowError {
            throw error
        } catch {
            throw LibraryScanWorkflowError.libraryUnavailable
        }
    }

    private static func libraryFolders(
        libraryID: LibraryID,
        from store: any ApplicationLibraryScanStore
    ) throws -> [LibraryFolder] {
        do {
            return try store.fetchLibraryFolders(libraryID: libraryID)
        } catch {
            throw LibraryScanWorkflowError.libraryUnavailable
        }
    }
}
