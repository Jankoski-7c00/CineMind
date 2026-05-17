import Domain
import Foundation

public struct PersistedMediaFile: Sendable, Equatable {
    public let id: MediaFileID
    public let mediaItemID: MediaItemID
    public let libraryFolderID: LibraryFolderID
    public let fileName: String
    public let fileExtension: String
    public let fileSizeBytes: Int64
    public let relativePath: String
    public let isAvailable: Bool
    public let folderIsAvailable: Bool
    public let folderRootPath: String
}

extension CineMindStore {
    public func fetchMediaFile(id: MediaFileID) throws -> PersistedMediaFile? {
        let statement = try preparePersistenceQuery("""
            SELECT mf.id, mf.media_item_id, mf.library_folder_id,
                   mf.file_name, mf.file_extension, mf.file_size_bytes,
                   mf.relative_path,
                   (mf.is_available = 1 AND COALESCE(lf.is_available, 0) = 1) AS is_available,
                   COALESCE(lf.is_available, 0) AS folder_is_available,
                   COALESCE(lf.root_path, '') AS folder_root_path
            FROM media_files mf
            LEFT JOIN library_folders lf ON mf.library_folder_id = lf.id
            WHERE mf.id = ?
            """)
        try statement.bind(id, at: 1)

        guard try statement.step() else {
            return nil
        }

        return try mapPersistedMediaFile(statement)
    }

    private func mapPersistedMediaFile(_ statement: SQLiteStatement) throws -> PersistedMediaFile {
        PersistedMediaFile(
            id: try requiredMediaFileString(statement, 0),
            mediaItemID: try requiredMediaFileString(statement, 1),
            libraryFolderID: try requiredMediaFileString(statement, 2),
            fileName: try requiredMediaFileString(statement, 3),
            fileExtension: try requiredMediaFileString(statement, 4),
            fileSizeBytes: try requiredMediaFileInt64(statement, 5),
            relativePath: try requiredMediaFileString(statement, 6),
            isAvailable: statement.bool(at: 7),
            folderIsAvailable: statement.bool(at: 8),
            folderRootPath: statement.string(at: 9) ?? ""
        )
    }
}

private func requiredMediaFileString(_ statement: SQLiteStatement, _ index: Int32) throws -> String {
    guard let value = statement.string(at: index) else {
        throw PersistenceError.stepFailed("expected string at column \(index)")
    }
    return value
}

private func requiredMediaFileInt64(_ statement: SQLiteStatement, _ index: Int32) throws -> Int64 {
    guard let value = statement.int64(at: index) else {
        throw PersistenceError.stepFailed("expected int64 at column \(index)")
    }
    return value
}
