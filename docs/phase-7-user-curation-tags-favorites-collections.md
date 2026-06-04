# Phase 7 User Curation: Tags, Favorites, and Collections

Canonical file: `docs/phase-7-user-curation-tags-favorites-collections.md`

Planning date: 2026-06-04

Phase 7 adds user-owned organization primitives on top of the existing local
library: manual tags, favorites, and collections. This phase should stay
local-first, offline, and deterministic. It is the bridge between Phase 6
keyword search and later AI tag suggestion: users must first have a durable,
manual curation model before AI can suggest anything into it.

This document is a development plan only. It does not implement code.

---

# 1. Current Audit

Current repository state at planning time:

- The working tree is clean on `main`.
- `main` is aligned with `origin/main`.
- Latest commit: `60b857a Implement phase 6 library search`.
- Phase 6 implemented local library keyword search through SQLite FTS5.
- Phase 6 added schema version 5 and the `media_search_fts` virtual table.
- Phase 6 wired search through Application DTOs and kept AppUI free of
  Persistence and SQLite imports.
- Phase 6 completion report explicitly deferred semantic search, embeddings,
  AI tagging, subtitle text search, path search, tags, favorites, collections,
  and poster wall.

Product and architecture signal:

- `docs/product-scope.md` lists the following MVP curation requirements:
  manual tags, favorites, and collections.
- `docs/architecture.md` defines `Tag` and `Collection` concepts.
- `docs/architecture.md` says manual tags take priority over AI-suggested tags.
- `docs/architecture.md` allows favorites to be implemented as a special
  collection, boolean relation, or tag-like relation.
- `docs/architecture.md` lists tags as a future keyword-search target and
  favorite as a search filter.
- `docs/architecture.md` places JSON export and AI after the current search
  and subtitle foundations.

Code audit summary:

- Source search found no existing user tag, favorite, or collection Domain
  models.
- Source search found no `tags`, `media_item_tags`, `collections`, or
  `collection_items` Persistence tables.
- Source search found no Application curation facade or AppUI curation handler.
- Existing `.tag(...)` references in AppUI are SwiftUI selection tags, not user
  curation tags.
- Current `LibraryItemSummary`, `PersistedMediaItemSummary`, and
  `LibrarySearchSnapshot` do not carry favorite, tag, or collection fields.
- Current `LibraryItemDetailShell` does not carry favorite, tag, or collection
  membership.
- Current `Package.swift` has no AI target, which supports keeping Phase 7
  manual and non-AI.

Migration decision:

- Migration required: yes.
- Reason: Phase 7 requires new stored user data that does not fit any existing
  table.
- Expected schema version: 6.
- `Sources/Persistence/Migrations.swift` should change during implementation,
  but not during this planning-only round.

Repository API decision:

- New Persistence API required: yes, after discovery.
- Reason: existing summary, detail, search, metadata, playback, subtitle, and
  scanner APIs do not read or write user curation data.
- New Application API required: yes.
- Reason: AppUI must not consume Persistence directly, and curation actions are
  user-facing commands.

---

# 2. Goal

Implement durable user curation for local media items so a user can:

- create, rename, and delete manual tags
- assign and remove tags on a media item
- mark and unmark a media item as favorite
- create, rename, and delete collections
- add and remove media items from collections
- view tags, favorite state, and collection membership in the detail surface
- browse favorites from the library browser
- browse user collections from the library browser
- filter or narrow library search by favorite and tag where the UI surface
  remains compact
- search tagged media by tag text if FTS trigger complexity remains narrow

Phase 7 must:

- preserve existing library browsing, search, folders, scanning, metadata,
  subtitles, and playback behavior
- keep all curation data local in SQLite
- route AppUI through Application protocols and DTOs only
- keep AI entirely optional and absent from the implementation
- use schema version 6 with migration tests
- keep migration and query changes focused

---

# 3. Non-Goals

Do not implement in Phase 7:

- AI provider abstraction
- semantic search
- embedding generation
- automatic tag suggestion
- AI-suggested tag acceptance UI
- JSON export
- subtitle summarization
- recommendations
- smart collections
- complex saved searches
- collection sharing
- multi-user ownership or permissions
- media server, sync, plugin, or HTTP API work
- automatic curation from metadata providers
- path search
- subtitle text search
- poster wall or grid browsing
- broad AppUI redesign
- playback behavior changes
- metadata rematch behavior changes
- scanner behavior changes unrelated to preserving media identity

Do not add AppUI dependencies on:

- `Persistence`
- `Metadata`
- `Subtitle`
- `Playback`
- `PlaybackAVFoundation`
- `AVFoundation`
- `AVKit`
- `AppKit`
- `AI`
- SQLite-specific types

