import Domain
import Foundation

public struct PersistedTag: Sendable, Equatable {
    public let id: TagID
    public let name: String
    public let normalizedName: String
    public let source: TagSource
    public let createdAt: Date
    public let updatedAt: Date
    public let mediaItemCount: Int?
}

public struct PersistedCollection: Sendable, Equatable {
    public let id: CollectionID
    public let name: String
    public let normalizedName: String
    public let description: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let mediaItemCount: Int?
}

public struct PersistedMediaItemCuration: Sendable, Equatable {
    public let mediaItemID: MediaItemID
    public let isFavorite: Bool
    public let tags: [PersistedTag]
    public let collections: [PersistedCollection]
}

extension CineMindStore {
    public func fetchTags() throws -> [PersistedTag] {
        try fetchTags(sql: tagListSQL(), stringBindings: [])
    }

    public func fetchTags(mediaItemID: MediaItemID) throws -> [PersistedTag] {
        try fetchTags(
            sql: tagListSQL(
                joinClause: """
                INNER JOIN media_item_tags
                  ON media_item_tags.tag_id = tags.id
                """,
                whereClause: "WHERE media_item_tags.media_item_id = ?"
            ),
            stringBindings: [mediaItemID]
        )
    }

    public func fetchTag(id: TagID) throws -> PersistedTag? {
        try fetchTags(
            sql: tagListSQL(whereClause: "WHERE tags.id = ?"),
            stringBindings: [id]
        ).first
    }

    public func fetchTag(normalizedName: String) throws -> PersistedTag? {
        try fetchTags(
            sql: tagListSQL(whereClause: "WHERE tags.normalized_name = ?"),
            stringBindings: [normalizedName]
        ).first
    }

    public func saveTag(_ tag: Tag) throws {
        let statement = try preparePersistenceQuery("""
            INSERT INTO tags (
                id, name, normalized_name, source, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                normalized_name = excluded.normalized_name,
                source = excluded.source,
                updated_at = excluded.updated_at
            """)
        try statement.bind(tag.id, at: 1)
        try statement.bind(tag.name, at: 2)
        try statement.bind(tag.normalizedName, at: 3)
        try statement.bind(tag.source.rawValue, at: 4)
        try statement.bind(curationTimestamp(tag.createdAt), at: 5)
        try statement.bind(curationTimestamp(tag.updatedAt), at: 6)
        _ = try statement.step()
    }

    public func deleteTag(id: TagID) throws {
        try withTransaction {
            let assignmentDelete = try preparePersistenceQuery("""
                DELETE FROM media_item_tags
                WHERE tag_id = ?
                """)
            try assignmentDelete.bind(id, at: 1)
            _ = try assignmentDelete.step()

            let tagDelete = try preparePersistenceQuery("""
                DELETE FROM tags
                WHERE id = ?
                """)
            try tagDelete.bind(id, at: 1)
            _ = try tagDelete.step()
        }
    }

    public func assignTag(
        tagID: TagID,
        to mediaItemID: MediaItemID,
        assignedAt: Date
    ) throws {
        let statement = try preparePersistenceQuery("""
            INSERT INTO media_item_tags (
                media_item_id, tag_id, assigned_at, updated_at
            )
            VALUES (?, ?, ?, ?)
            ON CONFLICT(media_item_id, tag_id) DO UPDATE SET
                updated_at = excluded.updated_at
            """)
        try statement.bind(mediaItemID, at: 1)
        try statement.bind(tagID, at: 2)
        try statement.bind(curationTimestamp(assignedAt), at: 3)
        try statement.bind(curationTimestamp(assignedAt), at: 4)
        _ = try statement.step()
    }

    public func removeTag(tagID: TagID, from mediaItemID: MediaItemID) throws {
        let statement = try preparePersistenceQuery("""
            DELETE FROM media_item_tags
            WHERE media_item_id = ?
              AND tag_id = ?
            """)
        try statement.bind(mediaItemID, at: 1)
        try statement.bind(tagID, at: 2)
        _ = try statement.step()
    }

