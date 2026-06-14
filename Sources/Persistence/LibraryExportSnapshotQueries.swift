import Domain
import Foundation

public struct PersistedExportLibraryFolder: Sendable, Equatable {
    public let id: LibraryFolderID
    public let libraryID: LibraryID
    public let displayName: String
    public let isAvailable: Bool
    public let lastSeenAt: Date?
    public let lastScanAt: Date?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: LibraryFolderID,
        libraryID: LibraryID,
        displayName: String,
        isAvailable: Bool,
        lastSeenAt: Date?,
        lastScanAt: Date?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.libraryID = libraryID
        self.displayName = displayName
        self.isAvailable = isAvailable
        self.lastSeenAt = lastSeenAt
        self.lastScanAt = lastScanAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct PersistedExportMediaFile: Sendable, Equatable {
    public let id: MediaFileID
    public let mediaItemID: MediaItemID
    public let libraryFolderID: LibraryFolderID
    public let relativePath: String
    public let fileName: String
    public let fileExtension: String
    public let fileSizeBytes: Int64
    public let modifiedAt: Date?
    public let isAvailable: Bool
    public let lastSeenAt: Date?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: MediaFileID,
        mediaItemID: MediaItemID,
        libraryFolderID: LibraryFolderID,
        relativePath: String,
        fileName: String,
        fileExtension: String,
        fileSizeBytes: Int64,
        modifiedAt: Date?,
        isAvailable: Bool,
        lastSeenAt: Date?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.mediaItemID = mediaItemID
        self.libraryFolderID = libraryFolderID
        self.relativePath = relativePath
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.fileSizeBytes = fileSizeBytes
        self.modifiedAt = modifiedAt
        self.isAvailable = isAvailable
        self.lastSeenAt = lastSeenAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct PersistedExportMetadataSourceRecord: Sendable, Equatable {
    public let id: MetadataSourceRecordID
    public let mediaItemID: MediaItemID
    public let provider: MetadataProviderName
    public let providerID: String
    public let providerMediaType: MetadataProviderMediaType
    public let confidence: Double
    public let matchSource: MetadataMatchSource
    public let manualMatchLocked: Bool
    public let matchedAt: Date
    public let refreshedAt: Date?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: MetadataSourceRecordID,
        mediaItemID: MediaItemID,
        provider: MetadataProviderName,
        providerID: String,
        providerMediaType: MetadataProviderMediaType,
        confidence: Double,
        matchSource: MetadataMatchSource,
        manualMatchLocked: Bool,
        matchedAt: Date,
        refreshedAt: Date?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.mediaItemID = mediaItemID
        self.provider = provider
        self.providerID = providerID
        self.providerMediaType = providerMediaType
        self.confidence = confidence
        self.matchSource = matchSource
        self.manualMatchLocked = manualMatchLocked
        self.matchedAt = matchedAt
        self.refreshedAt = refreshedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct PersistedExportPosterAsset: Sendable, Equatable {
    public let id: PosterAssetID
    public let mediaItemID: MediaItemID
    public let assetType: PosterAssetType
    public let source: PosterAssetSource
    public let remotePath: String
    public let width: Int?
    public let height: Int?
    public let isSelected: Bool
    public let selectionSource: PosterSelectionSource
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: PosterAssetID,
        mediaItemID: MediaItemID,
        assetType: PosterAssetType,
        source: PosterAssetSource,
        remotePath: String,
        width: Int?,
        height: Int?,
        isSelected: Bool,
        selectionSource: PosterSelectionSource,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.mediaItemID = mediaItemID
        self.assetType = assetType
        self.source = source
        self.remotePath = remotePath
        self.width = width
        self.height = height
        self.isSelected = isSelected
        self.selectionSource = selectionSource
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct PersistedLibraryExportSnapshot: Sendable, Equatable {
    public let library: Library
    public let folders: [PersistedExportLibraryFolder]
    public let mediaItems: [MediaItem]
    public let mediaFiles: [PersistedExportMediaFile]
    public let playbackHistory: [PlaybackHistory]
    public let metadataItems: [MetadataItem]
    public let metadataExternalIDs: [MetadataExternalID]
    public let metadataSourceRecords: [PersistedExportMetadataSourceRecord]
    public let posterAssets: [PersistedExportPosterAsset]
    public let subtitleAssets: [SubtitleAsset]
    public let tags: [Tag]
    public let mediaItemTags: [MediaItemTag]
    public let favorites: [FavoriteMediaItem]
    public let collections: [MediaCollection]
    public let collectionItems: [CollectionItem]

    public init(
        library: Library,
        folders: [PersistedExportLibraryFolder] = [],
        mediaItems: [MediaItem] = [],
        mediaFiles: [PersistedExportMediaFile] = [],
        playbackHistory: [PlaybackHistory] = [],
        metadataItems: [MetadataItem] = [],
        metadataExternalIDs: [MetadataExternalID] = [],
        metadataSourceRecords: [PersistedExportMetadataSourceRecord] = [],
        posterAssets: [PersistedExportPosterAsset] = [],
        subtitleAssets: [SubtitleAsset] = [],
        tags: [Tag] = [],
        mediaItemTags: [MediaItemTag] = [],
        favorites: [FavoriteMediaItem] = [],
        collections: [MediaCollection] = [],
        collectionItems: [CollectionItem] = []
    ) {
        self.library = library
        self.folders = folders
        self.mediaItems = mediaItems
        self.mediaFiles = mediaFiles
        self.playbackHistory = playbackHistory
        self.metadataItems = metadataItems
        self.metadataExternalIDs = metadataExternalIDs
        self.metadataSourceRecords = metadataSourceRecords
        self.posterAssets = posterAssets
        self.subtitleAssets = subtitleAssets
        self.tags = tags
        self.mediaItemTags = mediaItemTags
        self.favorites = favorites
        self.collections = collections
        self.collectionItems = collectionItems
    }
}

extension CineMindStore {
    public func fetchLibraryExportSnapshot() throws -> PersistedLibraryExportSnapshot {
        try withReadTransaction {
            guard let library = try fetchLibrary() else {
                throw PersistenceError.libraryExportUnavailable
            }

            let snapshot = PersistedLibraryExportSnapshot(
                library: library,
                folders: try fetchExportFolders(),
                mediaItems: try fetchExportMediaItems(),
                mediaFiles: try fetchExportMediaFiles(),
                playbackHistory: try fetchExportPlaybackHistory(),
                metadataItems: try fetchExportMetadataItems(),
                metadataExternalIDs: try fetchExportMetadataExternalIDs(),
                metadataSourceRecords: try fetchExportMetadataSourceRecords(),
                posterAssets: try fetchExportPosterAssets(),
                subtitleAssets: try fetchExportSubtitleAssets(),
                tags: try fetchExportTags(),
                mediaItemTags: try fetchExportMediaItemTags(),
                favorites: try fetchExportFavorites(),
                collections: try fetchExportCollections(),
                collectionItems: try fetchExportCollectionItems()
            )
            try validateExportRelationships(snapshot)
            return snapshot
        }
    }

    private func fetchExportFolders() throws -> [PersistedExportLibraryFolder] {
        let statement = try preparePersistenceQuery("""
            SELECT id, library_id, display_name, is_available, last_seen_at,
                   last_scan_at, created_at, updated_at
            FROM library_folders
            ORDER BY id ASC
            """)
        var values: [PersistedExportLibraryFolder] = []
        while try statement.step() {
            values.append(
                PersistedExportLibraryFolder(
                    id: try requiredExportString(statement, 0),
                    libraryID: try requiredExportString(statement, 1),
                    displayName: try requiredExportString(statement, 2),
                    isAvailable: try requiredExportBool(statement, 3),
                    lastSeenAt: decodePersistenceDate(statement.double(at: 4)),
                    lastScanAt: decodePersistenceDate(statement.double(at: 5)),
                    createdAt: try requiredExportDate(statement, 6),
                    updatedAt: try requiredExportDate(statement, 7)
                )
            )
        }
        return values
    }

    private func fetchExportMediaItems() throws -> [MediaItem] {
        let statement = try preparePersistenceQuery("""
            SELECT id, media_type, title, normalized_title, year, series_title,
                   season_number, episode_number, episode_title, created_at, updated_at
            FROM media_items
            ORDER BY id ASC
            """)
        var values: [MediaItem] = []
        while try statement.step() {
            let mediaType = try requiredExportEnum(MediaType.self, statement, 1)
            let episodeInfo: EpisodeInfo?
            if mediaType == .episode {
                episodeInfo = EpisodeInfo(
                    seriesTitle: try requiredExportString(statement, 5),
                    seasonNumber: try requiredExportInt(statement, 6),
                    episodeNumber: try requiredExportInt(statement, 7),
                    episodeTitle: statement.string(at: 8)
                )
            } else {
                episodeInfo = nil
            }
            values.append(
                MediaItem(
                    id: try requiredExportString(statement, 0),
                    mediaType: mediaType,
                    title: try requiredExportString(statement, 2),
                    normalizedTitle: try requiredExportString(statement, 3),
                    year: statement.int(at: 4),
                    episodeInfo: episodeInfo,
                    createdAt: try requiredExportDate(statement, 9),
                    updatedAt: try requiredExportDate(statement, 10)
                )
            )
        }
        return values
    }

    private func fetchExportMediaFiles() throws -> [PersistedExportMediaFile] {
        let statement = try preparePersistenceQuery("""
            SELECT id, media_item_id, library_folder_id, relative_path, file_name,
                   file_extension, file_size_bytes, modified_at, is_available,
                   last_seen_at, created_at, updated_at
            FROM media_files
            ORDER BY id ASC
            """)
        var values: [PersistedExportMediaFile] = []
        while try statement.step() {
            values.append(
                PersistedExportMediaFile(
                    id: try requiredExportString(statement, 0),
                    mediaItemID: try requiredExportString(statement, 1),
                    libraryFolderID: try requiredExportString(statement, 2),
                    relativePath: try requiredExportString(statement, 3),
                    fileName: try requiredExportString(statement, 4),
                    fileExtension: try requiredExportString(statement, 5),
                    fileSizeBytes: try requiredExportInt64(statement, 6),
                    modifiedAt: decodePersistenceDate(statement.double(at: 7)),
                    isAvailable: try requiredExportBool(statement, 8),
                    lastSeenAt: decodePersistenceDate(statement.double(at: 9)),
                    createdAt: try requiredExportDate(statement, 10),
                    updatedAt: try requiredExportDate(statement, 11)
                )
            )
        }
        return values
    }

    private func fetchExportPlaybackHistory() throws -> [PlaybackHistory] {
        let statement = try preparePersistenceQuery("""
            SELECT id, media_item_id, media_file_id, position_ms, duration_ms,
                   completed, play_count, last_played_at, created_at, updated_at
            FROM playback_history
            ORDER BY id ASC
            """)
        var values: [PlaybackHistory] = []
        while try statement.step() {
            values.append(
                PlaybackHistory(
                    id: try requiredExportString(statement, 0),
                    mediaItemID: try requiredExportString(statement, 1),
                    mediaFileID: try requiredExportString(statement, 2),
                    positionMS: try requiredExportInt(statement, 3),
                    durationMS: statement.int(at: 4),
                    completed: try requiredExportBool(statement, 5),
                    playCount: try requiredExportInt(statement, 6),
                    lastPlayedAt: try requiredExportDate(statement, 7),
                    createdAt: try requiredExportDate(statement, 8),
                    updatedAt: try requiredExportDate(statement, 9)
                )
            )
        }
        return values
    }

    private func fetchExportMetadataItems() throws -> [MetadataItem] {
        let statement = try preparePersistenceQuery("""
            SELECT id, media_item_id, title, original_title, summary, language,
                   release_date, air_date, title_override_locked,
                   summary_override_locked, language_override_locked, created_at, updated_at
            FROM metadata_items
            ORDER BY id ASC
            """)
        var values: [MetadataItem] = []
        while try statement.step() {
            values.append(
                MetadataItem(
                    id: try requiredExportString(statement, 0),
                    mediaItemID: try requiredExportString(statement, 1),
                    title: statement.string(at: 2),
                    originalTitle: statement.string(at: 3),
                    summary: statement.string(at: 4),
                    language: statement.string(at: 5),
                    releaseDate: statement.string(at: 6),
                    airDate: statement.string(at: 7),
                    titleOverrideLocked: try requiredExportBool(statement, 8),
                    summaryOverrideLocked: try requiredExportBool(statement, 9),
                    languageOverrideLocked: try requiredExportBool(statement, 10),
                    createdAt: try requiredExportDate(statement, 11),
                    updatedAt: try requiredExportDate(statement, 12)
                )
            )
        }
        return values
    }

    private func fetchExportMetadataExternalIDs() throws -> [MetadataExternalID] {
        let statement = try preparePersistenceQuery("""
            SELECT id, media_item_id, provider, external_id_type, external_id_value,
                   created_at, updated_at
            FROM metadata_external_ids
            ORDER BY id ASC
            """)
        var values: [MetadataExternalID] = []
        while try statement.step() {
            values.append(
                MetadataExternalID(
                    id: try requiredExportString(statement, 0),
                    mediaItemID: try requiredExportString(statement, 1),
                    provider: try requiredExportEnum(MetadataProviderName.self, statement, 2),
                    externalIDType: try requiredExportEnum(MetadataExternalIDType.self, statement, 3),
                    externalIDValue: try requiredExportString(statement, 4),
                    createdAt: try requiredExportDate(statement, 5),
                    updatedAt: try requiredExportDate(statement, 6)
                )
            )
        }
        return values
    }

    private func fetchExportMetadataSourceRecords() throws -> [PersistedExportMetadataSourceRecord] {
        let statement = try preparePersistenceQuery("""
            SELECT id, media_item_id, provider, provider_id, provider_media_type,
                   confidence, match_source, manual_match_locked, matched_at,
                   refreshed_at, created_at, updated_at
            FROM metadata_source_records
            ORDER BY id ASC
            """)
        var values: [PersistedExportMetadataSourceRecord] = []
        while try statement.step() {
            values.append(
                PersistedExportMetadataSourceRecord(
                    id: try requiredExportString(statement, 0),
                    mediaItemID: try requiredExportString(statement, 1),
                    provider: try requiredExportEnum(MetadataProviderName.self, statement, 2),
                    providerID: try requiredExportString(statement, 3),
                    providerMediaType: try requiredExportEnum(MetadataProviderMediaType.self, statement, 4),
                    confidence: try requiredExportDouble(statement, 5),
                    matchSource: try requiredExportEnum(MetadataMatchSource.self, statement, 6),
                    manualMatchLocked: try requiredExportBool(statement, 7),
                    matchedAt: try requiredExportDate(statement, 8),
                    refreshedAt: decodePersistenceDate(statement.double(at: 9)),
                    createdAt: try requiredExportDate(statement, 10),
                    updatedAt: try requiredExportDate(statement, 11)
                )
            )
        }
        return values
    }

    private func fetchExportPosterAssets() throws -> [PersistedExportPosterAsset] {
        let statement = try preparePersistenceQuery("""
            SELECT id, media_item_id, asset_type, source, remote_path, width, height,
                   is_selected, selection_source, created_at, updated_at
            FROM poster_assets
            ORDER BY id ASC
            """)
        var values: [PersistedExportPosterAsset] = []
        while try statement.step() {
            values.append(
                PersistedExportPosterAsset(
                    id: try requiredExportString(statement, 0),
                    mediaItemID: try requiredExportString(statement, 1),
                    assetType: try requiredExportEnum(PosterAssetType.self, statement, 2),
                    source: try requiredExportEnum(PosterAssetSource.self, statement, 3),
                    remotePath: try requiredExportString(statement, 4),
                    width: statement.int(at: 5),
                    height: statement.int(at: 6),
                    isSelected: try requiredExportBool(statement, 7),
                    selectionSource: try requiredExportEnum(PosterSelectionSource.self, statement, 8),
                    createdAt: try requiredExportDate(statement, 9),
                    updatedAt: try requiredExportDate(statement, 10)
                )
            )
        }
        return values
    }

    private func fetchExportSubtitleAssets() throws -> [SubtitleAsset] {
        let statement = try preparePersistenceQuery("""
            SELECT id, media_item_id, media_file_id, library_folder_id, relative_path,
                   file_name, file_extension, format, language_code, display_name,
                   source, is_available, last_seen_at, created_at, updated_at
            FROM subtitle_assets
            ORDER BY id ASC
            """)
        var values: [SubtitleAsset] = []
        while try statement.step() {
            values.append(
                SubtitleAsset(
                    id: try requiredExportString(statement, 0),
                    mediaItemID: try requiredExportString(statement, 1),
                    mediaFileID: statement.string(at: 2),
                    libraryFolderID: statement.string(at: 3),
                    relativePath: try requiredExportString(statement, 4),
                    fileName: try requiredExportString(statement, 5),
                    fileExtension: try requiredExportString(statement, 6),
                    format: try requiredExportEnum(SubtitleFormat.self, statement, 7),
                    languageCode: statement.string(at: 8),
                    displayName: statement.string(at: 9),
                    source: try requiredExportEnum(SubtitleAssetSource.self, statement, 10),
                    isAvailable: try requiredExportBool(statement, 11),
                    lastSeenAt: decodePersistenceDate(statement.double(at: 12)),
                    createdAt: try requiredExportDate(statement, 13),
                    updatedAt: try requiredExportDate(statement, 14)
                )
            )
        }
        return values
    }

    private func fetchExportTags() throws -> [Tag] {
        let statement = try preparePersistenceQuery("""
            SELECT id, name, normalized_name, source, created_at, updated_at
            FROM tags
            ORDER BY id ASC
            """)
        var values: [Tag] = []
        while try statement.step() {
            values.append(
                Tag(
                    id: try requiredExportString(statement, 0),
                    name: try requiredExportString(statement, 1),
                    normalizedName: try requiredExportString(statement, 2),
                    source: try requiredExportEnum(TagSource.self, statement, 3),
                    createdAt: try requiredExportDate(statement, 4),
                    updatedAt: try requiredExportDate(statement, 5)
                )
            )
        }
        return values
    }

    private func fetchExportMediaItemTags() throws -> [MediaItemTag] {
        let statement = try preparePersistenceQuery("""
            SELECT media_item_id, tag_id, assigned_at, updated_at
            FROM media_item_tags
            ORDER BY media_item_id ASC, tag_id ASC
            """)
        var values: [MediaItemTag] = []
        while try statement.step() {
            values.append(
                MediaItemTag(
                    mediaItemID: try requiredExportString(statement, 0),
                    tagID: try requiredExportString(statement, 1),
                    assignedAt: try requiredExportDate(statement, 2),
                    updatedAt: try requiredExportDate(statement, 3)
                )
            )
        }
        return values
    }

    private func fetchExportFavorites() throws -> [FavoriteMediaItem] {
        let statement = try preparePersistenceQuery("""
            SELECT media_item_id, created_at, updated_at
            FROM favorite_media_items
            ORDER BY media_item_id ASC
            """)
        var values: [FavoriteMediaItem] = []
        while try statement.step() {
            values.append(
                FavoriteMediaItem(
                    mediaItemID: try requiredExportString(statement, 0),
                    createdAt: try requiredExportDate(statement, 1),
                    updatedAt: try requiredExportDate(statement, 2)
                )
            )
        }
        return values
    }

    private func fetchExportCollections() throws -> [MediaCollection] {
        let statement = try preparePersistenceQuery("""
            SELECT id, name, normalized_name, description, created_at, updated_at
            FROM collections
            ORDER BY id ASC
            """)
        var values: [MediaCollection] = []
        while try statement.step() {
            values.append(
                MediaCollection(
                    id: try requiredExportString(statement, 0),
                    name: try requiredExportString(statement, 1),
                    normalizedName: try requiredExportString(statement, 2),
                    description: statement.string(at: 3),
                    createdAt: try requiredExportDate(statement, 4),
                    updatedAt: try requiredExportDate(statement, 5)
                )
            )
        }
        return values
    }

    private func fetchExportCollectionItems() throws -> [CollectionItem] {
        let statement = try preparePersistenceQuery("""
            SELECT collection_id, media_item_id, added_at, updated_at
            FROM collection_items
            ORDER BY collection_id ASC, media_item_id ASC
            """)
        var values: [CollectionItem] = []
        while try statement.step() {
            values.append(
                CollectionItem(
                    collectionID: try requiredExportString(statement, 0),
                    mediaItemID: try requiredExportString(statement, 1),
                    addedAt: try requiredExportDate(statement, 2),
                    updatedAt: try requiredExportDate(statement, 3)
                )
            )
        }
        return values
    }
}

private func validateExportRelationships(_ snapshot: PersistedLibraryExportSnapshot) throws {
    let folderIDs = Set(snapshot.folders.map(\.id))
    let mediaItemIDs = Set(snapshot.mediaItems.map(\.id))
    let mediaFileIDs = Set(snapshot.mediaFiles.map(\.id))
    let tagIDs = Set(snapshot.tags.map(\.id))
    let collectionIDs = Set(snapshot.collections.map(\.id))

    try requireExport(snapshot.folders.allSatisfy { $0.libraryID == snapshot.library.id }, "folder library")
    try requireExport(snapshot.mediaFiles.allSatisfy {
        mediaItemIDs.contains($0.mediaItemID) && folderIDs.contains($0.libraryFolderID)
    }, "media file")
    try requireExport(snapshot.playbackHistory.allSatisfy {
        mediaItemIDs.contains($0.mediaItemID) && mediaFileIDs.contains($0.mediaFileID)
    }, "playback history")
    try requireExport(snapshot.metadataItems.allSatisfy { mediaItemIDs.contains($0.mediaItemID) }, "metadata item")
    try requireExport(snapshot.metadataExternalIDs.allSatisfy { mediaItemIDs.contains($0.mediaItemID) }, "metadata external ID")
    try requireExport(snapshot.metadataSourceRecords.allSatisfy { mediaItemIDs.contains($0.mediaItemID) }, "metadata source")
    try requireExport(snapshot.posterAssets.allSatisfy { mediaItemIDs.contains($0.mediaItemID) }, "poster")
    try requireExport(snapshot.subtitleAssets.allSatisfy {
        mediaItemIDs.contains($0.mediaItemID)
            && $0.mediaFileID.map(mediaFileIDs.contains) ?? true
            && $0.libraryFolderID.map(folderIDs.contains) ?? true
    }, "subtitle")
    try requireExport(snapshot.mediaItemTags.allSatisfy {
        mediaItemIDs.contains($0.mediaItemID) && tagIDs.contains($0.tagID)
    }, "tag assignment")
    try requireExport(snapshot.favorites.allSatisfy { mediaItemIDs.contains($0.mediaItemID) }, "favorite")
    try requireExport(snapshot.collectionItems.allSatisfy {
        collectionIDs.contains($0.collectionID) && mediaItemIDs.contains($0.mediaItemID)
    }, "collection item")
}

private func requireExport(_ condition: Bool, _ relationship: String) throws {
    guard condition else {
        throw PersistenceError.libraryExportIntegrityViolation(
            "\(relationship) references an excluded parent"
        )
    }
}

private func requiredExportString(_ statement: SQLiteStatement, _ index: Int32) throws -> String {
    guard let value = statement.string(at: index) else {
        throw PersistenceError.stepFailed("expected export string at column \(index)")
    }
    return value
}

private func requiredExportInt(_ statement: SQLiteStatement, _ index: Int32) throws -> Int {
    guard let value = statement.int(at: index) else {
        throw PersistenceError.stepFailed("expected export int at column \(index)")
    }
    return value
}

private func requiredExportInt64(_ statement: SQLiteStatement, _ index: Int32) throws -> Int64 {
    guard let value = statement.int64(at: index) else {
        throw PersistenceError.stepFailed("expected export int64 at column \(index)")
    }
    return value
}

private func requiredExportDouble(_ statement: SQLiteStatement, _ index: Int32) throws -> Double {
    guard let value = statement.double(at: index) else {
        throw PersistenceError.stepFailed("expected export double at column \(index)")
    }
    return value
}

private func requiredExportBool(_ statement: SQLiteStatement, _ index: Int32) throws -> Bool {
    guard let value = statement.int(at: index), value == 0 || value == 1 else {
        throw PersistenceError.stepFailed("expected export bool at column \(index)")
    }
    return value == 1
}

private func requiredExportDate(_ statement: SQLiteStatement, _ index: Int32) throws -> Date {
    guard let timestamp = statement.double(at: index) else {
        throw PersistenceError.stepFailed("expected export date at column \(index)")
    }
    return Date(timeIntervalSince1970: timestamp)
}

private func requiredExportEnum<T>(
    _ type: T.Type,
    _ statement: SQLiteStatement,
    _ index: Int32
) throws -> T where T: RawRepresentable, T.RawValue == String {
    let rawValue = try requiredExportString(statement, index)
    guard let value = T(rawValue: rawValue) else {
        throw PersistenceError.stepFailed("expected export enum at column \(index)")
    }
    return value
}
