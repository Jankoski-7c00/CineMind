import Application
import Domain
import Foundation
@testable import Persistence
import XCTest

final class LibraryBrowserSummaryTests: XCTestCase {
    func testSectionMappingLibraryMoviesAndTVEpisodes() async throws {
        let store = RecordingLibraryMediaSummaryStore()
        let useCase = LibraryMediaSummaryUseCase(store: store)

        _ = try await useCase.browse(section: .library, page: LibraryBrowserPage(limit: 10))
        _ = try await useCase.browse(section: .movies, page: LibraryBrowserPage(limit: 10))
        _ = try await useCase.browse(section: .tvEpisodes, page: LibraryBrowserPage(limit: 10))

        XCTAssertEqual(
            store.calls,
            [
                .media(mediaType: nil, limit: 10, offset: 0),
                .media(mediaType: .movie, limit: 10, offset: 0),
                .media(mediaType: .episode, limit: 10, offset: 0)
            ]
        )
    }

    func testSectionMappingRecentlyPlayedAndNeedsMetadata() async throws {
        let store = RecordingLibraryMediaSummaryStore()
        let useCase = LibraryMediaSummaryUseCase(store: store)

        _ = try await useCase.browse(section: .recentlyPlayed, page: LibraryBrowserPage(limit: 10))
        _ = try await useCase.browse(
            section: .needsMetadata,
            page: LibraryBrowserPage(limit: 5, offset: 2)
        )

        XCTAssertEqual(
            store.calls,
            [
                .recentlyPlayed(limit: 10, offset: 0),
                .needsMetadata(limit: 5, offset: 2)
            ]
        )
    }

    func testSectionMappingFavoritesAndCollections() async throws {
        let store = RecordingLibraryMediaSummaryStore()
        let useCase = LibraryMediaSummaryUseCase(store: store)

        _ = try await useCase.browse(section: .favorites, page: LibraryBrowserPage(limit: 10))
        _ = try await useCase.browse(
            section: .collection("collection-1"),
            page: LibraryBrowserPage(limit: 5, offset: 2)
        )

        XCTAssertEqual(
            store.calls,
            [
                .favorites(limit: 10, offset: 0),
                .collection(collectionID: "collection-1", limit: 5, offset: 2)
            ]
        )
    }

    func testFoldersSectionThrowsUnsupportedMediaSectionWithoutStoreCall() async throws {
        let store = RecordingLibraryMediaSummaryStore()
        let useCase = LibraryMediaSummaryUseCase(store: store)

        do {
            _ = try await useCase.browse(section: .folders, page: LibraryBrowserPage(limit: 10))
            XCTFail("Expected folders to be unsupported by the media summary use case")
        } catch {
            XCTAssertEqual(
                error as? LibraryBrowserError,
                .unsupportedMediaSection(.folders)
            )
        }

        XCTAssertEqual(store.calls, [])
    }

    func testLimitLessThanOrEqualToZeroReturnsEmptySnapshotWithoutStoreCall() async throws {
        let store = RecordingLibraryMediaSummaryStore()
        let useCase = LibraryMediaSummaryUseCase(store: store)

        let zeroSnapshot = try await useCase.browse(
            section: .movies,
            page: LibraryBrowserPage(limit: 0, offset: 4)
        )
        let negativeSnapshot = try await useCase.browse(
            section: .tvEpisodes,
            page: LibraryBrowserPage(limit: -1, offset: -10)
        )

        XCTAssertEqual(
            zeroSnapshot,
            LibraryMediaSummarySnapshot(
                section: .movies,
                page: LibraryBrowserPage(limit: 0, offset: 4),
                items: []
            )
        )
        XCTAssertEqual(
            negativeSnapshot,
            LibraryMediaSummarySnapshot(
                section: .tvEpisodes,
                page: LibraryBrowserPage(limit: -1, offset: 0),
                items: []
            )
        )
        XCTAssertEqual(store.calls, [])
    }

    func testNegativeOffsetIsNormalizedBeforeStoreCallAndSnapshotIncludesPage() async throws {
        let store = RecordingLibraryMediaSummaryStore(
            summaries: [
                makeSummary(id: "arrival", mediaType: .movie, title: "Arrival")
            ]
        )
        let useCase = LibraryMediaSummaryUseCase(store: store)

        let snapshot = try await useCase.browse(
            section: .library,
            page: LibraryBrowserPage(limit: 20, offset: -5)
        )

        XCTAssertEqual(store.calls, [.media(mediaType: nil, limit: 20, offset: 0)])
        XCTAssertEqual(snapshot.section, .library)
        XCTAssertEqual(snapshot.page, LibraryBrowserPage(limit: 20, offset: 0))
        XCTAssertEqual(snapshot.items.map(\.id), ["arrival"])
    }

