import Application
import Domain
import Foundation
@testable import Persistence
import XCTest

final class LibraryItemDetailTests: XCTestCase {
    func testNoMetadataMapsMissingStatusNoSourceAndNoSelectedPoster() async throws {
        let itemID = "missing"
        let store = RecordingLibraryItemDetailStore(
            detail: makePersistedDetail(id: itemID)
        )
        let useCase = LibraryItemDetailUseCase(store: store)

        let result = try await useCase.fetchDetail(id: itemID)
        let detail = try XCTUnwrap(result)

        XCTAssertEqual(detail.metadataLabel, "missing")
        XCTAssertEqual(detail.metadataDetail.statusLabel, "missing")
        XCTAssertNil(detail.metadataDetail.source)
        XCTAssertNil(detail.selectedPoster.asset)
        XCTAssertNil(detail.selectedPoster.localCachePath)
        XCTAssertEqual(detail.selectedPoster.statusLabel, "no poster")
        XCTAssertEqual(detail.selectedPoster.placeholderSeed, itemID)
        XCTAssertEqual(detail.posterAssets, [])
        XCTAssertEqual(
            store.calls,
            [
                .mediaDetail(itemID),
                .metadataItem(itemID),
                .metadataSource(itemID, .tmdb),
                .posterAssets(itemID)
            ]
        )
    }

    func testMetadataItemOnlyMapsPartialStatus() async throws {
        let itemID = "item-only"
        let store = RecordingLibraryItemDetailStore(
            detail: makePersistedDetail(id: itemID),
            metadataItem: MetadataItem(
                mediaItemID: itemID,
                title: "Metadata Arrival"
            )
        )
        let useCase = LibraryItemDetailUseCase(store: store)

        let result = try await useCase.fetchDetail(id: itemID)
        let detail = try XCTUnwrap(result)

        XCTAssertEqual(detail.metadataLabel, "partial")
        XCTAssertEqual(detail.metadataDetail.statusLabel, "partial")
        XCTAssertEqual(detail.metadataDetail.metadataTitle, "Metadata Arrival")
        XCTAssertNil(detail.metadataDetail.source)
    }

    func testSourceOnlyMapsPartialStatus() async throws {
        let itemID = "source-only"
        let source = try metadataSourceRecord(mediaItemID: itemID)
        let store = RecordingLibraryItemDetailStore(
            detail: makePersistedDetail(id: itemID),
            sourceRecord: source
        )
        let useCase = LibraryItemDetailUseCase(store: store)

        let result = try await useCase.fetchDetail(id: itemID)
        let detail = try XCTUnwrap(result)

        XCTAssertEqual(detail.metadataLabel, "partial")
        XCTAssertEqual(detail.metadataDetail.statusLabel, "partial")
        XCTAssertEqual(detail.metadataDetail.source?.providerID, "movie:550")
    }

    func testMetadataAndSourceMapsCompleteStatusAndSourceLabels() async throws {
        let itemID = "complete"
        let source = try metadataSourceRecord(
            mediaItemID: itemID,
            providerID: "movie:123",
            confidence: 0.91,
            matchSource: .manual,
            manualMatchLocked: true,
            matchedAt: Date(timeIntervalSince1970: 1_000),
            refreshedAt: Date(timeIntervalSince1970: 2_000)
        )
        let store = RecordingLibraryItemDetailStore(
            detail: makePersistedDetail(id: itemID),
            metadataItem: MetadataItem(mediaItemID: itemID, title: "Metadata Arrival"),
            sourceRecord: source
        )
        let useCase = LibraryItemDetailUseCase(store: store)

        let result = try await useCase.fetchDetail(id: itemID)
        let detail = try XCTUnwrap(result)
        let sourceDetail = try XCTUnwrap(detail.metadataDetail.source)

        XCTAssertEqual(detail.metadataLabel, "complete")
        XCTAssertEqual(detail.metadataDetail.statusLabel, "complete")
        XCTAssertEqual(sourceDetail.providerLabel, "TMDB")
        XCTAssertEqual(sourceDetail.providerID, "movie:123")
        XCTAssertEqual(sourceDetail.providerMediaTypeLabel, "Movie")
        XCTAssertEqual(sourceDetail.confidenceLabel, "91%")
        XCTAssertEqual(sourceDetail.matchSourceLabel, "manual")
        XCTAssertEqual(sourceDetail.manualMatchLockLabel, "manual lock")
        XCTAssertEqual(sourceDetail.matchedAtLabel, "1970-01-01T00:16:40Z")
        XCTAssertEqual(sourceDetail.refreshedAtLabel, "1970-01-01T00:33:20Z")
    }

