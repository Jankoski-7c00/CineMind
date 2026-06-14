import Domain
import Foundation
import Persistence

public enum LibraryBrowserSection: Sendable, Equatable, Hashable {
    case library
    case movies
    case tvEpisodes
    case recentlyPlayed
    case needsMetadata
    case favorites
    case collection(CollectionID)
    case folders
}

public enum LibraryBrowserError: Error, Sendable, Equatable {
    case unsupportedMediaSection(LibraryBrowserSection)
}

public struct LibraryBrowserPage: Sendable, Equatable {
    public let limit: Int
    public let offset: Int

    public init(limit: Int, offset: Int = 0) {
        self.limit = limit
        self.offset = offset
    }
}

public struct LibraryItemSummary: Identifiable, Sendable, Equatable {
    public let id: MediaItemID
    public let displayTitle: String
    public let mediaTypeLabel: String
    public let yearOrEpisodeLabel: String?
    public let availabilityLabel: String
    public let metadataLabel: String
    public let lastPlayedLabel: String?
    public let isFavorite: Bool
    public let tagLabels: [String]

    public init(
        id: MediaItemID,
        displayTitle: String,
        mediaTypeLabel: String,
        yearOrEpisodeLabel: String?,
        availabilityLabel: String,
        metadataLabel: String,
        lastPlayedLabel: String?,
        isFavorite: Bool = false,
        tagLabels: [String] = []
    ) {
        self.id = id
        self.displayTitle = displayTitle
        self.mediaTypeLabel = mediaTypeLabel
        self.yearOrEpisodeLabel = yearOrEpisodeLabel
        self.availabilityLabel = availabilityLabel
        self.metadataLabel = metadataLabel
        self.lastPlayedLabel = lastPlayedLabel
        self.isFavorite = isFavorite
        self.tagLabels = tagLabels
    }
}

public struct LibraryMediaSummarySnapshot: Sendable, Equatable {
    public let section: LibraryBrowserSection
    public let page: LibraryBrowserPage
    public let items: [LibraryItemSummary]

    public init(
        section: LibraryBrowserSection,
        page: LibraryBrowserPage,
        items: [LibraryItemSummary]
    ) {
        self.section = section
        self.page = page
        self.items = items
    }
}

public protocol LibraryMediaSummaryBrowsing: Sendable {
    func browse(
        section: LibraryBrowserSection,
        page: LibraryBrowserPage
    ) async throws -> LibraryMediaSummarySnapshot
}

public protocol ApplicationLibraryMediaSummaryStore: Sendable {
    func fetchMediaItemSummaries(
        mediaType: MediaType?,
        limit: Int,
        offset: Int
    ) throws -> [PersistedMediaItemSummary]
    func fetchRecentlyPlayedMediaItemSummaries(
        limit: Int,
        offset: Int
    ) throws -> [PersistedMediaItemSummary]
    func fetchMediaItemSummariesNeedingMetadata(
        limit: Int,
        offset: Int
    ) throws -> [PersistedMediaItemSummary]
    func fetchFavoriteMediaItemSummaries(
        limit: Int,
        offset: Int
    ) throws -> [PersistedMediaItemSummary]
    func fetchMediaItemSummaries(
        collectionID: CollectionID,
        limit: Int,
        offset: Int
    ) throws -> [PersistedMediaItemSummary]
}

extension CineMindStore: ApplicationLibraryMediaSummaryStore {}

public struct LibraryMediaSummaryUseCase: LibraryMediaSummaryBrowsing, Sendable {
    private let store: any ApplicationLibraryMediaSummaryStore
    private let queue: DispatchQueue
    private let itemMapper: LibraryItemSummaryMapper

    public init(
        store: any ApplicationLibraryMediaSummaryStore,
        queueLabel: String = "CineMind.LibraryMediaSummaryUseCase"
    ) {
        self.init(
            store: store,
            queueLabel: queueLabel,
            lastPlayedLabel: Self.defaultLastPlayedLabel
        )
    }

    public init(
        store: any ApplicationLibraryMediaSummaryStore,
        queueLabel: String = "CineMind.LibraryMediaSummaryUseCase",
        lastPlayedLabel: @escaping @Sendable (Date) -> String
    ) {
        self.store = store
        self.queue = DispatchQueue(label: queueLabel)
        self.itemMapper = LibraryItemSummaryMapper(lastPlayedLabel: lastPlayedLabel)
    }

    public func browse(
        section: LibraryBrowserSection,
        page: LibraryBrowserPage
    ) async throws -> LibraryMediaSummarySnapshot {
        guard section != .folders else {
            throw LibraryBrowserError.unsupportedMediaSection(section)
        }

        let normalizedPage = LibraryBrowserPage(
            limit: page.limit,
            offset: max(page.offset, 0)
        )

        guard normalizedPage.limit > 0 else {
            return LibraryMediaSummarySnapshot(
                section: section,
                page: normalizedPage,
                items: []
            )
        }

        let summaries = try await fetchSummaries(
            section: section,
            page: normalizedPage
        )
        return LibraryMediaSummarySnapshot(
            section: section,
            page: normalizedPage,
            items: summaries.map(map)
        )
    }

