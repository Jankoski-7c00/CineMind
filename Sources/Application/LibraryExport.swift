import Domain
import Foundation
import Persistence

public protocol LibraryExporting: Sendable {
    func exportLibrary(to destinationPath: String) async throws -> LibraryExportResult
}

public protocol LibraryExportDestinationPicking: Sendable {
    @MainActor func pickLibraryExportDestination() async throws -> String?
}

public protocol ApplicationLibraryExportStore: Sendable {
    func fetchLibraryExportSnapshot() throws -> PersistedLibraryExportSnapshot
}

extension CineMindStore: ApplicationLibraryExportStore {}

public protocol LibraryExportEncoding: Sendable {
    func encode(_ document: LibraryExportDocumentV1) throws -> Data
}

public protocol LibraryExportFileWriting: Sendable {
    func write(_ data: Data, to destinationURL: URL) throws
}

public struct LibraryExportResult: Sendable, Equatable {
    public let destinationPath: String
    public let exportedAt: Date
    public let mediaItemCount: Int
    public let byteCount: Int

    public init(
        destinationPath: String,
        exportedAt: Date,
        mediaItemCount: Int,
        byteCount: Int
    ) {
        self.destinationPath = destinationPath
        self.exportedAt = exportedAt
        self.mediaItemCount = mediaItemCount
        self.byteCount = byteCount
    }
}

public enum LibraryExportError: Error, Sendable, Equatable, LocalizedError {
    case invalidDestination
    case snapshotUnavailable
    case inconsistentSnapshot
    case encodingFailed
    case writeFailed

    public var errorDescription: String? {
        switch self {
        case .invalidDestination:
            "Choose a valid JSON file destination."
        case .snapshotUnavailable:
            "CineMind could not read the library for export."
        case .inconsistentSnapshot:
            "CineMind could not export an inconsistent library snapshot."
        case .encodingFailed:
            "CineMind could not encode the library export."
        case .writeFailed:
            "CineMind could not write the library export file."
        }
    }
}

public struct JSONLibraryExportEncoder: LibraryExportEncoding {
    public init() {}

    public func encode(_ document: LibraryExportDocumentV1) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }
}

public struct FoundationLibraryExportFileWriter: LibraryExportFileWriting {
    public init() {}

    public func write(_ data: Data, to destinationURL: URL) throws {
        try data.write(to: destinationURL, options: .atomic)
    }
}

public struct LibraryExportUseCase: LibraryExporting, Sendable {
    private let store: any ApplicationLibraryExportStore
    private let encoder: any LibraryExportEncoding
    private let fileWriter: any LibraryExportFileWriting
    private let now: @Sendable () -> Date
    private let queue: DispatchQueue

    public init(
        store: any ApplicationLibraryExportStore,
        encoder: any LibraryExportEncoding = JSONLibraryExportEncoder(),
        fileWriter: any LibraryExportFileWriting = FoundationLibraryExportFileWriter(),
        now: @escaping @Sendable () -> Date = Date.init,
        queueLabel: String = "CineMind.LibraryExportUseCase"
    ) {
        self.store = store
        self.encoder = encoder
        self.fileWriter = fileWriter
        self.now = now
        self.queue = DispatchQueue(label: queueLabel, qos: .userInitiated)
    }

    public func exportLibrary(to destinationPath: String) async throws -> LibraryExportResult {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try exportLibrarySynchronously(to: destinationPath))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func exportLibrarySynchronously(to destinationPath: String) throws -> LibraryExportResult {
        let destinationURL = try Self.destinationURL(for: destinationPath)
        let snapshot: PersistedLibraryExportSnapshot
        do {
            snapshot = try store.fetchLibraryExportSnapshot()
        } catch {
            throw LibraryExportError.snapshotUnavailable
        }

        let exportedAt = now()
        let document = try Self.makeDocument(snapshot: snapshot, exportedAt: exportedAt)
        let data: Data
        do {
            data = try encoder.encode(document)
        } catch {
            throw LibraryExportError.encodingFailed
        }

        do {
            try fileWriter.write(data, to: destinationURL)
        } catch {
            throw LibraryExportError.writeFailed
        }

        return LibraryExportResult(
            destinationPath: destinationURL.path,
            exportedAt: exportedAt,
            mediaItemCount: document.mediaItems.count,
            byteCount: data.count
        )
    }

