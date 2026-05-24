import Domain
import Foundation
import Persistence
import Playback
import Shared

public enum ApplicationModule {
    public static let name = "Application"
}

public enum ApplicationPlaybackError: Error, Sendable, Equatable {
    case mediaFileNotFound
    case mediaFileUnavailable
    case libraryFolderNotFound
    case libraryFolderUnavailable
    case resolvedFileMissing
    case invalidResolvedURL
    case persistenceFailure
}

public struct PlayableFile: Sendable, Equatable {
    public let mediaItemID: MediaItemID
    public let mediaFileID: MediaFileID
    public let url: URL
    public let displayName: String
    public let resumePositionMS: Int?

    public init(
        mediaItemID: MediaItemID,
        mediaFileID: MediaFileID,
        url: URL,
        displayName: String,
        resumePositionMS: Int?
    ) throws {
        guard url.isFileURL else {
            throw ApplicationPlaybackError.invalidResolvedURL
        }

        self.mediaItemID = mediaItemID
        self.mediaFileID = mediaFileID
        self.url = url
        self.displayName = displayName
        self.resumePositionMS = resumePositionMS
    }
}

public protocol PlaybackProgressStore {
    func savePlaybackProgress(
        mediaItemID: MediaItemID,
        mediaFileID: MediaFileID,
        positionMS: Int,
        durationMS: Int?,
        completed: Bool,
        playedAt: Date
    ) throws
    func incrementPlaybackCount(
        mediaItemID: MediaItemID,
        mediaFileID: MediaFileID,
        playedAt: Date
    ) throws
}

public protocol ApplicationPlaybackStore: PlaybackProgressStore {
    func fetchLibrary() throws -> Library?
    func fetchLibraryFolders(libraryID: LibraryID) throws -> [LibraryFolder]
    func fetchMediaItems() throws -> [MediaItem]
    func fetchMediaFiles(mediaItemID: MediaItemID) throws -> [MediaFile]
    func fetchPlaybackHistory(
        mediaItemID: MediaItemID,
        mediaFileID: MediaFileID
    ) throws -> PlaybackHistory?
    func fetchMediaFile(id: MediaFileID) throws -> PersistedMediaFile?
    func fetchMediaItem(id: MediaItemID) throws -> MediaItem?
}

extension CineMindStore: ApplicationPlaybackStore {}

public struct OpenMediaUseCase {
    private let store: any ApplicationPlaybackStore
    private let fileManager: FileManager

    public init(
        store: any ApplicationPlaybackStore,
        fileManager: FileManager = .default
    ) {
        self.store = store
        self.fileManager = fileManager
    }

    public func open(mediaFileID: MediaFileID) throws -> PlayableFile {
        do {
            return try openMapped(mediaFileID: mediaFileID)
        } catch let error as ApplicationPlaybackError {
            throw error
        } catch {
            throw ApplicationPlaybackError.persistenceFailure
        }
    }

    private func openMapped(mediaFileID: MediaFileID) throws -> PlayableFile {
        guard let persistedFile = try store.fetchMediaFile(id: mediaFileID) else {
            throw ApplicationPlaybackError.mediaFileNotFound
        }

        guard !persistedFile.folderRootPath.isEmpty else {
            throw ApplicationPlaybackError.libraryFolderUnavailable
        }

        guard persistedFile.folderIsAvailable else {
            throw ApplicationPlaybackError.libraryFolderUnavailable
        }

        guard persistedFile.isAvailable else {
            throw ApplicationPlaybackError.mediaFileUnavailable
        }

        let resolvedURL = try resolveFileURL(
            rootPath: persistedFile.folderRootPath,
            relativePath: persistedFile.relativePath
        )

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw ApplicationPlaybackError.resolvedFileMissing
        }

        guard let mediaItem = try store.fetchMediaItem(id: persistedFile.mediaItemID) else {
            throw ApplicationPlaybackError.mediaFileNotFound
        }

        let history = try store.fetchPlaybackHistory(
            mediaItemID: persistedFile.mediaItemID,
            mediaFileID: persistedFile.id
        )

        let displayName = self.displayName(
            mediaItem: mediaItem,
            resolvedURL: resolvedURL,
            persistedFile: persistedFile
        )