---

# 4. Scope

Inspect before implementation:

- `docs/product-scope.md`
- `docs/architecture.md`
- `docs/phase-6-library-search-fts.md`
- `docs/phase-6-completion-report.md`
- `Package.swift`
- `Sources/Domain/Models.swift`
- `Sources/Persistence/Migrations.swift`
- `Sources/Persistence/CineMindStore.swift`
- `Sources/Persistence/LibraryMediaSummaryQueries.swift`
- `Sources/Persistence/LibrarySearchQueries.swift`
- `Sources/Persistence/MediaItemDetailQueries.swift`
- `Sources/Application/LibraryBrowserSummary.swift`
- `Sources/Application/LibrarySearch.swift`
- `Sources/Application/LibraryItemDetail.swift`
- `Sources/AppUI/AppShellEnvironment.swift`
- `Sources/AppUI/AppShellState.swift`
- `Sources/AppUI/AppShellViewModel.swift`
- `Sources/AppUI/SidebarView.swift`
- `Sources/AppUI/LibraryBrowserViewModel.swift`
- `Sources/AppUI/LibraryBrowserView.swift`
- `Sources/AppUI/LibraryItemDetailView.swift`
- `Sources/CineMindApp/CineMindAppEnvironmentFactory.swift`
- `Tests/DomainTests`
- `Tests/PersistenceTests/PersistenceRepositoryTests.swift`
- `Tests/ApplicationTests/LibraryBrowserSummaryTests.swift`
- `Tests/ApplicationTests/LibrarySearchTests.swift`
- `Tests/ApplicationTests/LibraryItemDetailTests.swift`

Likely implementation files:

- `Sources/Domain/Models.swift`
- `Sources/Persistence/Migrations.swift`
- `Sources/Persistence/CurationQueries.swift` (new)
- `Sources/Persistence/LibraryMediaSummaryQueries.swift`
- `Sources/Persistence/LibrarySearchQueries.swift`
- `Sources/Persistence/MediaItemDetailQueries.swift`
- `Sources/Persistence/CineMindStore.swift`
- `Sources/Application/LibraryCuration.swift` (new)
- `Sources/Application/LibraryBrowserSummary.swift`
- `Sources/Application/LibrarySearch.swift`
- `Sources/Application/LibraryItemDetail.swift`
- `Sources/AppUI/AppShellEnvironment.swift`
- `Sources/AppUI/AppShellState.swift`
- `Sources/AppUI/AppShellViewModel.swift`
- `Sources/AppUI/SidebarView.swift`
- `Sources/AppUI/LibraryBrowserViewModel.swift`
- `Sources/AppUI/LibraryBrowserView.swift`
- `Sources/AppUI/LibraryItemDetailView.swift`
- `Sources/CineMindApp/CineMindAppEnvironmentFactory.swift`
- `Tests/DomainTests/DomainModelTests.swift`
- `Tests/PersistenceTests/PersistenceRepositoryTests.swift`
- `Tests/ApplicationTests/LibraryCurationTests.swift` (new)
- `Tests/ApplicationTests/LibraryBrowserSummaryTests.swift`
- `Tests/ApplicationTests/LibrarySearchTests.swift`
- `Tests/ApplicationTests/LibraryItemDetailTests.swift`

Modify only if discovery proves necessary:

- `Package.swift`
  - Expected no target changes if Phase 7 stays inside existing modules.
- `Sources/AppUI/Components/**`
  - Only for small reusable controls such as tag chips or collection rows.
- `docs/product-scope.md`
  - Only if the roadmap page needs a link after completion.

Forbidden unless explicitly approved in a later phase:

- `Sources/AI/**`
- new AI targets
- third-party dependencies
- playback backend files
- subtitle provider files
- metadata provider behavior
- scanner matching/reconciliation behavior
- broad browser layout rewrite
- broad detail view refactor beyond the curation surface

---

# 5. Discovery Commands

Run before implementation:

```sh
git status --short
git diff --stat
rg -n -i "\\btag\\b|\\btags\\b|favorite|favorites|collection|collections|curation|media_tag|media_tags|user_tag|manual tag|ai_suggested" Sources Tests docs Package.swift
rg -n "Migration|Migrations|CREATE TABLE|CREATE INDEX|schema_migrations|version[0-9]Statements|CREATE VIRTUAL TABLE|ALTER TABLE" Sources/Persistence Tests/PersistenceTests
rg -n "public func|func fetch|func list|func load|func save|func update|func delete|func insert|func upsert" Sources/Persistence Sources/Application Tests
rg -n "protocol .*Repository|protocol .*Reading|protocol .*Writing|struct .*Repository|class .*Repository|actor .*Repository" Sources Tests
rg -n "Query|Queries|UseCase|Store|Repository|Detail|Summary|DTO|Mapper" Sources/Persistence Sources/Application Tests
rg -n "^import (Persistence|Metadata|Subtitle|Playback|PlaybackAVFoundation|AVFoundation|AVKit|AppKit)" Sources/AppUI || true
swift test --list-tests
```

