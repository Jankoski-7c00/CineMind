# Phase 3 Completion Report

## Phase Name

Phase 3 Metadata MVP

## Implementation Summary

Phase 3 delivered the metadata MVP defined in `docs/phase-3-metadata-mvp.md`.

Implemented:

- TMDB-only metadata provider abstraction and concrete provider.
- Metadata domain models separated from local scanner-created `MediaItem` identity.
- SQLite migration v3 for metadata items, external IDs, metadata source records, and poster assets.
- Application use cases for search, automatic match, manual match, refresh, library refresh, field overrides, clearing overrides, and poster selection.
- Poster asset persistence and optional poster file cache.
- `CineMindMetadataShell` debug shell for metadata validation and inspection.
- Unit, integration, and shell smoke test coverage with mocked provider/HTTP behavior.

Phase 3 preserves the key dependency boundaries:

- `Metadata` depends only on `Domain` and `Shared`.
- `Persistence` owns durable storage only.
- `Application` coordinates provider and persistence behavior.
- `MediaItem` remains the local logical media identity and does not carry provider metadata bloat.

## Module and Target Changes

### Domain

- Added Phase 3 metadata model types:
  - `MetadataItem`
  - `MetadataExternalID`
  - `MetadataSourceRecord`
  - `PosterAsset`
- Added TMDB-limited metadata enums for provider, source, external ID types, poster asset type, and poster selection source.
- Kept `MediaItem` focused on scanner/local identity fields only:
  - media type
  - title and normalized title
  - optional year
  - optional episode info
  - timestamps

### Metadata

- Added the `Metadata` library product and target.
- Added provider-facing protocols and value types:
  - `MetadataProvider`
  - `MetadataHTTPClient`
  - `MetadataSearchQuery`
  - `MetadataCandidate`
  - `MetadataProviderIdentifier`
  - `MetadataDetails`
  - `RemoteImage`
- Added TMDB provider implementation and response mapping.
- Added metadata candidate ranking and automatic match decision policy.
- Added poster cache implementation and TMDB image URL derivation.

### Persistence

- Added migration v3 and storage APIs for Phase 3 metadata tables.
- Added repository-style methods for:
  - metadata item fetch/save
  - external ID fetch/upsert
  - source record fetch/save
  - poster asset fetch/save/select
  - missing/stale metadata item lookup for library refresh
- No TMDB provider, network, or poster download logic was added to `Persistence`.

### Application

- Added metadata use cases that coordinate `Metadata` provider behavior with `Persistence`.
- Added app-level store protocols to keep use cases testable.
- Added poster caching adapter used by metadata writes when a cache is configured.

### CineMindMetadataShell

- Added `CineMindMetadataShell` executable target.
- Added shell smoke test target `CineMindMetadataShellTests`.

## Migration v3 Summary

Migration v3 adds durable metadata storage without changing `MediaItem` provider scope.

Tables added:

- `metadata_items`
  - One metadata item per media item.
  - Stores title, original title, summary, language, release date, air date, and field override locks.
- `metadata_external_ids`
  - Stores provider/external IDs separately from `MediaItem`.
  - Supports TMDB movie, TMDB TV series, TMDB episode, and IMDb IDs.
- `metadata_source_records`
  - Stores the current provider match source for a media item.
  - Tracks provider ID, provider media type, confidence, match source, manual match lock, compact raw payload, match time, and refresh time.
- `poster_assets`
  - Stores poster records and cache metadata.
  - Enforces one selected poster per media item and asset type through a partial unique index.

Migration behavior covered by tests:

- v1 database upgrades through v2 to v3.
- v2 database upgrades to v3.
- Metadata records persist and reopen correctly.
- Poster selected uniqueness is enforced.
- Repository transaction rollback protects against partial writes.

## Metadata Provider and TMDB Summary

Phase 3 supports TMDB as the only metadata provider.

Implemented TMDB behavior:

- Bearer token authentication through `CINEMIND_TMDB_READ_TOKEN`.
- Default language through `CINEMIND_TMDB_LANGUAGE`, falling back to `en-US`.
- Movie search.
- TV series search for episode matching.
- Movie detail fetch with external IDs.
- Episode detail fetch with external IDs.
- Movie poster image fetch.
- TV series image fetch for episode poster MVP.
- TMDB image configuration fetch.
- Runtime image URL construction from TMDB image configuration.
- Compact raw payload mapping that excludes large image/cast/crew payloads.
- Provider error mapping for missing token, unauthorized, not found, rate limit, server unavailable, invalid response, and transport failure.