        return try PlayableFile(
            mediaItemID: persistedFile.mediaItemID,
            mediaFileID: persistedFile.id,
            url: resolvedURL,
            displayName: displayName,
            resumePositionMS: PlaybackResumePolicy.resumePositionMS(for: history)
        )
    }

    private func resolveFileURL(rootPath: String, relativePath: String) throws -> URL {
        guard (rootPath as NSString).isAbsolutePath,
              !(relativePath as NSString).isAbsolutePath else {
            throw ApplicationPlaybackError.invalidResolvedURL
        }

        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
        let resolvedURL = rootURL
            .appendingPathComponent(relativePath, isDirectory: false)
            .standardizedFileURL

        guard rootURL.isFileURL, resolvedURL.isFileURL else {
            throw ApplicationPlaybackError.invalidResolvedURL
        }

        let rootPath = rootURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        let resolvedPath = resolvedURL.path
        guard resolvedPath == rootPath || resolvedPath.hasPrefix(rootPrefix) else {
            throw ApplicationPlaybackError.invalidResolvedURL
        }

        return resolvedURL
    }

    private func displayName(
        mediaItem: MediaItem,
        resolvedURL: URL,
        persistedFile: PersistedMediaFile
    ) -> String {
        let itemTitle = mediaItem.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !itemTitle.isEmpty {
            return itemTitle
        }

        let fileName = persistedFile.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fileName.isEmpty {
            return fileName
        }

        return resolvedURL.lastPathComponent
    }
}

public enum PlaybackResumePolicy {
    public static let minimumResumePositionMS = 10_000
    public static let nearEndRemainingMS = 120_000
    public static let completionProgressThreshold = 0.95

    public static func resumePositionMS(for history: PlaybackHistory?) -> Int? {
        guard let history else {
            return nil
        }
        return resumePositionMS(
            positionMS: history.positionMS,
            durationMS: history.durationMS,
            completed: history.completed
        )
    }

    public static func resumePositionMS(
        positionMS: Int,
        durationMS: Int?,
        completed: Bool
    ) -> Int? {
        guard !completed,
              positionMS >= minimumResumePositionMS else {
            return nil
        }

        if let durationMS {
            let remainingMS = durationMS - positionMS
            if remainingMS <= nearEndRemainingMS {
                return nil
            }

            if durationMS > 0 {
                let progress = Double(positionMS) / Double(durationMS)
                if progress >= completionProgressThreshold {
                    return nil
                }
            }
        }

        return positionMS
    }
}

public enum PlaybackCompletionPolicy {
    public static func isCompleted(
        reliableEndEventReceived: Bool,
        positionMS: Int,
        durationMS: Int?
    ) -> Bool {
        if reliableEndEventReceived {
            return true
        }

        guard let durationMS else {
            return false
        }

        let remainingMS = durationMS - positionMS
        if remainingMS <= PlaybackResumePolicy.nearEndRemainingMS {
            return true
        }

        guard durationMS > 0 else {
            return false
        }

        let progress = Double(positionMS) / Double(durationMS)
        return progress >= PlaybackResumePolicy.completionProgressThreshold
    }
}

public struct PlaybackProgressUseCase: @unchecked Sendable {
    private let store: any PlaybackProgressStore

    public init(store: any PlaybackProgressStore) {
        self.store = store
    }

    public func saveProgress(
        mediaItemID: MediaItemID,
        mediaFileID: MediaFileID,
        positionMS: Int,
        durationMS: Int?,
        completed: Bool,
        playedAt: Date
    ) throws {
        do {
            try store.savePlaybackProgress(
                mediaItemID: mediaItemID,
                mediaFileID: mediaFileID,
                positionMS: positionMS,
                durationMS: durationMS,
                completed: completed,
                playedAt: playedAt
            )
        } catch let error as ApplicationPlaybackError {
            throw error
        } catch {
            throw ApplicationPlaybackError.persistenceFailure
        }
    }

    public func incrementPlayCount(
        mediaItemID: MediaItemID,
        mediaFileID: MediaFileID,
        playedAt: Date
    ) throws {
        do {
            try store.incrementPlaybackCount(
                mediaItemID: mediaItemID,
                mediaFileID: mediaFileID,
                playedAt: playedAt
            )
        } catch let error as ApplicationPlaybackError {
            throw error
        } catch {
            throw ApplicationPlaybackError.persistenceFailure
        }
    }
}
