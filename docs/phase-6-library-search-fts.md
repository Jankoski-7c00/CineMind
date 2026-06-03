# Phase 6 Library Search and FTS

Canonical file: `docs/phase-6-library-search-fts.md`

Phase 6 implements local keyword search for the media library. This closes the
MVP requirement that keyword search works without AI and prepares the app for
later semantic search by establishing a clean Application-facing search
contract.

This phase is not an AI phase. Search must work offline, without metadata or
subtitle providers, and without changing playback behavior.

---

# 1. Current Audit

Current repository status before this plan:

- Phase 5 local/embedded subtitle support and Phase 5.2 provider-neutral online
  subtitle search/download plumbing are implemented.
- Recent metadata work improved TMDB candidate search/select behavior, but that
  is provider metadata search, not library search.
- `LibraryMediaSummaryUseCase` currently supports fixed browser sections:
  Library, Movies, TV Episodes, Recently Played, and Needs Metadata.
- `LibraryBrowserViewModel` loads a fixed first page for the selected section.
- `LibraryBrowserView` intentionally did not add search UI during Phase 4.8.
- Current SQLite schema includes media, files, playback history, metadata,
  poster assets, and subtitle assets.
- Current SQLite schema does not include an FTS virtual table or a media-search
  query surface.
- Current AppUI forbidden import checks have stayed clean in prior phases and
  must remain clean.

Current product/architecture signal:

- `docs/product-scope.md` lists keyword search, filters, and sorting as MVP
  search requirements.
- `docs/architecture.md` states that MVP keyword search uses SQLite FTS5.
- `docs/architecture.md` requires keyword search to work without AI.
- Semantic search is explicitly an AI feature and should come later.

Migration decision:

- Migration required: yes, if Phase 6 implements real SQLite FTS5 as the MVP
  contract requires.
- Migration required: no only for a temporary `LIKE`-based spike, which is not
  the recommended Phase 6 implementation.

New Persistence API required: yes, after current discovery.

Reason:

- Existing summary queries cover fixed browser sections and simple media-type
  filtering.
- Existing APIs do not expose keyword search, match ranking, search filters, or
  search-specific ordering.
- The new API should be narrow and return persisted search results or summaries,
  not UI view models.

Recommended next phase:

```text
Phase 6.1 Search Plan and Schema
Phase 6.2 Persistence Search Query
Phase 6.3 Application Search Use Case
Phase 6.4 AppUI Search Controls
Phase 6.5 Verification and Boundary Audit
```

---

# 2. Goal

Implement local media-library keyword search so a user can:

- type a query in the library browser
- search across media title, original title, series title, episode title,
  metadata title, metadata original title, metadata summary, and year
- narrow results by media type
- narrow results by availability
- sort results by relevance, title, recently added, recently played, or year
- open an existing media detail page from a search result

Search must:

- use SQLite FTS5 for keyword matching
- work without AI
- work without network
- preserve existing section browsing when no query/filter is active
- route AppUI through Application protocols and DTOs only
- keep existing playback, subtitle, metadata action, folder, and scan workflows
  intact

---

# 3. Non-Goals

Do not implement in Phase 6:

- semantic search
- embedding generation
- AI provider abstraction
- AI tag suggestion
- smart recommendations
- subtitle summarization
- manual tags
- favorites
- collections
- JSON export
- poster wall or grid browsing
- broad browser rewrite
- new playback controls
- new subtitle provider integration
- changes to TMDB matching behavior
- automatic metadata refresh after search
- server, plugin, sync, or background indexing daemon workflows

Do not add AppUI dependencies on:

- `Persistence`
- `Metadata`
- `Subtitle`
- `Playback`
- `PlaybackAVFoundation`
- `AVFoundation`
- `AVKit`
- `AppKit`
- SQLite-specific types

---

# 4. Scope

Inspect before code:

- `docs/product-scope.md`
- `docs/architecture.md`
- `docs/phase-4-2-library-browser.md`
- `docs/phase-4-8-liquid-glass-ui-redesign.md`
- `Sources/Persistence/Migrations.swift`
- `Sources/Persistence/LibraryMediaSummaryQueries.swift`
- `Sources/Persistence/MediaItemDetailQueries.swift`
- `Sources/Persistence/CineMindStore.swift`
- `Sources/Application/LibraryBrowserSummary.swift`
- `Sources/AppUI/LibraryBrowserViewModel.swift`
- `Sources/AppUI/LibraryBrowserView.swift`
- `Sources/AppUI/SidebarView.swift`
- `Sources/CineMindApp/CineMindAppEnvironmentFactory.swift`
- `Tests/PersistenceTests/PersistenceRepositoryTests.swift`
- `Tests/ApplicationTests/LibraryBrowserSummaryTests.swift`

