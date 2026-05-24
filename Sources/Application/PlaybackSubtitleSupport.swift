import Domain
import Foundation
import Persistence
import Subtitle

public enum PlaybackApplicationTrackSource: Sendable, Equatable {
    case embedded
    case external
    case unsupportedExternal
}

public struct PlaybackSubtitleAsset: Sendable, Equatable {
    public let id: SubtitleAssetID
    public let format: SubtitleFormat
    public let languageCode: String?
    public let displayName: String
    public let relativePath: String
    public let folderRootPath: String
    public let isAvailable: Bool

    public init(
        id: SubtitleAssetID,
        format: SubtitleFormat,
        languageCode: String?,
        displayName: String,
        relativePath: String,
        folderRootPath: String,
        isAvailable: Bool
    ) {
        self.id = id
        self.format = format
        self.languageCode = languageCode
        self.displayName = displayName
        self.relativePath = relativePath
        self.folderRootPath = folderRootPath
        self.isAvailable = isAvailable
    }

    public var trackID: String {
        "external:\(id)"
    }

    public var isSelectable: Bool {
        isAvailable && format.supportsExternalCueParsing && !folderRootPath.isEmpty
    }
}

public protocol PlaybackSubtitleAssetReading: Sendable {
    func fetchPlaybackSubtitleAssets(mediaFileID: MediaFileID) throws -> [PlaybackSubtitleAsset]
}

public protocol PlaybackSubtitleFileLoading: Sendable {
    func loadSubtitleText(from url: URL) throws -> String
}

public struct FileSystemPlaybackSubtitleFileLoader: PlaybackSubtitleFileLoading {
    public init() {}

    public func loadSubtitleText(from url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}

extension CineMindStore: PlaybackSubtitleAssetReading {
    public func fetchPlaybackSubtitleAssets(mediaFileID: MediaFileID) throws -> [PlaybackSubtitleAsset] {
        try fetchPersistedSubtitleAssets(mediaFileID: mediaFileID).map { persisted in
            let asset = persisted.asset
            return PlaybackSubtitleAsset(
                id: asset.id,
                format: asset.format,
                languageCode: asset.languageCode,
                displayName: playbackSubtitleDisplayName(for: asset),
                relativePath: asset.relativePath,
                folderRootPath: persisted.folderRootPath,
                isAvailable: persisted.isUsable
            )
        }
    }

    private func playbackSubtitleDisplayName(for asset: SubtitleAsset) -> String {
        if let displayName = asset.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !displayName.isEmpty {
            return displayName
        }
        if let languageCode = asset.languageCode?.trimmingCharacters(in: .whitespacesAndNewlines),
           !languageCode.isEmpty {
            return languageCode.uppercased()
        }
        return asset.fileName
    }
}