Questions to answer before code:

- What is the exact v6 schema shape?
- Should favorites be a boolean relation, special collection, or tag-like
  relation?
- Should tag names be unique case-insensitively across the whole library?
- Should collection names be unique case-insensitively across the whole library?
- Should deleting a tag delete only assignments or block when in use?
- Should deleting a collection delete only membership rows and preserve media?
- Should favorite rows be included in collection membership, or kept separate?
- Should Phase 7 search include tag text in FTS immediately?
- Can FTS tag indexing be maintained by simple triggers?
- Can `LibraryItemSummary` carry compact curation data without making summary
  queries too heavy?
- Should collection browsing reuse `LibraryMediaSummaryUseCase` or introduce a
  narrow curation browsing use case?
- Can sidebar collection rows preserve existing `List(selection:)` behavior?
- How should AppUI refresh detail and browser rows after curation mutations?

---

# 6. Data Model Plan

## 6.1 Domain Models

Add ID aliases:

```swift
public typealias TagID = String
public typealias CollectionID = String
```

Add tag source:

```swift
public enum TagSource: String, Codable, Sendable, Equatable, CaseIterable {
    case manual
    case aiSuggested = "ai_suggested"
    case imported
}
```

Phase 7 should create only manual tags from the UI. The enum should still carry
future-compatible cases because architecture already defines them. Do not build
AI suggestion workflows in this phase.

Add tag model:

```swift
public struct Tag: Codable, Sendable, Equatable {
    public var id: TagID
    public var name: String
    public var normalizedName: String
    public var source: TagSource
    public var createdAt: Date
    public var updatedAt: Date
}
```

Add assignment model:

```swift
public struct MediaItemTag: Codable, Sendable, Equatable {
    public var mediaItemID: MediaItemID
    public var tagID: TagID
    public var assignedAt: Date
    public var updatedAt: Date
}
```

Add collection model:

```swift
public struct MediaCollection: Codable, Sendable, Equatable {
    public var id: CollectionID
    public var name: String
    public var normalizedName: String
    public var description: String?
    public var createdAt: Date
    public var updatedAt: Date
}
```

Add collection membership model:

```swift
public struct CollectionItem: Codable, Sendable, Equatable {
    public var collectionID: CollectionID
    public var mediaItemID: MediaItemID
    public var addedAt: Date
    public var updatedAt: Date
}
```

Favorites recommendation:

- Implement favorites as a dedicated boolean relation table:
  `favorite_media_items`.
- Reason: this is the simplest model for MVP favorites and avoids reserved
  hidden collection naming, hidden collection creation, and collection rename
  edge cases.
- Application can later present favorites as collection-like without changing
  AppUI concepts.

Add favorite model only if useful in Domain:

```swift
public struct FavoriteMediaItem: Codable, Sendable, Equatable {
    public var mediaItemID: MediaItemID
    public var createdAt: Date
    public var updatedAt: Date
}
```

Validation:

- Add curation validation errors to `DomainValidationError`:
  - `emptyTagName`
  - `emptyCollectionName`
  - `emptyNormalizedTagName`
  - `emptyNormalizedCollectionName`
- Normalize by trimming leading/trailing whitespace, collapsing internal
  whitespace, and lowercasing.
- Do not reuse `MediaTitleNormalizer` for curation names unless discovery proves
  its punctuation behavior is desirable for tag names.
- Do not add arbitrary length limits unless the implementation has a clear UI or
  persistence reason.

## 6.2 Persistence Tables

Add schema version 6.

Recommended tables:

```sql
CREATE TABLE IF NOT EXISTS tags (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    normalized_name TEXT NOT NULL UNIQUE,
    source TEXT NOT NULL CHECK(source IN ('manual', 'ai_suggested', 'imported')),
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS media_item_tags (
    media_item_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE CASCADE,
    tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    assigned_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    PRIMARY KEY (media_item_id, tag_id)
);

CREATE INDEX IF NOT EXISTS idx_media_item_tags_tag_id
ON media_item_tags(tag_id);

CREATE TABLE IF NOT EXISTS favorite_media_items (
    media_item_id TEXT PRIMARY KEY REFERENCES media_items(id) ON DELETE CASCADE,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS collections (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    normalized_name TEXT NOT NULL UNIQUE,
    description TEXT,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS collection_items (
    collection_id TEXT NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
    media_item_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE CASCADE,
    added_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    PRIMARY KEY (collection_id, media_item_id)
);

CREATE INDEX IF NOT EXISTS idx_collection_items_media_item_id
ON collection_items(media_item_id);
```