Likely implementation files:

- `Sources/Persistence/Migrations.swift`
- `Sources/Persistence/LibrarySearchQueries.swift` (new)
- `Sources/Application/LibrarySearch.swift` (new) or
  `Sources/Application/LibraryBrowserSummary.swift`
- `Sources/AppUI/LibraryBrowserViewModel.swift`
- `Sources/AppUI/LibraryBrowserView.swift`
- `Sources/AppUI/AppShellEnvironment.swift`
- `Sources/CineMindApp/CineMindAppEnvironmentFactory.swift`
- `Tests/PersistenceTests/PersistenceRepositoryTests.swift`
- `Tests/ApplicationTests/LibraryBrowserSummaryTests.swift` or a new focused
  search test file

Modify only if discovery proves necessary:

- `Sources/Persistence/CineMindStore.swift`
- `Sources/Persistence/MediaItemDetailQueries.swift`
- `Sources/Application/LibraryItemDetail.swift`
- `Sources/AppUI/SidebarView.swift`
- `Package.swift`

Forbidden unless explicitly approved in a later phase:

- `Sources/AI/**`
- new AI targets
- new third-party dependencies
- playback backend files
- subtitle provider files
- broad AppUI redesign outside the browser search surface

---

# 5. Discovery Commands

Run before implementation:

```sh
git status --short
git diff --stat
rg -n "FTS|fts5|MATCH|bm25|MediaSearch|SearchQuery|filter|sort" Sources Tests docs
rg -n "fetchMediaItemSummaries|LibraryMediaSummary|LibraryBrowser" Sources/Persistence Sources/Application Sources/AppUI Tests
rg -n "CREATE TABLE|CREATE VIRTUAL TABLE|CREATE INDEX|Migration|schema_migrations|user_version" Sources/Persistence Tests/PersistenceTests
rg -n "metadata_items|media_items|playback_history|library_folders|media_files" Sources/Persistence
rg -n "^import (Persistence|Metadata|Subtitle|Playback|PlaybackAVFoundation|AVFoundation|AVKit|AppKit)" Sources/AppUI || true
swift test --list-tests
```

Questions to answer before code:

- Which fields should be indexed in the first FTS table?
- Should the FTS table be contentless or externally synchronized?
- Should metadata updates immediately refresh search index content?
- Should scanner writes immediately refresh search index content?
- Does the existing summary query provide enough fields for result rows?
- Can search results reuse `LibraryItemSummary`, or do they need
  `LibrarySearchResult` with match reason/rank?
- Should empty query plus active filters use the search query path or existing
  section browsing?
- What search/filter/sort combinations are safe for the first implementation?

---

# 6. Data Model Plan

Add schema v5 for FTS-backed media search.

Recommended FTS table:

```sql
CREATE VIRTUAL TABLE media_search_fts USING fts5(
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
```

Recommended support:

- Backfill existing media items during v5 migration.
- Keep one FTS row per `media_items.id`.
- Use existing media and metadata fields only.
- Do not index file paths in Phase 6.1 unless explicitly approved; path search
  can expose local directory structure too prominently in the UI.
- Do not index subtitle text in Phase 6; subtitle summarization/search belongs
  to later AI/Beta work.

Index maintenance decision point:

- If triggers are simple and reliable, use SQLite triggers for media and
  metadata insert/update/delete synchronization.
- If triggers become too complex because metadata writes are already
  Application-orchestrated, use explicit store helper calls in the existing
  write paths.
- Stop if FTS maintenance would require broad repository redesign.

Migration tests must cover:

- fresh database includes schema v5
- database upgraded from v4 includes `media_search_fts`
- existing media and metadata rows are searchable after upgrade
- migration is idempotent through `schema_migrations`
- read-only store can open and search an upgraded database

---

# 7. Persistence API Plan

Add the narrowest necessary query surface.

Candidate types:

```swift
public struct PersistedMediaSearchQuery: Sendable, Equatable {
    public var text: String
    public var mediaType: MediaType?
    public var availability: PersistedMediaSearchAvailability?
    public var sort: PersistedMediaSearchSort
    public var limit: Int
    public var offset: Int
}

public enum PersistedMediaSearchAvailability: Sendable, Equatable {
    case any
    case available
    case unavailable
}

public enum PersistedMediaSearchSort: Sendable, Equatable {
    case relevance
    case title
    case recentlyAdded
    case recentlyPlayed
    case year
}

public struct PersistedMediaSearchResult: Sendable, Equatable {
    public let summary: PersistedMediaItemSummary
    public let rank: Double?
    public let matchReason: String?
}
```

