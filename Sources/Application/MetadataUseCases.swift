import Domain
import Foundation
import Metadata
import Persistence

public enum ApplicationMetadataError: Error, Sendable, Equatable {
    case mediaItemNotFound(MediaItemID)
    case missingEpisodeInfo(MediaItemID)
    case invalidProviderID(String)
    case providerMismatch(
        mediaItemID: MediaItemID,
        expected: MetadataProviderName,
        actual: MetadataProviderName
    )
    case providerMediaTypeMismatch(mediaItemID: MediaItemID, providerID: String)
    case episodeProviderIDMismatch(
        mediaItemID: MediaItemID,
        expectedSeason: Int,
        expectedEpisode: Int,
        providerID: String
    )
}

public enum AutoMatchMetadataResult: Equatable, Sendable {
    case matched(MetadataCandidate)
    case skippedManualLock
    case noCandidates
    case lowConfidence
    case ambiguous
}

public enum RefreshMetadataResult: Equatable, Sendable {
    case autoMatched(AutoMatchMetadataResult)
    case refreshed(MetadataSourceRecord)
}

public protocol ApplicationMetadataStore {
    func fetchMediaItem(id: MediaItemID) throws -> MediaItem?
    func fetchMetadataItem(mediaItemID: MediaItemID) throws -> MetadataItem?
    func saveMetadataItem(_ item: MetadataItem) throws
    func upsertMetadataExternalIDs(_ externalIDs: [MetadataExternalID]) throws
    func fetchMetadataSourceRecord(
        mediaItemID: MediaItemID,
        provider: MetadataProviderName
    ) throws -> MetadataSourceRecord?
    func saveMetadataSourceRecord(_ record: MetadataSourceRecord) throws
    func fetchPosterAssets(mediaItemID: MediaItemID) throws -> [PosterAsset]
    func savePosterAsset(_ asset: PosterAsset) throws
    func withTransaction<T>(_ body: () throws -> T) throws -> T
}

extension CineMindStore: ApplicationMetadataStore {}

public struct SearchMetadataCandidatesUseCase {
    private let store: any ApplicationMetadataStore
    private let provider: any MetadataProvider

    public init(
        store: any ApplicationMetadataStore,
        provider: any MetadataProvider
    ) {
        self.store = store
        self.provider = provider
    }

    public func search(
        mediaItemID: MediaItemID,
        language: String? = nil
    ) async throws -> [MetadataCandidate] {
        let mediaItem = try fetchMediaItem(mediaItemID)
        let query = try MetadataApplicationMapper.searchQuery(
            for: mediaItem,
            language: language
        )
        return try await provider.search(query: query)
    }

    private func fetchMediaItem(_ mediaItemID: MediaItemID) throws -> MediaItem {
        guard let mediaItem = try store.fetchMediaItem(id: mediaItemID) else {
            throw ApplicationMetadataError.mediaItemNotFound(mediaItemID)
        }
        return mediaItem
    }
}

public struct AutoMatchMetadataUseCase {
    private let store: any ApplicationMetadataStore
    private let provider: any MetadataProvider
    private let policy: MetadataAutoMatchPolicy
    private let now: () -> Date

    public init(
        store: any ApplicationMetadataStore,
        provider: any MetadataProvider,
        policy: MetadataAutoMatchPolicy = MetadataAutoMatchPolicy(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.provider = provider
        self.policy = policy
        self.now = now
    }

    public func match(
        mediaItemID: MediaItemID,
        language: String? = nil
    ) async throws -> AutoMatchMetadataResult {
        let mediaItem = try fetchMediaItem(mediaItemID)
        let existingSource = try store.fetchMetadataSourceRecord(
            mediaItemID: mediaItem.id,
            provider: provider.providerName
        )

        if existingSource?.manualMatchLocked == true {
            return .skippedManualLock
        }

        let query = try MetadataApplicationMapper.searchQuery(
            for: mediaItem,
            language: language
        )
        let candidates = try await provider.search(query: query)

        switch policy.decision(for: candidates) {
        case .matched(let candidate):
            try MetadataApplicationMapper.validate(
                candidate.identifier,
                matches: mediaItem
            )
            let details = try await provider.fetchDetails(identifier: candidate.identifier)
            let images = try await provider.fetchImages(identifier: candidate.identifier)

            _ = try MetadataMatchWriter(
                store: store,
                providerName: provider.providerName,
                now: now
            ).write(
                mediaItem: mediaItem,
                details: details,
                images: images,
                confidence: candidate.confidence,
                matchSource: .automatic,
                manualMatchLocked: false
            )
            return .matched(candidate)
        case .noCandidates:
            return .noCandidates
        case .lowConfidence:
            return .lowConfidence
        case .ambiguous:
            return .ambiguous
        }
    }

    private func fetchMediaItem(_ mediaItemID: MediaItemID) throws -> MediaItem {
        guard let mediaItem = try store.fetchMediaItem(id: mediaItemID) else {
            throw ApplicationMetadataError.mediaItemNotFound(mediaItemID)
        }
        return mediaItem
    }
}

public struct RefreshMetadataUseCase {
    private let store: any ApplicationMetadataStore
    private let provider: any MetadataProvider
    private let policy: MetadataAutoMatchPolicy
    private let now: () -> Date

