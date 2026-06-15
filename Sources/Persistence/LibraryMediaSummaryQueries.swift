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
    public let isFavorite: Bool
    public let tagLabels: [String]
    public let selectedPosterLocalCachePath: String?

    public init(
        id: MediaItemID,
        mediaType: MediaType,
        title: String,
        year: Int? = nil,
        seriesTitle: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        episodeTitle: String? = nil,
        totalFileCount: Int = 0,
        availableFileCount: Int = 0,
        unavailableFileCount: Int = 0,
        hasMetadataItem: Bool = false,
        hasMetadataSourceRecord: Bool = false,
        latestPlayedAt: Date? = nil,
        isFavorite: Bool = false,
        tagLabels: [String] = [],
        selectedPosterLocalCachePath: String? = nil
    ) {
        self.id = id
        self.mediaType = mediaType
        self.title = title
        self.year = year
        self.seriesTitle = seriesTitle
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.episodeTitle = episodeTitle
        self.totalFileCount = totalFileCount
        self.availableFileCount = availableFileCount
        self.unavailableFileCount = unavailableFileCount
        self.hasMetadataItem = hasMetadataItem
        self.hasMetadataSourceRecord = hasMetadataSourceRecord
        self.latestPlayedAt = latestPlayedAt
        self.isFavorite = isFavorite
        self.tagLabels = tagLabels
        self.selectedPosterLocalCachePath = selectedPosterLocalCachePath
    }
}

extension CineMindStore {
    public func fetchMediaItemSummaries(
        mediaType: MediaType?,
        limit: Int,
        offset: Int = 0
    ) throws -> [PersistedMediaItemSummary] {
        try fetchMediaItemSummaries(
            sql: mediaItemSummarySQL(
                whereClause: mediaType != nil ? "WHERE media_items.media_type = ?" : "",
                orderClause: mediaItemTitleOrderSQL
            ),
            stringBindings: mediaType.map { [$0.rawValue] } ?? [],
            limit: limit,
            offset: offset
        )
    }

    public func fetchRecentlyPlayedMediaItemSummaries(
        limit: Int,
        offset: Int = 0
    ) throws -> [PersistedMediaItemSummary] {
        try fetchMediaItemSummaries(
            sql: mediaItemSummarySQL(
                whereClause: "WHERE latest_playback.latest_played_at IS NOT NULL",
                orderClause: mediaItemRecentlyPlayedOrderSQL
            ),
            stringBindings: [],
            limit: limit,
            offset: offset
        )
    }

    public func fetchMediaItemSummariesNeedingMetadata(
        limit: Int,
        offset: Int = 0
    ) throws -> [PersistedMediaItemSummary] {
        try fetchMediaItemSummaries(
            sql: mediaItemSummarySQL(
                whereClause: """
                    WHERE COALESCE(metadata_item_presence.has_metadata_item, 0) = 0
                       OR COALESCE(metadata_source_presence.has_metadata_source_record, 0) = 0
                    """,
                orderClause: mediaItemTitleOrderSQL
            ),
            stringBindings: [],
            limit: limit,
            offset: offset
        )
    }