Foreign key note:

- Keep explicit child-row deletes in repository methods when deleting tags or
  collections.
- Do not rely only on SQLite foreign-key cascades unless current connection
  setup is verified to enable foreign keys consistently.

## 6.3 FTS Integration Decision

Phase 6 created `media_search_fts` without tags. Architecture says keyword
search targets should include tags. Phase 7 should attempt tag text search only
if the migration and trigger maintenance remain narrow.

Recommended implementation path:

1. Add curation tables in v6.
2. Rebuild `media_search_fts` as derived data with an additional `tag_names`
   column.
3. Backfill FTS rows by aggregating assigned tag names per media item.
4. Recreate existing media and metadata triggers with the tag aggregation.
5. Add triggers for tag insert, update, delete, assignment insert, and
   assignment delete to refresh affected media item rows.
6. Keep collection names out of FTS in Phase 7.

Stop and defer tag text FTS if:

- trigger logic becomes broad or fragile
- FTS table rebuild risks user data beyond derived search rows
- tests cannot prove tag updates immediately affect search results

Fallback if stopped:

- Keep Phase 7 favorites, tags, and collections fully persisted.
- Add favorite and tag filters to search using normal joins.
- Defer tag text keyword matching to a follow-up Phase 7.x search polish pass.

---

# 7. Persistence API Plan

Add `Sources/Persistence/CurationQueries.swift`.

Candidate persisted DTOs:

```swift
public struct PersistedTag: Sendable, Equatable {
    public let id: TagID
    public let name: String
    public let normalizedName: String
    public let source: TagSource
    public let createdAt: Date
    public let updatedAt: Date
    public let mediaItemCount: Int?
}

public struct PersistedCollection: Sendable, Equatable {
    public let id: CollectionID
    public let name: String
    public let normalizedName: String
    public let description: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let mediaItemCount: Int?
}

public struct PersistedMediaItemCuration: Sendable, Equatable {
    public let mediaItemID: MediaItemID
    public let isFavorite: Bool
    public let tags: [PersistedTag]
    public let collections: [PersistedCollection]
}
```

Candidate store reads:

```swift
public func fetchTags() throws -> [PersistedTag]
public func fetchTags(mediaItemID: MediaItemID) throws -> [PersistedTag]
public func fetchTag(id: TagID) throws -> PersistedTag?
public func fetchTag(normalizedName: String) throws -> PersistedTag?

public func fetchCollections() throws -> [PersistedCollection]
public func fetchCollection(id: CollectionID) throws -> PersistedCollection?
public func fetchCollections(mediaItemID: MediaItemID) throws -> [PersistedCollection]

public func fetchMediaItemCuration(mediaItemID: MediaItemID) throws -> PersistedMediaItemCuration
public func fetchFavoriteMediaItemSummaries(limit: Int, offset: Int) throws -> [PersistedMediaItemSummary]
public func fetchMediaItemSummaries(tagID: TagID, limit: Int, offset: Int) throws -> [PersistedMediaItemSummary]
public func fetchMediaItemSummaries(collectionID: CollectionID, limit: Int, offset: Int) throws -> [PersistedMediaItemSummary]
```

Candidate store writes:

```swift
public func saveTag(_ tag: Tag) throws
public func deleteTag(id: TagID) throws
public func assignTag(tagID: TagID, to mediaItemID: MediaItemID, assignedAt: Date) throws
public func removeTag(tagID: TagID, from mediaItemID: MediaItemID) throws

public func setFavorite(mediaItemID: MediaItemID, isFavorite: Bool, updatedAt: Date) throws

public func saveCollection(_ collection: MediaCollection) throws
public func deleteCollection(id: CollectionID) throws
public func addMediaItem(_ mediaItemID: MediaItemID, toCollection collectionID: CollectionID, addedAt: Date) throws
public func removeMediaItem(_ mediaItemID: MediaItemID, fromCollection collectionID: CollectionID) throws
```

API design rules:

- Keep these APIs in Persistence names, not UI names.
- Use typed Domain IDs.
- Normalize names before save either in Domain initializers or Application use
  cases, and test the chosen ownership.
- Mutations that touch multiple tables must be transactional.
- Delete tag should remove `media_item_tags` rows and then the tag.
- Delete collection should remove `collection_items` rows and then the
  collection.
- Save tag and collection should preserve IDs and update timestamps
  predictably.