    func testNegativeOffsetIsNormalizedForExtraMediaSections() async throws {
        let store = RecordingLibraryMediaSummaryStore(
            summaries: [
                makeSummary(id: "arrival", mediaType: .movie, title: "Arrival")
            ]
        )
        let useCase = LibraryMediaSummaryUseCase(store: store)

        _ = try await useCase.browse(
            section: .recentlyPlayed,
            page: LibraryBrowserPage(limit: 20, offset: -5)
        )
        _ = try await useCase.browse(
            section: .needsMetadata,
            page: LibraryBrowserPage(limit: 20, offset: -10)
        )

        XCTAssertEqual(
            store.calls,
            [
                .recentlyPlayed(limit: 20, offset: 0),
                .needsMetadata(limit: 20, offset: 0)
            ]
        )
    }

    func testMovieTitleAndYearLabels() async throws {
        let store = RecordingLibraryMediaSummaryStore(
            summaries: [
                makeSummary(
                    id: "arrival",
                    mediaType: .movie,
                    title: "  Arrival  ",
                    year: 2016
                )
            ]
        )
        let useCase = LibraryMediaSummaryUseCase(store: store)

        let item = try await onlyItem(useCase)

        XCTAssertEqual(item.displayTitle, "Arrival")
        XCTAssertEqual(item.mediaTypeLabel, "Movie")
        XCTAssertEqual(item.yearOrEpisodeLabel, "2016")
    }

    func testDisplayTitleFallbackUsesEpisodeTitleThenUntitled() async throws {
        let store = RecordingLibraryMediaSummaryStore(
            summaries: [
                makeSummary(
                    id: "episode-title",
                    mediaType: .episode,
                    title: "  ",
                    episodeTitle: "  Pilot  "
                ),
                makeSummary(
                    id: "untitled",
                    mediaType: .movie,
                    title: "  ",
                    episodeTitle: "  "
                )
            ]
        )
        let useCase = LibraryMediaSummaryUseCase(store: store)

        let items = try await useCase.browse(
            section: .library,
            page: LibraryBrowserPage(limit: 10)
        ).items

        XCTAssertEqual(items.map(\.displayTitle), ["Pilot", "Untitled"])
    }

    func testEpisodeSeasonEpisodeLabelIncludesTitle() async throws {
        let store = RecordingLibraryMediaSummaryStore(
            summaries: [
                makeSummary(
                    id: "pilot",
                    mediaType: .episode,
                    title: "The Show",
                    seasonNumber: 1,
                    episodeNumber: 2,
                    episodeTitle: "Pilot"
                )
            ]
        )
        let useCase = LibraryMediaSummaryUseCase(store: store)

        let item = try await onlyItem(useCase)

        XCTAssertEqual(item.mediaTypeLabel, "TV Episode")
        XCTAssertEqual(item.yearOrEpisodeLabel, "S01E02 - Pilot")
    }

    func testAvailabilityLabels() async throws {
        let store = RecordingLibraryMediaSummaryStore(
            summaries: [
                makeSummary(id: "none", mediaType: .movie, totalFileCount: 0),
                makeSummary(
                    id: "available",
                    mediaType: .movie,
                    totalFileCount: 2,
                    availableFileCount: 2,
                    unavailableFileCount: 0
                ),
                makeSummary(
                    id: "partial",
                    mediaType: .movie,
                    totalFileCount: 3,
                    availableFileCount: 1,
                    unavailableFileCount: 2
                ),
                makeSummary(
                    id: "unavailable",
                    mediaType: .movie,
                    totalFileCount: 2,
                    availableFileCount: 0,
                    unavailableFileCount: 2
                )
            ]
        )
        let useCase = LibraryMediaSummaryUseCase(store: store)

        let items = try await useCase.browse(
            section: .library,
            page: LibraryBrowserPage(limit: 10)
        ).items

        XCTAssertEqual(
            items.map(\.availabilityLabel),
            ["no files", "available", "partially available", "unavailable"]
        )
    }

