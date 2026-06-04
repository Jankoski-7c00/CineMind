# Phase 7 Completion Report

Date: 2026-06-04

Canonical spec: `docs/phase-7-user-curation-tags-favorites-collections.md`

## Implemented Scope

- Added durable local curation for manual tags, favorites, and collections.
- Manual tags can be created, renamed, deleted, assigned to media items, and
  removed from media items.
- Tag and collection names are trimmed, whitespace-collapsed, normalized, and
  checked for duplicate normalized names.
- Favorite state can be toggled per media item, persisted, shown in summaries,
  and browsed from the sidebar.
- Collections can be created, renamed, deleted, used to group media items, and
  browsed from the sidebar.
- Detail view now shows current favorite, assigned tags, and collection
  membership with compact mutation controls.
- Library rows now expose compact favorite and tag state.
- Library search now supports favorite and tag filters through normal SQLite
  joins.
- Existing library browse, search, folder, scan, metadata, subtitle, and
  playback flows remain on their existing paths.

## Migration Summary

- `Sources/Persistence/Migrations.swift` now applies schema version 6.
- Version 6 creates:
  - `tags`
  - `media_item_tags`
  - `favorite_media_items`
  - `collections`
  - `collection_items`
- Version 6 adds indexes for tag membership and collection membership lookups.
- Tag and collection normalized names are unique at the database layer.
- Tag and collection delete APIs explicitly remove membership rows before
  deleting the parent record.
- Migration tests cover fresh schema creation, v5 to v6 upgrade, read-only
  access to migrated curation data, and rollback of partial v6 schema creation.

Migrations.swift changed: yes

## Persistence API Summary

- Added `Sources/Persistence/CurationQueries.swift`.
- Added persisted curation DTOs for tags, collections, and item curation.
- Added tag CRUD and tag assignment APIs.
- Added favorite set/unset, item curation, and favorite browse APIs.
- Added collection CRUD, collection membership, and collection browse APIs.
- Extended media summary rows with favorite state and tag labels.
- Extended search query filters with favorite and tag filtering.

New Persistence API required: yes

## Application API Summary

- Added `Sources/Application/LibraryCuration.swift`.
- Added `LibraryCurationBrowsing` and `LibraryCurationHandling`.
- Added `ApplicationLibraryCurationStore`.
- Added UI-safe DTOs for tag summaries, collection summaries, item curation,
  and the global curation snapshot.
- Added `LibraryCurationUseCase` for validation, duplicate checks, idempotent
  mutations, and persistence mapping.
- Extended `LibraryItemDetailShell` with curation detail.
- Extended `LibraryItemSummary` with favorite and tag-label fields.
- Extended `LibraryBrowserSection` with favorites and collection sections.
- Extended `LibrarySearchRequest` with favorite and tag filters.

## AppUI Summary

- `AppShellEnvironment` now carries curation browsing and handling facades.
- `CineMindAppEnvironmentFactory` constructs and injects
  `LibraryCurationUseCase`.
- `SidebarView` now includes Favorites and user collection rows.
- `LibraryBrowserViewModel` loads curation snapshots, routes favorites and
  collection sections, and preserves safe navigation after collection deletion.
- `LibraryBrowserView` adds compact favorite/tag search filters and row
  curation indicators.
- `LibraryItemDetailViewModel` owns curation mutation actions and refresh
  revision state.
- `LibraryItemDetailView` adds compact controls for favorite, tag, and
  collection edits without adding AppUI dependencies on Persistence.

## FTS and Search Decision

- Phase 7 did not rebuild `media_search_fts` for assigned tag text.
- The Phase 7 plan allowed deferring tag text FTS if trigger maintenance became
  broad or fragile.
- Favorite and tag filtering did ship through normal relational joins and is
  covered by Persistence and Application search tests.
- Tag text keyword matching is deferred to a focused Phase 7.x search polish
  pass where the FTS rebuild and trigger set can be isolated and tested.

## Boundary Audit

- `Sources/AppUI` imports only SwiftUI, Application, Domain, Shared, and local
  AppUI symbols for this feature.
- AppUI forbidden import grep returned no matches.
- AppUI SQLite/store/provider/playback/AI infrastructure grep returned no
  matches.
- Lower layers do not import or reference AppUI.
- `Package.swift` keeps AppUI depending on Application, Domain, and Shared; it
  does not add a Persistence dependency to AppUI.
- Application maps Persistence data into UI-safe DTOs and contains no raw SQL or
  migration logic.

## Verification

Passed:

- `git diff --check`
- `swift test --filter DomainModelTests`
  - 16 tests, 0 failures.
- `swift test --filter PersistenceRepositoryTests`
  - 62 tests, 0 failures.
- `swift test --filter LibraryCuration`
  - 2 tests, 0 failures.
- `swift test --filter LibraryItemDetailTests`
  - 15 tests, 0 failures.
- `swift test --filter LibraryBrowserSummaryTests`
  - 19 tests, 0 failures.
- `swift test --filter LibrarySearchTests`
  - 7 tests, 0 failures.
- `swift build --target AppUI`
- `swift build --target CineMindApp`
- `swift test`
  - 430 tests, 0 failures.

Boundary commands:

- `rg -n "^import (Persistence|Metadata|Subtitle|Playback|PlaybackAVFoundation|AVFoundation|AVKit|AppKit|AI)" Sources/AppUI`
  - no matches.
- `rg -n "SQLite|CineMindStore|MetadataProvider|SubtitleSearchProviding|AVPlayer|AVFoundation|Embedding|AI|Migrations|Migration|CREATE TABLE|ALTER TABLE|PRAGMA|Persistence\\." Sources/AppUI`
  - no matches.
- `rg -n "^import AppUI|AppUI\\." Sources/Persistence Sources/Application Sources/Domain Tests`
  - no matches.
- `rg -n "^import (SQLite|SQLite3|GRDB|FMDB)" Sources/AppUI Sources/Application Sources/Domain Tests`
  - expected persistence-test-only match: `Tests/PersistenceTests/PersistenceRepositoryTests.swift`.
- `rg -n "Persistence\\." Sources/AppUI Tests`
  - no matches.
- `rg -n "AppUI\\." Sources/Persistence Sources/Application Sources/Domain Tests`
  - no matches.

Manual app smoke:

- Not run in this session to avoid migrating or modifying the user's real
  Application Support database without an approved disposable app environment.
  The AppUI target, CineMindApp target, focused tests, and full automated suite
  passed.

## Known Deferred Work

- Assigned tag names are not yet indexed into `media_search_fts`.
- Collection names are not indexed into keyword search.
- No AI tag suggestion, semantic search, embeddings, smart collections, JSON
  export, sync, sharing, or poster-wall browsing was added.
- No broad AppUI redesign was performed.

## Completion Verdict

Phase 7 meets the planned manual curation scope with the explicit Phase 7.x
deferment of tag text FTS. The implementation keeps AppUI boundary-clean,
persists curation through schema version 6, and passes targeted and full-suite
verification.