- Duplicate normalized names should produce a deterministic Persistence error
  or Application-level validation error.

API coverage conclusion:

- Existing APIs provide no coverage for curation reads or writes.
- Existing summary SQL helpers provide partial coverage for media row mapping.
- Reuse `mediaItemSummarySQL`, `mapMediaItemSummary`, and existing summary CTEs
  for favorites, tags, and collection browse results when possible.
- Add new narrow APIs only for curation-specific tables and filters.

---

# 8. Application API Plan

Add `Sources/Application/LibraryCuration.swift`.

Application models:

```swift
public struct LibraryTagSummary: Identifiable, Sendable, Equatable {
    public let id: TagID
    public let name: String
    public let sourceLabel: String
    public let mediaItemCountLabel: String?
}

public struct LibraryCollectionSummary: Identifiable, Sendable, Equatable {
    public let id: CollectionID
    public let name: String
    public let description: String?
    public let mediaItemCountLabel: String?
}

public struct LibraryItemCurationDetail: Sendable, Equatable {
    public let isFavorite: Bool
    public let tags: [LibraryTagSummary]
    public let collections: [LibraryCollectionSummary]
}

public struct LibraryCurationSnapshot: Sendable, Equatable {
    public let tags: [LibraryTagSummary]
    public let collections: [LibraryCollectionSummary]
}
```

Application protocols:

```swift
public protocol LibraryCurationBrowsing: Sendable {
    func fetchCurationSnapshot() async throws -> LibraryCurationSnapshot
    func fetchItemCuration(mediaItemID: MediaItemID) async throws -> LibraryItemCurationDetail
}

public protocol LibraryCurationHandling: Sendable {
    func createTag(name: String) async throws -> LibraryTagSummary
    func renameTag(tagID: TagID, name: String) async throws -> LibraryTagSummary
    func deleteTag(tagID: TagID) async throws
    func assignTag(tagID: TagID, mediaItemID: MediaItemID) async throws -> LibraryItemCurationDetail
    func removeTag(tagID: TagID, mediaItemID: MediaItemID) async throws -> LibraryItemCurationDetail

    func setFavorite(mediaItemID: MediaItemID, isFavorite: Bool) async throws -> LibraryItemCurationDetail

    func createCollection(name: String, description: String?) async throws -> LibraryCollectionSummary
    func renameCollection(collectionID: CollectionID, name: String, description: String?) async throws -> LibraryCollectionSummary
    func deleteCollection(collectionID: CollectionID) async throws
    func addToCollection(collectionID: CollectionID, mediaItemID: MediaItemID) async throws -> LibraryItemCurationDetail
    func removeFromCollection(collectionID: CollectionID, mediaItemID: MediaItemID) async throws -> LibraryItemCurationDetail
}
```

Store protocol:

```swift
public protocol ApplicationLibraryCurationStore: Sendable {
    // Use the narrow Persistence reads/writes listed in Section 7.
}
```

Use-case behavior:

- All curation mutations validate media item existence before writing.
- Name inputs are trimmed and normalized before Persistence writes.
- Empty names throw user-safe validation errors.
- Duplicate tag or collection names throw a user-safe conflict error.
- Assigning an already assigned tag should be idempotent.
- Removing a missing tag assignment should be a no-op.
- Setting favorite to its current value should be idempotent.
- Adding an existing collection membership should be idempotent.
- Removing a missing collection membership should be a no-op.
- After every mutation, return refreshed item curation detail where the action is
  item-scoped.

Extend existing Application models:

- Add `curation` to `LibraryItemDetailShell`.
- Consider adding compact curation fields to `LibraryItemSummary`:
  - `isFavorite: Bool`
  - `tagLabels: [String]` or `tagSummaryLabel: String?`
- Extend `LibraryBrowserSection`:
  - `.favorites`
  - `.collection(CollectionID)`
- Consider `.tag(TagID)` only if tag browsing is clearly useful and can be
  added without cluttering the sidebar.

Search extension:

- Add `favorite` and `tagID` filters to `LibrarySearchRequest` only if AppUI can
  expose them compactly.
- Keep relevance/FTS rank hidden inside Persistence/Application.
- Keep raw `TagID` and `CollectionID` out of display strings except where they
  are selection identifiers.

Composition root:

- Add curation browsing and handling values to `AppShellEnvironment`.
- Construct curation use cases in `CineMindAppEnvironmentFactory`.
- Keep unavailable state unnecessary because local Persistence-backed curation
  should always be available when the store is available.

---

# 9. AppUI Plan

AppUI should remain compact, operational, and consistent with the current
Liquid Glass V1 style.

## 9.1 Detail Surface

