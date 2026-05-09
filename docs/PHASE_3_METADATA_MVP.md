# Phase 3 Metadata MVP

Canonical file: `docs/PHASE_3_METADATA_MVP.md`

This document defines Phase 3 of CineMind: a narrow metadata MVP using TMDB as the only provider.

Phase 3 is constrained by:

- `CLAUDE.md`
- `docs/PRODUCT_SCOPE.md`
- `docs/ARCHITECTURE.md`
- `docs/PHASE_1_LIBRARY_CORE.md`
- `docs/PHASE_1_COMPLETION_REPORT.md`
- `docs/phase_2_playback_mvp_document.md`
- `docs/PHASE_2_COMPLETION_REPORT.md`

Phase 3 builds on the completed local library, scanner, persistence, application, and playback foundations.

---

# 1. Phase 3 Scope

## Goal

Build the minimal metadata enrichment pipeline:

```text
Persisted MediaItem
  -> Application requests metadata search or refresh
  -> Metadata provider queries TMDB
  -> Application applies match and override rules
  -> Persistence stores metadata records, source records, external IDs, and poster assets
  -> poster cache stores image files outside SQLite
  -> shell can inspect and manually validate results
```

This phase is focused on:

- TMDB-only metadata lookup.
- Basic movie metadata.
- Shallow episode metadata.
- Poster asset discovery and local cache.
- Manual match and rematch.
- Manual metadata override preservation.
- Durable metadata source records.
- Mocked HTTP tests.
- Debug/manual validation through a shell target.

## Included

- `Metadata` module.
- TMDB provider abstraction and implementation.
- Application metadata use cases.
- SQLite migration v3.
- Metadata-specific persistence tables.
- Metadata source records.
- External ID records.
- Poster asset records.
- Poster cache strategy.
- Automatic match for high-confidence results.
- Manual match and manual rematch.
- Manual title, summary, and language overrides.
- Refresh behavior for matched and unmatched items.
- Mocked HTTP tests.
- Debug shell commands for search, match, refresh, and inspection.

## Explicitly Excluded

Do not implement:

- AI.
- Subtitles.
- Recommendations.
- Multiple metadata providers.
- FTS or search UI.
- Cast/person deep model.
- Media renaming.
- NFO import/export.
- Polished UI.
- Server architecture.
- Local HTTP API.
- Plugin system.
- Real-time filesystem watcher.
- Season model.
- Alternate episode ordering.
- Episode groups.
- Cast or crew import.

## Success Criteria

- Existing Phase 1 and Phase 2 behavior remains intact.
- A v1 or v2 database upgrades to v3 without losing library, scanner, media file, or playback data.
- A scanned movie can be searched, manually matched, refreshed, and assigned a cached poster.
- A scanned episode can receive shallow TMDB episode metadata and a series poster.
- Manual match locks prevent automatic rematching.
- Manual field override locks prevent refresh from overwriting user-edited title, summary, and language values.
- Tests use mocked HTTP and do not call live TMDB.

---

# 2. Target / Module Changes

## New Targets

```text
Sources/
  Metadata/
  CineMindMetadataShell/

Tests/
  MetadataTests/
```

## Package Changes

Add:

- `Metadata` library product.
- `Metadata` target depending on `Domain` and `Shared`.
- `MetadataTests` test target depending on `Metadata` and `Domain`.
- `CineMindMetadataShell` executable target depending on `Application`, `Persistence`, `Metadata`, and `Shared`.

Update:

- `Application` target depends on `Metadata`.

Do not add third-party dependencies in Phase 3 unless explicitly approved.

## Module Boundaries

### Domain

Domain owns pure metadata value types and validation only.

Allowed:

- Metadata IDs and enum definitions.
- Provider name enum limited to TMDB for MVP.
- Metadata match source enum.
- Poster asset selection source enum.
- Metadata source record model.
- Metadata item model.
- Metadata external ID model.
- Poster asset model.

Forbidden:

- TMDB response parsing.
- HTTP requests.
- Image URL construction from TMDB configuration.
- SQLite queries.
- File IO for poster cache.
- SwiftUI or AppKit.

### Metadata

Metadata owns provider-facing behavior.

Responsibilities:

- Provider abstraction.
- TMDB provider implementation.
- TMDB request construction.
- TMDB compact response mapping.
- TMDB error mapping.
- Metadata candidate ranking.
- Poster remote image representation.
- Poster cache helper.
- HTTP abstraction for mocked tests.

Must not contain:

- SQLite code.
- Application transaction policy.
- SwiftUI or AppKit.
- Playback logic.
- AI logic.

### Application

Application owns orchestration.

Responsibilities:

- Search use case.
- Automatic match use case.
- Manual match use case.
- Refresh item use case.
- Refresh library use case.
- Manual metadata override use cases.
- Poster selection use case.
- Transaction boundaries.
- Refresh and override preservation rules.
- Store protocols consumed by metadata use cases.

Application should depend on protocols where practical. Concrete persistence remains in `Persistence`, and concrete TMDB HTTP behavior remains in `Metadata`.

### Persistence

Persistence owns durable storage only.

Responsibilities:

- SQLite migration v3.
- Repository methods for metadata-specific records.
- Repository tests.
- Transaction support.

Must not contain:

- TMDB HTTP calls.
- TMDB response parsing.
- Poster image downloading.
- UI formatting.

### CineMindMetadataShell

The shell is a debug/manual validation harness.

Responsibilities:

- Open an existing database.
- Search metadata candidates.
- Apply manual matches.
- Run refreshes.
- List metadata and poster state.
- Use environment configuration for TMDB token and language.

The shell is not a polished UI.

## Provider Abstraction

Use a provider abstraction shaped around app-level metadata concepts, not TMDB response types:

```swift
protocol MetadataProvider {
    var providerName: MetadataProviderName { get }

    func search(query: MetadataSearchQuery) async throws -> [MetadataCandidate]
    func fetchDetails(identifier: MetadataProviderIdentifier) async throws -> MetadataDetails
    func fetchImages(identifier: MetadataProviderIdentifier) async throws -> [RemoteImage]
}
```

Supporting types:

- `MetadataSearchQuery`: media item ID, media type, title, year, series title, season number, episode number, language.
- `MetadataCandidate`: provider identifier, display title, original title, year or air date, overview preview, confidence inputs.
- `MetadataProviderIdentifier`:
  - movie: `movie:<tmdb_movie_id>`
  - episode: `tv:<tmdb_series_id>:s<season_number>:e<episode_number>`
- `MetadataDetails`: normalized title, original title, summary, language, release date or air date, compact external IDs, compact raw payload.
- `RemoteImage`: source, remote path, width, height, aspect ratio, preferred cache size.

The TMDB implementation is the only Phase 3 concrete provider.

## HTTP Abstraction

TMDB HTTP must be injectable:

```swift
protocol MetadataHTTPClient {
    func send(_ request: URLRequest) async throws -> MetadataHTTPResponse
}
```

Tests use a fake HTTP client with deterministic JSON fixtures. Unit tests must not depend on live TMDB or network availability.

---

# 3. Data Model Changes

## MediaItem Rule

Do not bloat `MediaItem` with provider-specific metadata.

`MediaItem` remains the local logical media identity created by scanning. Existing scanner identity fields remain valid:

- media type
- scanner-derived title
- normalized title
- scanner-derived year
- episode info from filename
- created and updated timestamps

Phase 3 must not add TMDB ID, IMDb ID, provider summary, provider language, provider original title, poster path, or manual metadata locks directly to `MediaItem`.

Provider metadata belongs in metadata-specific records and tables.

## MetadataItem

Represents the current displayable metadata for one media item.

Fields:

```text
id
media_item_id
title
original_title
summary
language
release_date
air_date
title_override_locked
summary_override_locked
language_override_locked
created_at
updated_at
```

Rules:

- At most one `MetadataItem` per `MediaItem`.
- `title`, `summary`, and `language` may come from TMDB or manual override.
- If a field override lock is set, refresh must not overwrite that field.
- Clearing a field override lock allows the next refresh to update that field.
- Missing metadata item means the library item has not yet been enriched.
- `release_date` is for movies.
- `air_date` is for episodes.

## MetadataExternalID

Represents durable provider and external IDs without storing them on `MediaItem`.

Fields:

```text
id
media_item_id
provider
external_id_type
external_id_value
created_at
updated_at
```

Allowed `provider` values in Phase 3:

```text
tmdb
```

Allowed `external_id_type` values in Phase 3:

```text
tmdb_movie
tmdb_tv_series
tmdb_episode
imdb
```

Rules:

- IDs are traceable without becoming core local identity.
- External ID values are unique per media item, provider, and ID type.
- Episode metadata may store both TMDB series ID and TMDB episode ID.
- IMDb ID is optional and stored only when returned by TMDB details or external IDs.

## MetadataSourceRecord

Tracks the current provider match for one media item.

Fields:

```text
id
media_item_id
provider
provider_id
provider_media_type
confidence
match_source
manual_match_locked
raw_payload_json
matched_at
refreshed_at
created_at
updated_at
```

Allowed `provider` values in Phase 3:

```text
tmdb
```

Allowed `provider_media_type` values:

```text
movie
episode
```

Allowed `match_source` values:

```text
automatic
manual
```

Provider ID format:

```text
movie:<tmdb_movie_id>
tv:<tmdb_series_id>:s<season_number>:e<episode_number>
```

Rules:

- At most one current TMDB source record per media item.
- Manual match sets `match_source = manual`, `confidence = 1.0`, and `manual_match_locked = true`.
- Automatic refresh must not replace a record with `manual_match_locked = true`.
- `raw_payload_json` stores only compact provider payloads.
- `raw_payload_json` must not store full TMDB responses, images arrays, cast, crew, or large unrelated data.

Compact payload examples:

Movie:

```json
{
  "id": 550,
  "title": "Fight Club",
  "original_title": "Fight Club",
  "overview": "...",
  "original_language": "en",
  "release_date": "1999-10-15",
  "imdb_id": "tt0137523",
  "poster_path": "/pB8BM7pdSp6B6Ih7QZ4DrQ3PmJK.jpg"
}
```

Episode:

```json
{
  "series_id": 95396,
  "series_name": "Severance",
  "season_number": 1,
  "episode_number": 2,
  "episode_id": 12345,
  "name": "Half Loop",
  "overview": "...",
  "air_date": "2022-02-18",
  "imdb_id": "tt0000000",
  "series_poster_path": "/example.jpg"
}
```

## PosterAsset

Represents poster assets and cache state.

Fields:

```text
id
media_item_id
asset_type
source
remote_path
width
height
preferred_cache_size
local_cache_path
cached_at
is_selected
selection_source
created_at
updated_at
```

Allowed `asset_type` values in Phase 3:

```text
poster
```

Allowed `source` values in Phase 3:

```text
tmdb
```

Allowed `selection_source` values:

```text
automatic
manual
```

Rules:

- Do not persist computed TMDB image URLs as source of truth.
- Persist `remote_path`, source, width, height, preferred cache size, cache path, and selection state.
- Derive full image URLs at runtime from TMDB configuration.
- Missing local cache file is a cache miss, not metadata corruption.
- Exactly one selected poster per media item and asset type when posters exist.
- Manual poster selection must not be replaced by automatic refresh.
- Phase 3 stores poster records only. Backdrop is deferred.

## Episode Metadata MVP

Episode metadata remains shallow.

Allowed:

- Episode title.
- Episode overview.
- Episode air date.
- TMDB episode ID.
- TMDB series ID.
- Series poster as the episode poster.

Forbidden:

- Season model.
- Season metadata table.
- Episode groups.
- Alternate ordering.
- Cast/person model.
- Crew model.
- Season posters.
- Episode stills as primary posters.

---

# 4. Persistence Changes

## Migration Version

Add SQLite migration v3.

Migration v3 must be forward-only and non-destructive.

It must not remove or rewrite Phase 1 or Phase 2 data.

## New Tables

### metadata_items

```text
id TEXT PRIMARY KEY
media_item_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE RESTRICT
title TEXT
original_title TEXT
summary TEXT
language TEXT
release_date TEXT
air_date TEXT
title_override_locked INTEGER NOT NULL DEFAULT 0 CHECK(title_override_locked IN (0, 1))
summary_override_locked INTEGER NOT NULL DEFAULT 0 CHECK(summary_override_locked IN (0, 1))
language_override_locked INTEGER NOT NULL DEFAULT 0 CHECK(language_override_locked IN (0, 1))
created_at REAL NOT NULL
updated_at REAL NOT NULL
UNIQUE(media_item_id)
```