    public init(
        store: any ApplicationMetadataStore,
        provider: any MetadataProvider,
        policy: MetadataAutoMatchPolicy = MetadataAutoMatchPolicy(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.provider = provider
        self.policy = policy
        self.now = now
    }

    public func refresh(
        mediaItemID: MediaItemID,
        language: String? = nil
    ) async throws -> RefreshMetadataResult {
        let mediaItem = try fetchMediaItem(mediaItemID)
        guard let source = try store.fetchMetadataSourceRecord(
            mediaItemID: mediaItem.id,
            provider: provider.providerName
        ) else {
            let result = try await AutoMatchMetadataUseCase(
                store: store,
                provider: provider,
                policy: policy,
                now: now
            ).match(mediaItemID: mediaItem.id, language: language)
            return .autoMatched(result)
        }

        guard source.provider == provider.providerName else {
            throw ApplicationMetadataError.providerMismatch(
                mediaItemID: mediaItem.id,
                expected: provider.providerName,
                actual: source.provider
            )
        }
        guard let identifier = MetadataProviderIdentifier(rawValue: source.providerID) else {
            throw ApplicationMetadataError.invalidProviderID(source.providerID)
        }
        try MetadataApplicationMapper.validate(identifier, matches: mediaItem)

        let details = try await provider.fetchDetails(identifier: identifier)
        let images = try await provider.fetchImages(identifier: identifier)

        let refreshedSource = try MetadataMatchWriter(
            store: store,
            providerName: provider.providerName,
            now: now
        ).refresh(
            mediaItem: mediaItem,
            source: source,
            details: details,
            images: images
        )
        return .refreshed(refreshedSource)
    }

    private func fetchMediaItem(_ mediaItemID: MediaItemID) throws -> MediaItem {
        guard let mediaItem = try store.fetchMediaItem(id: mediaItemID) else {
            throw ApplicationMetadataError.mediaItemNotFound(mediaItemID)
        }
        return mediaItem
    }
}

public struct ManualMatchMetadataUseCase {
    private let store: any ApplicationMetadataStore
    private let provider: any MetadataProvider
    private let now: () -> Date

    public init(
        store: any ApplicationMetadataStore,
        provider: any MetadataProvider,
        now: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.provider = provider
        self.now = now
    }

    public func match(
        mediaItemID: MediaItemID,
        providerID: String,
        language: String? = nil
    ) async throws -> MetadataSourceRecord {
        _ = language
        let mediaItem = try fetchMediaItem(mediaItemID)
        guard let identifier = MetadataProviderIdentifier(rawValue: providerID) else {
            throw ApplicationMetadataError.invalidProviderID(providerID)
        }

        try MetadataApplicationMapper.validate(identifier, matches: mediaItem)

        let details = try await provider.fetchDetails(identifier: identifier)
        let images = try await provider.fetchImages(identifier: identifier)

        return try MetadataMatchWriter(
            store: store,
            providerName: provider.providerName,
            now: now
        ).write(
            mediaItem: mediaItem,
            details: details,
            images: images,
            confidence: 1.0,
            matchSource: .manual,
            manualMatchLocked: true
        )
    }

    private func fetchMediaItem(_ mediaItemID: MediaItemID) throws -> MediaItem {
        guard let mediaItem = try store.fetchMediaItem(id: mediaItemID) else {
            throw ApplicationMetadataError.mediaItemNotFound(mediaItemID)
        }
        return mediaItem
    }
}

private enum MetadataApplicationMapper {
    static func searchQuery(
        for mediaItem: MediaItem,
        language: String?
    ) throws -> MetadataSearchQuery {
        switch mediaItem.mediaType {
        case .movie:
            return .movie(
                mediaItemID: mediaItem.id,
                title: mediaItem.title,
                year: mediaItem.year,
                language: language
            )
        case .episode:
            guard let episodeInfo = mediaItem.episodeInfo else {
                throw ApplicationMetadataError.missingEpisodeInfo(mediaItem.id)
            }
            return .episode(
                mediaItemID: mediaItem.id,
                seriesTitle: episodeInfo.seriesTitle,
                seasonNumber: episodeInfo.seasonNumber,
                episodeNumber: episodeInfo.episodeNumber,
                episodeTitle: episodeInfo.episodeTitle,
                language: language
            )
        }
    }