Add a curation card to `LibraryItemDetailView`:

- favorite toggle with a star icon
- assigned tag chips
- add tag control
- remove tag affordance on chips
- collection membership list or compact chips
- add to collection control
- create collection entry point if no suitable collection exists

UI constraints:

- Do not add instructional text describing how the feature works.
- Use icon buttons where commands are obvious.
- Use compact menus for choosing existing tags or collections.
- Use small inline text fields only for creating or renaming names.
- Keep detail layout stable and avoid nested cards.
- Do not let long tag or collection names overflow.
- Keep curation controls disabled or gracefully unavailable while no media item
  is loaded.

## 9.2 Browser Surface

Enhance library rows carefully:

- show a small favorite indicator where useful
- show one or two tag chips or a compact tag-count label only if it remains
  scannable
- preserve current table selection and detail loading behavior
- preserve Add Folder, Scan, search controls, and existing sections

Add Favorites browsing:

- sidebar row: `Favorites`
- selecting it loads favorite media summaries through Application
- empty state should be concise and not marketing-like

Add Collections browsing:

- sidebar group or list of user collections
- selecting a collection loads media summaries for that collection
- preserve `List(selection:)` identity and stable row tags
- avoid custom sidebar behavior that breaks selection

Tag browsing:

- Prefer search/filter integration over adding every tag to the sidebar in V1.
- Add tag sidebar rows only if the library remains manageable and selection
  mechanics remain simple.

## 9.3 Search Controls

Extend the existing Phase 6 search controls only if the added controls remain
compact:

- favorite filter: any/favorites only
- tag filter: optional menu of existing tags

Do not add:

- advanced query builder
- saved searches
- smart collections
- path search
- subtitle text search
- AI semantic toggle

## 9.4 State Refresh

After curation mutations:

- refresh the active detail curation state
- refresh browser rows if favorite/tag/collection indicators are visible
- refresh sidebar collection counts if shown
- preserve selected media item when possible
- preserve selected browser section when possible
- if a selected collection is deleted, navigate to `Library` or another safe
  default section

---

# 10. Implementation Sequence

## Phase 7.1 Plan and Schema Design

Goal:

- Confirm this plan against current source.
- Choose the final favorites model.
- Decide whether tag text search is included in v6 or deferred to 7.x.

Tasks:

1. Re-run discovery commands.
2. Confirm no existing curation APIs appeared since this plan.
3. Finalize table names and uniqueness constraints.
4. Finalize `LibraryBrowserSection` expansion strategy.
5. Decide FTS tag integration path.

Exit criteria:

- Final v6 migration shape is agreed.
- New Persistence API required: yes.
- Migrations.swift change is approved for implementation.

## Phase 7.2 Domain and Migration

Goal:

- Add Domain curation models and schema v6.

Tasks:

1. Add `TagID` and `CollectionID` aliases.
2. Add `TagSource`, `Tag`, `MediaItemTag`, `MediaCollection`,
   `CollectionItem`, and optionally `FavoriteMediaItem`.
3. Add curation validation errors.
4. Add `version6Statements` to `Migrations.swift`.
5. Update migrator to apply version 6.
6. Update migration diagnostics expected table names.
7. Add migration tests for fresh schema, v5 upgrade, idempotency, and rollback.

Tests:

```sh
swift test --filter DomainModelTests
swift test --filter PersistenceRepositoryTests
```

Acceptance:

- Fresh database includes curation tables.
- v5 database upgrades through v6 without data loss.
- Applied migration versions are `[1, 2, 3, 4, 5, 6]`.
- Migration failure rolls back partial curation schema.

## Phase 7.3 Persistence Queries

Goal:

- Add narrow curation read/write APIs and reuse existing media summary query
  helpers.

Tasks:

1. Add `CurationQueries.swift`.
2. Implement tag CRUD.
3. Implement tag assignment add/remove.
4. Implement favorite set/unset and favorite summary browse.
5. Implement collection CRUD.
6. Implement collection membership add/remove and collection summary browse.
7. Implement item curation fetch for detail.
8. Add tag/favorite filters to search if accepted in Phase 7.1.
9. Add FTS tag indexing if accepted in Phase 7.1.

Tests:

```sh
swift test --filter PersistenceRepositoryTests
```

Acceptance:

- Duplicate normalized tag names are rejected.
- Duplicate normalized collection names are rejected.
- Assignments are unique and idempotent where the Application contract requires.
- Deleting a tag removes assignments and preserves media.
- Deleting a collection removes memberships and preserves media.
- Favorites can be toggled and browsed.
- Collection browse reuses existing media summary semantics.
- Search filters and tag FTS behavior, if included, are covered.

