import Domain
import Foundation
import Persistence

public struct LibraryFileSummary: Sendable, Equatable {
    public let mediaFileID: MediaFileID
    public let isPlayable: Bool
    public let playabilityReason: String?
    public let resumePositionLabel: String?
    public let fileName: String
    public let fileExtension: String
    public let fileSizeLabel: String
    public let availabilityLabel: String
}

private let avFoundationPlayableExtensions: Set<String> = ["mp4", "mov", "m4v"]

private func isAVFoundationPlayable(fileExtension: String) -> Bool {
    let normalized = fileExtension
        .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        .lowercased()
    return avFoundationPlayableExtensions.contains(normalized)
}

public struct LibraryMetadataDetail: Sendable, Equatable {
    public let statusLabel: String
    public let localTitle: String
    public let metadataTitle: String?
    public let originalTitle: String?
    public let summary: String?
    public let languageLabel: String?
    public let releaseOrAirDateLabel: String?
    public let titleOverrideLocked: Bool
    public let summaryOverrideLocked: Bool
    public let languageOverrideLocked: Bool
    public let source: LibraryMetadataSourceDetail?
}

public struct LibraryMetadataSourceDetail: Sendable, Equatable {
    public let providerLabel: String
    public let providerID: String
    public let providerMediaTypeLabel: String
    public let confidenceLabel: String
    public let matchSourceLabel: String
    public let manualMatchLockLabel: String
    public let matchedAtLabel: String
    public let refreshedAtLabel: String?
}

public struct LibraryPosterAssetDetail: Identifiable, Sendable, Equatable {
    public let id: PosterAssetID
    public let isSelected: Bool
    public let sourceLabel: String
    public let remotePath: String
    public let dimensionsLabel: String?
    public let preferredCacheSizeLabel: String
    public let localCachePath: String?
    public let cachedAtLabel: String?
    public let selectionSourceLabel: String
    public let statusLabel: String
}

public struct LibrarySelectedPosterDetail: Sendable, Equatable {
    public let asset: LibraryPosterAssetDetail?
    public let localCachePath: String?
    public let statusLabel: String
    public let placeholderSeed: String
}

public struct LibraryItemDetailShell: Identifiable, Sendable, Equatable {
    public let id: MediaItemID
    public let displayTitle: String
    public let mediaTypeLabel: String
    public let yearOrEpisodeLabel: String?
    public let summary: String?
    public let availabilityLabel: String
    public let metadataLabel: String
    public let lastPlayedLabel: String?
    public let files: [LibraryFileSummary]
    public let curation: LibraryItemCurationDetail
    public let metadataDetail: LibraryMetadataDetail
    public let selectedPoster: LibrarySelectedPosterDetail
    public let posterAssets: [LibraryPosterAssetDetail]
}

public protocol LibraryItemDetailBrowsing: Sendable {
    func fetchDetail(id: MediaItemID) async throws -> LibraryItemDetailShell?
}

public protocol ApplicationLibraryItemDetailStore: Sendable {
    func fetchMediaItemDetail(id: MediaItemID) throws -> PersistedMediaItemDetail?
    func fetchMetadataItem(mediaItemID: MediaItemID) throws -> MetadataItem?
    func fetchMetadataSourceRecord(
        mediaItemID: MediaItemID,
        provider: MetadataProviderName
    ) throws -> MetadataSourceRecord?
    func fetchPosterAssets(mediaItemID: MediaItemID) throws -> [PosterAsset]
    func fetchMediaItemCuration(mediaItemID: MediaItemID) throws -> PersistedMediaItemCuration
}

extension CineMindStore: ApplicationLibraryItemDetailStore {}

public struct LibraryItemDetailUseCase: LibraryItemDetailBrowsing, Sendable {
    private let store: any ApplicationLibraryItemDetailStore
    private let queue: DispatchQueue
    private let lastPlayedLabel: @Sendable (Date) -> String
    private let fileSizeLabel: @Sendable (Int64) -> String