Tests use fake HTTP clients and deterministic JSON fixtures. There are no live TMDB calls in the automated test suite.

## Poster Cache Summary

Phase 3 supports poster asset records and optional poster file caching.

Implemented behavior:

- Poster records store TMDB remote path, dimensions, preferred cache size, local cache path, cached timestamp, selected state, and selection source.
- Computed TMDB image URLs are not persisted as source of truth.
- Poster cache derives the image URL at runtime from TMDB configuration and `RemoteImage`.
- Cache paths use stable hashes and safe local path components.
- Existing non-empty cached files are reused without HTTP.
- Missing or empty files are downloaded again when cache is enabled.
- Automatic metadata writes select the first returned poster when no poster is already selected.
- Manual poster selection is preserved across refresh when the selected poster still exists in returned provider images.

## Application Use Case Summary

Implemented use cases:

- `SearchMetadataCandidatesUseCase`
  - Builds app-level metadata search queries from `MediaItem`.
  - Calls the metadata provider search API.
- `AutoMatchMetadataUseCase`
  - Searches provider candidates.
  - Applies automatic match policy.
  - Writes metadata item, external IDs, source record, and poster assets.
  - Skips automatic matching when a manual match lock exists.
- `ManualMatchMetadataUseCase`
  - Validates a user-supplied provider ID.
  - Fetches provider details and images.
  - Writes a manually locked source record.
- `RefreshMetadataUseCase`
  - Refreshes the existing source record's exact provider ID.
  - Does not search replacement candidates when a source record exists.
  - Preserves manual source locks.
  - Preserves field override locks for title, summary, and language.
  - Supports a `force` parameter for API parity.
- `RefreshLibraryMetadataUseCase`
  - Refreshes missing or stale metadata sequentially for MVP.
  - Supports library-level `force` to consider all media items up to the requested limit.
  - Reports refreshed, skipped, unmatched, and failed counts.
- `SetMetadataOverrideUseCase`
  - Sets title, summary, or language override values and locks.
- `ClearMetadataOverrideUseCase`
  - Clears a selected override lock without deleting the field value.
- `SelectPosterAssetUseCase`
  - Validates poster ownership.
  - Selects one poster and unselects the previous selected poster for that media item and asset type.

## CineMindMetadataShell Summary

`CineMindMetadataShell` provides the Phase 3 debug and manual validation surface.

Commands implemented:

- `list`
- `search --item`
- `auto-match --item`
- `manual-match --item --provider-id`
- `refresh --item [--force]`
- `refresh-all [--limit N] [--force]`
- `override-title --item --value`
- `override-summary --item --value`
- `override-language --item --value`
- `clear-override --item --field`
- `select-poster --item --poster`

Shell behavior:

- Opens an existing SQLite database.
- Reads TMDB token and language from environment for live provider commands.
- Supports optional `--cache-root` for poster file caching.
- Prints media item, source record, metadata item, and poster state.
- Provides actionable missing-token errors without leaking authorization headers or bearer token values.

## Test Results

Command:

```sh
swift test
```

Result:

- Passed.
- Executed 215 tests.
- Failures: 0.
- Unexpected failures: 0.

Coverage includes:

- Domain metadata models and validation.
- Persistence migration and repository behavior.
- Metadata provider request construction, response mapping, error mapping, and compact payload filtering.
- Candidate ranking and automatic match policy.
- Poster cache pathing, cache hit/miss behavior, download error mapping, and safe file naming.
- Application metadata use cases for search, auto-match, manual match, refresh, overrides, poster selection, rollback behavior, and manual selection preservation.
- Shell smoke tests that do not call live network.

## Manual Validation

Manual live TMDB validation has not yet been recorded in this completion report.

Placeholder:

- Date:
- Database path:
- TMDB language:
- Poster cache root:
- Movie search result:
- Movie auto-match/manual-match result:
- Movie refresh result:
- Episode metadata result:
- Poster cache result:
- Override/refresh preservation result:
- Notes:

Suggested commands:

```sh
export CINEMIND_TMDB_READ_TOKEN=<tmdb-read-token>
export CINEMIND_TMDB_LANGUAGE=en-US

swift run CineMindMetadataShell --db <database-path> list
swift run CineMindMetadataShell --db <database-path> search --item <media-item-id>
swift run CineMindMetadataShell --db <database-path> auto-match --item <media-item-id> --cache-root /tmp/cinemind-metadata-cache
swift run CineMindMetadataShell --db <database-path> manual-match --item <media-item-id> --provider-id movie:<tmdb-movie-id> --cache-root /tmp/cinemind-metadata-cache
swift run CineMindMetadataShell --db <database-path> refresh --item <media-item-id> --force --cache-root /tmp/cinemind-metadata-cache
swift run CineMindMetadataShell --db <database-path> refresh-all --limit 20 --force --cache-root /tmp/cinemind-metadata-cache
swift run CineMindMetadataShell --db <database-path> override-title --item <media-item-id> --value "Custom Title"
swift run CineMindMetadataShell --db <database-path> clear-override --item <media-item-id> --field title
swift run CineMindMetadataShell --db <database-path> select-poster --item <media-item-id> --poster <poster-asset-id>
```

## Resolved Fix Pass Items

### Poster Auto-selection

Resolved.

- Automatic metadata writes now select a poster when provider images exist and no poster is already selected.
- The first returned image is selected automatically.
- Existing selected posters are preserved.
- Manual poster selection remains protected across refresh when the provider still returns that poster.

### Refresh --force Parity

Resolved.

- `RefreshMetadataUseCase.refresh` accepts `force`.
- `RefreshLibraryMetadataUseCase.refresh` forwards `force` to item refresh.
- `CineMindMetadataShell refresh --force` is parsed and passed to the API.
- `CineMindMetadataShell refresh-all --force` is parsed and passed to the library refresh API.

### Shell Smoke Tests

Resolved.

- `CineMindMetadataShellTests` was added.
- Smoke coverage verifies help output, invalid argument behavior, and missing-token behavior.
- Tests explicitly remove TMDB environment variables and do not call live network.

## Known Limitations

- Item-level `force` is behavior-neutral in Phase 3.
  - Existing source-record refresh always uses the exact stored provider ID.
  - Missing-source refresh delegates to auto-match.
  - Library-level `force` changes item selection by including all media items up to the limit.
- TMDB is the only metadata provider.
- Automated tests do not perform live network calls.
- There is no polished UI for metadata workflows.
- There is no cast/person/season model.
- Episode metadata MVP uses series posters rather than season posters or episode stills as primary posters.
- There is no background job queue for metadata refresh.
- There is no retry/backoff orchestration for provider rate limits or transient failures.
- There is no provider-agnostic conflict resolution beyond current manual locks and selected poster preservation.
- Search and matching are intentionally narrow and MVP-grade.

## Deferred Items

Deferred beyond Phase 3:

- Polished metadata UI.
- Full library browser integration for metadata display and edits.
- Background metadata refresh orchestration.
- Cast/person/crew modeling.
- Season model and season poster support.
- Episode still support.
- Multi-provider metadata architecture beyond TMDB.
- Provider conflict resolution and source comparison.
- Rich metadata search UX.
- Advanced fuzzy matching, aliases, alternate titles, and localized title strategy.
- Live-network integration test profile gated behind explicit credentials.
- Poster cache management UI and cleanup policy.
- Backdrop assets.
- Trailer/video assets.
- FTS/search indexes over metadata fields.
- AI-assisted classification, recommendations, semantic search, and tagging.

## Phase 4 Recommendation

Phase 3 can be considered complete based on the final review result and passing test suite.

The reviewed Phase 4 roadmap and Phase 4.1 implementation scope are now captured in
`docs/phase-4-library-ui-mvp.md`.

Recommended Phase 4 direction:

- Build the first polished app-facing library and metadata workflow on top of the completed Phase 1-3 foundations.
- Prioritize a user-visible library browser that can show local items, metadata title/summary/poster state, playback availability, and basic manual metadata correction.
- Keep the same dependency boundaries:
  - UI calls Application use cases.
  - Application coordinates Persistence, Metadata, and Playback.
  - Persistence remains storage-only.
  - Metadata remains provider/network/cache-only and independent of Persistence/Application.

Phase 4 should avoid expanding provider scope until the app has a usable metadata review/edit surface for the current TMDB-backed MVP.
