import Domain
import Foundation

public struct PersistedSubtitleAsset: Sendable, Equatable {
    public let asset: SubtitleAsset
    public let folderRootPath: String
    public let folderIsAvailable: Bool

    public var isUsable: Bool {
        asset.isAvailable && folderIsAvailable && !folderRootPath.isEmpty
    }
}

extension CineMindStore {
    public func saveSubtitleAsset(_ asset: SubtitleAsset) throws {
        if let mediaFileID = asset.mediaFileID {
            try verifySubtitleMediaFile(mediaFileID, belongsTo: asset.mediaItemID)
        }

        let statement = try preparePersistenceQuery("""
            INSERT INTO subtitle_assets (
                id, media_item_id, media_file_id, library_folder_id, relative_path,
                file_name, file_extension, format, language_code, display_name,
                source, is_available, last_seen_at, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                media_item_id = excluded.media_item_id,
                media_file_id = excluded.media_file_id,
                library_folder_id = excluded.library_folder_id,
                relative_path = excluded.relative_path,
                file_name = excluded.file_name,
                file_extension = excluded.file_extension,
                format = excluded.format,
                language_code = excluded.language_code,
                display_name = excluded.display_name,
                source = excluded.source,
                is_available = excluded.is_available,
                last_seen_at = excluded.last_seen_at,
                updated_at = excluded.updated_at
            """)
        try bindSubtitleAsset(asset, to: statement)
        _ = try statement.step()
    }

    public func fetchSubtitleAssets(mediaItemID: MediaItemID) throws -> [SubtitleAsset] {
        let statement = try preparePersistenceQuery(subtitleAssetSelectSQL + """
             WHERE media_item_id = ?
            ORDER BY is_available DESC, language_code ASC, relative_path ASC
            """)
        try statement.bind(mediaItemID, at: 1)
        return try mapSubtitleAssets(statement)
    }

    public func fetchSubtitleAssets(mediaFileID: MediaFileID) throws -> [SubtitleAsset] {
        let statement = try preparePersistenceQuery(subtitleAssetSelectSQL + """
             WHERE media_file_id = ?
            ORDER BY is_available DESC, language_code ASC, relative_path ASC
            """)
        try statement.bind(mediaFileID, at: 1)
        return try mapSubtitleAssets(statement)
    }

    public func fetchSubtitleAssets(libraryFolderID: LibraryFolderID) throws -> [SubtitleAsset] {
        let statement = try preparePersistenceQuery(subtitleAssetSelectSQL + """
             WHERE library_folder_id = ?
            ORDER BY relative_path ASC
            """)
        try statement.bind(libraryFolderID, at: 1)
        return try mapSubtitleAssets(statement)
    }

    public func fetchSubtitleAsset(
        libraryFolderID: LibraryFolderID,
        relativePath: String,
        source: SubtitleAssetSource = .external
    ) throws -> SubtitleAsset? {
        let statement = try preparePersistenceQuery(subtitleAssetSelectSQL + """
             WHERE library_folder_id = ?
               AND relative_path = ?
               AND source = ?
            LIMIT 1
            """)
        try statement.bind(libraryFolderID, at: 1)
        try statement.bind(relativePath, at: 2)
        try statement.bind(source.rawValue, at: 3)

        guard try statement.step() else {
            return nil
        }
        return try mapSubtitleAsset(statement)
    }

    public func fetchPersistedSubtitleAssets(mediaFileID: MediaFileID) throws -> [PersistedSubtitleAsset] {
        let statement = try preparePersistenceQuery("""
            SELECT subtitle_assets.id,
                   subtitle_assets.media_item_id,
                   subtitle_assets.media_file_id,
                   subtitle_assets.library_folder_id,
                   subtitle_assets.relative_path,
                   subtitle_assets.file_name,
                   subtitle_assets.file_extension,
                   subtitle_assets.format,
                   subtitle_assets.language_code,
                   subtitle_assets.display_name,
                   subtitle_assets.source,
                   subtitle_assets.is_available,
                   subtitle_assets.last_seen_at,
                   subtitle_assets.created_at,
                   subtitle_assets.updated_at,
                   COALESCE(library_folders.root_path, '') AS folder_root_path,
                   COALESCE(library_folders.is_available, 0) AS folder_is_available
            FROM subtitle_assets
            LEFT JOIN library_folders
              ON library_folders.id = subtitle_assets.library_folder_id
            WHERE subtitle_assets.media_file_id = ?
            ORDER BY subtitle_assets.is_available DESC,
                     subtitle_assets.language_code ASC,
                     subtitle_assets.relative_path ASC
            """)
        try statement.bind(mediaFileID, at: 1)

        var assets: [PersistedSubtitleAsset] = []
        while try statement.step() {
            assets.append(
                PersistedSubtitleAsset(
                    asset: try mapSubtitleAsset(statement),
                    folderRootPath: statement.string(at: 15) ?? "",
                    folderIsAvailable: statement.bool(at: 16)
                )
            )
        }
        return assets
    }

