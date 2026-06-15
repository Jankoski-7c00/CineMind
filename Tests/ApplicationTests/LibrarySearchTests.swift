import Application
import Domain
import Foundation
@testable import Persistence
import XCTest

final class LibrarySearchTests: XCTestCase {
    func testSearchMapsRequestToPersistenceQueryAndNormalizesPage() async throws {
        let store = RecordingLibraryMediaSearchStore()
        let useCase = LibraryMediaSearchUseCase(store: store)

        _ = try await useCase.search(
            LibrarySearchRequest(
                text: "Arrival",
                mediaType: .movies,
                availability: .unavailable,
                sort: .year,
                page: LibraryBrowserPage(limit: 20, offset: -5)
            )
        )

        XCTAssertEqual(
            store.queries,
            [
                PersistedMediaSearchQuery(
                    text: "Arrival",
                    mediaType: .movie,
                    availability: .unavailable,
                    sort: .year,
                    limit: 20,
                    offset: 0
                )
            ]
        )
    }

    func testEmptySearchTextWithActiveFiltersStillUsesSearchStore() async throws {
        let store = RecordingLibraryMediaSearchStore()
        let useCase = LibraryMediaSearchUseCase(store: store)

        _ = try await useCase.search(
            LibrarySearchRequest(
                text: "",
                mediaType: .tvEpisodes,
                availability: .available,
                sort: .recentlyPlayed,
                page: LibraryBrowserPage(limit: 10, offset: 2)
            )
        )

        XCTAssertEqual(
            store.queries,
            [
                PersistedMediaSearchQuery(
                    text: "",
                    mediaType: .episode,
                    availability: .available,
                    sort: .recentlyPlayed,
                    limit: 10,
                    offset: 2
                )
            ]
        )
    }

    func testSearchMapsCurationFiltersToPersistenceQuery() async throws {
        let store = RecordingLibraryMediaSearchStore()
        let useCase = LibraryMediaSearchUseCase(store: store)

        _ = try await useCase.search(
            LibrarySearchRequest(
                text: "",
                favorite: .favoritesOnly,
                tagID: "tag-1",
                page: LibraryBrowserPage(limit: 10)
            )
        )

        XCTAssertEqual(
            store.queries,
            [
                PersistedMediaSearchQuery(
                    text: "",
                    favorite: .favoritesOnly,
                    tagID: "tag-1",
                    limit: 10
                )
            ]
        )
    }

    func testLimitLessThanOrEqualToZeroReturnsEmptySnapshotWithoutStoreCall() async throws {
        let store = RecordingLibraryMediaSearchStore()
        let useCase = LibraryMediaSearchUseCase(store: store)

        let snapshot = try await useCase.search(
            LibrarySearchRequest(
                text: "Arrival",
                page: LibraryBrowserPage(limit: 0, offset: -10)
            )
        )

        XCTAssertEqual(
            snapshot,
            LibrarySearchSnapshot(
                request: LibrarySearchRequest(
                    text: "Arrival",
                    page: LibraryBrowserPage(limit: 0, offset: 0)
                ),
                items: [],
                resultDescription: "0 results"
            )
        )
        XCTAssertEqual(store.queries, [])
    }

    func testSearchMapsPersistedResultsToLibraryItemSummaries() async throws {
        let store = RecordingLibraryMediaSearchStore(
            results: [
                PersistedMediaSearchResult(
                    summary: makeSearchSummary(
                        id: "arrival",
                        mediaType: .movie,
                        title: " Arrival ",
                        year: 2016,
                        totalFileCount: 1,
                        availableFileCount: 1,
                        hasMetadataItem: true,
                        hasMetadataSourceRecord: true,
                        latestPlayedAt: Date(timeIntervalSince1970: 1_000),
                        selectedPosterLocalCachePath: "/cache/arrival.jpg"
                    ),
                    rank: -1.0
                )
            ]
        )
        let useCase = LibraryMediaSearchUseCase(
            store: store,
            lastPlayedLabel: { "played:\(Int($0.timeIntervalSince1970))" }
        )

        let snapshot = try await useCase.search(
            LibrarySearchRequest(text: "Arrival", page: LibraryBrowserPage(limit: 10))
        )

        XCTAssertEqual(snapshot.resultDescription, "1 result")
        XCTAssertEqual(snapshot.items.map(\.id), ["arrival"])
        XCTAssertEqual(snapshot.items[0].displayTitle, "Arrival")
        XCTAssertEqual(snapshot.items[0].mediaTypeLabel, "Movie")
        XCTAssertEqual(snapshot.items[0].yearOrEpisodeLabel, "2016")
        XCTAssertEqual(snapshot.items[0].availabilityLabel, "available")
        XCTAssertEqual(snapshot.items[0].metadataLabel, "complete")
        XCTAssertEqual(snapshot.items[0].lastPlayedLabel, "played:1000")
        XCTAssertEqual(snapshot.items[0].selectedPosterLocalCachePath, "/cache/arrival.jpg")
    }

