import Foundation

/// Phase 1 compatibility choice: IDs remain String-backed to preserve existing Scanner/Persistence APIs.
/// They may become wrapper value types once downstream targets can migrate together.
public typealias LibraryID = String
public typealias LibraryFolderID = String
public typealias MediaItemID = String
public typealias MediaFileID = String
public typealias ScanRunID = String
public typealias ScanIssueID = String
public typealias PlaybackHistoryID = String
public typealias MetadataItemID = String
public typealias MetadataExternalIDID = String
public typealias MetadataSourceRecordID = String
public typealias PosterAssetID = String
public typealias SubtitleAssetID = String

public enum DomainID {
    public static func new() -> String {
        UUID().uuidString
    }
}

public enum MediaTitleNormalizer {
    public static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }
}

public enum MediaType: String, Codable, Sendable, Equatable, CaseIterable {
    case movie
    case episode

    public var requiresEpisodeInfo: Bool {
        self == .episode
    }
}

public enum MediaFileAvailability: String, Codable, Sendable, Equatable, CaseIterable {
    case available
    case unavailable

    public init(isAvailable: Bool) {
        self = isAvailable ? .available : .unavailable
    }

    public var isAvailable: Bool {
        self == .available
    }
}

public enum ScanStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case running
    case completed
    case failed

    public var isTerminal: Bool {
        switch self {
        case .running:
            false
        case .completed, .failed:
            true
        }
    }
}

public typealias ScanRunStatus = ScanStatus

public enum ScanIssueType: String, Codable, Sendable, Equatable, CaseIterable {
    case folderUnavailable
    case unsupportedFile
    case metadataParseFailed
    case duplicateCandidate
    case renameCandidate
    case filesystemError
}

public enum MetadataProviderName: String, Codable, Sendable, Equatable, CaseIterable {
    case tmdb
}

public enum MetadataProviderMediaType: String, Codable, Sendable, Equatable, CaseIterable {
    case movie
    case episode
}

public enum MetadataMatchSource: String, Codable, Sendable, Equatable, CaseIterable {
    case automatic
    case manual
}

public enum MetadataExternalIDType: String, Codable, Sendable, Equatable, CaseIterable {
    case tmdbMovie = "tmdb_movie"
    case tmdbTVSeries = "tmdb_tv_series"
    case tmdbEpisode = "tmdb_episode"
    case imdb
}

public enum PosterAssetType: String, Codable, Sendable, Equatable, CaseIterable {
    case poster
}

public enum PosterAssetSource: String, Codable, Sendable, Equatable, CaseIterable {
    case tmdb
}

public enum PosterSelectionSource: String, Codable, Sendable, Equatable, CaseIterable {
    case automatic
    case manual
}

public enum SubtitleAssetSource: String, Codable, Sendable, Equatable, CaseIterable {
    case external
    case downloaded
}

public enum SubtitleFormat: String, Codable, Sendable, Equatable, CaseIterable {
    case srt
    case webVTT = "vtt"
    case ass
    case ssa

    public init?(fileExtension: String) {
        let normalized = fileExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        switch normalized {
        case "srt":
            self = .srt
        case "vtt", "webvtt":
            self = .webVTT
        case "ass":
            self = .ass
        case "ssa":
            self = .ssa
        default:
            return nil
        }
    }

    public var supportsExternalCueParsing: Bool {
        switch self {
        case .srt, .webVTT:
            true
        case .ass, .ssa:
            false
        }
    }
}

public enum DomainValidationError: Error, Sendable, Equatable {
    case emptySeriesTitle
    case invalidSeasonNumber(Int)
    case invalidEpisodeNumber(Int)
    case invalidPlaybackPositionMS(Int)
    case invalidPlaybackDurationMS(Int)
    case invalidPlaybackPlayCount(Int)
    case emptyMetadataExternalIDValue
    case emptyMetadataSourceProviderID
    case invalidMetadataSourceConfidence(Double)
    case emptyPosterRemotePath
    case emptyPosterPreferredCacheSize
    case invalidPosterWidth(Int)
    case invalidPosterHeight(Int)
}

