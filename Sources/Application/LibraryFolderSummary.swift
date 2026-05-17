import Domain
import Foundation
import Persistence

public struct LibraryFolderSummary: Identifiable, Sendable, Equatable {
    public let id: LibraryFolderID
    public let displayName: String
    public let rootPath: String
    public let availabilityLabel: String
    public let fileCountLabel: String
    public let lastSeenLabel: String?
    public let lastScanLabel: String?

    public init(
        id: LibraryFolderID,
        displayName: String,
        rootPath: String,
        availabilityLabel: String,
        fileCountLabel: String,
        lastSeenLabel: String?,
        lastScanLabel: String?
    ) {
        self.id = id
        self.displayName = displayName
        self.rootPath = rootPath
        self.availabilityLabel = availabilityLabel
        self.fileCountLabel = fileCountLabel
        self.lastSeenLabel = lastSeenLabel
        self.lastScanLabel = lastScanLabel
    }
}

public struct LibraryFolderSummarySnapshot: Sendable, Equatable {
    public let page: LibraryBrowserPage
    public let folders: [LibraryFolderSummary]

    public init(
        page: LibraryBrowserPage,
        folders: [LibraryFolderSummary]
    ) {
        self.page = page
        self.folders = folders
    }
}

public protocol LibraryFolderSummaryBrowsing: Sendable {
    func browseFolders(page: LibraryBrowserPage) async throws -> LibraryFolderSummarySnapshot
}

public protocol ApplicationLibraryFolderSummaryStore: Sendable {
    func fetchLibrary() throws -> Library?
    func fetchLibraryFolderSummaries(
        libraryID: LibraryID,
        limit: Int,
        offset: Int
    ) throws -> [PersistedLibraryFolderSummary]
}

extension CineMindStore: ApplicationLibraryFolderSummaryStore {}

public struct LibraryFolderSummaryUseCase: LibraryFolderSummaryBrowsing, Sendable {
    private let store: any ApplicationLibraryFolderSummaryStore
    private let queue: DispatchQueue
    private let dateLabel: @Sendable (Date) -> String

    public init(
        store: any ApplicationLibraryFolderSummaryStore,
        queueLabel: String = "CineMind.LibraryFolderSummaryUseCase"
    ) {
        self.init(
            store: store,
            queueLabel: queueLabel,
            dateLabel: LibraryBrowserDateLabel.format
        )
    }

    public init(
        store: any ApplicationLibraryFolderSummaryStore,
        queueLabel: String = "CineMind.LibraryFolderSummaryUseCase",
        dateLabel: @escaping @Sendable (Date) -> String
    ) {
        self.store = store
        self.queue = DispatchQueue(label: queueLabel)
        self.dateLabel = dateLabel
    }

    public func browseFolders(page: LibraryBrowserPage) async throws -> LibraryFolderSummarySnapshot {
        let normalizedPage = LibraryBrowserPage(
            limit: page.limit,
            offset: max(page.offset, 0)
        )

        guard normalizedPage.limit > 0 else {
            return LibraryFolderSummarySnapshot(page: normalizedPage, folders: [])
        }

        let summaries = try await fetchSummaries(page: normalizedPage)
        return LibraryFolderSummarySnapshot(
            page: normalizedPage,
            folders: summaries.map(map)
        )
    }

    private func fetchSummaries(
        page: LibraryBrowserPage
    ) async throws -> [PersistedLibraryFolderSummary] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard let library = try store.fetchLibrary() else {
                        continuation.resume(returning: [])
                        return
                    }

                    let summaries = try store.fetchLibraryFolderSummaries(
                        libraryID: library.id,
                        limit: page.limit,
                        offset: page.offset
                    )
                    continuation.resume(returning: summaries)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func map(_ summary: PersistedLibraryFolderSummary) -> LibraryFolderSummary {
        LibraryFolderSummary(
            id: summary.id,
            displayName: summary.displayName,
            rootPath: summary.rootPath,
            availabilityLabel: summary.isAvailable ? "available" : "unavailable",
            fileCountLabel: fileCountLabel(for: summary),
            lastSeenLabel: summary.lastSeenAt.map(dateLabel),
            lastScanLabel: summary.lastScanAt.map(dateLabel)
        )
    }

    private func fileCountLabel(for summary: PersistedLibraryFolderSummary) -> String {
        let countLabel = summary.mediaFileCount == 1
            ? "1 file"
            : "\(summary.mediaFileCount) files"
        guard summary.unavailableMediaFileCount > 0 else {
            return countLabel
        }

        let unavailableLabel = summary.unavailableMediaFileCount == 1
            ? "1 unavailable"
            : "\(summary.unavailableMediaFileCount) unavailable"
        return "\(countLabel), \(unavailableLabel)"
    }
}
