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
            if !applied.contains(3) {
                try apply(version: 3, statements: version3Statements, connection: connection)
                applied.insert(3)
            }
            if !applied.contains(4) {
                try apply(version: 4, statements: version4Statements, connection: connection)
                applied.insert(4)
            }
            if !applied.contains(5) {
                try apply(version: 5, statements: version5Statements, connection: connection)
                applied.insert(5)
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

    private static let version3Statements = [
        """
        CREATE TABLE IF NOT EXISTS metadata_items (
            id TEXT PRIMARY KEY,
            media_item_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE RESTRICT,
            title TEXT,
            original_title TEXT,
            summary TEXT,
            language TEXT,
            release_date TEXT,
            air_date TEXT,
            title_override_locked INTEGER NOT NULL DEFAULT 0 CHECK(title_override_locked IN (0, 1)),
            summary_override_locked INTEGER NOT NULL DEFAULT 0 CHECK(summary_override_locked IN (0, 1)),
            language_override_locked INTEGER NOT NULL DEFAULT 0 CHECK(language_override_locked IN (0, 1)),
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            UNIQUE(media_item_id)
        )
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_metadata_items_media_item_id
        ON metadata_items(media_item_id)
        """,
        """
        CREATE TABLE IF NOT EXISTS metadata_external_ids (
            id TEXT PRIMARY KEY,
            media_item_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE RESTRICT,
            provider TEXT NOT NULL CHECK(provider IN ('tmdb')),
            external_id_type TEXT NOT NULL CHECK(external_id_type IN ('tmdb_movie', 'tmdb_tv_series', 'tmdb_episode', 'imdb')),
            external_id_value TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            UNIQUE(media_item_id, provider, external_id_type)
        )
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_metadata_external_ids_media_item_id
        ON metadata_external_ids(media_item_id)
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_metadata_external_ids_lookup
        ON metadata_external_ids(provider, external_id_type, external_id_value)
        """,
        """
        CREATE TABLE IF NOT EXISTS metadata_source_records (
            id TEXT PRIMARY KEY,
            media_item_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE RESTRICT,
            provider TEXT NOT NULL CHECK(provider IN ('tmdb')),
            provider_id TEXT NOT NULL,
            provider_media_type TEXT NOT NULL CHECK(provider_media_type IN ('movie', 'episode')),
            confidence REAL NOT NULL CHECK(confidence >= 0.0 AND confidence <= 1.0),
            match_source TEXT NOT NULL CHECK(match_source IN ('automatic', 'manual')),
            manual_match_locked INTEGER NOT NULL DEFAULT 0 CHECK(manual_match_locked IN (0, 1)),
            raw_payload_json TEXT,
            matched_at REAL NOT NULL,
            refreshed_at REAL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            UNIQUE(media_item_id, provider)
        )
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_metadata_source_records_media_item_id
        ON metadata_source_records(media_item_id)
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_metadata_source_records_provider_id
        ON metadata_source_records(provider_id)
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_metadata_source_records_refreshed_at
        ON metadata_source_records(refreshed_at)
        """,
        """
        CREATE TABLE IF NOT EXISTS poster_assets (
            id TEXT PRIMARY KEY,
            media_item_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE RESTRICT,
            asset_type TEXT NOT NULL CHECK(asset_type IN ('poster')),
            source TEXT NOT NULL CHECK(source IN ('tmdb')),
            remote_path TEXT NOT NULL,
            width INTEGER,
            height INTEGER,
            preferred_cache_size TEXT NOT NULL,
            local_cache_path TEXT,
            cached_at REAL,
            is_selected INTEGER NOT NULL DEFAULT 0 CHECK(is_selected IN (0, 1)),
            selection_source TEXT NOT NULL CHECK(selection_source IN ('automatic', 'manual')),
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            UNIQUE(media_item_id, asset_type, source, remote_path)
        )
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_poster_assets_media_item_id
        ON poster_assets(media_item_id)
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_poster_assets_remote_path
        ON poster_assets(remote_path)
        """,
        """
        CREATE UNIQUE INDEX IF NOT EXISTS idx_poster_assets_selected_unique
        ON poster_assets(media_item_id, asset_type)
        WHERE is_selected = 1
        """
    ]

    private static let version4Statements = [
        """
        CREATE TABLE IF NOT EXISTS subtitle_assets (
            id TEXT PRIMARY KEY,
            media_item_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE RESTRICT,
            media_file_id TEXT REFERENCES media_files(id) ON DELETE SET NULL,
            library_folder_id TEXT REFERENCES library_folders(id) ON DELETE SET NULL,
            relative_path TEXT NOT NULL,
            file_name TEXT NOT NULL,
            file_extension TEXT NOT NULL,
            format TEXT NOT NULL CHECK(format IN ('srt', 'vtt', 'ass', 'ssa')),
            language_code TEXT,
            display_name TEXT,
            source TEXT NOT NULL CHECK(source IN ('external', 'downloaded')),
            is_available INTEGER NOT NULL DEFAULT 1 CHECK(is_available IN (0, 1)),
            last_seen_at REAL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            UNIQUE(library_folder_id, relative_path, source)
        )
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_subtitle_assets_media_item_id
        ON subtitle_assets(media_item_id)
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_subtitle_assets_media_file_id
        ON subtitle_assets(media_file_id)
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_subtitle_assets_library_path
        ON subtitle_assets(library_folder_id, relative_path)
        """
    ]

    private static let version5Statements = [
        """
        CREATE VIRTUAL TABLE IF NOT EXISTS media_search_fts USING fts5(
            media_item_id UNINDEXED,
            title,
            original_title,
            series_title,
            episode_title,
            metadata_title,
            metadata_original_title,
            metadata_summary,
            year,
            tokenize = 'unicode61'
        )
        """,
        """
        INSERT INTO media_search_fts (
            media_item_id,
            title,
            original_title,
            series_title,
            episode_title,
            metadata_title,
            metadata_original_title,
            metadata_summary,
            year
        )
        SELECT media_items.id,
               media_items.title,
               NULL,
               media_items.series_title,
               media_items.episode_title,
               metadata_items.title,
               metadata_items.original_title,
               metadata_items.summary,
               CAST(media_items.year AS TEXT)
        FROM media_items
        LEFT JOIN metadata_items
          ON metadata_items.media_item_id = media_items.id
        """,
        """
        CREATE TRIGGER IF NOT EXISTS media_search_media_items_ai
        AFTER INSERT ON media_items
        BEGIN
            DELETE FROM media_search_fts
            WHERE media_item_id = new.id;

            INSERT INTO media_search_fts (
                media_item_id,
                title,
                original_title,
                series_title,
                episode_title,
                metadata_title,
                metadata_original_title,
                metadata_summary,
                year
            )
            SELECT media_items.id,
                   media_items.title,
                   NULL,
                   media_items.series_title,
                   media_items.episode_title,
                   metadata_items.title,
                   metadata_items.original_title,
                   metadata_items.summary,
                   CAST(media_items.year AS TEXT)
            FROM media_items
            LEFT JOIN metadata_items
              ON metadata_items.media_item_id = media_items.id
            WHERE media_items.id = new.id;
        END
        """,
        """
        CREATE TRIGGER IF NOT EXISTS media_search_media_items_au
        AFTER UPDATE ON media_items
        BEGIN
            DELETE FROM media_search_fts
            WHERE media_item_id = old.id;

            INSERT INTO media_search_fts (
                media_item_id,
                title,
                original_title,
                series_title,
                episode_title,
                metadata_title,
                metadata_original_title,
                metadata_summary,
                year
            )
            SELECT media_items.id,
                   media_items.title,
                   NULL,
                   media_items.series_title,
                   media_items.episode_title,
                   metadata_items.title,
                   metadata_items.original_title,
                   metadata_items.summary,
                   CAST(media_items.year AS TEXT)
            FROM media_items
            LEFT JOIN metadata_items
              ON metadata_items.media_item_id = media_items.id
            WHERE media_items.id = new.id;
        END
        """,
        """
        CREATE TRIGGER IF NOT EXISTS media_search_media_items_ad
        AFTER DELETE ON media_items
        BEGIN
            DELETE FROM media_search_fts
            WHERE media_item_id = old.id;
        END
        """,
        """
        CREATE TRIGGER IF NOT EXISTS media_search_metadata_items_ai
        AFTER INSERT ON metadata_items
        BEGIN
            DELETE FROM media_search_fts
            WHERE media_item_id = new.media_item_id;

            INSERT INTO media_search_fts (
                media_item_id,
                title,
                original_title,
                series_title,
                episode_title,
                metadata_title,
                metadata_original_title,
                metadata_summary,
                year
            )
            SELECT media_items.id,
                   media_items.title,
                   NULL,
                   media_items.series_title,
                   media_items.episode_title,
                   metadata_items.title,
                   metadata_items.original_title,
                   metadata_items.summary,
                   CAST(media_items.year AS TEXT)
            FROM media_items
            LEFT JOIN metadata_items
              ON metadata_items.media_item_id = media_items.id
            WHERE media_items.id = new.media_item_id;
        END
        """,
        """
        CREATE TRIGGER IF NOT EXISTS media_search_metadata_items_au
        AFTER UPDATE ON metadata_items
        BEGIN
            DELETE FROM media_search_fts
            WHERE media_item_id = old.media_item_id;

            INSERT INTO media_search_fts (
                media_item_id,
                title,
                original_title,
                series_title,
                episode_title,
                metadata_title,
                metadata_original_title,
                metadata_summary,
                year
            )
            SELECT media_items.id,
                   media_items.title,
                   NULL,
                   media_items.series_title,
                   media_items.episode_title,
                   metadata_items.title,
                   metadata_items.original_title,
                   metadata_items.summary,
                   CAST(media_items.year AS TEXT)
            FROM media_items
            LEFT JOIN metadata_items
              ON metadata_items.media_item_id = media_items.id
            WHERE media_items.id = old.media_item_id;

            DELETE FROM media_search_fts
            WHERE media_item_id = new.media_item_id;

            INSERT INTO media_search_fts (
                media_item_id,
                title,
                original_title,
                series_title,
                episode_title,
                metadata_title,
                metadata_original_title,
                metadata_summary,
                year
            )
            SELECT media_items.id,
                   media_items.title,
                   NULL,
                   media_items.series_title,
                   media_items.episode_title,
                   metadata_items.title,
                   metadata_items.original_title,
                   metadata_items.summary,
                   CAST(media_items.year AS TEXT)
            FROM media_items
            LEFT JOIN metadata_items
              ON metadata_items.media_item_id = media_items.id
            WHERE media_items.id = new.media_item_id;
        END
        """,
        """
        CREATE TRIGGER IF NOT EXISTS media_search_metadata_items_ad
        AFTER DELETE ON metadata_items
        BEGIN
            DELETE FROM media_search_fts
            WHERE media_item_id = old.media_item_id;

            INSERT INTO media_search_fts (
                media_item_id,
                title,
                original_title,
                series_title,
                episode_title,
                metadata_title,
                metadata_original_title,
                metadata_summary,
                year
            )
            SELECT media_items.id,
                   media_items.title,
                   NULL,
                   media_items.series_title,
                   media_items.episode_title,
                   NULL,
                   NULL,
                   NULL,
                   CAST(media_items.year AS TEXT)
            FROM media_items
            WHERE media_items.id = old.media_item_id;
        END
        """
    ]
}