    public init(
        store: any ApplicationLibraryItemDetailStore,
        queueLabel: String = "CineMind.LibraryItemDetailUseCase"
    ) {
        self.init(
            store: store,
            queueLabel: queueLabel,
            lastPlayedLabel: Self.defaultLastPlayedLabel,
            fileSizeLabel: Self.defaultFileSizeLabel
        )
    }

    public init(
        store: any ApplicationLibraryItemDetailStore,
        queueLabel: String = "CineMind.LibraryItemDetailUseCase",
        lastPlayedLabel: @escaping @Sendable (Date) -> String,
        fileSizeLabel: @escaping @Sendable (Int64) -> String
    ) {
        self.store = store
        self.queue = DispatchQueue(label: queueLabel)
        self.lastPlayedLabel = lastPlayedLabel
        self.fileSizeLabel = fileSizeLabel
    }

    public func fetchDetail(id: MediaItemID) async throws -> LibraryItemDetailShell? {
        let persisted = try await fetchPersistedDetail(id: id)
        return persisted.map(map)
    }

    private func fetchPersistedDetail(
        id: MediaItemID
    ) async throws -> PersistedLibraryItemDetail? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard let detail = try store.fetchMediaItemDetail(id: id) else {
                        continuation.resume(returning: nil)
                        return
                    }

