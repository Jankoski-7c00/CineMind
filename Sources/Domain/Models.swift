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

public enum DomainValidationError: Error, Sendable, Equatable {
    case emptySeriesTitle
    case invalidSeasonNumber(Int)
    case invalidEpisodeNumber(Int)
    case invalidPlaybackPositionMS(Int)
    case invalidPlaybackDurationMS(Int)
    case invalidPlaybackPlayCount(Int)
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
