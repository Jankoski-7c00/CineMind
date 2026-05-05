import Domain
import Foundation

public final class CineMindStore {
    private let connection: SQLiteConnection

    public init(path: String) throws {
        connection = try SQLiteConnection(path: path)
        try SQLiteMigrator.migrate(connection)
    }

    public static func inMemory() throws -> CineMindStore {
        try CineMindStore(path: ":memory:")
    }

    public func withTransaction<T>(_ body: () throws -> T) throws -> T {
        try connection.transaction(body)
    }
}

// MARK: - Migration Diagnostics

extension CineMindStore {
    internal func schemaTableNames() throws -> [String] {
        let statement = try connection.prepare("""
            SELECT name
            FROM sqlite_master
            WHERE type = 'table'
              AND name NOT LIKE 'sqlite_%'
            ORDER BY name ASC
            """)

        var names: [String] = []
        while try statement.step() {
            names.append(try requiredString(statement, 0))
        }
        return names
    }

    internal func appliedMigrationVersions() throws -> [Int] {
        let statement = try connection.prepare("""
            SELECT version
            FROM schema_migrations
            ORDER BY version ASC
            """)

        var versions: [Int] = []
        while try statement.step() {
            versions.append(try requiredInt(statement, 0))
        }
        return versions
    }
}

// MARK: - Library

extension CineMindStore {
    public func createOrLoadLibrary(name: String = "CineMind Library") throws -> Library {
        try ensureLibrary(name: name)
    }

    public func ensureLibrary(name: String = "CineMind Library") throws -> Library {
        if let existing = try fetchLibrary() {
            return existing
        }

        let library = Library(name: name)
        try saveLibrary(library)
        return library
    }

    public func fetchLibrary() throws -> Library? {
        let statement = try connection.prepare("""
            SELECT id, name, created_at, updated_at
            FROM libraries
            ORDER BY created_at ASC
            LIMIT 1
            """)

        guard try statement.step() else {
            return nil
        }

        return try mapLibrary(statement)
    }

    public func fetchLibrary(id: LibraryID) throws -> Library? {
        let statement = try connection.prepare("""
            SELECT id, name, created_at, updated_at
            FROM libraries
            WHERE id = ?
            LIMIT 1
            """)
        try statement.bind(id, at: 1)

        guard try statement.step() else {
            return nil
        }

        return try mapLibrary(statement)
    }

    public func saveLibrary(_ library: Library) throws {
        let statement = try connection.prepare("""
            INSERT INTO libraries (id, name, created_at, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                updated_at = excluded.updated_at
            """)
        try statement.bind(library.id, at: 1)
        try statement.bind(library.name, at: 2)
        try statement.bind(timestamp(library.createdAt), at: 3)
        try statement.bind(timestamp(library.updatedAt), at: 4)
        _ = try statement.step()
    }
}

// MARK: - LibraryFolder

extension CineMindStore {
    public func addLibraryFolder(_ folder: LibraryFolder) throws {
        try saveLibraryFolder(folder)
    }

    public func saveLibraryFolder(_ folder: LibraryFolder) throws {
        let statement = try connection.prepare("""
            INSERT INTO library_folders (
                id, library_id, display_name, root_path, access_bookmark,
                is_available, last_seen_at, last_scan_at, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                library_id = excluded.library_id,
                display_name = excluded.display_name,
                root_path = excluded.root_path,
                access_bookmark = excluded.access_bookmark,
                is_available = excluded.is_available,
                last_seen_at = excluded.last_seen_at,
                last_scan_at = excluded.last_scan_at,
                updated_at = excluded.updated_at
            """)
        try statement.bind(folder.id, at: 1)
        try statement.bind(folder.libraryID, at: 2)
        try statement.bind(folder.displayName, at: 3)
        try statement.bind(folder.rootPath, at: 4)
        try statement.bind(folder.accessBookmark, at: 5)
        try statement.bind(folder.isAvailable, at: 6)
        try statement.bind(timestamp(folder.lastSeenAt), at: 7)
        try statement.bind(timestamp(folder.lastScanAt), at: 8)
        try statement.bind(timestamp(folder.createdAt), at: 9)
        try statement.bind(timestamp(folder.updatedAt), at: 10)
        _ = try statement.step()
    }

    public func fetchLibraryFolders(libraryID: LibraryID) throws -> [LibraryFolder] {
        let statement = try connection.prepare("""
            SELECT id, library_id, display_name, root_path, access_bookmark,
                   is_available, last_seen_at, last_scan_at, created_at, updated_at
            FROM library_folders
            WHERE library_id = ?
            ORDER BY created_at ASC
            """)
        try statement.bind(libraryID, at: 1)

        var folders: [LibraryFolder] = []
        while try statement.step() {
            folders.append(try mapLibraryFolder(statement))
        }
        return folders
    }

