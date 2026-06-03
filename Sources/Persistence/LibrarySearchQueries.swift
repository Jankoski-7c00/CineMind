import Domain
import Foundation

public struct PersistedMediaSearchQuery: Sendable, Equatable {
    public var text: String
    public var mediaType: MediaType?
    public var availability: PersistedMediaSearchAvailability
    public var sort: PersistedMediaSearchSort
    public var limit: Int
    public var offset: Int

    public init(
        text: String,
        mediaType: MediaType? = nil,
        availability: PersistedMediaSearchAvailability = .any,
        sort: PersistedMediaSearchSort = .relevance,
        limit: Int,
        offset: Int = 0
    ) {
        self.text = text
        self.mediaType = mediaType
        self.availability = availability
        self.sort = sort
        self.limit = limit
        self.offset = offset
    }
}

public enum PersistedMediaSearchAvailability: Sendable, Equatable {
    case any
    case available
    case unavailable
}

public enum PersistedMediaSearchSort: Sendable, Equatable {
    case relevance
    case title
    case recentlyAdded
    case recentlyPlayed
    case year
}

public struct PersistedMediaSearchResult: Sendable, Equatable {
    public let summary: PersistedMediaItemSummary
    public let rank: Double?
    public let matchReason: String?

    public init(
        summary: PersistedMediaItemSummary,
        rank: Double?,
        matchReason: String? = nil
    ) {
        self.summary = summary
        self.rank = rank
        self.matchReason = matchReason
    }
}

extension CineMindStore {
    public func searchMediaItems(
        query: PersistedMediaSearchQuery
    ) throws -> [PersistedMediaSearchResult] {
        guard query.limit > 0 else {
            return []
        }

        let matchExpression = ftsMatchExpression(for: query.text)
        let textSearchIsActive = matchExpression != nil
        var whereClauses: [String] = []
        var stringBindings: [String] = []

        if let matchExpression {
            stringBindings.append(matchExpression)
        }

        if let mediaType = query.mediaType {
            whereClauses.append("media_items.media_type = ?")
            stringBindings.append(mediaType.rawValue)
        }

        switch query.availability {
        case .any:
            break
        case .available:
            whereClauses.append("COALESCE(file_counts.available_file_count, 0) > 0")
        case .unavailable:
            whereClauses.append("COALESCE(file_counts.available_file_count, 0) = 0")
        }

        let sql = mediaSearchSQL(
            textSearchIsActive: textSearchIsActive,
            whereClauses: whereClauses,
            orderClause: mediaSearchOrderSQL(
                sort: query.sort,
                textSearchIsActive: textSearchIsActive
            )
        )
        let statement = try preparePersistenceQuery(sql)
        var bindIndex: Int32 = 1
        for stringBinding in stringBindings {
            try statement.bind(stringBinding, at: bindIndex)
            bindIndex += 1
        }
        try statement.bind(query.limit, at: bindIndex)
        try statement.bind(max(query.offset, 0), at: bindIndex + 1)

        var results: [PersistedMediaSearchResult] = []
        while try statement.step() {
            results.append(
                PersistedMediaSearchResult(
                    summary: try mapMediaItemSummary(statement),
                    rank: statement.double(at: 14),
                    matchReason: nil
                )
            )
        }
        return results
    }
}

private func mediaSearchSQL(
    textSearchIsActive: Bool,
    whereClauses: [String],
    orderClause: String
) -> String {
    let searchCTE = textSearchIsActive
        ? """
        search_matches AS (
            SELECT media_item_id,
                   bm25(media_search_fts) AS search_rank
            FROM media_search_fts
            WHERE media_search_fts MATCH ?
        ),
        """
        : ""
    let searchJoin = textSearchIsActive
        ? """
        INNER JOIN search_matches
          ON search_matches.media_item_id = media_items.id
        """
        : ""
    let searchRankColumn = textSearchIsActive
        ? "search_matches.search_rank"
        : "NULL"
    let whereClause = whereClauses.isEmpty
        ? ""
        : "WHERE \(whereClauses.joined(separator: " AND "))"

    return """
    WITH \(searchCTE)
    \(mediaItemSummaryCommonCTESQL)
    SELECT \(mediaItemSummarySelectColumnsSQL),
           \(searchRankColumn) AS search_rank
    FROM media_items
    \(searchJoin)
    \(mediaItemSummaryJoinSQL)
    \(whereClause)
    \(orderClause)
    LIMIT ? OFFSET ?
    """
}

private func mediaSearchOrderSQL(
    sort: PersistedMediaSearchSort,
    textSearchIsActive: Bool
) -> String {
    switch sort {
    case .relevance:
        if textSearchIsActive {
            return """
            ORDER BY search_matches.search_rank ASC,
                     media_items.title COLLATE NOCASE ASC,
                     media_items.id ASC
            """
        }
        return mediaItemTitleOrderSQL
    case .title:
        return mediaItemTitleOrderSQL
    case .recentlyAdded:
        return """
        ORDER BY media_items.created_at DESC,
                 media_items.id ASC
        """
    case .recentlyPlayed:
        return """
        ORDER BY latest_playback.latest_played_at IS NULL ASC,
                 latest_playback.latest_played_at DESC,
                 media_items.id ASC
        """
    case .year:
        return """
        ORDER BY media_items.year IS NULL ASC,
                 media_items.year DESC,
                 media_items.title COLLATE NOCASE ASC,
                 media_items.id ASC
        """
    }
}

private func ftsMatchExpression(for text: String) -> String? {
    let terms = text
        .split(whereSeparator: \.isWhitespace)
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .map { $0.replacingOccurrences(of: "\"", with: "\"\"") }
        .filter { !$0.isEmpty }
        .map { "\"\($0)\"" }

    guard !terms.isEmpty else {
        return nil
    }
    return terms.joined(separator: " AND ")
}