    func testMetadataFieldsMapWithoutReplacingLocalTitle() async throws {
        let itemID = "metadata-fields"
        let metadata = MetadataItem(
            mediaItemID: itemID,
            title: "  Metadata Arrival  ",
            originalTitle: "  Original Arrival  ",
            summary: "  Metadata summary  ",
            language: "  en  ",
            releaseDate: "  2016-11-11  ",
            airDate: "2016-10-10"
        )
        let store = RecordingLibraryItemDetailStore(
            detail: makePersistedDetail(id: itemID, title: "Local Arrival"),
            metadataItem: metadata
        )
        let useCase = LibraryItemDetailUseCase(store: store)

        let result = try await useCase.fetchDetail(id: itemID)
        let detail = try XCTUnwrap(result)

        XCTAssertEqual(detail.displayTitle, "Local Arrival")
        XCTAssertEqual(detail.metadataDetail.localTitle, "Local Arrival")
        XCTAssertEqual(detail.metadataDetail.metadataTitle, "Metadata Arrival")
        XCTAssertEqual(detail.metadataDetail.originalTitle, "Original Arrival")
        XCTAssertEqual(detail.metadataDetail.summary, "Metadata summary")
        XCTAssertEqual(detail.metadataDetail.languageLabel, "en")
        XCTAssertEqual(detail.metadataDetail.releaseOrAirDateLabel, "2016-11-11")
    }

    func testMetadataDateFallsBackToAirDate() async throws {
        let itemID = "air-date"
        let store = RecordingLibraryItemDetailStore(
            detail: makePersistedDetail(id: itemID),
            metadataItem: MetadataItem(
                mediaItemID: itemID,
                releaseDate: nil,
                airDate: "  2024-03-04  "
            )
        )
        let useCase = LibraryItemDetailUseCase(store: store)

        let result = try await useCase.fetchDetail(id: itemID)
        let detail = try XCTUnwrap(result)

        XCTAssertEqual(detail.metadataDetail.releaseOrAirDateLabel, "2024-03-04")
    }

    func testSelectedCachedPosterMapsLocalCachePathAndCacheLabels() async throws {
        let itemID = "cached-poster"
        let poster = try posterAsset(
            id: "poster-cached",
            mediaItemID: itemID,
            remotePath: "/cached.jpg",
            width: 500,
            height: 750,
            localCachePath: "  /cache/cached.jpg  ",
            cachedAt: Date(timeIntervalSince1970: 3_000),
            isSelected: true,
            selectionSource: .manual
        )
        let store = RecordingLibraryItemDetailStore(
            detail: makePersistedDetail(id: itemID),
            posterAssets: [poster]
        )
        let useCase = LibraryItemDetailUseCase(store: store)

        let result = try await useCase.fetchDetail(id: itemID)
        let detail = try XCTUnwrap(result)
        let selected = try XCTUnwrap(detail.selectedPoster.asset)

        XCTAssertEqual(detail.selectedPoster.localCachePath, "/cache/cached.jpg")
        XCTAssertEqual(detail.selectedPoster.statusLabel, "selected poster cached")
        XCTAssertEqual(detail.selectedPoster.placeholderSeed, "poster-cached")
        XCTAssertEqual(selected.id, "poster-cached")
        XCTAssertEqual(selected.sourceLabel, "TMDB")
        XCTAssertEqual(selected.dimensionsLabel, "500x750")
        XCTAssertEqual(selected.preferredCacheSizeLabel, "w500")
        XCTAssertEqual(selected.localCachePath, "/cache/cached.jpg")
        XCTAssertEqual(selected.cachedAtLabel, "1970-01-01T00:50:00Z")
        XCTAssertEqual(selected.selectionSourceLabel, "manual")
        XCTAssertEqual(selected.statusLabel, "cached")
    }