    private func fetchSummaries(
        section: LibraryBrowserSection,
        page: LibraryBrowserPage
    ) async throws -> [PersistedMediaItemSummary] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let summaries = try fetchPersistedSummaries(
                        section: section,
                        page: page,
                        store: store
                    )
                    continuation.resume(returning: summaries)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func map(_ summary: PersistedMediaItemSummary) -> LibraryItemSummary {
        itemMapper.map(summary)
    }

    private static func defaultLastPlayedLabel(_ date: Date) -> String {
        LibraryBrowserDateLabel.format(date)
    }
}

struct LibraryItemSummaryMapper {
    private let lastPlayedLabel: @Sendable (Date) -> String

    init(lastPlayedLabel: @escaping @Sendable (Date) -> String) {
        self.lastPlayedLabel = lastPlayedLabel
    }

    func map(_ summary: PersistedMediaItemSummary) -> LibraryItemSummary {
        LibraryItemSummary(
            id: summary.id,
            displayTitle: displayTitle(for: summary),
            mediaTypeLabel: mediaTypeLabel(for: summary.mediaType),
            yearOrEpisodeLabel: yearOrEpisodeLabel(for: summary),
            availabilityLabel: availabilityLabel(for: summary),
            metadataLabel: metadataLabel(for: summary),
            lastPlayedLabel: summary.latestPlayedAt.map(lastPlayedLabel),
            isFavorite: summary.isFavorite,
            tagLabels: summary.tagLabels
        )
    }

    private func displayTitle(for summary: PersistedMediaItemSummary) -> String {
        let persistedTitle = summary.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !persistedTitle.isEmpty {
            return persistedTitle
        }

        let episodeTitle = summary.episodeTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let episodeTitle, !episodeTitle.isEmpty {
            return episodeTitle
        }

        return "Untitled"
    }

    private func mediaTypeLabel(for mediaType: MediaType) -> String {
        switch mediaType {
        case .movie:
            "Movie"
        case .episode:
            "TV Episode"
        }
    }

    private func yearOrEpisodeLabel(for summary: PersistedMediaItemSummary) -> String? {
        switch summary.mediaType {
        case .movie:
            return summary.year.map(String.init)
        case .episode:
            guard let seasonNumber = summary.seasonNumber,
                  let episodeNumber = summary.episodeNumber else {
                return nil
            }

            let episodeCode = String(format: "S%02dE%02d", seasonNumber, episodeNumber)
            let episodeTitle = summary.episodeTitle?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let episodeTitle, !episodeTitle.isEmpty else {
                return episodeCode
            }
            return "\(episodeCode) - \(episodeTitle)"
        }
    }

    private func availabilityLabel(for summary: PersistedMediaItemSummary) -> String {
        if summary.totalFileCount <= 0 {
            return "no files"
        }
        if summary.availableFileCount == summary.totalFileCount {
            return "available"
        }
        if summary.availableFileCount <= 0 {
            return "unavailable"
        }
        return "partially available"
    }

    private func metadataLabel(for summary: PersistedMediaItemSummary) -> String {
        switch (summary.hasMetadataItem, summary.hasMetadataSourceRecord) {
        case (true, true):
            "complete"
        case (true, false), (false, true):
            "partial"
        case (false, false):
            "missing"
        }
    }
}

private func fetchPersistedSummaries(
    section: LibraryBrowserSection,
    page: LibraryBrowserPage,
    store: any ApplicationLibraryMediaSummaryStore
) throws -> [PersistedMediaItemSummary] {
    switch section {
    case .library:
        try store.fetchMediaItemSummaries(mediaType: nil, limit: page.limit, offset: page.offset)
    case .movies:
        try store.fetchMediaItemSummaries(mediaType: .movie, limit: page.limit, offset: page.offset)
    case .tvEpisodes:
        try store.fetchMediaItemSummaries(mediaType: .episode, limit: page.limit, offset: page.offset)
    case .recentlyPlayed:
        try store.fetchRecentlyPlayedMediaItemSummaries(limit: page.limit, offset: page.offset)
    case .needsMetadata:
        try store.fetchMediaItemSummariesNeedingMetadata(limit: page.limit, offset: page.offset)
    case .favorites:
        try store.fetchFavoriteMediaItemSummaries(limit: page.limit, offset: page.offset)
    case .collection(let collectionID):
        try store.fetchMediaItemSummaries(
            collectionID: collectionID,
            limit: page.limit,
            offset: page.offset
        )
    case .folders:
        throw LibraryBrowserError.unsupportedMediaSection(section)
    }
}

enum LibraryBrowserDateLabel {
    static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withFullDate,
            .withTime,
            .withTimeZone,
            .withColonSeparatorInTime
        ]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