Candidate store method:

```swift
public func searchMediaItems(
    query: PersistedMediaSearchQuery
) throws -> [PersistedMediaSearchResult]
```

Rules:

- Use typed `MediaItemID` through existing Domain aliases.
- Keep UI concepts out of Persistence names.
- Reuse the existing summary join shape where possible.
- Avoid duplicating all summary SQL if a helper can compose safely.
- Normalize negative offsets and non-positive limits consistently with existing
  summary queries.
- Do not expose raw SQLite rank expressions to AppUI.

---

# 8. Application Plan

Add an Application-facing search contract.

Candidate types:

```swift
public struct LibrarySearchRequest: Sendable, Equatable {
    public var text: String
    public var mediaType: LibrarySearchMediaTypeFilter
    public var availability: LibrarySearchAvailabilityFilter
    public var sort: LibrarySearchSort
    public var page: LibraryBrowserPage
}

public enum LibrarySearchMediaTypeFilter: Sendable, Equatable {
    case all
    case movies
    case tvEpisodes
}

public enum LibrarySearchAvailabilityFilter: Sendable, Equatable {
    case any
    case available
    case unavailable
}

public enum LibrarySearchSort: Sendable, Equatable {
    case relevance
    case title
    case recentlyAdded
    case recentlyPlayed
    case year
}

public struct LibrarySearchSnapshot: Sendable, Equatable {
    public let request: LibrarySearchRequest
    public let items: [LibraryItemSummary]
    public let resultDescription: String
}
```

Candidate protocol:

```swift
public protocol LibraryMediaSearching: Sendable {
    func search(_ request: LibrarySearchRequest) async throws -> LibrarySearchSnapshot
}
```

Rules:

- Map Persistence result types into Application DTOs.
- Keep AppUI unaware of FTS, SQLite, and rank implementation.
- Prefer `LibraryItemSummary` reuse unless match reason is needed for the first
  UI.
- Keep existing `LibraryMediaSummaryBrowsing` behavior unchanged for ordinary
  section browsing.
- If search and browsing need to share paging state, add small Application
  helpers instead of a broad browser rewrite.

---

# 9. AppUI Plan

Add browser search controls without rewriting the browser.

Expected UI:

- Search field in the library browser header.
- Media type filter using a segmented control or compact picker:
  All, Movies, TV.
- Availability filter using a compact menu:
  Any, Available, Missing.
- Sort menu:
  Relevance, Title, Recently Added, Recently Played, Year.
- Search result loading state.
- Empty search result state that distinguishes no library content from no
  matches.
- Existing Add Folder and Scan controls remain available.

Behavior:

- Empty search text with default filters uses the existing selected section
  browse path.
- Non-empty search text uses the search use case.
- Changing search text resets selected item and reloads results.
- Scanning reloads the active search results if search is active.
- Selecting a search result opens the same detail surface as browsing.
- Search errors do not clear existing non-search browser state unless the active
  view is search results.

Boundary:

- AppUI depends on `Application`, `Domain`, `Shared`, and `SwiftUI` only.
- AppUI must not import Persistence or reference SQLite/FTS/provider concepts.

---

# 10. Implementation Tasks

## Phase 6.1 Search Plan and Schema

- Confirm current docs and code state.
- Add schema v5 in `Migrations.swift`.
- Create FTS table and backfill from `media_items` and `metadata_items`.
- Add migration tests for fresh DB, v4 upgrade, idempotency, and read-only open.
- Stop if FTS5 is unavailable in the system SQLite used by tests.

## Phase 6.2 Persistence Search Query

- Add a narrow Persistence search query.
- Reuse summary joins for result rows.
- Implement query normalization and limit/offset behavior.
- Add tests for title, series title, episode title, metadata title, summary, and
  year matches.
- Add tests for media type, availability, and sort behavior.

## Phase 6.3 Application Search Use Case

- Add Application request/filter/sort DTOs.
- Add `LibraryMediaSearching`.
- Map Persistence search results to `LibraryItemSummary` or a small search
  snapshot.
- Add Application tests for request mapping, page normalization, empty query
  policy, filters, sorting, and store error propagation.

## Phase 6.4 AppUI Search Controls

- Extend `AppShellEnvironment` with a search service.
- Wire composition root in `CineMindApp`.
- Add search state to `LibraryBrowserViewModel`.
- Add header search field and filter/sort controls in `LibraryBrowserView`.
- Preserve existing section browsing and folder browsing.
- Build `AppUI` after each meaningful UI pass.