    public func fetchCollections() throws -> [PersistedCollection] {
        try fetchCollections(sql: collectionListSQL(), stringBindings: [])
    }

    public func fetchCollections(mediaItemID: MediaItemID) throws -> [PersistedCollection] {
        try fetchCollections(
            sql: collectionListSQL(
                joinClause: """
                INNER JOIN collection_items
                  ON collection_items.collection_id = collections.id
                """,
                whereClause: "WHERE collection_items.media_item_id = ?"
            ),
            stringBindings: [mediaItemID]
        )
    }

    public func fetchCollection(id: CollectionID) throws -> PersistedCollection? {
        try fetchCollections(
            sql: collectionListSQL(whereClause: "WHERE collections.id = ?"),
            stringBindings: [id]
        ).first
    }

    public func fetchCollection(normalizedName: String) throws -> PersistedCollection? {
        try fetchCollections(
            sql: collectionListSQL(whereClause: "WHERE collections.normalized_name = ?"),
            stringBindings: [normalizedName]
        ).first
    }

    public func saveCollection(_ collection: MediaCollection) throws {
        let statement = try preparePersistenceQuery("""
            INSERT INTO collections (
                id, name, normalized_name, description, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                normalized_name = excluded.normalized_name,
                description = excluded.description,
                updated_at = excluded.updated_at
            """)
        try statement.bind(collection.id, at: 1)
        try statement.bind(collection.name, at: 2)
        try statement.bind(collection.normalizedName, at: 3)
        try statement.bind(collection.description, at: 4)
        try statement.bind(curationTimestamp(collection.createdAt), at: 5)
        try statement.bind(curationTimestamp(collection.updatedAt), at: 6)
        _ = try statement.step()
    }

    public func deleteCollection(id: CollectionID) throws {
        try withTransaction {
            let itemDelete = try preparePersistenceQuery("""
                DELETE FROM collection_items
                WHERE collection_id = ?
                """)
            try itemDelete.bind(id, at: 1)
            _ = try itemDelete.step()

            let collectionDelete = try preparePersistenceQuery("""
                DELETE FROM collections
                WHERE id = ?
                """)
            try collectionDelete.bind(id, at: 1)
            _ = try collectionDelete.step()
        }
    }

    public func addMediaItem(
        _ mediaItemID: MediaItemID,
        toCollection collectionID: CollectionID,
        addedAt: Date
    ) throws {
        let statement = try preparePersistenceQuery("""
            INSERT INTO collection_items (
                collection_id, media_item_id, added_at, updated_at
            )
            VALUES (?, ?, ?, ?)
            ON CONFLICT(collection_id, media_item_id) DO UPDATE SET
                updated_at = excluded.updated_at
            """)
        try statement.bind(collectionID, at: 1)
        try statement.bind(mediaItemID, at: 2)
        try statement.bind(curationTimestamp(addedAt), at: 3)
        try statement.bind(curationTimestamp(addedAt), at: 4)
        _ = try statement.step()
    }

    public func removeMediaItem(
        _ mediaItemID: MediaItemID,
        fromCollection collectionID: CollectionID
    ) throws {
        let statement = try preparePersistenceQuery("""
            DELETE FROM collection_items
            WHERE collection_id = ?
              AND media_item_id = ?
            """)
        try statement.bind(collectionID, at: 1)
        try statement.bind(mediaItemID, at: 2)
        _ = try statement.step()
    }