    internal func fetchMediaItemSummaries(
        sql: String,
        stringBindings: [String],
        limit: Int,
        offset: Int
    ) throws -> [PersistedMediaItemSummary] {
        guard limit > 0 else {
            return []
        }

        let statement = try preparePersistenceQuery(sql)
        var bindIndex: Int32 = 1
        for stringBinding in stringBindings {
            try statement.bind(stringBinding, at: bindIndex)
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

    internal func mapMediaItemSummary(_ statement: SQLiteStatement) throws -> PersistedMediaItemSummary {
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
            latestPlayedAt: decodePersistenceDate(statement.double(at: 13)),
            isFavorite: try requiredSummaryBool(statement, 14),
            tagLabels: statement.string(at: 15).map(splitTagLabels) ?? [],
            selectedPosterLocalCachePath: statement.string(at: 16)
        )
    }
}

internal let mediaItemTitleOrderSQL = """
    ORDER BY media_items.title COLLATE NOCASE ASC,
             media_items.id ASC
    """

private let mediaItemRecentlyPlayedOrderSQL = """
    ORDER BY latest_playback.latest_played_at DESC,
             media_items.id ASC
    """

internal func mediaItemSummarySQL(whereClause: String, orderClause: String) -> String {
    """
    WITH \(mediaItemSummaryCommonCTESQL)
    SELECT \(mediaItemSummarySelectColumnsSQL)
    FROM media_items
    \(mediaItemSummaryJoinSQL)
    \(whereClause)
    \(orderClause)
    LIMIT ? OFFSET ?
    """
}

internal let mediaItemSummaryCommonCTESQL = """
    file_counts AS (
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
    ),
    favorite_presence AS (
        SELECT favorite_media_items.media_item_id,
               1 AS is_favorite
        FROM favorite_media_items
    ),
    ordered_tag_labels AS (
        SELECT media_item_tags.media_item_id,
               tags.name
        FROM media_item_tags
        INNER JOIN tags
          ON tags.id = media_item_tags.tag_id
        ORDER BY tags.name COLLATE NOCASE ASC,
                 tags.id ASC
    ),
    tag_label_summary AS (
        SELECT ordered_tag_labels.media_item_id,
               GROUP_CONCAT(ordered_tag_labels.name, '\(mediaItemTagLabelSeparator)') AS tag_labels
        FROM ordered_tag_labels
        GROUP BY ordered_tag_labels.media_item_id
    ),
    selected_poster AS (
        SELECT poster_assets.media_item_id,
               poster_assets.local_cache_path
        FROM poster_assets
        WHERE poster_assets.asset_type = 'poster'
          AND poster_assets.is_selected = 1
    )
    """

internal let mediaItemSummarySelectColumnsSQL = """
    media_items.id,
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
           latest_playback.latest_played_at,
           COALESCE(favorite_presence.is_favorite, 0) AS is_favorite,
           tag_label_summary.tag_labels,
           selected_poster.local_cache_path AS selected_poster_local_cache_path
    """

internal let mediaItemSummaryJoinSQL = """
    LEFT JOIN file_counts
      ON file_counts.media_item_id = media_items.id
    LEFT JOIN latest_playback
      ON latest_playback.media_item_id = media_items.id
    LEFT JOIN metadata_item_presence
      ON metadata_item_presence.media_item_id = media_items.id
    LEFT JOIN metadata_source_presence
      ON metadata_source_presence.media_item_id = media_items.id
    LEFT JOIN favorite_presence
      ON favorite_presence.media_item_id = media_items.id
    LEFT JOIN tag_label_summary
      ON tag_label_summary.media_item_id = media_items.id
    LEFT JOIN selected_poster
      ON selected_poster.media_item_id = media_items.id
    """

private let mediaItemTagLabelSeparator = "\u{1F}"

private func splitTagLabels(_ value: String) -> [String] {
    value
        .split(separator: Character(mediaItemTagLabelSeparator), omittingEmptySubsequences: true)
        .map(String.init)
}

internal func requiredSummaryString(_ statement: SQLiteStatement, _ index: Int32) throws -> String {
    guard let value = statement.string(at: index) else {
        throw PersistenceError.stepFailed("expected string at column \(index)")
    }
    return value
}

internal func requiredSummaryInt(_ statement: SQLiteStatement, _ index: Int32) throws -> Int {
    guard let value = statement.int(at: index) else {
        throw PersistenceError.stepFailed("expected int at column \(index)")
    }
    return value
}

internal func requiredSummaryBool(_ statement: SQLiteStatement, _ index: Int32) throws -> Bool {
    guard let value = statement.int(at: index), value == 0 || value == 1 else {
        throw PersistenceError.stepFailed("expected bool 0/1 at column \(index)")
    }
    return value == 1
}

internal func requiredSummaryMediaType(
    _ statement: SQLiteStatement,
    _ index: Int32
) throws -> MediaType {
    let rawValue = try requiredSummaryString(statement, index)
    guard let mediaType = MediaType(rawValue: rawValue) else {
        throw PersistenceError.stepFailed("expected media type at column \(index)")
    }
    return mediaType
}