## Phase 6.5 Verification and Boundary Audit

- Run targeted Persistence/Application tests.
- Build AppUI and CineMindApp.
- Run full `swift test`.
- Run AppUI forbidden import greps.
- If feasible, run a manual app smoke with a small test library:
  scan, search by title, search by metadata summary, clear search, and open
  detail from results.

---

# 11. Test Strategy

Targeted:

```sh
swift test --filter PersistenceRepositoryTests
swift test --filter LibraryBrowserSummaryTests
```

If a new test file is added:

```sh
swift test --filter LibrarySearch
```

Build:

```sh
swift build --target AppUI
swift build --target CineMindApp
```

Full:

```sh
swift test
```

Boundary:

```sh
rg -n "^import (Persistence|Metadata|Subtitle|Playback|PlaybackAVFoundation|AVFoundation|AVKit|AppKit)" Sources/AppUI || true
rg -n "SQLite|FTS|CineMindStore|MetadataProvider|SubtitleSearchProviding|AVPlayer|AVFoundation" Sources/AppUI || true
git diff -- Sources/Persistence/Migrations.swift
```

Expected boundary result:

- no forbidden AppUI import or infrastructure-reference matches

Manual smoke:

- Launch app with an existing local test library.
- Search by scanner-derived movie title.
- Search by TV series title.
- Search by metadata title or summary after metadata exists.
- Apply Movies and TV filters.
- Sort by title and recently played.
- Clear search and verify existing section browsing returns.
- Select a result and verify detail loads.
- Run scan and verify active search results refresh without clearing unrelated
  state.

---

# 12. Acceptance Criteria

Phase 6 is complete only if:

- SQLite schema v5 adds a working FTS5 media search surface.
- Existing v4 databases upgrade without data loss.
- Existing media and metadata rows are searchable after migration.
- New or updated media/metadata writes keep the search index in sync.
- Search returns deterministic results for title, series title, episode title,
  metadata title, metadata original title, metadata summary, and year.
- Filters cover at least media type and availability.
- Sort covers at least relevance, title, recently played, and year.
- Empty query with default filters preserves existing section browsing behavior.
- AppUI search controls are usable from the library browser header.
- Search result selection opens the existing detail view.
- Local browsing, folder add, scan, metadata actions, subtitles, and playback are
  not regressed.
- AppUI boundary remains clean.
- Targeted tests, AppUI build, CineMindApp build, full `swift test`, and
  boundary greps pass.

---

# 13. Stop Conditions

Stop and report before continuing if:

- System SQLite in the supported build/test environment does not provide FTS5.
- A migration cannot safely backfill existing v4 data.
- Search index maintenance requires broad rewrites of scanner or metadata
  persistence.
- AppUI needs Persistence or SQLite imports to complete the feature.
- Existing summary queries cannot be reused without large duplication and no
  narrow query shape is obvious.
- Product direction requires tags/favorites/collections in the same phase.
- Product direction requires semantic search or AI before keyword search.
- Tests reveal existing library browsing or migration behavior is already
  failing before Phase 6 changes.

---

# 14. Risks

Migration risk:

- FTS5 is a true schema addition. Migration tests must cover v4 upgrade,
  backfill, idempotency, and read-only open.

Index freshness risk:

- Media and metadata writes happen across scanner and metadata use cases. Search
  index maintenance must stay close to Persistence write paths or explicit store
  helpers, not AppUI.

API duplication risk:

- Existing summary queries already compute availability, metadata status, and
  latest playback. Search should reuse that shape instead of creating a second
  divergent browser summary model.

Boundary risk:

- Search UI may be tempted to know about FTS or SQLite rank. Keep those details
  inside Persistence/Application mapping.

UX risk:

- Browser already has Add Folder, Scan, sections, table selection, and detail
  loading. Search controls should be compact and predictable, not a broad UI
  redesign.

Performance risk:

- Relevance sorting and summary joins can become expensive on large libraries.
  Keep the first implementation paged and measure before adding broader
  optimization.

Privacy risk:

- Avoid path search in Phase 6 so search results do not expose full local/NAS
  path text as primary search content.

---

# 15. Completion Report Requirement

When Phase 6 implementation is complete, add either:

- a completion section to this document, or
- a separate `docs/phase-6-completion-report.md`

The report should include:

- implemented scope
- migration summary
- Persistence API summary
- AppUI boundary audit
- test/build commands and results
- manual smoke result, if run
- known deferred work