    private static func destinationURL(for destinationPath: String) throws -> URL {
        let trimmedPath = destinationPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty,
              (trimmedPath as NSString).isAbsolutePath else {
            throw LibraryExportError.invalidDestination
        }

        let destinationURL = URL(fileURLWithPath: trimmedPath, isDirectory: false).standardizedFileURL
        guard destinationURL.pathExtension.lowercased() == "json" else {
            throw LibraryExportError.invalidDestination
        }
        return destinationURL
    }

    private static func makeDocument(
        snapshot: PersistedLibraryExportSnapshot,
        exportedAt: Date
    ) throws -> LibraryExportDocumentV1 {
        try validateRelationships(snapshot)

        return LibraryExportDocumentV1(
            format: "cinemind-library-export",
            formatVersion: 1,
            exportedAt: exportedAt,
            library: LibraryExportLibraryV1(
                id: snapshot.library.id,
                name: snapshot.library.name,
                createdAt: snapshot.library.createdAt,
                updatedAt: snapshot.library.updatedAt
            ),
            folders: snapshot.folders
                .sorted { $0.id < $1.id }
                .map {
                    LibraryExportFolderV1(
                        id: $0.id,
                        libraryID: $0.libraryID,
                        displayName: $0.displayName,
                        isAvailable: $0.isAvailable,
                        lastSeenAt: $0.lastSeenAt,
                        lastScanAt: $0.lastScanAt,
                        createdAt: $0.createdAt,
                        updatedAt: $0.updatedAt
                    )
                },
            mediaItems: snapshot.mediaItems
                .sorted { $0.id < $1.id }
                .map {
                    LibraryExportMediaItemV1(
                        id: $0.id,
                        mediaType: $0.mediaType.rawValue,
                        title: $0.title,
                        normalizedTitle: $0.normalizedTitle,
                        year: $0.year,
                        seriesTitle: $0.episodeInfo?.seriesTitle,
                        seasonNumber: $0.episodeInfo?.seasonNumber,
                        episodeNumber: $0.episodeInfo?.episodeNumber,
                        episodeTitle: $0.episodeInfo?.episodeTitle,
                        createdAt: $0.createdAt,
                        updatedAt: $0.updatedAt
                    )
                },
            mediaFiles: snapshot.mediaFiles
                .sorted { $0.id < $1.id }
                .map {
                    LibraryExportMediaFileV1(
                        id: $0.id,
                        mediaItemID: $0.mediaItemID,
                        libraryFolderID: $0.libraryFolderID,
                        relativePath: $0.relativePath,
                        fileName: $0.fileName,
                        fileExtension: $0.fileExtension,
                        fileSizeBytes: $0.fileSizeBytes,
                        modifiedAt: $0.modifiedAt,
                        isAvailable: $0.isAvailable,
                        lastSeenAt: $0.lastSeenAt,
                        createdAt: $0.createdAt,
                        updatedAt: $0.updatedAt
                    )
                },
            playbackHistory: snapshot.playbackHistory
                .sorted { $0.id < $1.id }
                .map {
                    LibraryExportPlaybackHistoryV1(
                        id: $0.id,
                        mediaItemID: $0.mediaItemID,
                        mediaFileID: $0.mediaFileID,
                        positionMS: $0.positionMS,
                        durationMS: $0.durationMS,
                        completed: $0.completed,
                        playCount: $0.playCount,
                        lastPlayedAt: $0.lastPlayedAt,
                        createdAt: $0.createdAt,
                        updatedAt: $0.updatedAt
                    )
                },
            metadataItems: snapshot.metadataItems
                .sorted { $0.id < $1.id }
                .map {
                    LibraryExportMetadataItemV1(
                        id: $0.id,
                        mediaItemID: $0.mediaItemID,
                        title: $0.title,
                        originalTitle: $0.originalTitle,
                        summary: $0.summary,
                        language: $0.language,
                        releaseDate: $0.releaseDate,
                        airDate: $0.airDate,
                        titleOverrideLocked: $0.titleOverrideLocked,
                        summaryOverrideLocked: $0.summaryOverrideLocked,
                        languageOverrideLocked: $0.languageOverrideLocked,
                        createdAt: $0.createdAt,
                        updatedAt: $0.updatedAt
                    )
                },
            metadataExternalIDs: snapshot.metadataExternalIDs
                .sorted { $0.id < $1.id }
                .map {
                    LibraryExportMetadataExternalIDV1(
                        id: $0.id,
                        mediaItemID: $0.mediaItemID,
                        provider: $0.provider.rawValue,
                        externalIDType: $0.externalIDType.rawValue,
                        externalIDValue: $0.externalIDValue,
                        createdAt: $0.createdAt,
                        updatedAt: $0.updatedAt
                    )
                },
            metadataSourceRecords: snapshot.metadataSourceRecords
                .sorted { $0.id < $1.id }
                .map {
                    LibraryExportMetadataSourceRecordV1(
                        id: $0.id,
                        mediaItemID: $0.mediaItemID,
                        provider: $0.provider.rawValue,
                        providerID: $0.providerID,
                        providerMediaType: $0.providerMediaType.rawValue,
                        confidence: $0.confidence,
                        matchSource: $0.matchSource.rawValue,
                        manualMatchLocked: $0.manualMatchLocked,
                        matchedAt: $0.matchedAt,
                        refreshedAt: $0.refreshedAt,
                        createdAt: $0.createdAt,
                        updatedAt: $0.updatedAt
                    )
                },
            posterAssets: snapshot.posterAssets
                .sorted { $0.id < $1.id }
                .map {
                    LibraryExportPosterAssetV1(
                        id: $0.id,
                        mediaItemID: $0.mediaItemID,
                        assetType: $0.assetType.rawValue,
                        source: $0.source.rawValue,
                        remotePath: $0.remotePath,
                        width: $0.width,
                        height: $0.height,
                        isSelected: $0.isSelected,
                        selectionSource: $0.selectionSource.rawValue,
                        createdAt: $0.createdAt,
                        updatedAt: $0.updatedAt
                    )
                },
            subtitleAssets: snapshot.subtitleAssets
                .sorted { $0.id < $1.id }
                .map {
                    LibraryExportSubtitleAssetV1(
                        id: $0.id,
                        mediaItemID: $0.mediaItemID,
                        mediaFileID: $0.mediaFileID,
                        libraryFolderID: $0.libraryFolderID,
                        relativePath: $0.relativePath,
                        fileName: $0.fileName,
                        fileExtension: $0.fileExtension,
                        format: $0.format.rawValue,
                        languageCode: $0.languageCode,
                        displayName: $0.displayName,
                        source: $0.source.rawValue,
                        isAvailable: $0.isAvailable,
                        lastSeenAt: $0.lastSeenAt,
                        createdAt: $0.createdAt,
                        updatedAt: $0.updatedAt
                    )
                },
            tags: snapshot.tags
                .sorted { $0.id < $1.id }
                .map {
                    LibraryExportTagV1(
                        id: $0.id,
                        name: $0.name,
                        normalizedName: $0.normalizedName,
                        source: $0.source.rawValue,
                        createdAt: $0.createdAt,
                        updatedAt: $0.updatedAt
                    )
                },
            mediaItemTags: snapshot.mediaItemTags
                .sorted { ($0.mediaItemID, $0.tagID) < ($1.mediaItemID, $1.tagID) }
                .map {
                    LibraryExportMediaItemTagV1(
                        mediaItemID: $0.mediaItemID,
                        tagID: $0.tagID,
                        assignedAt: $0.assignedAt,
                        updatedAt: $0.updatedAt
                    )
                },
            favorites: snapshot.favorites
                .sorted { $0.mediaItemID < $1.mediaItemID }
                .map {
                    LibraryExportFavoriteV1(
                        mediaItemID: $0.mediaItemID,
                        createdAt: $0.createdAt,
                        updatedAt: $0.updatedAt
                    )
                },
            collections: snapshot.collections
                .sorted { $0.id < $1.id }
                .map {
                    LibraryExportCollectionV1(
                        id: $0.id,
                        name: $0.name,
                        normalizedName: $0.normalizedName,
                        description: $0.description,
                        createdAt: $0.createdAt,
                        updatedAt: $0.updatedAt
                    )
                },
            collectionItems: snapshot.collectionItems
                .sorted { ($0.collectionID, $0.mediaItemID) < ($1.collectionID, $1.mediaItemID) }
                .map {
                    LibraryExportCollectionItemV1(
                        collectionID: $0.collectionID,
                        mediaItemID: $0.mediaItemID,
                        addedAt: $0.addedAt,
                        updatedAt: $0.updatedAt
                    )
                }
        )
    }

