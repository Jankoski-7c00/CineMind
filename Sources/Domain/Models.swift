import Foundation
import Shared

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

public enum MediaType: String, Codable, Sendable, Equatable {
    case movie
    case episode
}

public enum ScanRunStatus: String, Codable, Sendable, Equatable {
    case running
    case completed
    case failed
}

public enum ScanIssueType: String, Codable, Sendable, Equatable {
    case folderUnavailable
    case unsupportedFile
    case metadataParseFailed
    case duplicateCandidate
    case renameCandidate
    case filesystemError
}

public struct Library: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = DomainID.new(),
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
    public var id: String
    public var libraryID: String
    public var displayName: String
    public var rootPath: String
    public var accessBookmark: Data?
    public var isAvailable: Bool
    public var lastSeenAt: Date?
    public var lastScanAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = DomainID.new(),
        libraryID: String,
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
}

public struct MediaItem: Codable, Sendable, Equatable {
    public var id: String
    public var mediaType: MediaType
    public var title: String
    public var normalizedTitle: String
    public var year: Int?
    public var episodeInfo: EpisodeInfo?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = DomainID.new(),
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
    public var id: String
    public var mediaItemID: String
    public var libraryFolderID: String
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

    public init(
        id: String = DomainID.new(),
        mediaItemID: String,
        libraryFolderID: String,
        relativePath: String,
        absolutePathHash: String,
        fileName: String,
        fileExtension: String,
        fileSizeBytes: Int64,
        modifiedAt: Date? = nil,
        isAvailable: Bool = true,
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
        self.isAvailable = isAvailable
        self.lastSeenAt = lastSeenAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ScanRun: Codable, Sendable, Equatable {
    public var id: String
    public var libraryID: String
    public var startedAt: Date
    public var finishedAt: Date?
    public var status: ScanRunStatus
    public var filesSeen: Int
    public var filesAdded: Int
    public var filesUpdated: Int
    public var filesMissing: Int
    public var issuesCount: Int

    public init(
        id: String = DomainID.new(),
        libraryID: String,
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
    public var id: String
    public var scanRunID: String
    public var libraryFolderID: String?
    public var pathHash: String?
    public var issueType: ScanIssueType
    public var message: String
    public var createdAt: Date

    public init(
        id: String = DomainID.new(),
        scanRunID: String,
        libraryFolderID: String?,
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