    func testSelectedUncachedPosterMapsUncachedStatus() async throws {
        let itemID = "uncached-poster"
        let poster = try posterAsset(
            id: "poster-uncached",
            mediaItemID: itemID,
            remotePath: "/uncached.jpg",
            isSelected: true
        )
        let store = RecordingLibraryItemDetailStore(
            detail: makePersistedDetail(id: itemID),
            posterAssets: [poster]
        )
        let useCase = LibraryItemDetailUseCase(store: store)

        let result = try await useCase.fetchDetail(id: itemID)
        let detail = try XCTUnwrap(result)
        let selected = try XCTUnwrap(detail.selectedPoster.asset)

        XCTAssertNil(detail.selectedPoster.localCachePath)
        XCTAssertEqual(detail.selectedPoster.statusLabel, "selected poster uncached")
        XCTAssertEqual(selected.statusLabel, "uncached")
    }

    func testNoSelectedPosterDoesNotAutoSelect() async throws {
        let itemID = "no-selected-poster"
        let poster = try posterAsset(
            id: "poster-unselected",
            mediaItemID: itemID,
            remotePath: "/unselected.jpg"
        )
        let store = RecordingLibraryItemDetailStore(
            detail: makePersistedDetail(id: itemID),
            posterAssets: [poster]
        )
        let useCase = LibraryItemDetailUseCase(store: store)

        let result = try await useCase.fetchDetail(id: itemID)
        let detail = try XCTUnwrap(result)

        XCTAssertEqual(detail.posterAssets.map(\.id), ["poster-unselected"])
        XCTAssertNil(detail.selectedPoster.asset)
        XCTAssertNil(detail.selectedPoster.localCachePath)
        XCTAssertEqual(detail.selectedPoster.statusLabel, "no poster")
        XCTAssertEqual(detail.selectedPoster.placeholderSeed, itemID)
    }

    func testMultiplePosterAssetsPreserveStoreOrderAndChooseSelectedPoster() async throws {
        let itemID = "poster-order"
        let first = try posterAsset(
            id: "poster-first",
            mediaItemID: itemID,
            remotePath: "/first.jpg"
        )
        let selected = try posterAsset(
            id: "poster-selected",
            mediaItemID: itemID,
            remotePath: "/selected.jpg",
            isSelected: true
        )
        let third = try posterAsset(
            id: "poster-third",
            mediaItemID: itemID,
            remotePath: "/third.jpg"
        )
        let store = RecordingLibraryItemDetailStore(
            detail: makePersistedDetail(id: itemID),
            posterAssets: [first, selected, third]
        )
        let useCase = LibraryItemDetailUseCase(store: store)

        let result = try await useCase.fetchDetail(id: itemID)
        let detail = try XCTUnwrap(result)

        XCTAssertEqual(
            detail.posterAssets.map(\.id),
            ["poster-first", "poster-selected", "poster-third"]
        )
        XCTAssertEqual(detail.selectedPoster.asset?.id, "poster-selected")
    }

    func testFilesMapIDsPlayabilityAndDisplayLabels() async throws {
        let itemID = "files"
        let files = [
            persistedMediaFileSummary(
                id: "file-playable",
                fileName: "Playable.mkv",
                fileExtension: "mkv",
                fileSizeBytes: 1536,
                isAvailable: true
            ),
            persistedMediaFileSummary(
                id: "file-unplayable",
                fileName: "Unplayable.mp4",
                fileExtension: "mp4",
                fileSizeBytes: 1024 * 1024,
                isAvailable: false
            )
        ]
        let store = RecordingLibraryItemDetailStore(
            detail: makePersistedDetail(id: itemID, files: files)
        )
        let useCase = LibraryItemDetailUseCase(store: store)

        let result = try await useCase.fetchDetail(id: itemID)
        let detail = try XCTUnwrap(result)

        XCTAssertEqual(detail.files.map(\.mediaFileID), ["file-playable", "file-unplayable"])
        XCTAssertEqual(detail.files.map(\.isPlayable), [true, false])
        XCTAssertEqual(detail.files.map(\.fileName), ["Playable.mkv", "Unplayable.mp4"])
        XCTAssertEqual(detail.files.map(\.fileExtension), ["mkv", "mp4"])
        XCTAssertEqual(detail.files.map(\.fileSizeLabel), ["1.5 KB", "1.0 MB"])
        XCTAssertEqual(detail.files.map(\.availabilityLabel), ["available", "unavailable"])
        XCTAssertEqual(
            detail.files.filter(\.isPlayable).map(\.mediaFileID),
            ["file-playable"]
        )
    }