Indexes:

```text
idx_metadata_items_media_item_id
```

### metadata_external_ids

```text
id TEXT PRIMARY KEY
media_item_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE RESTRICT
provider TEXT NOT NULL CHECK(provider IN ('tmdb'))
external_id_type TEXT NOT NULL CHECK(external_id_type IN ('tmdb_movie', 'tmdb_tv_series', 'tmdb_episode', 'imdb'))
external_id_value TEXT NOT NULL
created_at REAL NOT NULL
updated_at REAL NOT NULL
UNIQUE(media_item_id, provider, external_id_type)
```

Indexes:

```text
idx_metadata_external_ids_media_item_id
idx_metadata_external_ids_lookup
```

### metadata_source_records

```text
id TEXT PRIMARY KEY
media_item_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE RESTRICT
provider TEXT NOT NULL CHECK(provider IN ('tmdb'))
provider_id TEXT NOT NULL
provider_media_type TEXT NOT NULL CHECK(provider_media_type IN ('movie', 'episode'))
confidence REAL NOT NULL CHECK(confidence >= 0.0 AND confidence <= 1.0)
match_source TEXT NOT NULL CHECK(match_source IN ('automatic', 'manual'))
manual_match_locked INTEGER NOT NULL DEFAULT 0 CHECK(manual_match_locked IN (0, 1))
raw_payload_json TEXT
matched_at REAL NOT NULL
refreshed_at REAL
created_at REAL NOT NULL
updated_at REAL NOT NULL
UNIQUE(media_item_id, provider)
```

Indexes:

```text
idx_metadata_source_records_media_item_id
idx_metadata_source_records_provider_id
idx_metadata_source_records_refreshed_at
```

### poster_assets

```text
id TEXT PRIMARY KEY
media_item_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE RESTRICT
asset_type TEXT NOT NULL CHECK(asset_type IN ('poster'))
source TEXT NOT NULL CHECK(source IN ('tmdb'))
remote_path TEXT NOT NULL
width INTEGER
height INTEGER
preferred_cache_size TEXT NOT NULL
local_cache_path TEXT
cached_at REAL
is_selected INTEGER NOT NULL DEFAULT 0 CHECK(is_selected IN (0, 1))
selection_source TEXT NOT NULL CHECK(selection_source IN ('automatic', 'manual'))
created_at REAL NOT NULL
updated_at REAL NOT NULL
UNIQUE(media_item_id, asset_type, source, remote_path)
```

Indexes:

```text
idx_poster_assets_media_item_id
idx_poster_assets_remote_path
idx_poster_assets_selected_unique
```

`idx_poster_assets_selected_unique` should be a partial unique index on:

```text
(media_item_id, asset_type) WHERE is_selected = 1
```

## Repository Methods

Persistence should expose domain-oriented methods:

- `fetchMetadataItem(mediaItemID:)`
- `saveMetadataItem(_:)`
- `fetchMetadataExternalIDs(mediaItemID:)`
- `upsertMetadataExternalIDs(_:)`
- `fetchMetadataSourceRecord(mediaItemID:provider:)`
- `saveMetadataSourceRecord(_:)`
- `fetchPosterAssets(mediaItemID:)`
- `savePosterAsset(_:)`
- `selectPosterAsset(id:mediaItemID:selectionSource:)`
- `fetchMediaItemsMissingMetadata(limit:)`
- `fetchMediaItemsWithStaleMetadata(olderThan:limit:)`

Repository methods must not execute network calls or compute TMDB image URLs.

## Transaction Rules

Application must write related metadata changes in one transaction:

- metadata item
- external IDs
- metadata source record
- poster asset records
- selected poster update

If a refresh fails during provider fetch, existing persisted metadata must remain unchanged.

---

# 5. TMDB API Workflow

## Configuration

Use TMDB v3 API with Bearer token authentication.

Debug shell configuration:

```text
CINEMIND_TMDB_READ_TOKEN
CINEMIND_TMDB_LANGUAGE
```

Defaults:

```text
language = en-US
include_adult = false
```

The app must not log API tokens.

## Runtime Image URL Derivation

Fetch TMDB configuration through:

```text
GET /3/configuration
```

Use the returned secure image base URL and size list to derive poster URLs at runtime.