    public func setFavorite(
        mediaItemID: MediaItemID,
        isFavorite: Bool,
        updatedAt: Date
    ) throws {
        if isFavorite {
            let statement = try preparePersistenceQuery("""
                INSERT INTO favorite_media_items (
                    media_item_id, created_at, updated_at
                )
                VALUES (?, ?, ?)
                ON CONFLICT(media_item_id) DO UPDATE SET
                    updated_at = excluded.updated_at
                """)
            try statement.bind(mediaItemID, at: 1)
            try statement.bind(curationTimestamp(updatedAt), at: 2)
            try statement.bind(curationTimestamp(updatedAt), at: 3)
            _ = try statement.step()
        } else {
            let statement = try preparePersistenceQuery("""
                DELETE FROM favorite_media_items
                WHERE media_item_id = ?
                """)
            try statement.bind(mediaItemID, at: 1)
            _ = try statement.step()
        }
    }

    public func fetchMediaItemCuration(
        mediaItemID: MediaItemID
    ) throws -> PersistedMediaItemCuration {
        let favoriteStatement = try preparePersistenceQuery("""
            SELECT EXISTS(
                SELECT 1
                FROM favorite_media_items
                WHERE media_item_id = ?
            )
            """)
        try favoriteStatement.bind(mediaItemID, at: 1)

        guard try favoriteStatement.step() else {
            throw PersistenceError.stepFailed("expected favorite state")
        }

        return PersistedMediaItemCuration(
            mediaItemID: mediaItemID,
            isFavorite: try requiredCurationBool(favoriteStatement, 0),
            tags: try fetchTags(mediaItemID: mediaItemID),
            collections: try fetchCollections(mediaItemID: mediaItemID)
        )
    }

    public func fetchFavoriteMediaItemSummaries(
        limit: Int,
        offset: Int = 0
    ) throws -> [PersistedMediaItemSummary] {
        try fetchMediaItemSummaries(
            sql: mediaItemSummarySQL(
                whereClause: """
                    WHERE EXISTS (
                        SELECT 1
                        FROM favorite_media_items
                        WHERE favorite_media_items.media_item_id = media_items.id
                    )
                    """,
                orderClause: mediaItemTitleOrderSQL
            ),
            stringBindings: [],
            limit: limit,
            offset: offset
        )
    }

    public func fetchMediaItemSummaries(
        tagID: TagID,
        limit: Int,
        offset: Int = 0
    ) throws -> [PersistedMediaItemSummary] {
        try fetchMediaItemSummaries(
            sql: mediaItemSummarySQL(
                whereClause: """
                    WHERE EXISTS (
                        SELECT 1
                        FROM media_item_tags
                        WHERE media_item_tags.media_item_id = media_items.id
                          AND media_item_tags.tag_id = ?
                    )
                    """,
                orderClause: mediaItemTitleOrderSQL
            ),
            stringBindings: [tagID],
            limit: limit,
            offset: offset
        )
    }

    public func fetchMediaItemSummaries(
        collectionID: CollectionID,
        limit: Int,
        offset: Int = 0
    ) throws -> [PersistedMediaItemSummary] {
        try fetchMediaItemSummaries(
            sql: mediaItemSummarySQL(
                whereClause: """
                    WHERE EXISTS (
                        SELECT 1
                        FROM collection_items
                        WHERE collection_items.media_item_id = media_items.id
                          AND collection_items.collection_id = ?
                    )
                    """,
                orderClause: mediaItemTitleOrderSQL
            ),
            stringBindings: [collectionID],
            limit: limit,
            offset: offset
        )
    }

    private func fetchTags(
        sql: String,
        stringBindings: [String]
    ) throws -> [PersistedTag] {
        let statement = try preparePersistenceQuery(sql)
        try bindCurationStrings(stringBindings, to: statement)

        var tags: [PersistedTag] = []
        while try statement.step() {
            tags.append(try mapPersistedTag(statement))
        }
        return tags
    }

    private func fetchCollections(
        sql: String,
        stringBindings: [String]
    ) throws -> [PersistedCollection] {
        let statement = try preparePersistenceQuery(sql)
        try bindCurationStrings(stringBindings, to: statement)

        var collections: [PersistedCollection] = []
        while try statement.step() {
            collections.append(try mapPersistedCollection(statement))
        }
        return collections
    }
}