    private static func validateRelationships(_ snapshot: PersistedLibraryExportSnapshot) throws {
        let folderIDs = Set(snapshot.folders.map(\.id))
        let mediaItemIDs = Set(snapshot.mediaItems.map(\.id))
        let mediaFileIDs = Set(snapshot.mediaFiles.map(\.id))
        let tagIDs = Set(snapshot.tags.map(\.id))
        let collectionIDs = Set(snapshot.collections.map(\.id))

        guard snapshot.folders.allSatisfy({ $0.libraryID == snapshot.library.id }),
              snapshot.mediaFiles.allSatisfy({
                  mediaItemIDs.contains($0.mediaItemID) && folderIDs.contains($0.libraryFolderID)
              }),
              snapshot.playbackHistory.allSatisfy({
                  mediaItemIDs.contains($0.mediaItemID) && mediaFileIDs.contains($0.mediaFileID)
              }),
              snapshot.metadataItems.allSatisfy({ mediaItemIDs.contains($0.mediaItemID) }),
              snapshot.metadataExternalIDs.allSatisfy({ mediaItemIDs.contains($0.mediaItemID) }),
              snapshot.metadataSourceRecords.allSatisfy({ mediaItemIDs.contains($0.mediaItemID) }),
              snapshot.posterAssets.allSatisfy({ mediaItemIDs.contains($0.mediaItemID) }),
              snapshot.subtitleAssets.allSatisfy({
                  mediaItemIDs.contains($0.mediaItemID)
                      && ($0.mediaFileID.map(mediaFileIDs.contains) ?? true)
                      && ($0.libraryFolderID.map(folderIDs.contains) ?? true)
              }),
              snapshot.mediaItemTags.allSatisfy({
                  mediaItemIDs.contains($0.mediaItemID) && tagIDs.contains($0.tagID)
              }),
              snapshot.favorites.allSatisfy({ mediaItemIDs.contains($0.mediaItemID) }),
              snapshot.collectionItems.allSatisfy({
                  collectionIDs.contains($0.collectionID) && mediaItemIDs.contains($0.mediaItemID)
              }) else {
            throw LibraryExportError.inconsistentSnapshot
        }
    }
}