Do not persist computed image URLs in SQLite.

Persist only:

- remote path
- source
- width
- height
- preferred cache size
- local cache path
- cache timestamp

## Movie Workflow

Search:

```text
GET /3/search/movie
```

Parameters:

- `query`
- `include_adult=false`
- `language`
- `primary_release_year` when scanner-derived year exists
- first page only for MVP

Details:

```text
GET /3/movie/{movie_id}?append_to_response=external_ids
```

Images:

```text
GET /3/movie/{movie_id}/images
```

Persist:

- title
- original title
- overview as summary
- original language
- release date
- TMDB movie ID in external IDs
- IMDb ID when present
- compact source payload
- poster remote paths

## Episode Workflow

Search series:

```text
GET /3/search/tv
```

Parameters:

- `query` from scanner-derived series title
- `include_adult=false`
- `language`
- first page only for MVP

Fetch episode details:

```text
GET /3/tv/{series_id}/season/{season_number}/episode/{episode_number}?append_to_response=external_ids
```

Fetch series images:

```text
GET /3/tv/{series_id}/images
```

Persist only shallow episode metadata:

- episode title
- episode overview as summary
- episode air date
- original language when available from series or details payload
- TMDB series ID in external IDs
- TMDB episode ID in external IDs
- IMDb ID when present
- compact source payload
- series poster remote paths

Do not fetch or persist:

- season details
- season metadata
- cast
- crew
- person records
- episode groups
- alternate ordering

## Matching Rules

Automatic matching considers:

- media type
- normalized title
- scanner-derived year for movies
- series title for episodes
- season and episode number for episodes
- TMDB result year or first air year
- existing source record
- manual match lock

Automatic match thresholds:

- Apply automatically only when top confidence is at least `0.85`.
- Top confidence must be at least `0.10` higher than the next candidate.
- Otherwise return candidates and require manual match.

Automatic matching must be reversible through manual rematch.

## Error Mapping

Map provider failures into typed metadata errors:

- missing token
- invalid token or unauthorized
- not found
- rate limited
- server unavailable
- invalid response
- transport failure

TMDB failure must not corrupt existing local metadata.

---

# 6. Use Cases

## SearchMetadataCandidatesUseCase

Inputs:

- media item ID
- optional language

Behavior:

- Loads local media item.
- Builds metadata search query.
- Calls TMDB provider search.
- Returns ranked candidates.
- Does not mutate persistence.

## AutoMatchMetadataUseCase

Inputs:

- media item ID
- optional language

Behavior:

- Skips item when current source record has `manual_match_locked = true`.
- Searches TMDB.
- Applies only high-confidence unambiguous candidate.
- Fetches details and images.
- Writes metadata item, external IDs, source record, and poster assets in one transaction.
- Returns no-match result when confidence is too low.

## ManualMatchMetadataUseCase

Inputs:

- media item ID
- TMDB provider ID
- optional language

Behavior:

- Validates provider ID shape against media type.
- Fetches details and images.
- Writes metadata records in one transaction.
- Sets source record:
  - `match_source = manual`
  - `confidence = 1.0`
  - `manual_match_locked = true`
- Does not overwrite locked metadata fields.

## RefreshMetadataUseCase

Inputs:

- media item ID
- force flag
- optional language

Behavior:

- If no source record exists, attempts automatic match.
- If source record exists, refreshes that exact provider ID.
- If source record is manually locked, refreshes the locked provider ID and never searches replacement candidates.
- Preserves locked title, summary, and language fields.
- Preserves manual poster selection.
- Updates `refreshed_at` only after successful persistence.

## RefreshLibraryMetadataUseCase

Inputs:

- limit
- stale threshold
- force flag
- optional language

Behavior:

- Finds items missing metadata or stale source records.
- Runs item refresh sequentially for MVP.
- Continues after item-level provider failure.
- Returns counts for refreshed, skipped, unmatched, and failed.

Default stale threshold:

```text
30 days
```

## SetMetadataOverrideUseCase

Inputs:

- media item ID
- field
- value

Allowed fields:

- title
- summary
- language

Behavior:

- Creates metadata item if needed.
- Writes field value.
- Sets that field override lock.
- Does not change provider source record.

## ClearMetadataOverrideUseCase