    public func updateLibraryFolderAvailability(
        id: LibraryFolderID,
        isAvailable: Bool,
        lastSeenAt: Date?,
        lastScanAt: Date?,
        updatedAt: Date = Date()
    ) throws {
        let statement = try connection.prepare("""
            UPDATE library_folders
            SET is_available = ?,
                last_seen_at = ?,
                last_scan_at = ?,
                updated_at = ?
            WHERE id = ?
            """)
        try statement.bind(isAvailable, at: 1)
        try statement.bind(timestamp(lastSeenAt), at: 2)
        try statement.bind(timestamp(lastScanAt), at: 3)
        try statement.bind(timestamp(updatedAt), at: 4)
        try statement.bind(id, at: 5)
        _ = try statement.step()
    }
}

// MARK: - MediaItem

extension CineMindStore {
    public func saveMediaItem(_ item: MediaItem) throws {
        let statement = try connection.prepare("""
            INSERT INTO media_items (
                id, media_type, title, normalized_title, year,
                series_title, season_number, episode_number, episode_title,
                created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                media_type = excluded.media_type,
                title = excluded.title,
                normalized_title = excluded.normalized_title,
                year = excluded.year,
                series_title = excluded.series_title,
                season_number = excluded.season_number,
                episode_number = excluded.episode_number,
                episode_title = excluded.episode_title,
                updated_at = excluded.updated_at
            """)
        try bindMediaItem(item, to: statement)
        _ = try statement.step()
    }

    public func fetchMediaItem(id: MediaItemID) throws -> MediaItem? {
        let statement = try connection.prepare(mediaItemSelectSQL + " WHERE id = ?")
        try statement.bind(id, at: 1)

        guard try statement.step() else {
            return nil
        }

        return try mapMediaItem(statement)
    }

    public func fetchMediaItems() throws -> [MediaItem] {
        let statement = try connection.prepare(mediaItemSelectSQL + " ORDER BY title ASC")
        var items: [MediaItem] = []
        while try statement.step() {
            items.append(try mapMediaItem(statement))
        }
        return items
    }

    public func findMovieItem(normalizedTitle: String, year: Int?) throws -> MediaItem? {
        let statement: SQLiteStatement
        if let year {
            statement = try connection.prepare(mediaItemSelectSQL + """
                 WHERE media_type = ? AND normalized_title = ? AND year = ?
                LIMIT 1
                """)
            try statement.bind(MediaType.movie.rawValue, at: 1)
            try statement.bind(normalizedTitle, at: 2)
            try statement.bind(year, at: 3)
        } else {
            statement = try connection.prepare(mediaItemSelectSQL + """
                 WHERE media_type = ? AND normalized_title = ? AND year IS NULL
                LIMIT 1
                """)
            try statement.bind(MediaType.movie.rawValue, at: 1)
            try statement.bind(normalizedTitle, at: 2)
        }

        guard try statement.step() else {
            return nil
        }

        return try mapMediaItem(statement)
    }

    public func findEpisodeItem(
        normalizedSeriesTitle: String,
        seasonNumber: Int,
        episodeNumber: Int
    ) throws -> MediaItem? {
        let statement = try connection.prepare(mediaItemSelectSQL + """
             WHERE media_type = ?
               AND normalized_title = ?
               AND season_number = ?
               AND episode_number = ?
            LIMIT 1
            """)
        try statement.bind(MediaType.episode.rawValue, at: 1)
        try statement.bind(normalizedSeriesTitle, at: 2)
        try statement.bind(seasonNumber, at: 3)
        try statement.bind(episodeNumber, at: 4)

        guard try statement.step() else {
            return nil
        }

        return try mapMediaItem(statement)
    }
}

// MARK: - MediaFile

extension CineMindStore {
    public func saveMediaFile(_ file: MediaFile) throws {
        let statement = try connection.prepare("""
            INSERT INTO media_files (
                id, media_item_id, library_folder_id, relative_path,
                absolute_path_hash, file_name, file_extension, file_size_bytes,
                modified_at, is_available, last_seen_at, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                media_item_id = excluded.media_item_id,
                library_folder_id = excluded.library_folder_id,
                relative_path = excluded.relative_path,
                absolute_path_hash = excluded.absolute_path_hash,
                file_name = excluded.file_name,
                file_extension = excluded.file_extension,
                file_size_bytes = excluded.file_size_bytes,
                modified_at = excluded.modified_at,
                is_available = excluded.is_available,
                last_seen_at = excluded.last_seen_at,
                updated_at = excluded.updated_at
            """)
        try bindMediaFile(file, to: statement)
        _ = try statement.step()
    }