public struct LibraryExportDocumentV1: Codable, Sendable, Equatable {
    public let format: String
    public let formatVersion: Int
    public let exportedAt: Date
    public let library: LibraryExportLibraryV1
    public let folders: [LibraryExportFolderV1]
    public let mediaItems: [LibraryExportMediaItemV1]
    public let mediaFiles: [LibraryExportMediaFileV1]
    public let playbackHistory: [LibraryExportPlaybackHistoryV1]
    public let metadataItems: [LibraryExportMetadataItemV1]
    public let metadataExternalIDs: [LibraryExportMetadataExternalIDV1]
    public let metadataSourceRecords: [LibraryExportMetadataSourceRecordV1]
    public let posterAssets: [LibraryExportPosterAssetV1]
    public let subtitleAssets: [LibraryExportSubtitleAssetV1]
    public let tags: [LibraryExportTagV1]
    public let mediaItemTags: [LibraryExportMediaItemTagV1]
    public let favorites: [LibraryExportFavoriteV1]
    public let collections: [LibraryExportCollectionV1]
    public let collectionItems: [LibraryExportCollectionItemV1]
}

public struct LibraryExportLibraryV1: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let createdAt: Date
    public let updatedAt: Date
}

public struct LibraryExportFolderV1: Codable, Sendable, Equatable {
    public let id: String
    public let libraryID: String
    public let displayName: String
    public let isAvailable: Bool
    public let lastSeenAt: Date?
    public let lastScanAt: Date?
    public let createdAt: Date
    public let updatedAt: Date
}

