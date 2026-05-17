import Domain
import Foundation

public struct PersistedLibraryFolderSummary: Sendable, Equatable {
    public let id: LibraryFolderID
    public let displayName: String
    public let rootPath: String
    public let isAvailable: Bool
    public let lastSeenAt: Date?
    public let lastScanAt: Date?
    public let mediaFileCount: Int
    public let unavailableMediaFileCount: Int
}

extension CineMindStore {
    public func fetchLibraryFolderSummaries(
        libraryID: LibraryID,
        limit: Int,
        offset: Int = 0
    ) throws -> [PersistedLibraryFolderSummary] {
        guard limit > 0 else {
            return []
        }

        let statement = try preparePersistenceQuery(libraryFolderSummarySQL)
        try statement.bind(libraryID, at: 1)
        try statement.bind(limit, at: 2)
        try statement.bind(max(offset, 0), at: 3)

        var summaries: [PersistedLibraryFolderSummary] = []
        while try statement.step() {
            summaries.append(try mapLibraryFolderSummary(statement))
        }
        return summaries
    }

    private func mapLibraryFolderSummary(
        _ statement: SQLiteStatement
    ) throws -> PersistedLibraryFolderSummary {
        PersistedLibraryFolderSummary(
            id: try requiredFolderSummaryString(statement, 0),
            displayName: try requiredFolderSummaryString(statement, 1),
            rootPath: try requiredFolderSummaryString(statement, 2),
            isAvailable: try requiredFolderSummaryBool(statement, 3),
            lastSeenAt: decodePersistenceDate(statement.double(at: 4)),
            lastScanAt: decodePersistenceDate(statement.double(at: 5)),
            mediaFileCount: try requiredFolderSummaryInt(statement, 6),
            unavailableMediaFileCount: try requiredFolderSummaryInt(statement, 7)
        )
    }
}

private let libraryFolderSummarySQL = """
    SELECT library_folders.id,
           library_folders.display_name,
           library_folders.root_path,
           library_folders.is_available,
           library_folders.last_seen_at,
           library_folders.last_scan_at,
           COUNT(media_files.id) AS media_file_count,
           SUM(
               CASE
                   WHEN media_files.id IS NOT NULL
                    AND (
                        media_files.is_available = 0
                        OR library_folders.is_available = 0
                    ) THEN 1
                   ELSE 0
               END
           ) AS unavailable_media_file_count
    FROM library_folders
    LEFT JOIN media_files
      ON media_files.library_folder_id = library_folders.id
    WHERE library_folders.library_id = ?
    GROUP BY library_folders.id,
             library_folders.display_name,
             library_folders.root_path,
             library_folders.is_available,
             library_folders.last_seen_at,
             library_folders.last_scan_at
    ORDER BY library_folders.display_name COLLATE NOCASE ASC,
             library_folders.id ASC
    LIMIT ? OFFSET ?
    """

private func requiredFolderSummaryString(
    _ statement: SQLiteStatement,
    _ index: Int32
) throws -> String {
    guard let value = statement.string(at: index) else {
        throw PersistenceError.stepFailed("expected string at column \(index)")
    }
    return value
}

private func requiredFolderSummaryInt(
    _ statement: SQLiteStatement,
    _ index: Int32
) throws -> Int {
    guard let value = statement.int(at: index) else {
        throw PersistenceError.stepFailed("expected int at column \(index)")
    }
    return value
}

private func requiredFolderSummaryBool(
    _ statement: SQLiteStatement,
    _ index: Int32
) throws -> Bool {
    guard let value = statement.int(at: index), value == 0 || value == 1 else {
        throw PersistenceError.stepFailed("expected bool 0/1 at column \(index)")
    }
    return value == 1
}