    public func fetchMediaFile(
        libraryFolderID: LibraryFolderID,
        relativePath: String
    ) throws -> MediaFile? {
        let statement = try connection.prepare(mediaFileSelectSQL + """
             WHERE library_folder_id = ? AND relative_path = ?
            LIMIT 1
            """)
        try statement.bind(libraryFolderID, at: 1)
        try statement.bind(relativePath, at: 2)

        guard try statement.step() else {
            return nil
        }

        return try mapMediaFile(statement)
    }

    public func fetchMediaFiles(libraryFolderID: LibraryFolderID) throws -> [MediaFile] {
        let statement = try connection.prepare(mediaFileSelectSQL + """
             WHERE library_folder_id = ?
            ORDER BY relative_path ASC
            """)
        try statement.bind(libraryFolderID, at: 1)

        var files: [MediaFile] = []
        while try statement.step() {
            files.append(try mapMediaFile(statement))
        }
        return files
    }

    public func fetchMediaFiles(mediaItemID: MediaItemID) throws -> [MediaFile] {
        let statement = try connection.prepare(mediaFileSelectSQL + """
             WHERE media_item_id = ?
            ORDER BY relative_path ASC
            """)
        try statement.bind(mediaItemID, at: 1)

        var files: [MediaFile] = []
        while try statement.step() {
            files.append(try mapMediaFile(statement))
        }
        return files
    }

    public func markMediaFileUnavailable(id: MediaFileID, updatedAt: Date = Date()) throws {
        let statement = try connection.prepare("""
            UPDATE media_files
            SET is_available = 0,
                updated_at = ?
            WHERE id = ?
            """)
        try statement.bind(timestamp(updatedAt), at: 1)
        try statement.bind(id, at: 2)
        _ = try statement.step()
    }
}

// MARK: - Scan

extension CineMindStore {
    public func createScanRun(libraryID: LibraryID, startedAt: Date = Date()) throws -> ScanRun {
        let run = ScanRun(libraryID: libraryID, startedAt: startedAt)
        try saveScanRun(run)
        return run
    }

    public func finishScanRun(
        id: ScanRunID,
        finishedAt: Date = Date(),
        status: ScanRunStatus,
        filesSeen: Int,
        filesAdded: Int,
        filesUpdated: Int,
        filesMissing: Int,
        issuesCount: Int
    ) throws {
        let statement = try connection.prepare("""
            UPDATE scan_runs
            SET finished_at = ?,
                status = ?,
                files_seen = ?,
                files_added = ?,
                files_updated = ?,
                files_missing = ?,
                issues_count = ?
            WHERE id = ?
            """)
        try statement.bind(timestamp(finishedAt), at: 1)
        try statement.bind(status.rawValue, at: 2)
        try statement.bind(filesSeen, at: 3)
        try statement.bind(filesAdded, at: 4)
        try statement.bind(filesUpdated, at: 5)
        try statement.bind(filesMissing, at: 6)
        try statement.bind(issuesCount, at: 7)
        try statement.bind(id, at: 8)
        _ = try statement.step()
    }

    public func saveScanRun(_ run: ScanRun) throws {
        let statement = try connection.prepare("""
            INSERT INTO scan_runs (
                id, library_id, started_at, finished_at, status,
                files_seen, files_added, files_updated, files_missing, issues_count
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                finished_at = excluded.finished_at,
                status = excluded.status,
                files_seen = excluded.files_seen,
                files_added = excluded.files_added,
                files_updated = excluded.files_updated,
                files_missing = excluded.files_missing,
                issues_count = excluded.issues_count
            """)
        try statement.bind(run.id, at: 1)
        try statement.bind(run.libraryID, at: 2)
        try statement.bind(timestamp(run.startedAt), at: 3)
        try statement.bind(timestamp(run.finishedAt), at: 4)
        try statement.bind(run.status.rawValue, at: 5)
        try statement.bind(run.filesSeen, at: 6)
        try statement.bind(run.filesAdded, at: 7)
        try statement.bind(run.filesUpdated, at: 8)
        try statement.bind(run.filesMissing, at: 9)
        try statement.bind(run.issuesCount, at: 10)
        _ = try statement.step()
    }

    public func fetchScanRun(id: ScanRunID) throws -> ScanRun? {
        let statement = try connection.prepare(scanRunSelectSQL + " WHERE id = ?")
        try statement.bind(id, at: 1)

        guard try statement.step() else {
            return nil
        }

        return try mapScanRun(statement)
    }

