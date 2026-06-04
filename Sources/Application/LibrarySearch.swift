import Domain
import Foundation
import Persistence

public struct LibrarySearchRequest: Sendable, Equatable {
    public var text: String
    public var mediaType: LibrarySearchMediaTypeFilter
    public var availability: LibrarySearchAvailabilityFilter
    public var favorite: LibrarySearchFavoriteFilter
    public var tagID: TagID?
    public var sort: LibrarySearchSort
    public var page: LibraryBrowserPage

    public init(
        text: String,
        mediaType: LibrarySearchMediaTypeFilter = .all,
        availability: LibrarySearchAvailabilityFilter = .any,
        favorite: LibrarySearchFavoriteFilter = .any,
        tagID: TagID? = nil,
        sort: LibrarySearchSort = .relevance,
        page: LibraryBrowserPage
    ) {
        self.text = text
        self.mediaType = mediaType
        self.availability = availability
        self.favorite = favorite
        self.tagID = tagID
        self.sort = sort
        self.page = page
    }
}

public enum LibrarySearchMediaTypeFilter: Sendable, Equatable, Hashable, CaseIterable {
    case all
    case movies
    case tvEpisodes
}

public enum LibrarySearchAvailabilityFilter: Sendable, Equatable, Hashable, CaseIterable {
    case any
    case available
    case unavailable
}

public enum LibrarySearchFavoriteFilter: Sendable, Equatable, Hashable, CaseIterable {
    case any
    case favoritesOnly
}

public enum LibrarySearchSort: Sendable, Equatable, Hashable, CaseIterable {
    case relevance
    case title
    case recentlyAdded
    case recentlyPlayed
    case year
}

public struct LibrarySearchSnapshot: Sendable, Equatable {
    public let request: LibrarySearchRequest
    public let items: [LibraryItemSummary]
    public let resultDescription: String

    public init(
        request: LibrarySearchRequest,
        items: [LibraryItemSummary],
        resultDescription: String
    ) {
        self.request = request
        self.items = items
        self.resultDescription = resultDescription
    }
}

public protocol LibraryMediaSearching: Sendable {
    func search(_ request: LibrarySearchRequest) async throws -> LibrarySearchSnapshot
}

public protocol ApplicationLibraryMediaSearchStore: Sendable {
    func searchMediaItems(query: PersistedMediaSearchQuery) throws -> [PersistedMediaSearchResult]
}

extension CineMindStore: ApplicationLibraryMediaSearchStore {}

public struct LibraryMediaSearchUseCase: LibraryMediaSearching, Sendable {
    private let store: any ApplicationLibraryMediaSearchStore
    private let queue: DispatchQueue
    private let itemMapper: LibraryItemSummaryMapper

    public init(
        store: any ApplicationLibraryMediaSearchStore,
        queueLabel: String = "CineMind.LibraryMediaSearchUseCase"
    ) {
        self.init(
            store: store,
            queueLabel: queueLabel,
            lastPlayedLabel: LibraryBrowserDateLabel.format
        )
    }

    public init(
        store: any ApplicationLibraryMediaSearchStore,
        queueLabel: String = "CineMind.LibraryMediaSearchUseCase",
        lastPlayedLabel: @escaping @Sendable (Date) -> String
    ) {
        self.store = store
        self.queue = DispatchQueue(label: queueLabel)
        self.itemMapper = LibraryItemSummaryMapper(lastPlayedLabel: lastPlayedLabel)
    }

    public func search(_ request: LibrarySearchRequest) async throws -> LibrarySearchSnapshot {
        let normalizedRequest = LibrarySearchRequest(
            text: request.text,
            mediaType: request.mediaType,
            availability: request.availability,
            favorite: request.favorite,
            tagID: request.tagID,
            sort: request.sort,
            page: LibraryBrowserPage(
                limit: request.page.limit,
                offset: max(request.page.offset, 0)
            )
        )

        guard normalizedRequest.page.limit > 0 else {
            return LibrarySearchSnapshot(
                request: normalizedRequest,
                items: [],
                resultDescription: "0 results"
            )
        }

        let results = try await searchPersistedResults(request: normalizedRequest)
        let items = results.map { itemMapper.map($0.summary) }
        return LibrarySearchSnapshot(
            request: normalizedRequest,
            items: items,
            resultDescription: resultDescription(count: items.count)
        )
    }

    private func searchPersistedResults(
        request: LibrarySearchRequest
    ) async throws -> [PersistedMediaSearchResult] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let results = try store.searchMediaItems(
                        query: PersistedMediaSearchQuery(
                            text: request.text,
                            mediaType: mediaType(for: request.mediaType),
                            availability: availability(for: request.availability),
                            favorite: favorite(for: request.favorite),
                            tagID: request.tagID,
                            sort: sort(for: request.sort),
                            limit: request.page.limit,
                            offset: request.page.offset
                        )
                    )
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private func mediaType(for filter: LibrarySearchMediaTypeFilter) -> MediaType? {
    switch filter {
    case .all:
        nil
    case .movies:
        .movie
    case .tvEpisodes:
        .episode
    }
}

private func availability(
    for filter: LibrarySearchAvailabilityFilter
) -> PersistedMediaSearchAvailability {
    switch filter {
    case .any:
        .any
    case .available:
        .available
    case .unavailable:
        .unavailable
    }
}

private func favorite(
    for filter: LibrarySearchFavoriteFilter
) -> PersistedMediaSearchFavoriteFilter {
    switch filter {
    case .any:
        .any
    case .favoritesOnly:
        .favoritesOnly
    }
}

private func sort(for sort: LibrarySearchSort) -> PersistedMediaSearchSort {
    switch sort {
    case .relevance:
        .relevance
    case .title:
        .title
    case .recentlyAdded:
        .recentlyAdded
    case .recentlyPlayed:
        .recentlyPlayed
    case .year:
        .year
    }
}

private func resultDescription(count: Int) -> String {
    count == 1 ? "1 result" : "\(count) results"
}