Inputs:

- media item ID
- field

Behavior:

- Clears the selected field override lock.
- Does not immediately overwrite the field.
- Next successful refresh may update the field from TMDB.

## SelectPosterAssetUseCase

Inputs:

- media item ID
- poster asset ID

Behavior:

- Ensures poster belongs to media item.
- Sets selected poster.
- Sets `selection_source = manual`.
- Unselects other posters for the same media item and asset type.
- Future automatic refresh must preserve manual selection when possible.

---

# 7. Tasks

## Task 1: Package and Module Skeleton

- Add `Metadata` product and target.
- Add `MetadataTests`.
- Add `CineMindMetadataShell`.
- Update `Application` dependencies to include `Metadata`.
- Keep all new code within existing dependency rules.

## Task 2: Domain Metadata Models

- Add metadata-specific ID aliases.
- Add metadata enums.
- Add `MetadataItem`.
- Add `MetadataExternalID`.
- Add `MetadataSourceRecord`.
- Add `PosterAsset`.
- Add focused validation for confidence and non-empty provider IDs.
- Do not add provider metadata fields to `MediaItem`.

## Task 3: SQLite Migration v3

- Add v3 migration after v2.
- Create metadata tables and indexes.
- Add repository methods.
- Add migration and CRUD tests.
- Verify read-only store behavior remains unchanged.

## Task 4: Metadata Provider Abstraction

- Define provider protocols and value types.
- Add injectable HTTP client.
- Add TMDB request builder.
- Add TMDB response mappers.
- Add typed error mapping.
- Ensure compact payload extraction.

## Task 5: Matching Policy

- Implement automatic candidate ranking.
- Enforce confidence threshold.
- Enforce ambiguity gap threshold.
- Skip automatic replacement of manually locked matches.

## Task 6: Poster Cache Strategy

- Fetch TMDB image configuration.
- Derive full image URLs at runtime.
- Download selected or best poster to local cache.
- Store cache path and timestamp.
- Treat missing local file as cache miss.
- Avoid SQLite image blobs.

## Task 7: Application Use Cases

- Implement candidate search.
- Implement auto match.
- Implement manual match.
- Implement item refresh.
- Implement library refresh.
- Implement metadata field overrides.
- Implement poster selection.
- Keep writes transactional.

## Task 8: Debug Shell

- Add shell command parsing.
- Add commands for list, search, auto-match, manual-match, refresh, refresh-all, overrides, and poster selection.
- Read TMDB token from environment.
- Support explicit cache root for validation.
- Print actionable errors without logging secrets.

## Task 9: Documentation and Completion Report

- Update phase completion report after implementation.
- Record test results and manual validation results.
- Document known limitations.

---

# 8. Tests

## Domain Tests

Cover:

- Metadata item defaults.
- Override lock behavior at model level.
- Source record confidence validation.
- Manual match lock representation.
- External ID type coverage.
- Poster asset selection source coverage.
- Media item remains scanner-compatible.

## Persistence Tests

Cover:

- New database creates v1, v2, and v3 schemas.
- v2 database upgrades to v3 without data loss.
- v1 database upgrades through v2 to v3 without data loss.
- Migration v3 is idempotent across reopen.
- Migration v3 rollback prevents partial schema application.
- Metadata item upsert and reopen.
- External ID uniqueness.
- Source record upsert and manual lock persistence.
- Poster asset upsert.
- Single selected poster partial unique index.
- Repository methods do not affect playback history.
- Read-only store can read v3 records but cannot write.

## Metadata Tests

Use mocked HTTP only.

Cover:

- TMDB auth header is present.
- Token is not exposed in errors.
- Movie search request path and query.
- Movie details request with external IDs.
- Movie image request.
- TV search request path and query.
- Episode details request.
- TV series image request for series posters.
- Configuration request for image base URL.
- Runtime image URL derivation.
- Compact movie payload mapping.
- Compact episode payload mapping.
- Images arrays are not copied into raw payload JSON.
- Cast and crew are ignored.
- 401 maps to unauthorized.
- 404 maps to not found.
- 429 maps to rate limited.
- 5xx maps to server unavailable.
- Invalid JSON maps to invalid response.
- Transport failure maps to transport failure.

## Application Tests

