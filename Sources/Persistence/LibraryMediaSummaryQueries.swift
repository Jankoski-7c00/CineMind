import Domain
import Foundation

public struct PersistedMediaItemSummary: Sendable, Equatable {
    public let id: MediaItemID
    public let mediaType: MediaType
    public let title: String
    public let year: Int?
    public let seriesTitle: String?
    public let seasonNumber: Int?
    public let episodeNumber: Int?
    public let episodeTitle: String?
    public let totalFileCount: Int
    public let availableFileCount: Int
    public let unavailableFileCount: Int
    public let hasMetadataItem: Bool
    public let hasMetadataSourceRecord: Bool
    public let latestPlayedAt: Date?
}

extension CineMindStore {
    public func fetchMediaItemSummaries(
        mediaType: MediaType?,
        limit: Int,
        offset: Int = 0
    ) throws -> [PersistedMediaItemSummary] {
        guard limit > 0 else {
            return []
        }

        let statement = try preparePersistenceQuery(
            mediaItemSummarySQL(hasMediaTypeFilter: mediaType != nil)
        )
        var bindIndex: Int32 = 1
        if let mediaType {
            try statement.bind(mediaType.rawValue, at: bindIndex)
            bindIndex += 1
        }
        try statement.bind(limit, at: bindIndex)
        try statement.bind(max(offset, 0), at: bindIndex + 1)

        var summaries: [PersistedMediaItemSummary] = []
        while try statement.step() {
            summaries.append(try mapMediaItemSummary(statement))
        }
        return summaries
    }

    private func mapMediaItemSummary(_ statement: SQLiteStatement) throws -> PersistedMediaItemSummary {
        PersistedMediaItemSummary(
            id: try requiredSummaryString(statement, 0),
            mediaType: try requiredSummaryMediaType(statement, 1),
            title: try requiredSummaryString(statement, 2),
            year: statement.int(at: 3),
            seriesTitle: statement.string(at: 4),
            seasonNumber: statement.int(at: 5),
            episodeNumber: statement.int(at: 6),
            episodeTitle: statement.string(at: 7),
            totalFileCount: try requiredSummaryInt(statement, 8),
            availableFileCount: try requiredSummaryInt(statement, 9),
            unavailableFileCount: try requiredSummaryInt(statement, 10),
            hasMetadataItem: try requiredSummaryBool(statement, 11),
            hasMetadataSourceRecord: try requiredSummaryBool(statement, 12),
            latestPlayedAt: decodePersistenceDate(statement.double(at: 13))
        )
    }
}

private func mediaItemSummarySQL(hasMediaTypeFilter: Bool) -> String {
    """
    WITH file_counts AS (
        SELECT media_files.media_item_id,
               COUNT(*) AS total_file_count,
               SUM(
                   CASE
                       WHEN media_files.is_available = 1
                        AND library_folders.is_available = 1 THEN 1
                       ELSE 0
                   END
               ) AS available_file_count,
               SUM(
                   CASE
                       WHEN media_files.is_available = 0
                         OR library_folders.is_available = 0 THEN 1
                       ELSE 0
                   END
               ) AS unavailable_file_count
        FROM media_files
        INNER JOIN library_folders
          ON library_folders.id = media_files.library_folder_id
        GROUP BY media_files.media_item_id
    ),
    latest_playback AS (
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
           COALESCE(file_counts.total_file_count, 0) AS total_file_count,
           COALESCE(file_counts.available_file_count, 0) AS available_file_count,
           COALESCE(file_counts.unavailable_file_count, 0) AS unavailable_file_count,
           COALESCE(metadata_item_presence.has_metadata_item, 0) AS has_metadata_item,
           COALESCE(metadata_source_presence.has_metadata_source_record, 0) AS has_metadata_source_record,
           latest_playback.latest_played_at
    FROM media_items
    LEFT JOIN file_counts
      ON file_counts.media_item_id = media_items.id
    LEFT JOIN latest_playback
      ON latest_playback.media_item_id = media_items.id
    LEFT JOIN metadata_item_presence
      ON metadata_item_presence.media_item_id = media_items.id
    LEFT JOIN metadata_source_presence
      ON metadata_source_presence.media_item_id = media_items.id
    \(hasMediaTypeFilter ? "WHERE media_items.media_type = ?" : "")
    ORDER BY media_items.title COLLATE NOCASE ASC,
             media_items.id ASC
    LIMIT ? OFFSET ?
    """
}

private func requiredSummaryString(_ statement: SQLiteStatement, _ index: Int32) throws -> String {
    guard let value = statement.string(at: index) else {
        throw PersistenceError.stepFailed("expected string at column \(index)")
    }
    return value
}

private func requiredSummaryInt(_ statement: SQLiteStatement, _ index: Int32) throws -> Int {
    guard let value = statement.int(at: index) else {
        throw PersistenceError.stepFailed("expected int at column \(index)")
    }
    return value
}

private func requiredSummaryBool(_ statement: SQLiteStatement, _ index: Int32) throws -> Bool {
    guard let value = statement.int(at: index), value == 0 || value == 1 else {
        throw PersistenceError.stepFailed("expected bool 0/1 at column \(index)")
    }
    return value == 1
}

private func requiredSummaryMediaType(
    _ statement: SQLiteStatement,
    _ index: Int32
) throws -> MediaType {
    let rawValue = try requiredSummaryString(statement, index)
    guard let mediaType = MediaType(rawValue: rawValue) else {
        throw PersistenceError.stepFailed("expected media type at column \(index)")
    }
    return mediaType
}