    static func validate(
        _ identifier: MetadataProviderIdentifier,
        matches mediaItem: MediaItem
    ) throws {
        switch mediaItem.mediaType {
        case .movie:
            guard identifier.kind == .movie else {
                throw ApplicationMetadataError.providerMediaTypeMismatch(
                    mediaItemID: mediaItem.id,
                    providerID: identifier.rawValue
                )
            }
        case .episode:
            guard identifier.kind == .episode else {
                throw ApplicationMetadataError.providerMediaTypeMismatch(
                    mediaItemID: mediaItem.id,
                    providerID: identifier.rawValue
                )
            }
            guard let episodeInfo = mediaItem.episodeInfo else {
                throw ApplicationMetadataError.missingEpisodeInfo(mediaItem.id)
            }
            guard identifier.seasonNumber == episodeInfo.seasonNumber,
                  identifier.episodeNumber == episodeInfo.episodeNumber else {
                throw ApplicationMetadataError.episodeProviderIDMismatch(
                    mediaItemID: mediaItem.id,
                    expectedSeason: episodeInfo.seasonNumber,
                    expectedEpisode: episodeInfo.episodeNumber,
                    providerID: identifier.rawValue
                )
            }
        }
    }
}

private struct MetadataMatchWriter {
    let store: any ApplicationMetadataStore
    let providerName: MetadataProviderName
    let now: () -> Date

    func write(
        mediaItem: MediaItem,
        details: MetadataDetails,
        images: [RemoteImage],
        confidence: Double,
        matchSource: MetadataMatchSource,
        manualMatchLocked: Bool
    ) throws -> MetadataSourceRecord {
        try write(
            mediaItem: mediaItem,
            details: details,
            images: images,
            sourceUpdate: .match(
                confidence: confidence,
                matchSource: matchSource,
                manualMatchLocked: manualMatchLocked
            )
        )
    }

    func refresh(
        mediaItem: MediaItem,
        source: MetadataSourceRecord,
        details: MetadataDetails,
        images: [RemoteImage]
    ) throws -> MetadataSourceRecord {
        guard source.provider == providerName else {
            throw ApplicationMetadataError.providerMismatch(
                mediaItemID: mediaItem.id,
                expected: providerName,
                actual: source.provider
            )
        }
        return try write(
            mediaItem: mediaItem,
            details: details,
            images: images,
            sourceUpdate: .refresh(source)
        )
    }

    private func write(
        mediaItem: MediaItem,
        details: MetadataDetails,
        images: [RemoteImage],
        sourceUpdate: SourceUpdate
    ) throws -> MetadataSourceRecord {
        try MetadataApplicationMapper.validate(details.identifier, matches: mediaItem)

        return try store.withTransaction {
            let writtenAt = now()
            let existingMetadata = try store.fetchMetadataItem(mediaItemID: mediaItem.id)
            let existingSource = try store.fetchMetadataSourceRecord(
                mediaItemID: mediaItem.id,
                provider: providerName
            )
            let existingPosters = try store.fetchPosterAssets(mediaItemID: mediaItem.id)

            let metadataItem = metadataItem(
                mediaItemID: mediaItem.id,
                details: details,
                existing: existingMetadata,
                writtenAt: writtenAt
            )
            try store.saveMetadataItem(metadataItem)

            let externalIDs = try details.externalIDs.map { externalIDType, value in
                try MetadataExternalID.validated(
                    mediaItemID: mediaItem.id,
                    provider: providerName,
                    externalIDType: externalIDType,
                    externalIDValue: value,
                    createdAt: writtenAt,
                    updatedAt: writtenAt
                )
            }
            if !externalIDs.isEmpty {
                try store.upsertMetadataExternalIDs(externalIDs)
            }

            let sourceRecord = try sourceRecord(
                mediaItemID: mediaItem.id,
                details: details,
                existing: existingSource,
                sourceUpdate: sourceUpdate,
                writtenAt: writtenAt
            )
            try store.saveMetadataSourceRecord(sourceRecord)

            let posterByIdentity = Dictionary(
                uniqueKeysWithValues: existingPosters.map { poster in
                    (PosterIdentity(poster), poster)
                }
            )
            for image in images {
                let poster = try posterAsset(
                    mediaItemID: mediaItem.id,
                    image: image,
                    existing: posterByIdentity[PosterIdentity(image)],
                    writtenAt: writtenAt
                )
                try store.savePosterAsset(poster)
            }

            return sourceRecord
        }
    }