public struct Library: Codable, Sendable, Equatable {
    public var id: LibraryID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: LibraryID = DomainID.new(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct LibraryFolder: Codable, Sendable, Equatable {
    public var id: LibraryFolderID
    public var libraryID: LibraryID
    public var displayName: String
    public var rootPath: String
    public var accessBookmark: Data?
    public var isAvailable: Bool
    public var lastSeenAt: Date?
    public var lastScanAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: LibraryFolderID = DomainID.new(),
        libraryID: LibraryID,
        displayName: String,
        rootPath: String,
        accessBookmark: Data? = nil,
        isAvailable: Bool = true,
        lastSeenAt: Date? = nil,
        lastScanAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.libraryID = libraryID
        self.displayName = displayName
        self.rootPath = rootPath
        self.accessBookmark = accessBookmark
        self.isAvailable = isAvailable
        self.lastSeenAt = lastSeenAt
        self.lastScanAt = lastScanAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct EpisodeInfo: Codable, Sendable, Equatable {
    public var seriesTitle: String
    public var seasonNumber: Int
    public var episodeNumber: Int
    public var episodeTitle: String?

    public init(
        seriesTitle: String,
        seasonNumber: Int,
        episodeNumber: Int,
        episodeTitle: String? = nil
    ) {
        precondition(!seriesTitle.isEmpty, "seriesTitle must not be empty")
        precondition(seasonNumber > 0, "seasonNumber must be greater than zero")
        precondition(episodeNumber > 0, "episodeNumber must be greater than zero")
        self.seriesTitle = seriesTitle
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.episodeTitle = episodeTitle
    }

    public static func validated(
        seriesTitle: String,
        seasonNumber: Int,
        episodeNumber: Int,
        episodeTitle: String? = nil
    ) throws -> EpisodeInfo {
        guard !seriesTitle.isEmpty else {
            throw DomainValidationError.emptySeriesTitle
        }
        guard seasonNumber > 0 else {
            throw DomainValidationError.invalidSeasonNumber(seasonNumber)
        }
        guard episodeNumber > 0 else {
            throw DomainValidationError.invalidEpisodeNumber(episodeNumber)
        }

        return EpisodeInfo(
            seriesTitle: seriesTitle,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            episodeTitle: episodeTitle
        )
    }
}

public struct MediaItem: Codable, Sendable, Equatable {
    public var id: MediaItemID
    public var mediaType: MediaType
    public var title: String
    public var normalizedTitle: String
    public var year: Int?
    public var episodeInfo: EpisodeInfo?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: MediaItemID = DomainID.new(),
        mediaType: MediaType,
        title: String,
        normalizedTitle: String? = nil,
        year: Int? = nil,
        episodeInfo: EpisodeInfo? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        precondition(!title.isEmpty, "title must not be empty")
        if mediaType == .episode {
            precondition(episodeInfo != nil, "episode media items require episodeInfo")
        }

        self.id = id
        self.mediaType = mediaType
        self.title = title
        self.normalizedTitle = normalizedTitle ?? MediaTitleNormalizer.normalize(title)
        self.year = year
        self.episodeInfo = episodeInfo
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct MediaFile: Codable, Sendable, Equatable {
    public var id: MediaFileID
    public var mediaItemID: MediaItemID
    public var libraryFolderID: LibraryFolderID
    public var relativePath: String
    public var absolutePathHash: String
    public var fileName: String
    public var fileExtension: String
    public var fileSizeBytes: Int64
    public var modifiedAt: Date?
    public var isAvailable: Bool
    public var lastSeenAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public var availability: MediaFileAvailability {
        get {
            MediaFileAvailability(isAvailable: isAvailable)
        }
        set {
            isAvailable = newValue.isAvailable
        }
    }

    public init(
        id: MediaFileID = DomainID.new(),
        mediaItemID: MediaItemID,
        libraryFolderID: LibraryFolderID,
        relativePath: String,
        absolutePathHash: String,
        fileName: String,
        fileExtension: String,
        fileSizeBytes: Int64,
        modifiedAt: Date? = nil,
        isAvailable: Bool = true,
        availability: MediaFileAvailability? = nil,
        lastSeenAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        precondition(!mediaItemID.isEmpty, "mediaItemID must not be empty")
        precondition(!libraryFolderID.isEmpty, "libraryFolderID must not be empty")
        precondition(!relativePath.isEmpty, "relativePath must not be empty")
        self.id = id
        self.mediaItemID = mediaItemID
        self.libraryFolderID = libraryFolderID
        self.relativePath = relativePath
        self.absolutePathHash = absolutePathHash
        self.fileName = fileName
        self.fileExtension = fileExtension.lowercased()
        self.fileSizeBytes = fileSizeBytes
        self.modifiedAt = modifiedAt
        self.isAvailable = availability?.isAvailable ?? isAvailable
        self.lastSeenAt = lastSeenAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ScanRun: Codable, Sendable, Equatable {
    public var id: ScanRunID
    public var libraryID: LibraryID
    public var startedAt: Date
    public var finishedAt: Date?
    public var status: ScanRunStatus
    public var filesSeen: Int
    public var filesAdded: Int
    public var filesUpdated: Int
    public var filesMissing: Int
    public var issuesCount: Int

    public init(
        id: ScanRunID = DomainID.new(),
        libraryID: LibraryID,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        status: ScanRunStatus = .running,
        filesSeen: Int = 0,
        filesAdded: Int = 0,
        filesUpdated: Int = 0,
        filesMissing: Int = 0,
        issuesCount: Int = 0
    ) {
        self.id = id
        self.libraryID = libraryID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.filesSeen = filesSeen
        self.filesAdded = filesAdded
        self.filesUpdated = filesUpdated
        self.filesMissing = filesMissing
        self.issuesCount = issuesCount
    }
}

public struct ScanIssue: Codable, Sendable, Equatable {
    public var id: ScanIssueID
    public var scanRunID: ScanRunID
    public var libraryFolderID: LibraryFolderID?
    public var pathHash: String?
    public var issueType: ScanIssueType
    public var message: String
    public var createdAt: Date

    public init(
        id: ScanIssueID = DomainID.new(),
        scanRunID: ScanRunID,
        libraryFolderID: LibraryFolderID?,
        pathHash: String?,
        issueType: ScanIssueType,
        message: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.scanRunID = scanRunID
        self.libraryFolderID = libraryFolderID
        self.pathHash = pathHash
        self.issueType = issueType
        self.message = message
        self.createdAt = createdAt
    }
}

public struct PlaybackHistory: Codable, Sendable, Equatable {
    public var id: PlaybackHistoryID
    public var mediaItemID: MediaItemID
    public var mediaFileID: MediaFileID
    public var positionMS: Int
    public var durationMS: Int?
    public var completed: Bool
    public var playCount: Int
    public var lastPlayedAt: Date
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: PlaybackHistoryID = DomainID.new(),
        mediaItemID: MediaItemID,
        mediaFileID: MediaFileID,
        positionMS: Int,
        durationMS: Int? = nil,
        completed: Bool,
        playCount: Int,
        lastPlayedAt: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        precondition(positionMS >= 0, "positionMS must be non-negative")
        if let durationMS {
            precondition(durationMS >= 0, "durationMS must be non-negative when known")
        }
        precondition(playCount >= 0, "playCount must be non-negative")

        self.id = id
        self.mediaItemID = mediaItemID
        self.mediaFileID = mediaFileID
        self.positionMS = positionMS
        self.durationMS = durationMS
        self.completed = completed
        self.playCount = playCount
        self.lastPlayedAt = lastPlayedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func validated(
        id: PlaybackHistoryID = DomainID.new(),
        mediaItemID: MediaItemID,
        mediaFileID: MediaFileID,
        positionMS: Int,
        durationMS: Int? = nil,
        completed: Bool,
        playCount: Int,
        lastPlayedAt: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) throws -> PlaybackHistory {
        try validate(positionMS: positionMS, durationMS: durationMS, playCount: playCount)
        return PlaybackHistory(
            id: id,
            mediaItemID: mediaItemID,
            mediaFileID: mediaFileID,
            positionMS: positionMS,
            durationMS: durationMS,
            completed: completed,
            playCount: playCount,
            lastPlayedAt: lastPlayedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    public func validate() throws {
        try Self.validate(positionMS: positionMS, durationMS: durationMS, playCount: playCount)
    }

    public static func validate(positionMS: Int, durationMS: Int?, playCount: Int) throws {
        guard positionMS >= 0 else {
            throw DomainValidationError.invalidPlaybackPositionMS(positionMS)
        }
        if let durationMS, durationMS < 0 {
            throw DomainValidationError.invalidPlaybackDurationMS(durationMS)
        }
        guard playCount >= 0 else {
            throw DomainValidationError.invalidPlaybackPlayCount(playCount)
        }
    }
}

public struct MetadataItem: Codable, Sendable, Equatable {
    public var id: MetadataItemID
    public var mediaItemID: MediaItemID
    public var title: String?
    public var originalTitle: String?
    public var summary: String?
    public var language: String?
    public var releaseDate: String?
    public var airDate: String?
    public var titleOverrideLocked: Bool
    public var summaryOverrideLocked: Bool
    public var languageOverrideLocked: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: MetadataItemID = DomainID.new(),
        mediaItemID: MediaItemID,
        title: String? = nil,
        originalTitle: String? = nil,
        summary: String? = nil,
        language: String? = nil,
        releaseDate: String? = nil,
        airDate: String? = nil,
        titleOverrideLocked: Bool = false,
        summaryOverrideLocked: Bool = false,
        languageOverrideLocked: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.mediaItemID = mediaItemID
        self.title = title
        self.originalTitle = originalTitle
        self.summary = summary
        self.language = language
        self.releaseDate = releaseDate
        self.airDate = airDate
        self.titleOverrideLocked = titleOverrideLocked
        self.summaryOverrideLocked = summaryOverrideLocked
        self.languageOverrideLocked = languageOverrideLocked
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct MetadataExternalID: Codable, Sendable, Equatable {
    public var id: MetadataExternalIDID
    public var mediaItemID: MediaItemID
    public var provider: MetadataProviderName
    public var externalIDType: MetadataExternalIDType
    public var externalIDValue: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: MetadataExternalIDID = DomainID.new(),
        mediaItemID: MediaItemID,
        provider: MetadataProviderName,
        externalIDType: MetadataExternalIDType,
        externalIDValue: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        precondition(!externalIDValue.isEmpty, "externalIDValue must not be empty")

        self.id = id
        self.mediaItemID = mediaItemID
        self.provider = provider
        self.externalIDType = externalIDType
        self.externalIDValue = externalIDValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func validated(
        id: MetadataExternalIDID = DomainID.new(),
        mediaItemID: MediaItemID,
        provider: MetadataProviderName,
        externalIDType: MetadataExternalIDType,
        externalIDValue: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) throws -> MetadataExternalID {
        try validate(externalIDValue: externalIDValue)
        return MetadataExternalID(
            id: id,
            mediaItemID: mediaItemID,
            provider: provider,
            externalIDType: externalIDType,
            externalIDValue: externalIDValue,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    public func validate() throws {
        try Self.validate(externalIDValue: externalIDValue)
    }

    public static func validate(externalIDValue: String) throws {
        guard !externalIDValue.isEmpty else {
            throw DomainValidationError.emptyMetadataExternalIDValue
        }
    }
}

public struct MetadataSourceRecord: Codable, Sendable, Equatable {
    public var id: MetadataSourceRecordID
    public var mediaItemID: MediaItemID
    public var provider: MetadataProviderName
    public var providerID: String
    public var providerMediaType: MetadataProviderMediaType
    public var confidence: Double
    public var matchSource: MetadataMatchSource
    public var manualMatchLocked: Bool
    public var rawPayloadJSON: String?
    public var matchedAt: Date
    public var refreshedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: MetadataSourceRecordID = DomainID.new(),
        mediaItemID: MediaItemID,
        provider: MetadataProviderName,
        providerID: String,
        providerMediaType: MetadataProviderMediaType,
        confidence: Double,
        matchSource: MetadataMatchSource,
        manualMatchLocked: Bool = false,
        rawPayloadJSON: String? = nil,
        matchedAt: Date = Date(),
        refreshedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        precondition(!providerID.isEmpty, "providerID must not be empty")
        precondition(
            confidence >= 0.0 && confidence <= 1.0,
            "confidence must be between 0.0 and 1.0"
        )

        self.id = id
        self.mediaItemID = mediaItemID
        self.provider = provider
        self.providerID = providerID
        self.providerMediaType = providerMediaType
        self.confidence = confidence
        self.matchSource = matchSource
        self.manualMatchLocked = manualMatchLocked
        self.rawPayloadJSON = rawPayloadJSON
        self.matchedAt = matchedAt
        self.refreshedAt = refreshedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func validated(
        id: MetadataSourceRecordID = DomainID.new(),
        mediaItemID: MediaItemID,
        provider: MetadataProviderName,
        providerID: String,
        providerMediaType: MetadataProviderMediaType,
        confidence: Double,
        matchSource: MetadataMatchSource,
        manualMatchLocked: Bool = false,
        rawPayloadJSON: String? = nil,
        matchedAt: Date = Date(),
        refreshedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) throws -> MetadataSourceRecord {
        try validate(providerID: providerID, confidence: confidence)
        return MetadataSourceRecord(
            id: id,
            mediaItemID: mediaItemID,
            provider: provider,
            providerID: providerID,
            providerMediaType: providerMediaType,
            confidence: confidence,
            matchSource: matchSource,
            manualMatchLocked: manualMatchLocked,
            rawPayloadJSON: rawPayloadJSON,
            matchedAt: matchedAt,
            refreshedAt: refreshedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    public func validate() throws {
        try Self.validate(providerID: providerID, confidence: confidence)
    }

    public static func validate(providerID: String, confidence: Double) throws {
        guard !providerID.isEmpty else {
            throw DomainValidationError.emptyMetadataSourceProviderID
        }
        guard confidence >= 0.0 && confidence <= 1.0 else {
            throw DomainValidationError.invalidMetadataSourceConfidence(confidence)
        }
    }
}

public struct PosterAsset: Codable, Sendable, Equatable {
    public var id: PosterAssetID
    public var mediaItemID: MediaItemID
    public var assetType: PosterAssetType
    public var source: PosterAssetSource
    public var remotePath: String
    public var width: Int?
    public var height: Int?
    public var preferredCacheSize: String
    public var localCachePath: String?
    public var cachedAt: Date?
    public var isSelected: Bool
    public var selectionSource: PosterSelectionSource
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: PosterAssetID = DomainID.new(),
        mediaItemID: MediaItemID,
        assetType: PosterAssetType,
        source: PosterAssetSource,
        remotePath: String,
        width: Int? = nil,
        height: Int? = nil,
        preferredCacheSize: String,
        localCachePath: String? = nil,
        cachedAt: Date? = nil,
        isSelected: Bool = false,
        selectionSource: PosterSelectionSource = .automatic,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        precondition(!remotePath.isEmpty, "remotePath must not be empty")
        precondition(!preferredCacheSize.isEmpty, "preferredCacheSize must not be empty")
        if let width {
            precondition(width > 0, "width must be greater than zero when known")
        }
        if let height {
            precondition(height > 0, "height must be greater than zero when known")
        }

        self.id = id
        self.mediaItemID = mediaItemID
        self.assetType = assetType
        self.source = source
        self.remotePath = remotePath
        self.width = width
        self.height = height
        self.preferredCacheSize = preferredCacheSize
        self.localCachePath = localCachePath
        self.cachedAt = cachedAt
        self.isSelected = isSelected
        self.selectionSource = selectionSource
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func validated(
        id: PosterAssetID = DomainID.new(),
        mediaItemID: MediaItemID,
        assetType: PosterAssetType,
        source: PosterAssetSource,
        remotePath: String,
        width: Int? = nil,
        height: Int? = nil,
        preferredCacheSize: String,
        localCachePath: String? = nil,
        cachedAt: Date? = nil,
        isSelected: Bool = false,
        selectionSource: PosterSelectionSource = .automatic,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) throws -> PosterAsset {
        try validate(
            remotePath: remotePath,
            width: width,
            height: height,
            preferredCacheSize: preferredCacheSize
        )
        return PosterAsset(
            id: id,
            mediaItemID: mediaItemID,
            assetType: assetType,
            source: source,
            remotePath: remotePath,
            width: width,
            height: height,
            preferredCacheSize: preferredCacheSize,
            localCachePath: localCachePath,
            cachedAt: cachedAt,
            isSelected: isSelected,
            selectionSource: selectionSource,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    public func validate() throws {
        try Self.validate(
            remotePath: remotePath,
            width: width,
            height: height,
            preferredCacheSize: preferredCacheSize
        )
    }

    public static func validate(
        remotePath: String,
        width: Int?,
        height: Int?,
        preferredCacheSize: String
    ) throws {
        guard !remotePath.isEmpty else {
            throw DomainValidationError.emptyPosterRemotePath
        }
        guard !preferredCacheSize.isEmpty else {
            throw DomainValidationError.emptyPosterPreferredCacheSize
        }
        if let width, width <= 0 {
            throw DomainValidationError.invalidPosterWidth(width)
        }
        if let height, height <= 0 {
            throw DomainValidationError.invalidPosterHeight(height)
        }
    }
}

public struct SubtitleAsset: Codable, Sendable, Equatable {
    public var id: SubtitleAssetID
    public var mediaItemID: MediaItemID
    public var mediaFileID: MediaFileID?
    public var libraryFolderID: LibraryFolderID?
    public var relativePath: String
    public var fileName: String
    public var fileExtension: String
    public var format: SubtitleFormat
    public var languageCode: String?
    public var displayName: String?
    public var source: SubtitleAssetSource
    public var isAvailable: Bool
    public var lastSeenAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: SubtitleAssetID = DomainID.new(),
        mediaItemID: MediaItemID,
        mediaFileID: MediaFileID? = nil,
        libraryFolderID: LibraryFolderID? = nil,
        relativePath: String,
        fileName: String,
        fileExtension: String,
        format: SubtitleFormat,
        languageCode: String? = nil,
        displayName: String? = nil,
        source: SubtitleAssetSource,
        isAvailable: Bool = true,
        lastSeenAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        precondition(!mediaItemID.isEmpty, "mediaItemID must not be empty")
        precondition(!relativePath.isEmpty, "relativePath must not be empty")
        precondition(!fileName.isEmpty, "fileName must not be empty")
        precondition(!fileExtension.isEmpty, "fileExtension must not be empty")

        self.id = id
        self.mediaItemID = mediaItemID
        self.mediaFileID = mediaFileID
        self.libraryFolderID = libraryFolderID
        self.relativePath = relativePath
        self.fileName = fileName
        self.fileExtension = fileExtension.lowercased()
        self.format = format
        self.languageCode = languageCode
        self.displayName = displayName
        self.source = source
        self.isAvailable = isAvailable
        self.lastSeenAt = lastSeenAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