private func tagListSQL(
    joinClause: String = "",
    whereClause: String = ""
) -> String {
    """
    WITH tag_counts AS (
        SELECT tag_id,
               COUNT(*) AS media_item_count
        FROM media_item_tags
        GROUP BY tag_id
    )
    SELECT tags.id,
           tags.name,
           tags.normalized_name,
           tags.source,
           tags.created_at,
           tags.updated_at,
           COALESCE(tag_counts.media_item_count, 0) AS media_item_count
    FROM tags
    LEFT JOIN tag_counts
      ON tag_counts.tag_id = tags.id
    \(joinClause)
    \(whereClause)
    ORDER BY tags.name COLLATE NOCASE ASC,
             tags.id ASC
    """
}

private func collectionListSQL(
    joinClause: String = "",
    whereClause: String = ""
) -> String {
    """
    WITH collection_counts AS (
        SELECT collection_id,
               COUNT(*) AS media_item_count
        FROM collection_items
        GROUP BY collection_id
    )
    SELECT collections.id,
           collections.name,
           collections.normalized_name,
           collections.description,
           collections.created_at,
           collections.updated_at,
           COALESCE(collection_counts.media_item_count, 0) AS media_item_count
    FROM collections
    LEFT JOIN collection_counts
      ON collection_counts.collection_id = collections.id
    \(joinClause)
    \(whereClause)
    ORDER BY collections.name COLLATE NOCASE ASC,
             collections.id ASC
    """
}

private func bindCurationStrings(
    _ stringBindings: [String],
    to statement: SQLiteStatement
) throws {
    var bindIndex: Int32 = 1
    for stringBinding in stringBindings {
        try statement.bind(stringBinding, at: bindIndex)
        bindIndex += 1
    }
}

private func mapPersistedTag(_ statement: SQLiteStatement) throws -> PersistedTag {
    let rawSource = try requiredCurationString(statement, 3)
    guard let source = TagSource(rawValue: rawSource) else {
        throw PersistenceError.stepFailed("expected tag source at column 3")
    }

    return PersistedTag(
        id: try requiredCurationString(statement, 0),
        name: try requiredCurationString(statement, 1),
        normalizedName: try requiredCurationString(statement, 2),
        source: source,
        createdAt: try requiredCurationDate(statement, 4),
        updatedAt: try requiredCurationDate(statement, 5),
        mediaItemCount: statement.int(at: 6)
    )
}

private func mapPersistedCollection(
    _ statement: SQLiteStatement
) throws -> PersistedCollection {
    PersistedCollection(
        id: try requiredCurationString(statement, 0),
        name: try requiredCurationString(statement, 1),
        normalizedName: try requiredCurationString(statement, 2),
        description: statement.string(at: 3),
        createdAt: try requiredCurationDate(statement, 4),
        updatedAt: try requiredCurationDate(statement, 5),
        mediaItemCount: statement.int(at: 6)
    )
}

private func requiredCurationString(
    _ statement: SQLiteStatement,
    _ index: Int32
) throws -> String {
    guard let value = statement.string(at: index) else {
        throw PersistenceError.stepFailed("expected string at column \(index)")
    }
    return value
}

private func requiredCurationDate(
    _ statement: SQLiteStatement,
    _ index: Int32
) throws -> Date {
    guard let timestamp = statement.double(at: index) else {
        throw PersistenceError.stepFailed("expected date at column \(index)")
    }
    return Date(timeIntervalSince1970: timestamp)
}

private func requiredCurationBool(
    _ statement: SQLiteStatement,
    _ index: Int32
) throws -> Bool {
    guard let value = statement.int(at: index), value == 0 || value == 1 else {
        throw PersistenceError.stepFailed("expected bool 0/1 at column \(index)")
    }
    return value == 1
}

private func curationTimestamp(_ date: Date) -> Double {
    date.timeIntervalSince1970
}
