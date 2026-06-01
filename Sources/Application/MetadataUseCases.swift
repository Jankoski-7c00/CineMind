import Domain
import Foundation
import Metadata
import Persistence

public enum ApplicationMetadataError: Error, Sendable, Equatable {
    case mediaItemNotFound(MediaItemID)
    case posterAssetMediaItemMismatch(mediaItemID: MediaItemID, posterAssetID: PosterAssetID)
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

public struct RefreshLibraryMetadataResult: Equatable, Sendable {
    public var refreshed: Int
    public var skipped: Int
    public var unmatched: Int
    public var failed: Int

    public init(
        refreshed: Int = 0,
        skipped: Int = 0,
        unmatched: Int = 0,
        failed: Int = 0
    ) {
        self.refreshed = refreshed
        self.skipped = skipped
        self.unmatched = unmatched
        self.failed = failed
    }
}

public enum MetadataOverrideField: Sendable, Equatable {
    case title
    case summary
    case language
}

public protocol ApplicationMetadataStore {
    func fetchMediaItem(id: MediaItemID) throws -> MediaItem?
    func fetchMediaFiles(mediaItemID: MediaItemID) throws -> [MediaFile]
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
    func selectPosterAsset(
        id: PosterAssetID,
        mediaItemID: MediaItemID,
        selectionSource: PosterSelectionSource
    ) throws
    func withTransaction<T>(_ body: () throws -> T) throws -> T
}

extension CineMindStore: ApplicationMetadataStore {}

public protocol ApplicationLibraryMetadataRefreshStore: ApplicationMetadataStore {
    func fetchMediaItems() throws -> [MediaItem]
    func fetchMediaItemsMissingMetadata(limit: Int) throws -> [MediaItem]
    func fetchMediaItemsWithStaleMetadata(
        olderThan threshold: Date,
        limit: Int
    ) throws -> [MediaItem]
}

extension CineMindStore: ApplicationLibraryMetadataRefreshStore {}

public protocol ApplicationPosterCaching {
    func cache(_ image: RemoteImage) async throws -> PosterCacheResult
}

public struct ApplicationPosterCache: ApplicationPosterCaching {
    private let posterCache: PosterCache
    private let imageConfiguration: TMDBImageConfiguration

    public init(
        posterCache: PosterCache,
        imageConfiguration: TMDBImageConfiguration
    ) {
        self.posterCache = posterCache
        self.imageConfiguration = imageConfiguration
    }

