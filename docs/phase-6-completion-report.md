# Phase 6 Completion Report

Date: 2026-06-03

Canonical spec: `docs/phase-6-library-search-fts.md`

## Implemented Scope

- Added local media-library keyword search backed by SQLite FTS5.
- Search indexes media title, series title, episode title, metadata title,
  metadata original title, metadata summary, and year.
- Added media type filters for all, movies, and TV episodes.
- Added availability filters for any, available, and missing/unavailable.
- Added sort modes for relevance, title, recently added, recently played, and
  year.
- Wired search through Application DTOs and protocols so AppUI does not depend
  on Persistence or SQLite.
- Added compact search controls to the library browser header.
- Preserved existing section browsing when search text, filters, and sort are
  all default.
- Search result selection reuses the existing media table selection and detail
  loading path.

## Migration Summary

- `Sources/Persistence/Migrations.swift` now applies schema version 5.
- Version 5 creates `media_search_fts` using SQLite FTS5.
- Existing v4 media and metadata rows are backfilled during migration.
- SQLite triggers keep the FTS table synchronized after `media_items` and
  `metadata_items` insert, update, and delete events.
- Migration diagnostics hide FTS shadow tables and report the logical
  `media_search_fts` table.

Migrations.swift changed: yes

## Persistence API Summary

- Added `PersistedMediaSearchQuery`.
- Added `PersistedMediaSearchAvailability`.
- Added `PersistedMediaSearchSort`.
- Added `PersistedMediaSearchResult`.
- Added `CineMindStore.searchMediaItems(query:)`.
- Reused the existing media summary aggregate shape for availability, metadata
  status, latest playback, and result row mapping.

## Application API Summary

- Added `LibrarySearchRequest`.
- Added `LibrarySearchMediaTypeFilter`.
- Added `LibrarySearchAvailabilityFilter`.
- Added `LibrarySearchSort`.
- Added `LibrarySearchSnapshot`.
- Added `LibraryMediaSearching`.
- Added `LibraryMediaSearchUseCase`.
- Extracted shared `LibraryItemSummary` mapping so browse and search rows stay
  consistent.

## AppUI Summary

- `AppShellEnvironment` now carries `LibraryMediaSearching`.
- `CineMindAppEnvironmentFactory` constructs `LibraryMediaSearchUseCase`.
- `LibraryBrowserViewModel` owns search text, filter, sort, and active search
  loading state.
- `LibraryBrowserView` adds header search controls and a search-specific empty
  state.
- Add Folder, Scan, section browsing, table selection, and detail loading remain
  on the existing paths.

## Boundary Audit

- `Sources/AppUI` imports only Application, Domain, SwiftUI, and local AppUI
  symbols for this feature.
- AppUI forbidden import grep returned no matches.
- AppUI SQLite/FTS/provider/playback infrastructure grep returned no matches.
- `Package.swift` keeps AppUI depending on Application, Domain, and Shared; it
  does not add a Persistence dependency to AppUI.
- Application maps Persistence results into UI-safe DTOs and does not contain
  raw SQL or migration logic.

## Verification

Passed:

- `swift test --filter PersistenceRepositoryTests`
  - 58 tests, 0 failures.
- `swift test --filter LibrarySearch`
  - 6 tests, 0 failures.
- `swift build --target AppUI`
- `swift test --filter LibraryBrowserSummaryTests`
  - 17 tests, 0 failures.
- `swift build --target CineMindApp`
- `swift test`
  - 418 tests, 0 failures.

Boundary commands:

- `rg -n "^import (Persistence|Metadata|Subtitle|Playback|PlaybackAVFoundation|AVFoundation|AVKit|AppKit)" Sources/AppUI`
  - no matches.
- `rg -n "SQLite|FTS|CineMindStore|MetadataProvider|SubtitleSearchProviding|AVPlayer|AVFoundation" Sources/AppUI`
  - no matches.
- `rg -n "import AppUI" Sources/Persistence Sources/Application Sources/Domain Tests`
  - no matches.
- `rg -n "Persistence\\." Sources/AppUI Tests`
  - no matches.
- `rg -n "AppUI\\." Sources/Persistence Sources/Application Sources/Domain Tests`
  - no matches.

Manual app smoke:

- Not run in this session to avoid migrating or modifying the user's real
  Application Support database. The app target build and full automated suite
  passed.

## Known Deferred Work

- No semantic search, embeddings, AI tagging, subtitle text search, path search,
  tags, favorites, collections, or poster wall were added.
- No debounced search typing or advanced result highlighting was added.
- No search-result match reason is shown in AppUI; Persistence returns rank for
  relevance sorting and keeps `matchReason` reserved.
