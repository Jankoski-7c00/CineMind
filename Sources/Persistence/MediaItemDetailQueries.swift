import Domain
import Foundation

public struct PersistedMediaFileSummary: Sendable, Equatable {
    public let id: MediaFileID
    public let fileName: String
    public let fileExtension: String
    public let fileSizeBytes: Int64
    public let relativePath: String
    public let isAvailable: Bool
    public let folderDisplayName: String?
    public let folderIsAvailable: Bool?
}

public struct PersistedMediaItemDetail: Sendable, Equatable {
    public let id: MediaItemID
    public let mediaType: MediaType
    public let title: String
    public let year: Int?
    public let seriesTitle: String?
    public let seasonNumber: Int?
    public let episodeNumber: Int?
    public let episodeTitle: String?
    public let summary: String?
    public let language: String?
    public let hasMetadataItem: Bool
    public let hasMetadataSourceRecord: Bool
    public let latestPlayedAt: Date?
    public let files: [PersistedMediaFileSummary]
}

extension CineMindStore {
    public func fetchMediaItemDetail(id: MediaItemID) throws -> PersistedMediaItemDetail? {
        let statement = try preparePersistenceQuery(mediaItemDetailSQL)
        try statement.bind(id, at: 1)

        guard try statement.step() else {
            return nil
        }

        let files = try fetchDetailFiles(mediaItemID: id)

        return PersistedMediaItemDetail(
            id: try requiredDetailString(statement, 0),
            mediaType: try requiredDetailMediaType(statement, 1),
            title: try requiredDetailString(statement, 2),
            year: statement.int(at: 3),
            seriesTitle: statement.string(at: 4),
            seasonNumber: statement.int(at: 5),
            episodeNumber: statement.int(at: 6),
            episodeTitle: statement.string(at: 7),
            summary: statement.string(at: 8),
            language: statement.string(at: 9),
            hasMetadataItem: try requiredDetailBool(statement, 10),
            hasMetadataSourceRecord: try requiredDetailBool(statement, 11),
            latestPlayedAt: decodePersistenceDate(statement.double(at: 12)),
            files: files
        )
    }

    private func fetchDetailFiles(mediaItemID: MediaItemID) throws -> [PersistedMediaFileSummary] {
        let statement = try preparePersistenceQuery(mediaItemDetailFilesSQL)
        try statement.bind(mediaItemID, at: 1)

        var files: [PersistedMediaFileSummary] = []
        while try statement.step() {
            files.append(try mapDetailFile(statement))
        }
        return files
    }

    private func mapDetailFile(_ statement: SQLiteStatement) throws -> PersistedMediaFileSummary {
        let fileAvailable = try requiredDetailBool(statement, 5)
        let folderAvailable = statement.int(at: 7).map { $0 == 1 } ?? false

        return PersistedMediaFileSummary(
            id: try requiredDetailString(statement, 0),
            fileName: try requiredDetailString(statement, 1),
            fileExtension: try requiredDetailString(statement, 2),
            fileSizeBytes: Int64(try requiredDetailInt(statement, 3)),
            relativePath: try requiredDetailString(statement, 4),
            isAvailable: fileAvailable && folderAvailable,
            folderDisplayName: statement.string(at: 6),
            folderIsAvailable: statement.int(at: 7).map { $0 == 1 }
        )
    }
}

private let mediaItemDetailSQL = """
    WITH latest_playback AS (
        SELECT playback_history.media_item_id,
               MAX(playback_history.last_played_at) AS latest_played_at
        FROM playback_history
        GROUP BY playback_history.media_item_id
    ),
    metadata_item_presence AS (
        SELECT DISTINCT metadata_items.media_item_id,
               1 AS has_metadata_item
        FROM metadata_items
    ),
    metadata_source_presence AS (
        SELECT DISTINCT metadata_source_records.media_item_id,
               1 AS has_metadata_source_record
        FROM metadata_source_records
    )
    SELECT media_items.id,
           media_items.media_type,
           media_items.title,
           media_items.year,
           media_items.series_title,
           media_items.season_number,
           media_items.episode_number,
           media_items.episode_title,
           metadata_items.summary,
           metadata_items.language,
           COALESCE(metadata_item_presence.has_metadata_item, 0) AS has_metadata_item,
           COALESCE(metadata_source_presence.has_metadata_source_record, 0) AS has_metadata_source_record,
           latest_playback.latest_played_at
    FROM media_items
    LEFT JOIN metadata_items
      ON metadata_items.media_item_id = media_items.id
    LEFT JOIN latest_playback
      ON latest_playback.media_item_id = media_items.id
    LEFT JOIN metadata_item_presence
      ON metadata_item_presence.media_item_id = media_items.id
    LEFT JOIN metadata_source_presence
      ON metadata_source_presence.media_item_id = media_items.id
    WHERE media_items.id = ?
    LIMIT 1
    """

private let mediaItemDetailFilesSQL = """
    SELECT media_files.id,
           media_files.file_name,
           media_files.file_extension,
           media_files.file_size_bytes,
           media_files.relative_path,
           media_files.is_available,
           library_folders.display_name,
           library_folders.is_available
    FROM media_files
    INNER JOIN library_folders
      ON library_folders.id = media_files.library_folder_id
    WHERE media_files.media_item_id = ?
    ORDER BY media_files.relative_path ASC
    """

private func requiredDetailString(_ statement: SQLiteStatement, _ index: Int32) throws -> String {
    guard let value = statement.string(at: index) else {
        throw PersistenceError.stepFailed("expected string at column \(index)")
    }
    return value
}

private func requiredDetailInt(_ statement: SQLiteStatement, _ index: Int32) throws -> Int {
    guard let value = statement.int(at: index) else {
        throw PersistenceError.stepFailed("expected int at column \(index)")
    }
    return value
}

private func requiredDetailBool(_ statement: SQLiteStatement, _ index: Int32) throws -> Bool {
    guard let value = statement.int(at: index), value == 0 || value == 1 else {
        throw PersistenceError.stepFailed("expected bool 0/1 at column \(index)")
    }
    return value == 1
}

private func requiredDetailMediaType(
    _ statement: SQLiteStatement,
    _ index: Int32
) throws -> MediaType {
    let rawValue = try requiredDetailString(statement, index)
    guard let mediaType = MediaType(rawValue: rawValue) else {
        throw PersistenceError.stepFailed("expected media type at column \(index)")
    }
    return mediaType
}
