import Foundation

internal enum SQLiteMigrator {
    internal static func migrate(_ connection: SQLiteConnection) throws {
        try connection.execute("""
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version INTEGER PRIMARY KEY,
                applied_at REAL NOT NULL
            )
            """)

        do {
            var applied = try appliedVersions(connection)
            if !applied.contains(1) {
                try apply(version: 1, statements: version1Statements, connection: connection)
                applied.insert(1)
            }
            if !applied.contains(2) {
                try apply(version: 2, statements: version2Statements, connection: connection)
                applied.insert(2)
            }
        } catch {
            throw PersistenceError.migrationFailed(error.localizedDescription)
        }
    }

    private static func apply(
        version: Int,
        statements: [String],
        connection: SQLiteConnection
    ) throws {
        try connection.transaction {
            for statement in statements {
                try connection.execute(statement)
            }
            let insert = try connection.prepare("""
                INSERT OR IGNORE INTO schema_migrations (version, applied_at)
                VALUES (?, ?)
                """)
            try insert.bind(version, at: 1)
            try insert.bind(Date().timeIntervalSince1970, at: 2)
            _ = try insert.step()
        }
    }

    private static func appliedVersions(_ connection: SQLiteConnection) throws -> Set<Int> {
        let statement = try connection.prepare("SELECT version FROM schema_migrations")
        var versions = Set<Int>()
        while try statement.step() {
            if let version = statement.int(at: 0) {
                versions.insert(version)
            }
        }
        return versions
    }

    private static let version1Statements = [
        """
        CREATE TABLE IF NOT EXISTS libraries (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS library_folders (
            id TEXT PRIMARY KEY,
            library_id TEXT NOT NULL REFERENCES libraries(id) ON DELETE RESTRICT,
            display_name TEXT NOT NULL,
            root_path TEXT NOT NULL,
            access_bookmark BLOB,
            is_available INTEGER NOT NULL,
            last_seen_at REAL,
            last_scan_at REAL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        )
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_library_folders_library_id
        ON library_folders(library_id)
        """,
        """
        CREATE TABLE IF NOT EXISTS media_items (
            id TEXT PRIMARY KEY,
            media_type TEXT NOT NULL,
            title TEXT NOT NULL,
            normalized_title TEXT NOT NULL,
            year INTEGER,
            series_title TEXT,
            season_number INTEGER,
            episode_number INTEGER,
            episode_title TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        )
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_media_items_identity
        ON media_items(media_type, normalized_title, year, season_number, episode_number)
        """,
        """
        CREATE TABLE IF NOT EXISTS media_files (
            id TEXT PRIMARY KEY,
            media_item_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE RESTRICT,
            library_folder_id TEXT NOT NULL REFERENCES library_folders(id) ON DELETE RESTRICT,
            relative_path TEXT NOT NULL,
            absolute_path_hash TEXT NOT NULL,
            file_name TEXT NOT NULL,
            file_extension TEXT NOT NULL,
            file_size_bytes INTEGER NOT NULL,
            modified_at REAL,
            is_available INTEGER NOT NULL,
            last_seen_at REAL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            UNIQUE(library_folder_id, relative_path)
        )
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_media_files_media_item_id
        ON media_files(media_item_id)
        """,
        """
        CREATE TABLE IF NOT EXISTS scan_runs (
            id TEXT PRIMARY KEY,
            library_id TEXT NOT NULL REFERENCES libraries(id) ON DELETE RESTRICT,
            started_at REAL NOT NULL,
            finished_at REAL,
            status TEXT NOT NULL,
            files_seen INTEGER NOT NULL,
            files_added INTEGER NOT NULL,
            files_updated INTEGER NOT NULL,
            files_missing INTEGER NOT NULL,
            issues_count INTEGER NOT NULL
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS scan_issues (
            id TEXT PRIMARY KEY,
            scan_run_id TEXT NOT NULL REFERENCES scan_runs(id) ON DELETE CASCADE,
            library_folder_id TEXT REFERENCES library_folders(id) ON DELETE SET NULL,
            path_hash TEXT,
            issue_type TEXT NOT NULL,
            message TEXT NOT NULL,
            created_at REAL NOT NULL
        )
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_scan_issues_scan_run_id
        ON scan_issues(scan_run_id)
        """
    ]

    private static let version2Statements = [
        """
        CREATE TABLE IF NOT EXISTS playback_history (
            id TEXT PRIMARY KEY,
            media_item_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE RESTRICT,
            media_file_id TEXT NOT NULL REFERENCES media_files(id) ON DELETE RESTRICT,
            position_ms INTEGER NOT NULL CHECK(position_ms >= 0),
            duration_ms INTEGER CHECK(duration_ms IS NULL OR duration_ms >= 0),
            completed INTEGER NOT NULL CHECK(completed IN (0, 1)),
            play_count INTEGER NOT NULL CHECK(play_count >= 0),
            last_played_at REAL NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            UNIQUE(media_item_id, media_file_id)
        )
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_playback_history_media_item_id
        ON playback_history(media_item_id)
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_playback_history_media_file_id
        ON playback_history(media_file_id)
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_playback_history_last_played_at
        ON playback_history(last_played_at)
        """
    ]
}