public struct LibraryExportMediaItemV1: Codable, Sendable, Equatable {
    public let id: String
    public let mediaType: String
    public let title: String
    public let normalizedTitle: String
    public let year: Int?
    public let seriesTitle: String?
    public let seasonNumber: Int?
    public let episodeNumber: Int?
    public let episodeTitle: String?
    public let createdAt: Date
    public let updatedAt: Date
}

public struct LibraryExportMediaFileV1: Codable, Sendable, Equatable {
    public let id: String
    public let mediaItemID: String
    public let libraryFolderID: String
    public let relativePath: String
    public let fileName: String
    public let fileExtension: String
    public let fileSizeBytes: Int64
    public let modifiedAt: Date?
    public let isAvailable: Bool
    public let lastSeenAt: Date?
    public let createdAt: Date
    public let updatedAt: Date
}

public struct LibraryExportPlaybackHistoryV1: Codable, Sendable, Equatable {
    public let id: String
    public let mediaItemID: String
    public let mediaFileID: String
    public let positionMS: Int
    public let durationMS: Int?
    public let completed: Bool
    public let playCount: Int
    public let lastPlayedAt: Date
    public let createdAt: Date
    public let updatedAt: Date
}

public struct LibraryExportMetadataItemV1: Codable, Sendable, Equatable {
    public let id: String
    public let mediaItemID: String
    public let title: String?
    public let originalTitle: String?
    public let summary: String?
    public let language: String?
    public let releaseDate: String?
    public let airDate: String?
    public let titleOverrideLocked: Bool
    public let summaryOverrideLocked: Bool
    public let languageOverrideLocked: Bool
    public let createdAt: Date
    public let updatedAt: Date
}

public struct LibraryExportMetadataExternalIDV1: Codable, Sendable, Equatable {
    public let id: String
    public let mediaItemID: String
    public let provider: String
    public let externalIDType: String
    public let externalIDValue: String
    public let createdAt: Date
    public let updatedAt: Date
}

public struct LibraryExportMetadataSourceRecordV1: Codable, Sendable, Equatable {
    public let id: String
    public let mediaItemID: String
    public let provider: String
    public let providerID: String
    public let providerMediaType: String
    public let confidence: Double
    public let matchSource: String
    public let manualMatchLocked: Bool
    public let matchedAt: Date
    public let refreshedAt: Date?
    public let createdAt: Date
    public let updatedAt: Date
}

public struct LibraryExportPosterAssetV1: Codable, Sendable, Equatable {
    public let id: String
    public let mediaItemID: String
    public let assetType: String
    public let source: String
    public let remotePath: String
    public let width: Int?
    public let height: Int?
    public let isSelected: Bool
    public let selectionSource: String
    public let createdAt: Date
    public let updatedAt: Date
}

public struct LibraryExportSubtitleAssetV1: Codable, Sendable, Equatable {
    public let id: String
    public let mediaItemID: String
    public let mediaFileID: String?
    public let libraryFolderID: String?
    public let relativePath: String
    public let fileName: String
    public let fileExtension: String
    public let format: String
    public let languageCode: String?
    public let displayName: String?
    public let source: String
    public let isAvailable: Bool
    public let lastSeenAt: Date?
    public let createdAt: Date
    public let updatedAt: Date
}

public struct LibraryExportTagV1: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let normalizedName: String
    public let source: String
    public let createdAt: Date
    public let updatedAt: Date
}

public struct LibraryExportMediaItemTagV1: Codable, Sendable, Equatable {
    public let mediaItemID: String
    public let tagID: String
    public let assignedAt: Date
    public let updatedAt: Date
}

public struct LibraryExportFavoriteV1: Codable, Sendable, Equatable {
    public let mediaItemID: String
    public let createdAt: Date
    public let updatedAt: Date
}

public struct LibraryExportCollectionV1: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let normalizedName: String
    public let description: String?
    public let createdAt: Date
    public let updatedAt: Date
}

public struct LibraryExportCollectionItemV1: Codable, Sendable, Equatable {
    public let collectionID: String
    public let mediaItemID: String
    public let addedAt: Date
    public let updatedAt: Date
}