    private enum SourceUpdate {
        case match(
            confidence: Double,
            matchSource: MetadataMatchSource,
            manualMatchLocked: Bool
        )
        case refresh(MetadataSourceRecord)
    }

    private func metadataItem(
        mediaItemID: MediaItemID,
        details: MetadataDetails,
        existing: MetadataItem?,
        writtenAt: Date
    ) -> MetadataItem {
        let titleLocked = existing?.titleOverrideLocked ?? false
        let summaryLocked = existing?.summaryOverrideLocked ?? false
        let languageLocked = existing?.languageOverrideLocked ?? false

        return MetadataItem(
            id: existing?.id ?? DomainID.new(),
            mediaItemID: mediaItemID,
            title: titleLocked ? existing?.title : details.title,
            originalTitle: details.originalTitle,
            summary: summaryLocked ? existing?.summary : details.summary,
            language: languageLocked ? existing?.language : details.language,
            releaseDate: details.releaseDate,
            airDate: details.airDate,
            titleOverrideLocked: titleLocked,
            summaryOverrideLocked: summaryLocked,
            languageOverrideLocked: languageLocked,
            createdAt: existing?.createdAt ?? writtenAt,
            updatedAt: writtenAt
        )
    }

    private func sourceRecord(
        mediaItemID: MediaItemID,
        details: MetadataDetails,
        existing: MetadataSourceRecord?,
        sourceUpdate: SourceUpdate,
        writtenAt: Date
    ) throws -> MetadataSourceRecord {
        switch sourceUpdate {
        case .match(let confidence, let matchSource, let manualMatchLocked):
            return try MetadataSourceRecord.validated(
                id: existing?.id ?? DomainID.new(),
                mediaItemID: mediaItemID,
                provider: providerName,
                providerID: details.identifier.rawValue,
                providerMediaType: details.providerMediaType,
                confidence: confidence,
                matchSource: matchSource,
                manualMatchLocked: manualMatchLocked,
                rawPayloadJSON: details.rawPayloadJSON,
                matchedAt: writtenAt,
                refreshedAt: writtenAt,
                createdAt: existing?.createdAt ?? writtenAt,
                updatedAt: writtenAt
            )
        case .refresh(let source):
            return try MetadataSourceRecord.validated(
                id: source.id,
                mediaItemID: mediaItemID,
                provider: source.provider,
                providerID: source.providerID,
                providerMediaType: source.providerMediaType,
                confidence: source.confidence,
                matchSource: source.matchSource,
                manualMatchLocked: source.manualMatchLocked,
                rawPayloadJSON: details.rawPayloadJSON,
                matchedAt: source.matchedAt,
                refreshedAt: writtenAt,
                createdAt: source.createdAt,
                updatedAt: writtenAt
            )
        }
    }

    private func posterAsset(
        mediaItemID: MediaItemID,
        image: RemoteImage,
        existing: PosterAsset?,
        writtenAt: Date
    ) throws -> PosterAsset {
        try PosterAsset.validated(
            id: existing?.id ?? DomainID.new(),
            mediaItemID: mediaItemID,
            assetType: .poster,
            source: image.source,
            remotePath: image.remotePath,
            width: image.width,
            height: image.height,
            preferredCacheSize: image.preferredCacheSize,
            localCachePath: existing?.localCachePath,
            cachedAt: existing?.cachedAt,
            isSelected: existing?.isSelected ?? false,
            selectionSource: existing?.selectionSource ?? .automatic,
            createdAt: existing?.createdAt ?? writtenAt,
            updatedAt: writtenAt
        )
    }
}

private struct PosterIdentity: Hashable {
    let assetType: PosterAssetType
    let source: PosterAssetSource
    let remotePath: String

    init(_ asset: PosterAsset) {
        self.assetType = asset.assetType
        self.source = asset.source
        self.remotePath = asset.remotePath
    }

    init(_ image: RemoteImage) {
        self.assetType = .poster
        self.source = image.source
        self.remotePath = image.remotePath
    }
}