    public func recordScanIssue(_ issue: ScanIssue) throws {
        try saveScanIssue(issue)
    }

    public func saveScanIssue(_ issue: ScanIssue) throws {
        let statement = try connection.prepare("""
            INSERT INTO scan_issues (
                id, scan_run_id, library_folder_id, path_hash,
                issue_type, message, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                scan_run_id = excluded.scan_run_id,
                library_folder_id = excluded.library_folder_id,
                path_hash = excluded.path_hash,
                issue_type = excluded.issue_type,
                message = excluded.message
            """)
        try statement.bind(issue.id, at: 1)
        try statement.bind(issue.scanRunID, at: 2)
        try statement.bind(issue.libraryFolderID, at: 3)
        try statement.bind(issue.pathHash, at: 4)
        try statement.bind(issue.issueType.rawValue, at: 5)
        try statement.bind(issue.message, at: 6)
        try statement.bind(timestamp(issue.createdAt), at: 7)
        _ = try statement.step()
    }

    public func fetchScanIssues(scanRunID: ScanRunID) throws -> [ScanIssue] {
        let statement = try connection.prepare("""
            SELECT id, scan_run_id, library_folder_id, path_hash,
                   issue_type, message, created_at
            FROM scan_issues
            WHERE scan_run_id = ?
            ORDER BY created_at ASC
            """)
        try statement.bind(scanRunID, at: 1)

        var issues: [ScanIssue] = []
        while try statement.step() {
            issues.append(try mapScanIssue(statement))
        }
        return issues
    }
}

// MARK: - Mapping

extension CineMindStore {
    private func bindMediaItem(_ item: MediaItem, to statement: SQLiteStatement) throws {
        try statement.bind(item.id, at: 1)
        try statement.bind(item.mediaType.rawValue, at: 2)
        try statement.bind(item.title, at: 3)
        try statement.bind(item.normalizedTitle, at: 4)
        try statement.bind(item.year, at: 5)
        try statement.bind(item.episodeInfo?.seriesTitle, at: 6)
        try statement.bind(item.episodeInfo?.seasonNumber, at: 7)
        try statement.bind(item.episodeInfo?.episodeNumber, at: 8)
        try statement.bind(item.episodeInfo?.episodeTitle, at: 9)
        try statement.bind(timestamp(item.createdAt), at: 10)
        try statement.bind(timestamp(item.updatedAt), at: 11)
    }

    private func bindMediaFile(_ file: MediaFile, to statement: SQLiteStatement) throws {
        try statement.bind(file.id, at: 1)
        try statement.bind(file.mediaItemID, at: 2)
        try statement.bind(file.libraryFolderID, at: 3)
        try statement.bind(file.relativePath, at: 4)
        try statement.bind(file.absolutePathHash, at: 5)
        try statement.bind(file.fileName, at: 6)
        try statement.bind(file.fileExtension, at: 7)
        try statement.bind(file.fileSizeBytes, at: 8)
        try statement.bind(timestamp(file.modifiedAt), at: 9)
        try statement.bind(file.isAvailable, at: 10)
        try statement.bind(timestamp(file.lastSeenAt), at: 11)
        try statement.bind(timestamp(file.createdAt), at: 12)
        try statement.bind(timestamp(file.updatedAt), at: 13)
    }

    private func mapLibrary(_ statement: SQLiteStatement) throws -> Library {
        Library(
            id: try requiredString(statement, 0),
            name: try requiredString(statement, 1),
            createdAt: try requiredDate(statement, 2),
            updatedAt: try requiredDate(statement, 3)
        )
    }

    private func mapLibraryFolder(_ statement: SQLiteStatement) throws -> LibraryFolder {
        LibraryFolder(
            id: try requiredString(statement, 0),
            libraryID: try requiredString(statement, 1),
            displayName: try requiredString(statement, 2),
            rootPath: try requiredString(statement, 3),
            accessBookmark: statement.data(at: 4),
            isAvailable: statement.bool(at: 5),
            lastSeenAt: date(statement.double(at: 6)),
            lastScanAt: date(statement.double(at: 7)),
            createdAt: try requiredDate(statement, 8),
            updatedAt: try requiredDate(statement, 9)
        )
    }

