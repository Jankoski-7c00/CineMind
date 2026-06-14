# Phase 8 Completion Report

Date: 2026-06-14

Canonical spec: `docs/phase-8-basic-json-export.md`

## Implemented Scope

- Added a user-triggered `Library > Export Library...` macOS command.
- Added a native `NSSavePanel` destination picker with JSON content-type
  restriction, a readable default file name, cancellation as a silent no-op,
  and concise non-backup wording.
- Added duplicate-start protection plus concise success and failure alerts.
- Added a transaction-consistent typed Persistence snapshot covering durable
  version 1 library, media, playback, metadata, subtitle, and curation state.
- Added an explicit version 1 Application wire contract and privacy projection.
- Added deterministic array ordering, sorted JSON keys, readable indentation,
  and UTC ISO 8601 dates.
- Added off-main-thread export assembly, encoding, and atomic file writing.
- Added focused errors for invalid destinations, snapshot failures,
  inconsistent relationships, encoding failures, and write failures.

## Export Format

- Format identity: `cinemind-library-export`
- Format version: `1`
- Included categories:
  - library
  - folders
  - media items
  - media files
  - playback history
  - metadata items
  - metadata external IDs
  - sanitized metadata source records
  - sanitized poster assets
  - subtitle assets
  - tags and tag assignments
  - favorites
  - collections and collection memberships
- Stable IDs and relationship IDs are preserved.
- Arrays are sorted by stable IDs or stable relationship-key pairs.
- Keys are sorted by `JSONEncoder`.
- Dates use UTC ISO 8601 encoding.

## Privacy And Excluded Fields

The version 1 allowlist excludes:

- absolute library-folder paths
- security-scoped bookmark data
- absolute media path hashes
- raw metadata provider payload JSON
- local poster-cache paths and cache implementation fields
- media, subtitle, and poster file contents
- database paths and files
- scan runs and scan issues
- FTS and migration records

Relative media and subtitle paths remain included because they describe
relationships within a user-authorized library folder without exposing the
machine-local root path.

## Transaction Consistency

- `fetchLibraryExportSnapshot()` assembles the complete typed snapshot inside
  one deferred read transaction.
- Encoding, file writing, save-panel presentation, and user feedback happen
  after the transaction finishes.
- `SQLiteConnection` now serializes access with a recursive connection lock so
  another operation using the same `CineMindStore` cannot interleave statements
  inside the export transaction.
- A concurrency test proves a same-store write waits until the read transaction
  completes and the transaction observes one stable value.
- Deferred read transactions work with read-only stores and avoid taking the
  write reservation used by `BEGIN IMMEDIATE`.

## Persistence API Summary

- Added `Sources/Persistence/LibraryExportSnapshotQueries.swift`.
- Added one narrow public API:
  - `fetchLibraryExportSnapshot()`
- Added export-specific typed projections that omit sensitive Persistence and
  Domain fields before the snapshot leaves Persistence.
- Added relationship validation before returning the snapshot.
- No general raw-table dump or unrelated repository APIs were added.

New Persistence API required: yes

## Application API Summary

- Added `Sources/Application/LibraryExport.swift`.
- Added:
  - `LibraryExporting`
  - `LibraryExportDestinationPicking`
  - `ApplicationLibraryExportStore`
  - `LibraryExportEncoding`
  - `LibraryExportFileWriting`
  - `LibraryExportUseCase`
  - `LibraryExportResult`
  - `LibraryExportError`
  - explicit `LibraryExportDocumentV1` wire DTOs
- `LibraryExportUseCase` validates the destination and relationships, maps the
  privacy-reviewed V1 document, encodes deterministically, and writes
  atomically on a dedicated queue.

## macOS App Integration

- Added `Sources/CineMindApp/AppKitLibraryExportDestinationPicker.swift`.
- `CineMindAppEnvironmentFactory` constructs the exporter and picker in the
  composition root.
- `CineMindApp` owns the global command, busy state, save-panel workflow, and
  feedback alerts.
- `AppShellEnvironment` and `Sources/AppUI` were not changed for export.

## Migration Decision

- Phase 8 reads existing durable schema version 6 data.
- No table, column, index, constraint, or stored state was added.
- No migration tests were required beyond verifying schema version 6 remains
  unchanged.

Migrations.swift changed: no

## Boundary Audit

- AppUI forbidden import grep returned no matches.
- AppUI SQLite/store/save-panel/export-encoder grep returned no matches.
- Lower layers do not import or reference AppUI.
- Application contains no raw SQL or migration logic.
- AppKit save-panel ownership remains in `CineMindApp`.
- `Package.swift` dependencies were unchanged.

Boundary status: clean

## Verification

Passed:

- `git diff --check`
- `swift test --filter LibraryExportSnapshotTests`
  - 4 tests, 0 failures.
- `swift test --filter PersistenceRepositoryTests`
  - 62 tests, 0 failures.
- `swift test --filter LibraryExportTests`
  - 5 tests, 0 failures.
- `swift build --target AppUI`
- `swift build --target CineMindApp`
- `swift test`
  - 439 tests, 0 failures.

Focused export verification covers:

- minimal and complete snapshots
- all version 1 durable categories
- read-only database export
- unchanged schema version 6
- deterministic array and JSON output
- UTC ISO 8601 dates
- explicit privacy-field exclusion
- relationship validation
- same-store transaction isolation
- invalid destination, snapshot, encoding, and writer failures
- atomic replacement of an existing destination
- generated JSON parsing and result counts

Boundary commands:

- `rg -n "^import (Persistence|Metadata|Subtitle|Playback|PlaybackAVFoundation|AVFoundation|AVKit|AppKit|AI)" Sources/AppUI`
  - no matches.
- `rg -n "SQLite|CineMindStore|JSONEncoder|NSSavePanel|Migrations|Migration|CREATE TABLE|ALTER TABLE|PRAGMA|Persistence\\." Sources/AppUI`
  - no matches.
- `rg -n "^import AppUI|AppUI\\." Sources/Persistence Sources/Application Sources/Domain Tests`
  - no matches.
- `rg -n "^import (SQLite|SQLite3|GRDB|FMDB)" Sources/AppUI Sources/Application Sources/Domain Tests`
  - expected Persistence test-only match.

## Real-App Smoke

- `swift run CineMindApp` built and launched the real app successfully.
- Automated menu and save-panel interaction could not run because macOS denied
  `osascript` Accessibility access in this environment.
- Cancellation and menu-click behavior were therefore not directly observed
  through UI automation in this session.
- The underlying cancellation branch is a silent return, and the export file
  generation/replacement/parse workflow passed focused integration tests using
  disposable destinations.

## Known Deferred Work

- JSON import and restore
- database backup
- scheduled export
- archive, sharing, sync, or cloud export
- media, subtitle, or poster file export
- streaming encoding for very large libraries
- AI artifacts or provider configuration export

## Completion Verdict

Phase 8 implements the planned basic JSON export contract and macOS workflow.
The export is versioned, deterministic, privacy-projected, transaction
consistent, atomic, provider-independent, and boundary-clean. All automated
acceptance gates pass; direct menu/save-panel UI observation remains
environment-blocked by macOS Accessibility permission.