    func testMetadataLabels() async throws {
        let store = RecordingLibraryMediaSummaryStore(
            summaries: [
                makeSummary(
                    id: "complete",
                    mediaType: .movie,
                    hasMetadataItem: true,
                    hasMetadataSourceRecord: true
                ),
                makeSummary(
                    id: "item-only",
                    mediaType: .movie,
                    hasMetadataItem: true,
                    hasMetadataSourceRecord: false
                ),
                makeSummary(
                    id: "source-only",
                    mediaType: .movie,
                    hasMetadataItem: false,
                    hasMetadataSourceRecord: true
                ),
                makeSummary(
                    id: "missing",
                    mediaType: .movie,
                    hasMetadataItem: false,
                    hasMetadataSourceRecord: false
                )
            ]
        )
        let useCase = LibraryMediaSummaryUseCase(store: store)

        let items = try await useCase.browse(
            section: .library,
            page: LibraryBrowserPage(limit: 10)
        ).items

        XCTAssertEqual(
            items.map(\.metadataLabel),
            ["complete", "partial", "partial", "missing"]
        )
    }

    func testLastPlayedLabelPresentAndAbsent() async throws {
        let playedAt = Date(timeIntervalSince1970: 1_000)
        let store = RecordingLibraryMediaSummaryStore(
            summaries: [
                makeSummary(
                    id: "played",
                    mediaType: .movie,
                    latestPlayedAt: playedAt
                ),
                makeSummary(
                    id: "never-played",
                    mediaType: .movie,
                    latestPlayedAt: nil
                )
            ]
        )
        let useCase = LibraryMediaSummaryUseCase(
            store: store,
            lastPlayedLabel: { "played:\(Int($0.timeIntervalSince1970))" }
        )

        let items = try await useCase.browse(
            section: .library,
            page: LibraryBrowserPage(limit: 10)
        ).items

        XCTAssertEqual(items.map(\.lastPlayedLabel), ["played:1000", nil])
    }

    func testCurationSummaryFieldsMapThroughBrowserItems() async throws {
        let store = RecordingLibraryMediaSummaryStore(
            summaries: [
                makeSummary(
                    id: "favorite",
                    mediaType: .movie,
                    isFavorite: true,
                    tagLabels: ["Sci Fi", "Weekend"],
                    selectedPosterLocalCachePath: "/cache/arrival.jpg"
                )
            ]
        )
        let useCase = LibraryMediaSummaryUseCase(store: store)

        let item = try await onlyItem(useCase)

        XCTAssertTrue(item.isFavorite)
        XCTAssertEqual(item.tagLabels, ["Sci Fi", "Weekend"])
        XCTAssertEqual(item.selectedPosterLocalCachePath, "/cache/arrival.jpg")
    }

    func testDefaultLastPlayedLabelIsDeterministic() async throws {
        let store = RecordingLibraryMediaSummaryStore(
            summaries: [
                makeSummary(
                    id: "played",
                    mediaType: .movie,
                    latestPlayedAt: Date(timeIntervalSince1970: 1_000)
                )
            ]
        )
        let useCase = LibraryMediaSummaryUseCase(store: store)

        let first = try await onlyItem(useCase).lastPlayedLabel
        let second = try await onlyItem(useCase).lastPlayedLabel

        XCTAssertEqual(first, second)
        XCTAssertEqual(first, "1970-01-01T00:16:40Z")
    }

    func testSnapshotIncludesSectionPageAndItems() async throws {
        let expectedItem = makeSummary(id: "arrival", mediaType: .movie, title: "Arrival")
        let store = RecordingLibraryMediaSummaryStore(summaries: [expectedItem])
        let useCase = LibraryMediaSummaryUseCase(store: store)

        let snapshot = try await useCase.browse(
            section: .movies,
            page: LibraryBrowserPage(limit: 1, offset: 2)
        )

        XCTAssertEqual(snapshot.section, .movies)
        XCTAssertEqual(snapshot.page, LibraryBrowserPage(limit: 1, offset: 2))
        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.items[0].id, "arrival")
        XCTAssertEqual(snapshot.items[0].displayTitle, "Arrival")
    }

    func testBrowsingDoesNotMutateStoreSummaries() async throws {
        let summaries = [
            makeSummary(id: "arrival", mediaType: .movie, title: "Arrival", year: 2016)
        ]
        let store = RecordingLibraryMediaSummaryStore(summaries: summaries)
        let useCase = LibraryMediaSummaryUseCase(store: store)

        _ = try await useCase.browse(section: .library, page: LibraryBrowserPage(limit: 10))

        XCTAssertEqual(store.summaries, summaries)
    }

    func testConcurrentBrowsingSerializesStoreAccess() async throws {
        let store = RecordingLibraryMediaSummaryStore(
            summaries: [
                makeSummary(id: "arrival", mediaType: .movie, title: "Arrival")
            ],
            callDelay: 0.02
        )
        let useCase = LibraryMediaSummaryUseCase(store: store)

        async let first = useCase.browse(section: .library, page: LibraryBrowserPage(limit: 10))
        async let second = useCase.browse(section: .movies, page: LibraryBrowserPage(limit: 10))
        async let third = useCase.browse(section: .tvEpisodes, page: LibraryBrowserPage(limit: 10))
        _ = try await [first, second, third]

        XCTAssertEqual(store.maxConcurrentCalls, 1)
        XCTAssertEqual(store.calls.count, 3)
    }

    @MainActor
    func testBrowseCanBeCalledFromMainActorContext() async throws {
        let store = RecordingLibraryMediaSummaryStore(
            summaries: [
                makeSummary(id: "arrival", mediaType: .movie, title: "Arrival")
            ]
        )
        let browser: any LibraryMediaSummaryBrowsing = LibraryMediaSummaryUseCase(store: store)

        let snapshot = try await browser.browse(
            section: .library,
            page: LibraryBrowserPage(limit: 10)
        )

        XCTAssertEqual(snapshot.items.map(\.id), ["arrival"])
    }

    private func onlyItem(_ useCase: LibraryMediaSummaryUseCase) async throws -> LibraryItemSummary {
        let snapshot = try await useCase.browse(
            section: .library,
            page: LibraryBrowserPage(limit: 10)
        )
        return try XCTUnwrap(snapshot.items.first)
    }
}