## Phase 7.4 Application Use Cases

Goal:

- Expose curation through Application DTOs and protocols.

Tasks:

1. Add `LibraryCuration.swift`.
2. Add `LibraryCurationBrowsing`.
3. Add `LibraryCurationHandling`.
4. Add `ApplicationLibraryCurationStore`.
5. Map Persistence curation DTOs into UI-safe Application models.
6. Extend `LibraryItemDetailShell` with `curation`.
7. Extend `LibraryItemSummary` only as needed for compact browser indicators.
8. Extend `LibraryBrowserSection` and `LibraryMediaSummaryUseCase` for
   favorites and collections.
9. Extend `LibraryMediaSearchUseCase` for favorite/tag filters only if accepted.

Tests:

```sh
swift test --filter LibraryCuration
swift test --filter LibraryItemDetailTests
swift test --filter LibraryBrowserSummaryTests
swift test --filter LibrarySearchTests
```

Acceptance:

- AppUI-facing models contain no Persistence types.
- Mutations normalize and validate names.
- Duplicate names produce user-safe errors.
- Idempotent operations stay idempotent.
- Detail fetch includes current favorite, tags, and collection membership.
- Favorite and collection sections return media summaries through existing
  summary semantics.

## Phase 7.5 AppUI Wiring

Goal:

- Add usable curation controls without a broad redesign.

Tasks:

1. Add curation dependencies to `AppShellEnvironment`.
2. Construct curation use cases in `CineMindAppEnvironmentFactory`.
3. Add curation state and action methods to `LibraryItemDetailViewModel`.
4. Add curation card to `LibraryItemDetailView`.
5. Add favorite row indicator and optional tag labels to browser rows only if
   they stay readable.
6. Add Favorites sidebar section.
7. Add Collections sidebar rows or group.
8. Add favorite/tag search filters only if compact.
9. Preserve existing selection and detail load behavior.

Tests/builds:

```sh
swift build --target AppUI
swift build --target CineMindApp
```

Acceptance:

- AppUI builds with no Persistence import.
- Favorite toggle updates detail and browser state.
- Tag assignment/removal updates detail and search/filter state.
- Collection membership updates detail and collection browsing.
- Deleted selected collection falls back to a safe section.
- Existing library, folder, scan, metadata, subtitle, and playback controls
  remain reachable.

## Phase 7.6 Verification and Completion Report

Goal:

- Close the phase with automated evidence, boundary audit, and a durable report.

Tasks:

1. Run targeted tests.
2. Run AppUI and CineMindApp builds.
3. Run full test suite.
4. Run boundary greps.
5. Run optional manual app smoke against a disposable test library.
6. Write `docs/phase-7-completion-report.md`.
7. Link the completion report if a roadmap doc needs it.

Commands:

```sh
git diff --check
swift test --filter DomainModelTests
swift test --filter PersistenceRepositoryTests
swift test --filter LibraryCuration
swift test --filter LibraryItemDetailTests
swift test --filter LibraryBrowserSummaryTests
swift test --filter LibrarySearchTests
swift build --target AppUI
swift build --target CineMindApp
swift test
rg -n "^import (Persistence|Metadata|Subtitle|Playback|PlaybackAVFoundation|AVFoundation|AVKit|AppKit|AI)" Sources/AppUI || true
rg -n "SQLite|CineMindStore|MetadataProvider|SubtitleSearchProviding|AVPlayer|AVFoundation|Embedding|AI" Sources/AppUI || true
rg -n "import AppUI" Sources/Persistence Sources/Application Sources/Domain Tests || true
rg -n "Persistence\\." Sources/AppUI Tests || true
rg -n "AppUI\\." Sources/Persistence Sources/Application Sources/Domain Tests || true
```

Manual smoke, using an approved disposable library:

- Launch app.
- Create a tag from a media detail page.
- Assign and remove the tag.
- Favorite and unfavorite a media item.
- Browse Favorites.
- Create a collection.
- Add the media item to the collection.
- Browse the collection.
- Delete the collection and verify navigation recovers.
- Search or filter by tag/favorite if those controls are included.

---

# 11. Migration Test Plan

Required migration tests:

- Fresh database creates:
  - `tags`
  - `media_item_tags`
  - `favorite_media_items`
  - `collections`
  - `collection_items`
- Fresh database records applied versions `[1, 2, 3, 4, 5, 6]`.
- Reopening a migrated database is idempotent.
- v5 database upgrades to v6 without losing:
  - libraries
  - library folders
  - media items
  - media files
  - playback history
  - metadata
  - poster assets
  - subtitle assets
  - search FTS functionality