Use fake provider and in-memory or temporary SQLite store.

Cover:

- Search returns candidates without mutation.
- High-confidence auto match persists metadata.
- Low-confidence auto match leaves database unchanged.
- Ambiguous auto match leaves database unchanged.
- Manual match persists source record and lock.
- Manual rematch replaces source record.
- Refresh uses existing source record.
- Refresh of manually locked match does not search replacement.
- Locked title survives refresh.
- Locked summary survives refresh.
- Locked language survives refresh.
- Manual poster selection survives refresh.
- Failed refresh leaves existing metadata unchanged.
- Poster cache miss is redownloaded.
- Playback history is not modified.

## Shell Smoke Tests

Cover:

- `--help` works without token.
- Missing token produces actionable error for live TMDB commands.
- Invalid arguments return non-zero status.
- Shell target builds.

## Full Verification

Required commands after implementation:

```sh
swift build
swift test
```

---

# 9. Manual Validation

Manual validation uses the shell because Phase 3 does not include polished UI.

## Environment

```sh
export CINEMIND_TMDB_READ_TOKEN=<tmdb-read-token>
export CINEMIND_TMDB_LANGUAGE=en-US
```

Use a temporary poster cache root during validation:

```text
/tmp/cinemind-metadata-cache
```

## Suggested Flow

Create or reuse a scanned database, then run:

```sh
swift run CineMindMetadataShell --db <database-path> list
```

Search candidates:

```sh
swift run CineMindMetadataShell --db <database-path> search --item <media-item-id>
```

Automatic match:

```sh
swift run CineMindMetadataShell --db <database-path> auto-match --item <media-item-id> --cache-root /tmp/cinemind-metadata-cache
```

Manual match:

```sh
swift run CineMindMetadataShell --db <database-path> manual-match --item <media-item-id> --provider-id movie:<tmdb-movie-id> --cache-root /tmp/cinemind-metadata-cache
```

Refresh:

```sh
swift run CineMindMetadataShell --db <database-path> refresh --item <media-item-id> --force --cache-root /tmp/cinemind-metadata-cache
```

Refresh all:

```sh
swift run CineMindMetadataShell --db <database-path> refresh-all --limit 20 --cache-root /tmp/cinemind-metadata-cache
```

Override title:

```sh
swift run CineMindMetadataShell --db <database-path> override-title --item <media-item-id> --value "Custom Title"
```

Override summary:

```sh
swift run CineMindMetadataShell --db <database-path> override-summary --item <media-item-id> --value "Custom summary"
```

Override language:

```sh
swift run CineMindMetadataShell --db <database-path> override-language --item <media-item-id> --value "en"
```

Select poster:

```sh
swift run CineMindMetadataShell --db <database-path> select-poster --item <media-item-id> --poster <poster-asset-id>
```

## Validate

Confirm:

- Migration version includes v3.
- Metadata item exists for matched item.
- Source record provider is `tmdb`.
- Provider ID is in the expected format.
- Manual match lock is set after manual match.
- Raw payload JSON is compact.
- No computed TMDB image URL is stored in SQLite.
- Poster asset stores remote path and cache metadata.
- Poster cache file exists when downloaded.
- Manual field override survives refresh.
- Manual poster selection survives refresh.
- Existing playback history remains unchanged.

Also run:

```sh
swift run CineMindShell <database-path>
```

The existing library listing should still work.

---

# 10. Risks and Assumptions

## Risks

- TMDB search can be ambiguous, especially for remakes and localized titles.
- TMDB rate limits or outages can affect manual validation.
- Filename-derived episode data may be too weak for some TV matches.
- Poster cache files can be deleted outside the app.
- Manual overrides can make displayed metadata diverge from provider metadata.

## Assumptions

- TMDB is the only metadata provider in MVP.
- TMDB token configuration through environment variables is acceptable for Phase 3 shell validation.
- Default metadata language is `en-US`.
- Automatic matching should be conservative and prefer no match over wrong match.
- Metadata refresh is user-triggered or shell-triggered in Phase 3.
- Batch refresh can be sequential in MVP.
- Poster cache stores files on disk, not in SQLite.
- Backdrops are deferred even though the broader product scope allows them as optional later.
- Episode metadata remains shallow and uses series posters only.
- No UI polish is required in Phase 3.

