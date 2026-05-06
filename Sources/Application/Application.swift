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

public protocol ApplicationPlaybackStore {
    func fetchLibrary() throws -> Library?
    func fetchLibraryFolders(libraryID: LibraryID) throws -> [LibraryFolder]
    func fetchMediaItems() throws -> [MediaItem]
    func fetchMediaFiles(mediaItemID: MediaItemID) throws -> [MediaFile]
    func fetchPlaybackHistory(
        mediaItemID: MediaItemID,
        mediaFileID: MediaFileID
    ) throws -> PlaybackHistory?
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
        let (mediaFile, mediaItem) = try fetchMediaFileAndItem(mediaFileID: mediaFileID)
        guard mediaFile.isAvailable else {
            throw ApplicationPlaybackError.mediaFileUnavailable
        }

        let libraryFolder = try fetchLibraryFolder(id: mediaFile.libraryFolderID)
        guard libraryFolder.isAvailable else {
            throw ApplicationPlaybackError.libraryFolderUnavailable
        }

        let resolvedURL = try resolveFileURL(
            rootPath: libraryFolder.rootPath,
            relativePath: mediaFile.relativePath
        )

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw ApplicationPlaybackError.resolvedFileMissing
        }

        let history = try store.fetchPlaybackHistory(
            mediaItemID: mediaFile.mediaItemID,
            mediaFileID: mediaFile.id
        )

        return try PlayableFile(
            mediaItemID: mediaFile.mediaItemID,
            mediaFileID: mediaFile.id,
            url: resolvedURL,
            displayName: displayName(
                mediaItem: mediaItem,
                mediaFile: mediaFile,
                resolvedURL: resolvedURL
            ),
            resumePositionMS: PlaybackResumePolicy.resumePositionMS(for: history)
        )
    }

    private func fetchMediaFileAndItem(
        mediaFileID: MediaFileID
    ) throws -> (MediaFile, MediaItem) {
        // Phase 2 temporary lookup: replace with direct fetchMediaFile(id:) once Persistence exposes it.
        for item in try store.fetchMediaItems() {
            for file in try store.fetchMediaFiles(mediaItemID: item.id) where file.id == mediaFileID {
                return (file, item)
            }
        }

        throw ApplicationPlaybackError.mediaFileNotFound
    }

    private func fetchLibraryFolder(id libraryFolderID: LibraryFolderID) throws -> LibraryFolder {
        guard let library = try store.fetchLibrary() else {
            throw ApplicationPlaybackError.libraryFolderNotFound
        }

        guard let folder = try store.fetchLibraryFolders(libraryID: library.id)
            .first(where: { $0.id == libraryFolderID }) else {
            throw ApplicationPlaybackError.libraryFolderNotFound
        }

        return folder
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
        mediaFile: MediaFile,
        resolvedURL: URL
    ) -> String {
        let itemTitle = mediaItem.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !itemTitle.isEmpty {
            return itemTitle
        }

        let fileName = mediaFile.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
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
        guard let history,
              !history.completed,
              history.positionMS >= minimumResumePositionMS else {
            return nil
        }

        if let durationMS = history.durationMS {
            let remainingMS = durationMS - history.positionMS
            if remainingMS <= nearEndRemainingMS {
                return nil
            }

            if durationMS > 0 {
                let progress = Double(history.positionMS) / Double(durationMS)
                if progress >= completionProgressThreshold {
                    return nil
                }
            }
        }

        return history.positionMS
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

public struct PlaybackProgressUseCase {
    private let store: any ApplicationPlaybackStore

    public init(store: any ApplicationPlaybackStore) {
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