- Partial v6 failure rolls back curation schema and does not record version 6.
- Read-only open of an already migrated v6 database still supports curation
  reads if existing read-only behavior is available for the store.

If FTS tag integration is included:

- Existing media remains searchable after v6 FTS rebuild.
- Assigning a tag makes the media searchable by that tag.
- Renaming a tag updates search results.
- Removing a tag assignment removes the tag from search results.
- Deleting a tag removes it from search results.
- Metadata and media item updates continue updating FTS rows as in Phase 6.

---

# 12. Acceptance Criteria

Phase 7 is complete only if:

- Manual tags can be created, renamed, deleted, assigned, and removed.
- Tag names are normalized and duplicates are handled predictably.
- Favorite state can be toggled and persists across store reopen.
- Favorite media can be browsed from AppUI.
- Collections can be created, renamed, deleted, and used to group media items.
- Collection membership persists across store reopen.
- Collection media can be browsed from AppUI.
- Detail view shows current favorite, tag, and collection state.
- AppUI does not import Persistence, concrete provider modules, playback
  backend modules, AppKit, AVFoundation, or AI.
- Existing library browse, search, folder, scan, metadata, subtitle, and
  playback workflows are not regressed.
- Migration v6 is covered by tests.
- Targeted tests pass.
- `swift build --target AppUI` passes.
- `swift build --target CineMindApp` passes.
- Full `swift test` passes.
- Boundary greps pass.
- Completion report is written.

If tag text FTS is included:

- Search can find media by assigned tag names.
- Tag assignment, rename, removal, and deletion keep FTS rows fresh.

If tag text FTS is deferred:

- The completion report must explicitly record the deferment and confirm that
  favorite/tag filter behavior works.

---

# 13. Stop Conditions

Stop and report before continuing if:

- Current source already contains a different curation implementation.
- Existing API coverage turns out to be sufficient and new APIs are not needed.
- Schema v6 cannot be added without broad migration rewrites.
- FTS tag indexing requires fragile or broad trigger logic.
- Curation table relationships require changing scanner or media identity
  semantics.
- AppUI needs a direct Persistence import to complete the feature.
- Sidebar dynamic collection rows break selection behavior.
- `LibraryItemDetailView` changes become a broad refactor rather than a focused
  curation surface.
- Tests reveal existing Phase 6 search/migration behavior is failing before
  Phase 7 changes.
- Manual smoke would mutate the user's real Application Support database without
  explicit approval.

---

# 14. Risks

Migration risk:

- Phase 7 is a true schema addition. Keep v6 statements small and test upgrade,
  idempotency, rollback, and data preservation.

FTS freshness risk:

- Tags are user-editable and can be renamed. If tag names are indexed in FTS,
  tag and assignment triggers must refresh affected media rows reliably.

API duplication risk:

- Existing media summary and search queries already compute availability,
  metadata status, and latest playback. Reuse those helpers for favorite and
  collection browsing instead of creating divergent row mapping.

Boundary risk:

- AppUI will need richer curation state, but it must consume Application DTOs
  only. Keep Persistence DTOs and SQL out of AppUI.

UI complexity risk:

- Tags and collections can sprawl quickly. Keep V1 controls compact: detail card,
  favorites section, collection browsing, and optional search filters.

State synchronization risk:

- Mutations affect detail, browser, sidebar, and search results. Refresh state
  narrowly after each mutation and preserve selection where possible.

Future AI risk:

- The tag model includes `ai_suggested`, but Phase 7 must not build AI provider
  behavior. AI-suggested tags must not be silently applied in future phases.

Data ownership risk:

- Metadata refresh must not overwrite tags, favorites, or collections.
  Curation is user-owned data.

Manual smoke risk:

- Real app smoke can migrate or mutate the user's database. Use a disposable
  test library unless the user explicitly approves otherwise.

---

# 15. Completion Report Requirement

When implementation is complete, write:

```text
docs/phase-7-completion-report.md
```

The report must include:

- implemented scope
- migration summary
- Persistence API summary
- Application API summary
- AppUI summary
- FTS/search integration decision
- boundary audit
- verification commands and results
- manual smoke status
- known deferred work
- completion verdict

The report must state:

```text
Migrations.swift changed: yes
New Persistence API required: yes
```

---

# 16. Recommended Next Step

Start Phase 7 with a short implementation preflight:

1. Re-run discovery commands from Section 5.
2. Confirm the favorites model: dedicated `favorite_media_items` table.
3. Decide whether tag text FTS belongs in initial Phase 7 or a follow-up 7.x
   pass.
4. Implement Phase 7.2 first: Domain models and schema v6.
5. Stop after targeted Domain/Persistence tests before moving to Application and
   AppUI.
