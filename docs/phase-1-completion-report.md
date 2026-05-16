# Phase 1 Completion Report: Library Core Foundation

Date: 2026-05-06

## 1. Implementation Scope

Phase 1 completed the local library core foundation defined in `docs/phase-1-library-core.md`.

Implemented:

- Swift Package structure for the Phase 1 library core.
- Pure domain models for libraries, folders, media items, media files, scan runs, and scan issues.
- SQLite persistence with versioned migration, repository-style APIs, transactions, read-only open mode, and durable records.
- Scanner MVP for local folder traversal, supported video file filtering, basic filename parsing, media item/file persistence, incremental rescans, missing file handling, and conservative rename candidate reporting.
- Minimal read-only debug listing executable through `CineMindShell`.
- Unit/integration coverage for Domain, Persistence, and Scanner behavior.

Out of scope for Phase 1 and not implemented:

- Playback/libmpv integration.
- TMDB or other online metadata providers.
- Subtitle discovery, linking, or rendering.
- AI classification, semantic search, recommendations, or tagging.
- Plugin system, local HTTP API, sync, or multi-user features.
- Real-time filesystem watcher and production background job orchestration.
- UI polish or full application workflow UI.

## 2. Module List

### Shared

- `Sources/Shared/Shared.swift`
- Provides shared build metadata and stable path hashing used by scanner diagnostics.

### Domain

- `Sources/Domain/Models.swift`
- Defines:
  - `Library`
  - `LibraryFolder`
  - `MediaItem`
  - `MediaFile`
  - `EpisodeInfo`
  - `ScanRun`
  - `ScanIssue`
  - supporting ID aliases, enums, normalization, and validation helpers.

### Persistence

- `Sources/Persistence/SQLiteConnection.swift`
- `Sources/Persistence/Migrations.swift`
- `Sources/Persistence/CineMindStore.swift`
- Implements:
  - SQLite connection wrapper.
  - `schema_migrations` version tracking.
  - version 1 schema for all Phase 1 tables.
  - repository-style CRUD and lookup APIs.
  - transaction handling and rollback behavior.
  - read-only store access for debug listing.

### Scanner

- `Sources/Scanner/Scanner.swift`
- Implements:
  - local filesystem adapter.
  - injectable scanner filesystem protocol for tests.
  - supported extension filtering: `.mp4`, `.mkv`, `.mov`, `.avi`, `.m4v`.
  - movie parsing with optional year.
  - episode parsing using `SxxExx` / `sxxexx`.
  - scan run creation and completion.
  - exact-path updates on rescan.
  - missing file marking without deletion.
  - duplicate file attachment to the same logical media item.
  - conservative rename/move candidate issue recording.
  - folder unavailable and filesystem error issue recording.

### CineMindShell

- `Sources/CineMindShell/main.swift`
- Provides a minimal read-only command-line listing:
  - opens an existing SQLite database path.
  - prints the library name.
  - lists media items and their associated files with availability.

### Tests

- `Tests/DomainTests/DomainModelTests.swift`
- `Tests/PersistenceTests/PersistenceRepositoryTests.swift`
- `Tests/ScannerTests/ScannerTests.swift`

## 3. Test Results

Command:

```sh
swift test
```

Result:

- Passed.
- Executed 36 XCTest cases.
- Failures: 0.
- Unexpected failures: 0.

Breakdown:

- `DomainModelTests`: 10 tests passed.
- `PersistenceRepositoryTests`: 13 tests passed.
- `ScannerTests`: 13 tests passed.

Coverage represented by the tests:

- Domain identity separation between `MediaItem` and `MediaFile`.
- Movie vs episode modeling and validation.
- Title normalization.
- Availability state behavior.
- Scan status and scan issue type coverage.
- SQLite migration table creation and idempotent reopen.
- Library, folder, media item, media file, scan run, and scan issue persistence.
- Read-only store access.
- Transaction rollback on persistence failure.
- Scanner creation of new movie and episode records.
- Repeated scan update behavior.
- Missing file marking without deleting item/file records.
- Duplicate file handling.
- Rename/move candidate issue recording.
- Unavailable folder handling.
- Filesystem and persistence error behavior during scans.
- Unsupported extension filtering.

Note: The first sandboxed `swift test` attempt failed because SwiftPM/Clang could not write to user-level module caches under the sandbox. The same command passed when run with the required cache permissions.

## 4. Manual Acceptance Results

Manual acceptance was performed at the package/command-line level because Phase 1 does not include a full UI.

Results:

- Package manifest and all Phase 1 targets build successfully as part of `swift test`.
- `CineMindShell` builds successfully with:

```sh
swift run CineMindShell
```

- Running `CineMindShell` without a database argument returns the expected usage contract:

```text
Expected exactly one SQLite database path argument.
Usage: CineMindShell <sqlite-database-path>
```

Phase 1 acceptance criteria status:

- Database initializes correctly: accepted via migration creation and reopen tests.
- Folder can be added: accepted via library folder CRUD tests.
- Scan populates media: accepted via new movie and episode scan tests.
- Rescan reconciles data: accepted via repeated scan, missing file, duplicate file, rename candidate, unavailable folder, and failure handling tests.
- Debug listing exists: accepted via `CineMindShell` build and argument contract smoke test.

## 5. Known Limitations

- Phase 1 has no playback surface and does not integrate libmpv.
- There is no production SwiftUI workflow for adding folders or running scans.
- `CineMindShell` is read-only and only lists existing databases; it does not create libraries, add folders, or trigger scans.
- Filename parsing is intentionally basic:
  - movie title plus optional trailing year.
  - episode `SxxExx` / `sxxexx`.
  - no provider-backed matching, aliases, alternate titles, language handling, or fuzzy matching.
- Rename/move handling is conservative; it records a candidate issue and preserves both file records rather than merging or deleting automatically.
- Missing files are marked unavailable and preserved by design.
- If a whole library folder is unavailable, existing files are not marked missing.
- Supported video extensions are limited to `.mp4`, `.mkv`, `.mov`, `.avi`, and `.m4v`.
- No ffprobe integration, video fingerprinting, duration, codec, resolution, stream, or bitrate extraction.
- Access bookmarks are represented in the model/schema, but there is no UI flow yet to acquire or refresh security-scoped bookmarks.
- IDs are currently String-backed aliases for Phase 1 compatibility.
- SQLite schema is versioned, but only migration version 1 exists.
- No FTS, advanced search indexes, or metadata cache tables are included in Phase 1.

## 6. Deferred Items

Deferred to later phases:

- Playback MVP with libmpv.
- Application-level use cases and user-facing folder selection/scan workflows.
- SwiftUI library browser and playback UI.
- Security-scoped bookmark acquisition and refresh UX.
- TMDB metadata matching and refresh pipeline.
- Subtitle discovery, persistence, selection, and rendering integration.
- AI-assisted classification, semantic search, suggestions, and tagging.
- Real-time filesystem watcher.
- Background job queue beyond synchronous scan execution.
- ffprobe/media technical metadata extraction.
- Video fingerprinting or robust duplicate detection.
- Advanced filename parser and provider-assisted reconciliation.
- Local HTTP API.
- Plugin system.
- Sync, remote library access, and multi-user support.
- Future SQLite migrations for metadata, playback state, subtitles, FTS/search, and AI-derived fields.