private final class RecordingLibraryMediaSummaryStore: ApplicationLibraryMediaSummaryStore,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storedSummaries: [PersistedMediaItemSummary]
    private var recordedCalls: [StoreCall] = []
    private var activeCalls = 0
    private var recordedMaxConcurrentCalls = 0
    private let callDelay: TimeInterval

    init(
        summaries: [PersistedMediaItemSummary] = [],
        callDelay: TimeInterval = 0
    ) {
        self.storedSummaries = summaries
        self.callDelay = callDelay
    }

    var summaries: [PersistedMediaItemSummary] {
        lock.withLock {
            storedSummaries
        }
    }

    var calls: [StoreCall] {
        lock.withLock {
            recordedCalls
        }
    }

    var maxConcurrentCalls: Int {
        lock.withLock {
            recordedMaxConcurrentCalls
        }
    }

    func fetchMediaItemSummaries(
        mediaType: MediaType?,
        limit: Int,
        offset: Int
    ) throws -> [PersistedMediaItemSummary] {
        fetchSummaries(recording: .media(mediaType: mediaType, limit: limit, offset: offset))
    }

    func fetchRecentlyPlayedMediaItemSummaries(
        limit: Int,
        offset: Int
    ) throws -> [PersistedMediaItemSummary] {
        fetchSummaries(recording: .recentlyPlayed(limit: limit, offset: offset))
    }

    func fetchMediaItemSummariesNeedingMetadata(
        limit: Int,
        offset: Int
    ) throws -> [PersistedMediaItemSummary] {
        fetchSummaries(recording: .needsMetadata(limit: limit, offset: offset))
    }

    func fetchFavoriteMediaItemSummaries(
        limit: Int,
        offset: Int
    ) throws -> [PersistedMediaItemSummary] {
        fetchSummaries(recording: .favorites(limit: limit, offset: offset))
    }

    func fetchMediaItemSummaries(
        collectionID: CollectionID,
        limit: Int,
        offset: Int
    ) throws -> [PersistedMediaItemSummary] {
        fetchSummaries(recording: .collection(collectionID: collectionID, limit: limit, offset: offset))
    }

    private func fetchSummaries(recording call: StoreCall) -> [PersistedMediaItemSummary] {
        lock.withLock {
            activeCalls += 1
            recordedMaxConcurrentCalls = max(recordedMaxConcurrentCalls, activeCalls)
            recordedCalls.append(call)
        }

        if callDelay > 0 {
            Thread.sleep(forTimeInterval: callDelay)
        }

        return lock.withLock {
            activeCalls -= 1
            return storedSummaries
        }
    }
}

private enum StoreCall: Equatable {
    case media(mediaType: MediaType?, limit: Int, offset: Int)
    case recentlyPlayed(limit: Int, offset: Int)
    case needsMetadata(limit: Int, offset: Int)
    case favorites(limit: Int, offset: Int)
    case collection(collectionID: CollectionID, limit: Int, offset: Int)
}

private func makeSummary(
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
    isFavorite: Bool = false,
    tagLabels: [String] = [],
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
        isFavorite: isFavorite,
        tagLabels: tagLabels,
        selectedPosterLocalCachePath: selectedPosterLocalCachePath
    )
}