    public func markSubtitleAssetUnavailable(id: SubtitleAssetID, updatedAt: Date = Date()) throws {
        let statement = try preparePersistenceQuery("""
            UPDATE subtitle_assets
            SET is_available = 0,
                updated_at = ?
            WHERE id = ?
            """)
        try statement.bind(subtitleTimestamp(updatedAt), at: 1)
        try statement.bind(id, at: 2)
        _ = try statement.step()
    }

    private func verifySubtitleMediaFile(
        _ mediaFileID: MediaFileID,
        belongsTo mediaItemID: MediaItemID
    ) throws {
        guard let file = try fetchMediaFile(id: mediaFileID) else {
            return
        }
        guard file.mediaItemID == mediaItemID else {
            throw PersistenceError.mediaFileMediaItemMismatch(
                mediaItemID: mediaItemID,
                mediaFileID: mediaFileID,
                actualMediaItemID: file.mediaItemID
            )
        }
    }

    private func bindSubtitleAsset(_ asset: SubtitleAsset, to statement: SQLiteStatement) throws {
        try statement.bind(asset.id, at: 1)
        try statement.bind(asset.mediaItemID, at: 2)
        try statement.bind(asset.mediaFileID, at: 3)
        try statement.bind(asset.libraryFolderID, at: 4)
        try statement.bind(asset.relativePath, at: 5)
        try statement.bind(asset.fileName, at: 6)
        try statement.bind(asset.fileExtension, at: 7)
        try statement.bind(asset.format.rawValue, at: 8)
        try statement.bind(asset.languageCode, at: 9)
        try statement.bind(asset.displayName, at: 10)
        try statement.bind(asset.source.rawValue, at: 11)
        try statement.bind(asset.isAvailable, at: 12)
        try statement.bind(subtitleTimestamp(asset.lastSeenAt), at: 13)
        try statement.bind(subtitleTimestamp(asset.createdAt), at: 14)
        try statement.bind(subtitleTimestamp(asset.updatedAt), at: 15)
    }

    private func mapSubtitleAssets(_ statement: SQLiteStatement) throws -> [SubtitleAsset] {
        var assets: [SubtitleAsset] = []
        while try statement.step() {
            assets.append(try mapSubtitleAsset(statement))
        }
        return assets
    }

    private func mapSubtitleAsset(_ statement: SQLiteStatement) throws -> SubtitleAsset {
        SubtitleAsset(
            id: try requiredSubtitleString(statement, 0),
            mediaItemID: try requiredSubtitleString(statement, 1),
            mediaFileID: statement.string(at: 2),
            libraryFolderID: statement.string(at: 3),
            relativePath: try requiredSubtitleString(statement, 4),
            fileName: try requiredSubtitleString(statement, 5),
            fileExtension: try requiredSubtitleString(statement, 6),
            format: SubtitleFormat(rawValue: try requiredSubtitleString(statement, 7)) ?? .srt,
            languageCode: statement.string(at: 8),
            displayName: statement.string(at: 9),
            source: SubtitleAssetSource(rawValue: try requiredSubtitleString(statement, 10)) ?? .external,
            isAvailable: try requiredSubtitleBool(statement, 11),
            lastSeenAt: decodePersistenceDate(statement.double(at: 12)),
            createdAt: try requiredSubtitleDate(statement, 13),
            updatedAt: try requiredSubtitleDate(statement, 14)
        )
    }

    private func subtitleTimestamp(_ date: Date?) -> Double? {
        date?.timeIntervalSince1970
    }

    private func requiredSubtitleString(_ statement: SQLiteStatement, _ index: Int32) throws -> String {
        guard let value = statement.string(at: index) else {
            throw PersistenceError.stepFailed("expected string at column \(index)")
        }
        return value
    }

    private func requiredSubtitleBool(_ statement: SQLiteStatement, _ index: Int32) throws -> Bool {
        guard let value = statement.int(at: index), value == 0 || value == 1 else {
            throw PersistenceError.stepFailed("expected bool 0/1 at column \(index)")
        }
        return value == 1
    }

    private func requiredSubtitleDate(_ statement: SQLiteStatement, _ index: Int32) throws -> Date {
        guard let value = decodePersistenceDate(statement.double(at: index)) else {
            throw PersistenceError.stepFailed("expected date at column \(index)")
        }
        return value
    }
}

private let subtitleAssetSelectSQL = """
    SELECT id, media_item_id, media_file_id, library_folder_id, relative_path,
           file_name, file_extension, format, language_code, display_name,
           source, is_available, last_seen_at, created_at, updated_at
    FROM subtitle_assets
    """