    public func cache(_ image: RemoteImage) async throws -> PosterCacheResult {
        try await posterCache.cache(image, using: imageConfiguration)
    }
}

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
        let mediaFiles = try store.fetchMediaFiles(mediaItemID: mediaItem.id)
        let query = try MetadataApplicationMapper.searchQuery(
            for: mediaItem,
            mediaFiles: mediaFiles,
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
    private let posterCache: (any ApplicationPosterCaching)?
    private let policy: MetadataAutoMatchPolicy
    private let now: () -> Date

    public init(
        store: any ApplicationMetadataStore,
        provider: any MetadataProvider,
        posterCache: (any ApplicationPosterCaching)? = nil,
        policy: MetadataAutoMatchPolicy = MetadataAutoMatchPolicy(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.provider = provider
        self.posterCache = posterCache
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
            mediaFiles: try store.fetchMediaFiles(mediaItemID: mediaItem.id),
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

            _ = try await MetadataMatchWriter(
                store: store,
                providerName: provider.providerName,
                posterCache: posterCache,
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
    private let posterCache: (any ApplicationPosterCaching)?
    private let policy: MetadataAutoMatchPolicy
    private let now: () -> Date

    public init(
        store: any ApplicationMetadataStore,
        provider: any MetadataProvider,
        posterCache: (any ApplicationPosterCaching)? = nil,
        policy: MetadataAutoMatchPolicy = MetadataAutoMatchPolicy(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.provider = provider
        self.posterCache = posterCache
        self.policy = policy
        self.now = now
    }

    public func refresh(
        mediaItemID: MediaItemID,
        force: Bool = false,
        language: String? = nil
    ) async throws -> RefreshMetadataResult {
        _ = force
        let mediaItem = try fetchMediaItem(mediaItemID)
        guard let source = try store.fetchMetadataSourceRecord(
            mediaItemID: mediaItem.id,
            provider: provider.providerName
        ) else {
            let result = try await AutoMatchMetadataUseCase(
                store: store,
                provider: provider,
                posterCache: posterCache,
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

        let refreshedSource = try await MetadataMatchWriter(
            store: store,
            providerName: provider.providerName,
            posterCache: posterCache,
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
    private let posterCache: (any ApplicationPosterCaching)?
    private let now: () -> Date

    public init(
        store: any ApplicationMetadataStore,
        provider: any MetadataProvider,
        posterCache: (any ApplicationPosterCaching)? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.provider = provider
        self.posterCache = posterCache
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

        return try await MetadataMatchWriter(
            store: store,
            providerName: provider.providerName,
            posterCache: posterCache,
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

public struct RefreshLibraryMetadataUseCase {
    public static let defaultStaleInterval: TimeInterval = 30 * 24 * 60 * 60

    private let store: any ApplicationLibraryMetadataRefreshStore
    private let provider: any MetadataProvider
    private let posterCache: (any ApplicationPosterCaching)?
    private let policy: MetadataAutoMatchPolicy
    private let now: () -> Date

    public init(
        store: any ApplicationLibraryMetadataRefreshStore,
        provider: any MetadataProvider,
        posterCache: (any ApplicationPosterCaching)? = nil,
        policy: MetadataAutoMatchPolicy = MetadataAutoMatchPolicy(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.provider = provider
        self.posterCache = posterCache
        self.policy = policy
        self.now = now
    }

    public func refresh(
        limit: Int,
        staleThreshold: Date? = nil,
        force: Bool = false,
        language: String? = nil
    ) async throws -> RefreshLibraryMetadataResult {
        guard limit > 0 else {
            return RefreshLibraryMetadataResult()
        }

        let threshold = staleThreshold ?? now().addingTimeInterval(-Self.defaultStaleInterval)
        let mediaItems = try mediaItemsToRefresh(
            limit: limit,
            staleThreshold: threshold,
            force: force
        )
        var result = RefreshLibraryMetadataResult()
        let refreshUseCase = RefreshMetadataUseCase(
            store: store,
            provider: provider,
            posterCache: posterCache,
            policy: policy,
            now: now
        )

        for mediaItem in mediaItems {
            do {
                let itemResult = try await refreshUseCase.refresh(
                    mediaItemID: mediaItem.id,
                    force: force,
                    language: language
                )
                result.record(itemResult)
            } catch {
                result.failed += 1
            }
        }

        return result
    }

    private func mediaItemsToRefresh(
        limit: Int,
        staleThreshold: Date,
        force: Bool
    ) throws -> [MediaItem] {
        if force {
            return Array(try store.fetchMediaItems().prefix(limit))
        }

        var mediaItems: [MediaItem] = []
        var seenIDs = Set<MediaItemID>()

        func appendIfNeeded(_ item: MediaItem) {
            guard mediaItems.count < limit,
                  !seenIDs.contains(item.id) else {
                return
            }
            seenIDs.insert(item.id)
            mediaItems.append(item)
        }

        for item in try store.fetchMediaItemsMissingMetadata(limit: limit) {
            appendIfNeeded(item)
        }

        if mediaItems.count < limit {
            for item in try store.fetchMediaItemsWithStaleMetadata(
                olderThan: staleThreshold,
                limit: limit
            ) {
                appendIfNeeded(item)
            }
        }

        return mediaItems
    }
}

private extension RefreshLibraryMetadataResult {
    mutating func record(_ itemResult: RefreshMetadataResult) {
        switch itemResult {
        case .refreshed:
            refreshed += 1
        case .autoMatched(let autoMatchResult):
            record(autoMatchResult)
        }
    }

    mutating func record(_ autoMatchResult: AutoMatchMetadataResult) {
        switch autoMatchResult {
        case .matched:
            refreshed += 1
        case .skippedManualLock:
            skipped += 1
        case .noCandidates, .lowConfidence, .ambiguous:
            unmatched += 1
        }
    }
}

public struct SetMetadataOverrideUseCase {
    private let store: any ApplicationMetadataStore
    private let now: () -> Date

    public init(
        store: any ApplicationMetadataStore,
        now: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.now = now
    }

    public func set(
        mediaItemID: MediaItemID,
        field: MetadataOverrideField,
        value: String?
    ) throws -> MetadataItem {
        let mediaItem = try fetchMediaItem(mediaItemID)

        return try store.withTransaction {
            let writtenAt = now()
            let existing = try store.fetchMetadataItem(mediaItemID: mediaItem.id)
            var metadata = MetadataItem(
                id: existing?.id ?? DomainID.new(),
                mediaItemID: mediaItem.id,
                title: existing?.title,
                originalTitle: existing?.originalTitle,
                summary: existing?.summary,
                language: existing?.language,
                releaseDate: existing?.releaseDate,
                airDate: existing?.airDate,
                titleOverrideLocked: existing?.titleOverrideLocked ?? false,
                summaryOverrideLocked: existing?.summaryOverrideLocked ?? false,
                languageOverrideLocked: existing?.languageOverrideLocked ?? false,
                createdAt: existing?.createdAt ?? writtenAt,
                updatedAt: writtenAt
            )

            switch field {
            case .title:
                metadata.title = value
                metadata.titleOverrideLocked = true
            case .summary:
                metadata.summary = value
                metadata.summaryOverrideLocked = true
            case .language:
                metadata.language = value
                metadata.languageOverrideLocked = true
            }

            try store.saveMetadataItem(metadata)
            return metadata
        }
    }

    private func fetchMediaItem(_ mediaItemID: MediaItemID) throws -> MediaItem {
        guard let mediaItem = try store.fetchMediaItem(id: mediaItemID) else {
            throw ApplicationMetadataError.mediaItemNotFound(mediaItemID)
        }
        return mediaItem
    }
}

public struct ClearMetadataOverrideUseCase {
    private let store: any ApplicationMetadataStore
    private let now: () -> Date

    public init(
        store: any ApplicationMetadataStore,
        now: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.now = now
    }

    public func clear(
        mediaItemID: MediaItemID,
        field: MetadataOverrideField
    ) throws -> MetadataItem? {
        let mediaItem = try fetchMediaItem(mediaItemID)

        return try store.withTransaction {
            guard var metadata = try store.fetchMetadataItem(mediaItemID: mediaItem.id) else {
                return nil
            }

            let didClear: Bool
            switch field {
            case .title:
                didClear = metadata.titleOverrideLocked
                metadata.titleOverrideLocked = false
            case .summary:
                didClear = metadata.summaryOverrideLocked
                metadata.summaryOverrideLocked = false
            case .language:
                didClear = metadata.languageOverrideLocked
                metadata.languageOverrideLocked = false
            }

            guard didClear else {
                return metadata
            }

            metadata.updatedAt = now()
            try store.saveMetadataItem(metadata)
            return metadata
        }
    }

    private func fetchMediaItem(_ mediaItemID: MediaItemID) throws -> MediaItem {
        guard let mediaItem = try store.fetchMediaItem(id: mediaItemID) else {
            throw ApplicationMetadataError.mediaItemNotFound(mediaItemID)
        }
        return mediaItem
    }
}

public struct SelectPosterAssetUseCase {
    private let store: any ApplicationMetadataStore

    public init(store: any ApplicationMetadataStore) {
        self.store = store
    }

    public func select(
        mediaItemID: MediaItemID,
        posterAssetID: PosterAssetID
    ) throws {
        let mediaItem = try fetchMediaItem(mediaItemID)

        try store.withTransaction {
            let posters = try store.fetchPosterAssets(mediaItemID: mediaItem.id)
            guard posters.contains(where: { $0.id == posterAssetID }) else {
                throw ApplicationMetadataError.posterAssetMediaItemMismatch(
                    mediaItemID: mediaItem.id,
                    posterAssetID: posterAssetID
                )
            }

            try store.selectPosterAsset(
                id: posterAssetID,
                mediaItemID: mediaItem.id,
                selectionSource: .manual
            )
        }
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
        mediaFiles: [MediaFile] = [],
        language: String?
    ) throws -> MetadataSearchQuery {
        let imdbID = IMDBHintExtractor.uniqueIMDBID(mediaItem: mediaItem, mediaFiles: mediaFiles)
        switch mediaItem.mediaType {
        case .movie:
            return .movie(
                mediaItemID: mediaItem.id,
                title: mediaItem.title,
                year: mediaItem.year,
                imdbID: imdbID,
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
                imdbID: imdbID,
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

private enum IMDBHintExtractor {
    static func uniqueIMDBID(mediaItem: MediaItem, mediaFiles: [MediaFile]) -> String? {
        var ids = Set<String>()
        collectIDs(from: mediaItem.title, into: &ids)
        if let episodeTitle = mediaItem.episodeInfo?.episodeTitle {
            collectIDs(from: episodeTitle, into: &ids)
        }
        for file in mediaFiles {
            collectIDs(from: file.fileName, into: &ids)
            collectIDs(from: file.relativePath, into: &ids)
        }
        return ids.count == 1 ? ids.first : nil
    }

    private static func collectIDs(from value: String, into ids: inout Set<String>) {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)\btt\d{7,9}\b"#) else {
            return
        }
        let range = NSRange(value.startIndex..., in: value)
        for match in regex.matches(in: value, range: range) {
            guard let idRange = Range(match.range, in: value) else {
                continue
            }
            ids.insert(String(value[idRange]).lowercased())
        }
    }
}

private struct MetadataMatchWriter {
    let store: any ApplicationMetadataStore
    let providerName: MetadataProviderName
    let posterCache: (any ApplicationPosterCaching)?
    let now: () -> Date

    func write(
        mediaItem: MediaItem,
        details: MetadataDetails,
        images: [RemoteImage],
        confidence: Double,
        matchSource: MetadataMatchSource,
        manualMatchLocked: Bool
    ) async throws -> MetadataSourceRecord {
        try await write(
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
    ) async throws -> MetadataSourceRecord {
        guard source.provider == providerName else {
            throw ApplicationMetadataError.providerMismatch(
                mediaItemID: mediaItem.id,
                expected: providerName,
                actual: source.provider
            )
        }
        return try await write(
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
    ) async throws -> MetadataSourceRecord {
        try MetadataApplicationMapper.validate(details.identifier, matches: mediaItem)
        let existingPostersForCache = try store.fetchPosterAssets(mediaItemID: mediaItem.id)
        let cachedPoster = await cachedPoster(
            mediaItemID: mediaItem.id,
            images: images,
            existingPosters: existingPostersForCache
        )

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
            let shouldAutoSelectPoster = !existingPosters.contains {
                $0.assetType == .poster && $0.isSelected
            }
            for (index, image) in images.enumerated() {
                let poster = try posterAsset(
                    mediaItemID: mediaItem.id,
                    image: image,
                    existing: posterByIdentity[PosterIdentity(image)],
                    cachedPoster: cachedPoster,
                    shouldAutoSelect: shouldAutoSelectPoster && index == 0,
                    writtenAt: writtenAt
                )
                try store.savePosterAsset(poster)
            }

            return sourceRecord
        }
    }

    private func cachedPoster(
        mediaItemID: MediaItemID,
        images: [RemoteImage],
        existingPosters: [PosterAsset]
    ) async -> CachedPoster? {
        guard let posterCache,
              let image = imageToCache(images: images, existingPosters: existingPosters) else {
            return nil
        }

        do {
            let result = try await posterCache.cache(image)
            return CachedPoster(mediaItemID: mediaItemID, image: image, result: result)
        } catch {
            return nil
        }
    }

    private func imageToCache(
        images: [RemoteImage],
        existingPosters: [PosterAsset]
    ) -> RemoteImage? {
        guard !images.isEmpty else {
            return nil
        }

        if let selectedPoster = existingPosters.first(where: \.isSelected),
           let selectedImage = images.first(where: { PosterIdentity($0) == PosterIdentity(selectedPoster) }) {
            return selectedImage
        }

        return images[0]
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
        cachedPoster: CachedPoster?,
        shouldAutoSelect: Bool,
        writtenAt: Date
    ) throws -> PosterAsset {
        let cacheResult = cachedPoster?.result(for: mediaItemID, image: image)
        let isSelected = existing?.isSelected ?? shouldAutoSelect
        let selectionSource: PosterSelectionSource
        if shouldAutoSelect, existing?.isSelected != true {
            selectionSource = .automatic
        } else {
            selectionSource = existing?.selectionSource ?? .automatic
        }

        return try PosterAsset.validated(
            id: existing?.id ?? DomainID.new(),
            mediaItemID: mediaItemID,
            assetType: .poster,
            source: image.source,
            remotePath: image.remotePath,
            width: image.width,
            height: image.height,
            preferredCacheSize: image.preferredCacheSize,
            localCachePath: cacheResult?.localPath ?? existing?.localCachePath,
            cachedAt: cacheResult?.cachedAt ?? existing?.cachedAt,
            isSelected: isSelected,
            selectionSource: selectionSource,
            createdAt: existing?.createdAt ?? writtenAt,
            updatedAt: writtenAt
        )
    }
}

private struct CachedPoster {
    let mediaItemID: MediaItemID
    let imageIdentity: PosterIdentity
    let result: PosterCacheResult

    init(
        mediaItemID: MediaItemID,
        image: RemoteImage,
        result: PosterCacheResult
    ) {
        self.mediaItemID = mediaItemID
        self.imageIdentity = PosterIdentity(image)
        self.result = result
    }

    func result(for mediaItemID: MediaItemID, image: RemoteImage) -> PosterCacheResult? {
        guard self.mediaItemID == mediaItemID,
              imageIdentity == PosterIdentity(image) else {
            return nil
        }
        return result
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