    func testStoreErrorPropagates() async throws {
        let store = RecordingLibraryMediaSearchStore(error: SearchStoreError.failure)
        let useCase = LibraryMediaSearchUseCase(store: store)

        do {
            _ = try await useCase.search(
                LibrarySearchRequest(text: "Arrival", page: LibraryBrowserPage(limit: 10))
            )
            XCTFail("Expected search to propagate store error")
        } catch {
            XCTAssertEqual(error as? SearchStoreError, .failure)
        }
    }

    func testConcurrentSearchSerializesStoreAccess() async throws {
        let store = RecordingLibraryMediaSearchStore(
            results: [
                PersistedMediaSearchResult(
                    summary: makeSearchSummary(id: "arrival", mediaType: .movie, title: "Arrival"),
                    rank: -1.0
                )
            ],
            callDelay: 0.02
        )
        let useCase = LibraryMediaSearchUseCase(store: store)

        async let first = useCase.search(
            LibrarySearchRequest(text: "Arrival", page: LibraryBrowserPage(limit: 10))
        )
        async let second = useCase.search(
            LibrarySearchRequest(text: "Moon", page: LibraryBrowserPage(limit: 10))
        )
        async let third = useCase.search(
            LibrarySearchRequest(text: "Pilot", page: LibraryBrowserPage(limit: 10))
        )
        _ = try await [first, second, third]

        XCTAssertEqual(store.maxConcurrentCalls, 1)
        XCTAssertEqual(store.queries.count, 3)
    }
}

private final class RecordingLibraryMediaSearchStore: ApplicationLibraryMediaSearchStore,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let results: [PersistedMediaSearchResult]
    private let error: Error?
    private let callDelay: TimeInterval
    private var recordedQueries: [PersistedMediaSearchQuery] = []
    private var activeCalls = 0
    private var recordedMaxConcurrentCalls = 0

    init(
        results: [PersistedMediaSearchResult] = [],
        error: Error? = nil,
        callDelay: TimeInterval = 0
    ) {
        self.results = results
        self.error = error
        self.callDelay = callDelay
    }

    var queries: [PersistedMediaSearchQuery] {
        lock.withLock {
            recordedQueries
        }
    }

    var maxConcurrentCalls: Int {
        lock.withLock {
            recordedMaxConcurrentCalls
        }
    }

    func searchMediaItems(query: PersistedMediaSearchQuery) throws -> [PersistedMediaSearchResult] {
        lock.withLock {
            activeCalls += 1
            recordedMaxConcurrentCalls = max(recordedMaxConcurrentCalls, activeCalls)
            recordedQueries.append(query)
        }

        if callDelay > 0 {
            Thread.sleep(forTimeInterval: callDelay)
        }

        defer {
            lock.withLock {
                activeCalls -= 1
            }
        }

        if let error {
            throw error
        }
        return results
    }
}

private enum SearchStoreError: Error, Equatable {
    case failure
}

private func makeSearchSummary(
    id: MediaItemID,
    mediaType: MediaType,
    title: String = "Title",
    year: Int? = nil,
    seriesTitle: String? = nil,
    seasonNumber: Int? = nil,
    episodeNumber: Int? = nil,
    episodeTitle: String? = nil,
    totalFileCount: Int = 0,
    availableFileCount: Int = 0,
    unavailableFileCount: Int = 0,
    hasMetadataItem: Bool = false,
    hasMetadataSourceRecord: Bool = false,
    latestPlayedAt: Date? = nil,
    selectedPosterLocalCachePath: String? = nil
) -> PersistedMediaItemSummary {
    PersistedMediaItemSummary(
        id: id,
        mediaType: mediaType,
        title: title,
        year: year,
        seriesTitle: seriesTitle,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        episodeTitle: episodeTitle,
        totalFileCount: totalFileCount,
        availableFileCount: availableFileCount,
        unavailableFileCount: unavailableFileCount,
        hasMetadataItem: hasMetadataItem,
        hasMetadataSourceRecord: hasMetadataSourceRecord,
        latestPlayedAt: latestPlayedAt,
        selectedPosterLocalCachePath: selectedPosterLocalCachePath
    )
}