                    let metadataItem = try store.fetchMetadataItem(mediaItemID: detail.id)
                    let sourceRecord = try store.fetchMetadataSourceRecord(
                        mediaItemID: detail.id,
                        provider: .tmdb
                    )
                    let posterAssets = try store.fetchPosterAssets(mediaItemID: detail.id)
                    let curation = try store.fetchMediaItemCuration(mediaItemID: detail.id)
                    continuation.resume(
                        returning: PersistedLibraryItemDetail(
                            detail: detail,
                            metadataItem: metadataItem,
                            sourceRecord: sourceRecord,
                            posterAssets: posterAssets,
                            curation: curation
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func map(_ persisted: PersistedLibraryItemDetail) -> LibraryItemDetailShell {
        let detail = persisted.detail
        let metadataDetail = mapMetadataDetail(
            detail: detail,
            metadataItem: persisted.metadataItem,
            sourceRecord: persisted.sourceRecord
        )
        let posterAssets = persisted.posterAssets.map(mapPosterAsset)
        return LibraryItemDetailShell(
            id: detail.id,
            displayTitle: displayTitle(for: detail),
            mediaTypeLabel: mediaTypeLabel(for: detail.mediaType),
            yearOrEpisodeLabel: yearOrEpisodeLabel(for: detail),
            summary: detail.summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            availabilityLabel: availabilityLabel(for: detail.files),
            metadataLabel: metadataDetail.statusLabel,
            lastPlayedLabel: detail.latestPlayedAt.map(lastPlayedLabel),
            files: detail.files.map(mapFile),
            curation: mapItemCuration(persisted.curation),
            metadataDetail: metadataDetail,
            selectedPoster: selectedPoster(
                mediaItemID: detail.id,
                posterAssets: persisted.posterAssets,
                posterAssetDetails: posterAssets
            ),
            posterAssets: posterAssets
        )
    }

    private func mapFile(_ file: PersistedMediaFileSummary) -> LibraryFileSummary {
        let playable = file.isAvailable
            && isAVFoundationPlayable(fileExtension: file.fileExtension)
        let resumeLabel: String? = {
            guard let ps = file.playbackSummary else { return nil }
            guard let positionMS = PlaybackResumePolicy.resumePositionMS(
                positionMS: ps.positionMS,
                durationMS: ps.durationMS,
                completed: ps.completed
            ) else { return nil }
            return Self.resumeTimeLabel(positionMS)
        }()
        return LibraryFileSummary(
            mediaFileID: file.id,
            isPlayable: playable,
            playabilityReason: playabilityReason(for: file, isPlayable: playable),
            resumePositionLabel: resumeLabel,
            fileName: file.fileName,
            fileExtension: file.fileExtension,
            fileSizeLabel: fileSizeLabel(file.fileSizeBytes),
            availabilityLabel: fileAvailabilityLabel(for: file)
        )
    }

    private func playabilityReason(
        for file: PersistedMediaFileSummary,
        isPlayable: Bool
    ) -> String? {
        if isPlayable { return nil }
        if file.folderIsAvailable == false { return "Folder unavailable" }
        if !file.isAvailable { return "File is unavailable" }
        return "Unsupported format for built-in player"
    }

    private func displayTitle(for detail: PersistedMediaItemDetail) -> String {
        let persistedTitle = detail.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !persistedTitle.isEmpty {
            return persistedTitle
        }

        let episodeTitle = detail.episodeTitle?
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

    private func yearOrEpisodeLabel(for detail: PersistedMediaItemDetail) -> String? {
        switch detail.mediaType {
        case .movie:
            return detail.year.map(String.init)
        case .episode:
            guard let seasonNumber = detail.seasonNumber,
                  let episodeNumber = detail.episodeNumber else {
                return nil
            }

            let episodeCode = String(format: "S%02dE%02d", seasonNumber, episodeNumber)
            let episodeTitle = detail.episodeTitle?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let episodeTitle, !episodeTitle.isEmpty else {
                return episodeCode
            }
            return "\(episodeCode) - \(episodeTitle)"
        }
    }

    private func availabilityLabel(for files: [PersistedMediaFileSummary]) -> String {
        if files.isEmpty {
            return "no files"
        }
        let availableCount = files.filter(\.isAvailable).count
        if availableCount == files.count {
            return "available"
        }
        if availableCount <= 0 {
            return "unavailable"
        }
        return "partially available"
    }

    private func mapMetadataDetail(
        detail: PersistedMediaItemDetail,
        metadataItem: MetadataItem?,
        sourceRecord: MetadataSourceRecord?
    ) -> LibraryMetadataDetail {
        LibraryMetadataDetail(
            statusLabel: metadataLabel(
                metadataItem: metadataItem,
                sourceRecord: sourceRecord
            ),
            localTitle: displayTitle(for: detail),
            metadataTitle: trimmedLabel(metadataItem?.title),
            originalTitle: trimmedLabel(metadataItem?.originalTitle),
            summary: trimmedLabel(metadataItem?.summary),
            languageLabel: trimmedLabel(metadataItem?.language),
            releaseOrAirDateLabel: releaseOrAirDateLabel(for: metadataItem),
            titleOverrideLocked: metadataItem?.titleOverrideLocked ?? false,
            summaryOverrideLocked: metadataItem?.summaryOverrideLocked ?? false,
            languageOverrideLocked: metadataItem?.languageOverrideLocked ?? false,
            source: sourceRecord.map(mapMetadataSource)
        )
    }

    private func mapMetadataSource(
        _ sourceRecord: MetadataSourceRecord
    ) -> LibraryMetadataSourceDetail {
        LibraryMetadataSourceDetail(
            providerLabel: providerLabel(for: sourceRecord.provider),
            providerID: sourceRecord.providerID,
            providerMediaTypeLabel: providerMediaTypeLabel(for: sourceRecord.providerMediaType),
            confidenceLabel: confidenceLabel(for: sourceRecord.confidence),
            matchSourceLabel: matchSourceLabel(for: sourceRecord.matchSource),
            manualMatchLockLabel: sourceRecord.manualMatchLocked ? "manual lock" : "unlocked",
            matchedAtLabel: dateLabel(sourceRecord.matchedAt),
            refreshedAtLabel: sourceRecord.refreshedAt.map(dateLabel)
        )
    }

    private func mapPosterAsset(_ asset: PosterAsset) -> LibraryPosterAssetDetail {
        let localCachePath = trimmedLabel(asset.localCachePath)
        return LibraryPosterAssetDetail(
            id: asset.id,
            isSelected: asset.isSelected,
            sourceLabel: posterSourceLabel(for: asset.source),
            remotePath: asset.remotePath,
            dimensionsLabel: dimensionsLabel(width: asset.width, height: asset.height),
            preferredCacheSizeLabel: asset.preferredCacheSize,
            localCachePath: localCachePath,
            cachedAtLabel: asset.cachedAt.map(dateLabel),
            selectionSourceLabel: selectionSourceLabel(for: asset.selectionSource),
            statusLabel: localCachePath == nil ? "uncached" : "cached"
        )
    }

    private func selectedPoster(
        mediaItemID: MediaItemID,
        posterAssets: [PosterAsset],
        posterAssetDetails: [LibraryPosterAssetDetail]
    ) -> LibrarySelectedPosterDetail {
        guard let selectedIndex = posterAssets.firstIndex(where: {
            $0.assetType == .poster && $0.isSelected
        }) else {
            return LibrarySelectedPosterDetail(
                asset: nil,
                localCachePath: nil,
                statusLabel: "no poster",
                placeholderSeed: mediaItemID
            )
        }

        let asset = posterAssetDetails[selectedIndex]
        return LibrarySelectedPosterDetail(
            asset: asset,
            localCachePath: asset.localCachePath,
            statusLabel: asset.localCachePath == nil
                ? "selected poster uncached"
                : "selected poster cached",
            placeholderSeed: asset.id
        )
    }

    private func metadataLabel(
        metadataItem: MetadataItem?,
        sourceRecord: MetadataSourceRecord?
    ) -> String {
        switch (metadataItem != nil, sourceRecord != nil) {
        case (true, true):
            "complete"
        case (true, false), (false, true):
            "partial"
        case (false, false):
            "missing"
        }
    }

    private func releaseOrAirDateLabel(for metadataItem: MetadataItem?) -> String? {
        trimmedLabel(metadataItem?.releaseDate) ?? trimmedLabel(metadataItem?.airDate)
    }

    private func providerLabel(for provider: MetadataProviderName) -> String {
        provider.rawValue.uppercased()
    }

    private func providerMediaTypeLabel(for mediaType: MetadataProviderMediaType) -> String {
        switch mediaType {
        case .movie:
            "Movie"
        case .episode:
            "TV Episode"
        }
    }

    private func confidenceLabel(for confidence: Double) -> String {
        "\(Int((confidence * 100.0).rounded()))%"
    }

    private func matchSourceLabel(for matchSource: MetadataMatchSource) -> String {
        switch matchSource {
        case .automatic:
            "automatic"
        case .manual:
            "manual"
        }
    }

    private func posterSourceLabel(for source: PosterAssetSource) -> String {
        source.rawValue.uppercased()
    }

    private func dimensionsLabel(width: Int?, height: Int?) -> String? {
        guard let width, let height else {
            return nil
        }
        return "\(width)x\(height)"
    }

    private func selectionSourceLabel(for selectionSource: PosterSelectionSource) -> String {
        switch selectionSource {
        case .automatic:
            "automatic"
        case .manual:
            "manual"
        }
    }

    private func dateLabel(_ date: Date) -> String {
        Self.defaultLastPlayedLabel(date)
    }

    private func trimmedLabel(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private func fileAvailabilityLabel(for file: PersistedMediaFileSummary) -> String {
        if file.folderIsAvailable == false {
            return "folder unavailable"
        }
        if file.isAvailable {
            return "available"
        }
        return "unavailable"
    }

    public static func defaultLastPlayedLabel(_ date: Date) -> String {
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

    public static func defaultFileSizeLabel(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes) bytes"
        }
        let kb = Double(bytes) / 1024.0
        if kb < 1024.0 {
            return String(format: "%.1f KB", kb)
        }
        let mb = kb / 1024.0
        if mb < 1024.0 {
            return String(format: "%.1f MB", mb)
        }
        let gb = mb / 1024.0
        return String(format: "%.1f GB", gb)
    }

    public static func resumeTimeLabel(_ positionMS: Int) -> String {
        let totalSeconds = positionMS / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct PersistedLibraryItemDetail {
    let detail: PersistedMediaItemDetail
    let metadataItem: MetadataItem?
    let sourceRecord: MetadataSourceRecord?
    let posterAssets: [PosterAsset]
    let curation: PersistedMediaItemCuration
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