    func testMissingMediaItemReturnsNilWithoutMetadataOrPosterReads() async throws {
        let store = RecordingLibraryItemDetailStore(detail: nil)
        let useCase = LibraryItemDetailUseCase(store: store)

        let detail = try await useCase.fetchDetail(id: "missing-media")

        XCTAssertNil(detail)
        XCTAssertEqual(store.calls, [.mediaDetail("missing-media")])
    }

    func testStoreFetchFailuresPropagate() async throws {
        let itemID = "failure"
        let cases: [(DetailStoreFailure, [LibraryItemDetailStoreCall])] = [
            (.mediaDetail, [.mediaDetail(itemID)]),
            (.metadataItem, [.mediaDetail(itemID), .metadataItem(itemID)]),
            (
                .metadataSource,
                [.mediaDetail(itemID), .metadataItem(itemID), .metadataSource(itemID, .tmdb)]
            ),
            (
                .posterAssets,
                [
                    .mediaDetail(itemID),
                    .metadataItem(itemID),
                    .metadataSource(itemID, .tmdb),
                    .posterAssets(itemID)
                ]
            )
        ]

        for (failure, expectedCalls) in cases {
            let store = RecordingLibraryItemDetailStore(
                detail: makePersistedDetail(id: itemID)
            )
            store.failures.insert(failure)
            let useCase = LibraryItemDetailUseCase(store: store)

            do {
                _ = try await useCase.fetchDetail(id: itemID)
                XCTFail("Expected \(failure).")
            } catch {
                XCTAssertEqual(error as? DetailStoreFailure, failure)
            }
            XCTAssertEqual(store.calls, expectedCalls)
        }
    }
}

final class LibraryItemDetailFileSizeLabelTests: XCTestCase {
    func testZeroBytes() {
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(0), "0 bytes")
    }

    func testBytesBelow1024() {
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(1), "1 bytes")
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(500), "500 bytes")
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(1023), "1023 bytes")
    }

    func testOneKB() {
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(1024), "1.0 KB")
    }

    func testKB() {
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(1536), "1.5 KB")
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(1024 * 1023), "1023.0 KB")
    }

    func testOneMB() {
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(1024 * 1024), "1.0 MB")
    }

    func testMB() {
        let oneMB: Int64 = 1024 * 1024
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(oneMB * 3 / 2), "1.5 MB")
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(oneMB * 100 + oneMB / 2), "100.5 MB")
    }

    func testOneGB() {
        let oneGB: Int64 = 1024 * 1024 * 1024
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(oneGB), "1.0 GB")
    }

    func testGB() {
        let oneGB: Int64 = 1024 * 1024 * 1024
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(oneGB * 2 + oneGB / 2), "2.5 GB")
    }

    func testDecimalSeparatorIsDot() {
        let oneMB: Int64 = 1024 * 1024
        let label = LibraryItemDetailUseCase.defaultFileSizeLabel(oneMB + oneMB / 2)
        XCTAssertTrue(label.contains("."), "decimal separator must be dot, got: \(label)")
        XCTAssertFalse(label.contains(","), "decimal separator must not be comma, got: \(label)")
    }

    func testExactBoundaries() {
        let oneKB: Int64 = 1024
        let oneMB: Int64 = 1024 * 1024
        let oneGB: Int64 = 1024 * 1024 * 1024

        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(oneKB - 1), "1023 bytes")
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(oneKB), "1.0 KB")
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(oneMB - oneKB), "1023.0 KB")
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(oneMB), "1.0 MB")
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(oneGB - oneMB), "1023.0 MB")
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(oneGB), "1.0 GB")
    }
}