    private func mapMediaItem(_ statement: SQLiteStatement) throws -> MediaItem {
        let mediaType = MediaType(rawValue: try requiredString(statement, 1)) ?? .movie
        let seriesTitle = statement.string(at: 5)
        let seasonNumber = statement.int(at: 6)
        let episodeNumber = statement.int(at: 7)
        let episodeInfo: EpisodeInfo?

        if mediaType == .episode,
           let seriesTitle,
           let seasonNumber,
           let episodeNumber {
            episodeInfo = EpisodeInfo(
                seriesTitle: seriesTitle,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber,
                episodeTitle: statement.string(at: 8)
            )
        } else {
            episodeInfo = nil
        }

        return MediaItem(
            id: try requiredString(statement, 0),
            mediaType: mediaType,
            title: try requiredString(statement, 2),
            normalizedTitle: try requiredString(statement, 3),
            year: statement.int(at: 4),
            episodeInfo: episodeInfo,
            createdAt: try requiredDate(statement, 9),
            updatedAt: try requiredDate(statement, 10)
        )
    }

    private func mapMediaFile(_ statement: SQLiteStatement) throws -> MediaFile {
        MediaFile(
            id: try requiredString(statement, 0),
            mediaItemID: try requiredString(statement, 1),
            libraryFolderID: try requiredString(statement, 2),
            relativePath: try requiredString(statement, 3),
            absolutePathHash: try requiredString(statement, 4),
            fileName: try requiredString(statement, 5),
            fileExtension: try requiredString(statement, 6),
            fileSizeBytes: try requiredInt64(statement, 7),
            modifiedAt: date(statement.double(at: 8)),
            isAvailable: statement.bool(at: 9),
            lastSeenAt: date(statement.double(at: 10)),
            createdAt: try requiredDate(statement, 11),
            updatedAt: try requiredDate(statement, 12)
        )
    }

    private func mapScanRun(_ statement: SQLiteStatement) throws -> ScanRun {
        ScanRun(
            id: try requiredString(statement, 0),
            libraryID: try requiredString(statement, 1),
            startedAt: try requiredDate(statement, 2),
            finishedAt: date(statement.double(at: 3)),
            status: ScanRunStatus(rawValue: try requiredString(statement, 4)) ?? .failed,
            filesSeen: try requiredInt(statement, 5),
            filesAdded: try requiredInt(statement, 6),
            filesUpdated: try requiredInt(statement, 7),
            filesMissing: try requiredInt(statement, 8),
            issuesCount: try requiredInt(statement, 9)
        )
    }

    private func mapScanIssue(_ statement: SQLiteStatement) throws -> ScanIssue {
        ScanIssue(
            id: try requiredString(statement, 0),
            scanRunID: try requiredString(statement, 1),
            libraryFolderID: statement.string(at: 2),
            pathHash: statement.string(at: 3),
            issueType: ScanIssueType(rawValue: try requiredString(statement, 4)) ?? .filesystemError,
            message: try requiredString(statement, 5),
            createdAt: try requiredDate(statement, 6)
        )
    }

    private func requiredString(_ statement: SQLiteStatement, _ index: Int32) throws -> String {
        guard let value = statement.string(at: index) else {
            throw PersistenceError.stepFailed("expected string at column \(index)")
        }
        return value
    }

    private func requiredInt(_ statement: SQLiteStatement, _ index: Int32) throws -> Int {
        guard let value = statement.int(at: index) else {
            throw PersistenceError.stepFailed("expected int at column \(index)")
        }
        return value
    }

    private func requiredInt64(_ statement: SQLiteStatement, _ index: Int32) throws -> Int64 {
        guard let value = statement.int64(at: index) else {
            throw PersistenceError.stepFailed("expected int64 at column \(index)")
        }
        return value
    }

    private func requiredDate(_ statement: SQLiteStatement, _ index: Int32) throws -> Date {
        guard let value = date(statement.double(at: index)) else {
            throw PersistenceError.stepFailed("expected date at column \(index)")
        }
        return value
    }

    private func timestamp(_ date: Date?) -> Double? {
        date?.timeIntervalSince1970
    }

    private func date(_ timestamp: Double?) -> Date? {
        timestamp.map(Date.init(timeIntervalSince1970:))
    }
}

private let mediaItemSelectSQL = """
    SELECT id, media_type, title, normalized_title, year,
           series_title, season_number, episode_number, episode_title,
           created_at, updated_at
    FROM media_items
    """

private let mediaFileSelectSQL = """
    SELECT id, media_item_id, library_folder_id, relative_path,
           absolute_path_hash, file_name, file_extension, file_size_bytes,
           modified_at, is_available, last_seen_at, created_at, updated_at
    FROM media_files
    """

private let scanRunSelectSQL = """
    SELECT id, library_id, started_at, finished_at, status,
           files_seen, files_added, files_updated, files_missing, issues_count
    FROM scan_runs
    """