private final class RecordingLibraryItemDetailStore: ApplicationLibraryItemDetailStore,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var recordedCalls: [LibraryItemDetailStoreCall] = []
    private let detail: PersistedMediaItemDetail?
    private let metadataItem: MetadataItem?
    private let sourceRecord: MetadataSourceRecord?
    private let posterAssets: [PosterAsset]
    var failures: Set<DetailStoreFailure> = []

    init(
        detail: PersistedMediaItemDetail?,
        metadataItem: MetadataItem? = nil,
        sourceRecord: MetadataSourceRecord? = nil,
        posterAssets: [PosterAsset] = []
    ) {
        self.detail = detail
        self.metadataItem = metadataItem
        self.sourceRecord = sourceRecord
        self.posterAssets = posterAssets
    }

    var calls: [LibraryItemDetailStoreCall] {
        withLock {
            recordedCalls
        }
    }

    func fetchMediaItemDetail(id: MediaItemID) throws -> PersistedMediaItemDetail? {
        try record(.mediaDetail(id), failingWith: .mediaDetail)
        return detail
    }

    func fetchMetadataItem(mediaItemID: MediaItemID) throws -> MetadataItem? {
        try record(.metadataItem(mediaItemID), failingWith: .metadataItem)
        return metadataItem
    }

    func fetchMetadataSourceRecord(
        mediaItemID: MediaItemID,
        provider: MetadataProviderName
    ) throws -> MetadataSourceRecord? {
        try record(.metadataSource(mediaItemID, provider), failingWith: .metadataSource)
        return sourceRecord
    }

    func fetchPosterAssets(mediaItemID: MediaItemID) throws -> [PosterAsset] {
        try record(.posterAssets(mediaItemID), failingWith: .posterAssets)
        return posterAssets
    }

    private func record(
        _ call: LibraryItemDetailStoreCall,
        failingWith failure: DetailStoreFailure
    ) throws {
        let shouldFail = withLock {
            recordedCalls.append(call)
            return failures.contains(failure)
        }
        if shouldFail {
            throw failure
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private enum LibraryItemDetailStoreCall: Equatable {
    case mediaDetail(MediaItemID)
    case metadataItem(MediaItemID)
    case metadataSource(MediaItemID, MetadataProviderName)
    case posterAssets(MediaItemID)
}

private enum DetailStoreFailure: Error, Equatable, Hashable {
    case mediaDetail
    case metadataItem
    case metadataSource
    case posterAssets
}

private func makePersistedDetail(
    id: MediaItemID,
    title: String = "Arrival",
    mediaType: MediaType = .movie,
    year: Int? = 2016,
    files: [PersistedMediaFileSummary] = []
) -> PersistedMediaItemDetail {
    PersistedMediaItemDetail(
        id: id,
        mediaType: mediaType,
        title: title,
        year: year,
        seriesTitle: nil,
        seasonNumber: nil,
        episodeNumber: nil,
        episodeTitle: nil,
        summary: nil,
        language: nil,
        hasMetadataItem: false,
        hasMetadataSourceRecord: false,
        latestPlayedAt: nil,
        files: files
    )
}

private func persistedMediaFileSummary(
    id: MediaFileID,
    fileName: String,
    fileExtension: String,
    fileSizeBytes: Int64,
    isAvailable: Bool
) -> PersistedMediaFileSummary {
    PersistedMediaFileSummary(
        id: id,
        fileName: fileName,
        fileExtension: fileExtension,
        fileSizeBytes: fileSizeBytes,
        relativePath: fileName,
        isAvailable: isAvailable,
        folderDisplayName: "Movies",
        folderIsAvailable: true
    )
}

private func metadataSourceRecord(
    mediaItemID: MediaItemID,
    providerID: String = "movie:550",
    confidence: Double = 0.9,
    matchSource: MetadataMatchSource = .automatic,
    manualMatchLocked: Bool = false,
    matchedAt: Date = Date(timeIntervalSince1970: 1_000),
    refreshedAt: Date? = nil
) throws -> MetadataSourceRecord {
    try MetadataSourceRecord.validated(
        mediaItemID: mediaItemID,
        provider: .tmdb,
        providerID: providerID,
        providerMediaType: .movie,
        confidence: confidence,
        matchSource: matchSource,
        manualMatchLocked: manualMatchLocked,
        matchedAt: matchedAt,
        refreshedAt: refreshedAt,
        createdAt: matchedAt,
        updatedAt: refreshedAt ?? matchedAt
    )
}

private func posterAsset(
    id: PosterAssetID,
    mediaItemID: MediaItemID,
    remotePath: String,
    width: Int? = nil,
    height: Int? = nil,
    localCachePath: String? = nil,
    cachedAt: Date? = nil,
    isSelected: Bool = false,
    selectionSource: PosterSelectionSource = .automatic
) throws -> PosterAsset {
    try PosterAsset.validated(
        id: id,
        mediaItemID: mediaItemID,
        assetType: .poster,
        source: .tmdb,
        remotePath: remotePath,
        width: width,
        height: height,
        preferredCacheSize: "w500",
        localCachePath: localCachePath,
        cachedAt: cachedAt,
        isSelected: isSelected,
        selectionSource: selectionSource,
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 1_000)
    )
}
