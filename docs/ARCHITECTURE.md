# ARCHITECTURE.md

## Project: CineMind

CineMind is a macOS-native, local-first, single-user personal media library application.

This document defines the system architecture, module boundaries, data model, data flow, dependency rules, and implementation constraints for the project.

It must be read together with:

- `CLAUDE.md`
- `PRODUCT_SCOPE.md`

Where documents conflict, the priority order is:

1. `CLAUDE.md`
2. `PRODUCT_SCOPE.md`
3. `ARCHITECTURE.md`

---

# 1. Architectural Goals

CineMind is optimized for:

- local-first media management
- stable playback
- predictable scanning
- durable metadata
- strict privacy
- optional AI enhancement
- long-term maintainability
- single-developer feasibility

The architecture must prevent:

- server-first drift
- UI/database coupling
- playback logic leaking into domain logic
- AI becoming a core dependency
- plugin/API/sync features entering MVP unintentionally
- filesystem state changes destroying user data

---

# 2. High-Level Architecture

```text
+-----------------------------------------------------------+
|                         AppUI                             |
|  SwiftUI views, navigation, presentation state, commands   |
+-----------------------------+-----------------------------+
                              |
                              v
+-----------------------------------------------------------+
|                         Domain                            |
|  Entities, value objects, domain rules, use-case models    |
+-----------------------------+-----------------------------+
                              |
                              v
+-----------------------------------------------------------+
|                       Application                         |
|  Use cases, coordinators, workflows, task orchestration    |
+---------+-------------+-------------+----------+----------+
          |             |             |          |
          v             v             v          v
+---------+--+   +------+-----+   +---+----+   +-+----------+
| Persistence|   |  Playback  |   |Metadata|   | Subtitle   |
| SQLite     |   | libmpv     |   | TMDB   |   | Local/Online|
+------------+   +------------+   +--------+   +------------+
          |
          v
+-----------------------------------------------------------+
|                            AI                             |
| Optional provider abstraction; semantic search and tags    |
+-----------------------------------------------------------+
```

## Core Rule

The UI must not directly access SQLite, libmpv, TMDB, subtitle providers, or AI providers.

All user-facing features must pass through explicit application-level use cases or coordinators.

---

# 3. Module Overview

The project should be organized into independent Swift packages or logical modules.

Recommended module layout:

```text
CineMind/
  App/
    CineMindApp/
  Packages/
    Domain/
    Application/
    Persistence/
    Playback/
    Metadata/
    Subtitle/
    AI/
    Jobs/
    Shared/
  Tests/
    DomainTests/
    PersistenceTests/
    ScannerTests/
    MetadataTests/
    AITests/
```

## 3.1 AppUI

Responsible for:

- SwiftUI views
- app entry point
- navigation
- menus
- window management
- user interaction
- localization display
- binding view state to use cases

Must not contain:

- SQLite queries
- mpv calls
- TMDB calls
- subtitle provider calls
- AI provider calls
- business identity logic
- scanning reconciliation logic

Allowed dependencies:

```text
AppUI -> Application
AppUI -> Domain
AppUI -> Shared
```

Forbidden dependencies:

```text
AppUI -> Persistence
AppUI -> Playback internals
AppUI -> Metadata provider SDKs
AppUI -> AI provider SDKs
```

---

## 3.2 Domain

Responsible for:

- entities
- value objects
- domain invariants
- media identity concepts
- enum definitions
- validation rules
- pure business logic

Must not contain:

- database code
- filesystem IO
- network IO
- mpv references
- SwiftUI references
- AI prompt logic
- TMDB response parsing

Allowed dependencies:

```text
Domain -> Shared
```

Domain must remain mostly pure and testable.

---

## 3.3 Application

Responsible for:

- use cases
- workflow coordination
- service orchestration
- command handling
- transaction boundaries
- background task coordination
- view-facing application models

Examples:

- `AddLibraryFolderUseCase`
- `RunLibraryScanUseCase`
- `OpenMediaUseCase`
- `ResumePlaybackUseCase`
- `RefreshMetadataUseCase`
- `SearchLibraryUseCase`
- `SuggestTagsUseCase`

Allowed dependencies:

```text
Application -> Domain
Application -> Persistence interfaces
Application -> Playback interfaces
Application -> Metadata interfaces
Application -> Subtitle interfaces
Application -> AI interfaces
Application -> Jobs
Application -> Shared
```

Application should depend on protocols, not concrete implementations, where practical.

---

## 3.4 Persistence

Responsible for:

- SQLite database connection
- migrations
- repositories
- transactions
- FTS indexes
- JSON persistence where needed
- cache metadata
- persistence tests

Must expose repository-style interfaces to Application.

Must not contain:

- SwiftUI code
- mpv code
- network calls
- AI provider calls
- UI formatting logic

Recommended technologies:

- SQLite
- WAL mode
- FTS5
- migration version table

Persistence is the source of truth for durable app state.

---

## 3.5 Playback

Responsible for:

- libmpv integration
- playback lifecycle
- playback state machine
- audio/subtitle track enumeration
- seek/play/pause commands
- playback error mapping
- progress events
- resume position updates

Must expose:

- `PlaybackCoordinator`
- `PlaybackSession`
- `PlaybackState`
- `PlaybackCommand`
- `PlaybackEvent`

Must not expose raw mpv handles outside the module.

Forbidden:

- direct mpv calls from UI
- direct mpv calls from Domain
- playback state stored only in UI state

---

## 3.6 Metadata

Responsible for:

- metadata provider abstraction
- TMDB provider implementation
- metadata matching
- poster/backdrop fetching
- response caching
- manual rematch support
- provider error mapping

MVP provider:

- TMDB only

Future providers must not change the Domain model directly.

Metadata updates must preserve:

- manual edits
- tags
- collections
- playback history
- user overrides

---

## 3.7 Subtitle

Responsible for:

- local subtitle discovery
- embedded subtitle representation
- online subtitle search
- subtitle download/import
- subtitle metadata
- subtitle provider abstraction

Subtitle features must be non-blocking.

Playback must work even if subtitle providers fail.

---

## 3.8 AI

Responsible for:

- AI provider abstraction
- local/cloud provider configuration
- semantic search
- automatic tag suggestion
- subtitle summarization in Beta
- recommendation in Beta
- AI artifact storage coordination
- privacy filtering

AI must be optional.

The app must behave correctly when:

- no provider is configured
- local provider is unavailable
- cloud provider fails
- AI request times out
- user disables AI globally

AI must never be required for:

- scanning
- playback
- metadata display
- keyword search
- manual tagging
- favorites
- JSON export

---

## 3.9 Jobs

Responsible for:

- background task execution
- scan jobs
- metadata refresh jobs
- poster cache jobs
- AI jobs
- cancellation
- progress reporting
- retry policy

Jobs must not block the main thread.

Jobs must be observable by AppUI through Application-level state.

---

## 3.10 Shared

Responsible for:

- shared utility types
- logging interfaces
- result wrappers
- time abstractions
- path redaction helpers
- localization keys if needed

Shared must remain lightweight.

Do not turn Shared into a dumping ground.

---

# 4. Dependency Rules

## 4.1 Allowed Dependency Direction

```text
AppUI
  ↓
Application
  ↓
Domain

Application
  ↓
Persistence / Playback / Metadata / Subtitle / AI / Jobs

Persistence / Playback / Metadata / Subtitle / AI
  ↓
Domain
  ↓
Shared
```

## 4.2 Forbidden Dependencies

The following are not allowed:

```text
Domain -> AppUI
Domain -> Persistence
Domain -> Playback
Domain -> Metadata
Domain -> Subtitle
Domain -> AI

AppUI -> SQLite
AppUI -> libmpv
AppUI -> TMDB SDK
AppUI -> AI SDK

Persistence -> Playback
Playback -> Persistence
Metadata -> AppUI
AI -> AppUI
Subtitle -> AppUI
```

## 4.3 Dependency Inversion

Application should own key protocol definitions when it orchestrates external services.

Example:

```swift
protocol MediaRepository { ... }
protocol PlaybackControlling { ... }
protocol MetadataProvider { ... }
protocol SubtitleProvider { ... }
protocol EmbeddingProvider { ... }
```

Concrete implementations live in the corresponding modules.

---

# 5. Core Data Model

## 5.1 Entity Overview

Required entities:

- `Library`
- `LibraryFolder`
- `MediaItem`
- `MediaFile`
- `EpisodeInfo`
- `SubtitleTrack`
- `PosterAsset`
- `PlaybackHistory`
- `MetadataSourceRecord`
- `Tag`
- `Collection`
- `AiArtifact`
- `ScanRun`
- `ScanIssue`

---

## 5.2 Library

Represents the single user library.

Even though MVP supports only one library, the schema may still use a `library_id` to avoid future destructive migrations.

Fields:

```text
id
name
created_at
updated_at
```

Rules:

- only one active library in MVP
- multiple folders may belong to the library

---

## 5.3 LibraryFolder

Represents a user-authorized root folder.

Fields:

```text
id
library_id
display_name
root_path
access_bookmark
is_available
last_seen_at
last_scan_at
created_at
updated_at
```

Rules:

- local folders and mounted NAS paths are both represented as folders
- unavailable NAS paths must not cause data deletion
- folder access must be recoverable

---

## 5.4 MediaItem

Represents logical media identity.

Examples:

- a movie
- a TV episode
- potentially a series/season grouping object if needed later

Fields:

```text
id
media_type
title
original_title
normalized_title
year
summary
language
tmdb_id
imdb_id
series_title
season_number
episode_number
manual_match_locked
created_at
updated_at
```

Rules:

- `MediaItem` is not a file
- `MediaItem` may have multiple `MediaFile` records
- metadata refresh must not destroy manual overrides
- file path must never be the primary identity

---

## 5.5 MediaFile

Represents a physical file.

Fields:

```text
id
media_item_id
library_folder_id
relative_path
absolute_path_hash
file_name
file_extension
container
video_codec
audio_codec
duration_ms
file_size_bytes
fingerprint
modified_at
is_available
last_seen_at
created_at
updated_at
```

Rules:

- every `MediaFile` belongs to exactly one `MediaItem`
- file paths may change
- rename/move should preserve identity when confidence is high
- deleted/missing files are marked unavailable, not immediately deleted

---

## 5.6 EpisodeInfo

For TV series support.

MVP supports full series direction but should implement it incrementally.

Fields may be embedded in `MediaItem` initially or split later:

```text
series_title
season_number
episode_number
episode_title
absolute_episode_number
special_type
```

MVP required:

- detect `SxxExx`
- group by series and season
- list episodes

Not required in MVP:

- alternate episode orders
- special episode rules
- multi-version episode merging beyond normal MediaFile mapping
- advanced airing metadata

---

## 5.7 SubtitleTrack

Represents local, embedded, or downloaded subtitles.

Fields:

```text
id
media_item_id
media_file_id
kind
source
path_or_embedded_ref
language
format
title
is_default
is_available
created_at
updated_at
```

Rules:

- subtitle failure must not block playback
- online subtitles must be explicitly imported or cached
- embedded subtitles are discovered through playback/probing

---

## 5.8 PosterAsset

Represents poster/backdrop assets.

Fields:

```text
id
media_item_id
asset_type
source
remote_url
local_cache_path
width
height
created_at
updated_at
```

Rules:

- cache may be regenerated
- missing cache must not corrupt metadata
- poster refresh should be separate from metadata identity

---

## 5.9 PlaybackHistory

Represents durable playback state.

Fields:

```text
id
media_item_id
media_file_id
position_ms
duration_ms
completed
play_count
last_played_at
created_at
updated_at
```

Rules:

- playback history must survive metadata refresh
- playback history must survive file rename/move if identity is preserved
- one media item may have multiple file-specific histories if needed

---

## 5.10 MetadataSourceRecord

Tracks provider matches.

Fields:

```text
id
media_item_id
provider
provider_id
confidence
raw_payload_json
matched_at
refreshed_at
```

Rules:

- provider data must be traceable
- manual match should lock or override automatic matching
- raw payload caching is allowed but must be bounded

---

## 5.11 Tag

Represents user tags and AI-suggested tags.

Fields:

```text
id
name
normalized_name
source
created_at
updated_at
```

Sources:

```text
manual
ai_suggested
imported
```

Rules:

- AI-suggested tags must not be silently applied unless user allows
- manual tags take priority

---

## 5.12 Collection

Represents user-created groups/favorites.

Fields:

```text
id
name
description
created_at
updated_at
```

Favorites may be implemented as:

- special collection
- boolean relation
- tag-like relation

Choose the simpler model during implementation.

---

## 5.13 AiArtifact

Stores AI outputs.

Fields:

```text
id
media_item_id
artifact_type
provider
model
input_hash
payload_json
created_at
expires_at
```

Artifact types:

```text
embedding
tag_suggestion
semantic_summary
recommendation
```

MVP allowed:

```text
embedding
tag_suggestion
```

Beta allowed:

```text
semantic_summary
recommendation
```

Rules:

- artifacts must be cacheable
- artifacts must be invalidated when relevant source data changes
- artifacts must not become source of truth for core metadata

---

## 5.14 ScanRun

Represents a scan execution.

Fields:

```text
id
library_id
started_at
finished_at
status
files_seen
files_added
files_updated
files_missing
issues_count
```

Rules:

- scan history should be inspectable for debugging
- failed scans must not partially corrupt library state

---

## 5.15 ScanIssue

Represents recoverable scan problems.

Fields:

```text
id
scan_run_id
library_folder_id
path_hash
issue_type
message
created_at
```

Examples:

```text
permission_lost
folder_unavailable
unsupported_file
metadata_parse_failed
duplicate_candidate
```

---

# 6. SQLite Architecture

## 6.1 Database Principles

SQLite is the primary durable store.

Use:

- WAL mode
- migration table
- explicit schema versions
- transaction boundaries
- FTS5 for keyword search
- JSON columns only where schema flexibility is required

Avoid:

- storing large video blobs
- storing poster image blobs unless there is a strong reason
- relying on raw absolute paths as stable identity
- live API calls in repository methods

---

## 6.2 Suggested Tables

```text
libraries
library_folders
media_items
media_files
subtitle_tracks
poster_assets
playback_history
metadata_source_records
tags
media_item_tags
collections
collection_items
ai_artifacts
scan_runs
scan_issues
```

FTS tables:

```text
media_items_fts
```

Searchable fields:

```text
title
original_title
series_title
summary
year
tags
```

---

## 6.3 Migration Rules

Every schema change must include:

- migration number
- forward migration
- test fixture or migration test when possible
- no destructive migration without explicit approval

Manual user data must not be discarded silently.

---

## 6.4 Repository Rules

Repositories should expose domain-oriented methods.

Good:

```swift
findMediaItem(id:)
savePlaybackProgress(...)
markFileUnavailable(...)
searchMedia(...)
```

Bad:

```swift
executeRawSQLFromUI(...)
updateTable(...)
```

---

# 7. Scanning Architecture

## 7.1 Scanner Responsibilities

The scanner discovers local media files and reconciles them with existing records.

Responsibilities:

- walk authorized folders
- filter supported media files
- extract filename tokens
- detect movie/episode candidates
- compute lightweight identity information
- update `MediaFile`
- create or match `MediaItem`
- mark unavailable files
- record scan issues

---

## 7.2 Scanner Pipeline

```text
User triggers scan
  ↓
Resolve library folders
  ↓
Check folder availability
  ↓
Walk filesystem
  ↓
Collect candidate files
  ↓
Extract file metadata
  ↓
Parse filename
  ↓
Match existing MediaFile
  ↓
Match or create MediaItem
  ↓
Reconcile missing files
  ↓
Commit transaction
  ↓
Publish scan result
```

---

## 7.3 File Matching Strategy

Matching should use multiple signals:

- library folder
- relative path
- filename
- file size
- modified time
- duration if available
- fingerprint if available
- title/year/episode parse result

Do not rely on one signal only.

---

## 7.4 Missing File Policy

If a file disappears:

```text
media_files.is_available = false
last_seen_at unchanged
```

Do not delete:

- media item
- playback history
- metadata
- tags
- AI artifacts

Deletion cleanup may be a future explicit user action.

---

## 7.5 Rename/Move Policy

When a file appears to be renamed or moved:

- preserve `MediaItem`
- update `MediaFile.relative_path`
- keep playback history
- record scan event if useful

If confidence is low:

- create a new file record
- mark old file unavailable
- let user resolve later

---

## 7.6 Duplicate Policy

When duplicates are detected:

- attach as additional `MediaFile` to the same `MediaItem` if confidence is high
- otherwise create separate candidates
- never overwrite an existing file record blindly

---

# 8. Playback Architecture

## 8.1 Playback Coordinator

All playback must go through `PlaybackCoordinator`.

Responsibilities:

- create playback session
- load selected `MediaFile`
- configure libmpv
- expose playback state
- map mpv events to app events
- handle progress persistence
- handle track selection
- report errors

---

## 8.2 Playback State

Recommended states:

```text
idle
loading
ready
playing
paused
buffering
ended
failed
```

---

## 8.3 Playback Events

Examples:

```text
didStart(mediaFileID)
didPause(position)
didSeek(position)
didEnd
didFail(error)
didUpdateProgress(position, duration)
didDiscoverTracks(audio, subtitles)
```

---

## 8.4 Progress Persistence

Playback progress should be saved:

- periodically
- on pause
- on seek completion
- on app background/close
- on playback end

Do not write to SQLite excessively.

Use throttling.

---

## 8.5 Playback Error Handling

Errors must be mapped to user-readable categories:

```text
file_missing
permission_denied
unsupported_format
mpv_error
subtitle_error
unknown
```

Playback failure must not crash the app.

---

# 9. Metadata Architecture

## 9.1 Provider Abstraction

```swift
protocol MetadataProvider {
    func search(query: MetadataSearchQuery) async throws -> [MetadataCandidate]
    func fetchDetails(id: MetadataProviderID) async throws -> MetadataDetails
    func fetchImages(id: MetadataProviderID) async throws -> [RemoteImage]
}
```

MVP implementation:

```text
TMDBMetadataProvider
```

---

## 9.2 Metadata Matching

Matching should consider:

- parsed title
- year
- media type
- episode fields
- existing provider ID
- manual lock

Confidence score should be stored.

Automatic matching must be reversible.

---

## 9.3 Manual Override

If user manually rematches metadata:

- set `manual_match_locked = true`
- preserve user-selected provider ID
- do not overwrite with future automatic matches

---

## 9.4 Metadata Refresh

Refresh may update:

- summary
- poster
- backdrop
- external IDs
- episode title

Refresh must not overwrite:

- manual title edits
- tags
- collections
- playback history
- user notes if added later

---

# 10. Subtitle Architecture

## 10.1 Subtitle Sources

Supported:

- embedded subtitles
- local external subtitle files
- online subtitle search

---

## 10.2 Local Subtitle Discovery

The scanner or subtitle service may detect:

```text
Movie.mkv
Movie.zh.srt
Movie.en.srt
Movie.ass
```

Detected subtitles should be associated with the nearest media file or media item.

---

## 10.3 Online Subtitle Search

Online subtitle search must be:

- user-triggered
- non-blocking
- cancellable
- isolated from playback

Downloaded subtitles should become local subtitle records.

---

## 10.4 Subtitle Failure Policy

Subtitle search/download failure must not block:

- playback
- scanning
- metadata display
- search

---

# 11. Search Architecture

## 11.1 Keyword Search

MVP keyword search uses SQLite FTS5.

Search targets:

- title
- original title
- series title
- summary
- year
- tags

Filters:

- media type
- year
- favorite
- watched/unwatched
- availability

Sort options:

- title
- recently added
- recently played
- year

---

## 11.2 Semantic Search

Semantic search is an AI feature.

It must be optional.

Pipeline:

```text
User query
  ↓
Embedding provider
  ↓
Compare against stored media embeddings
  ↓
Return candidate MediaItems
  ↓
Apply normal permission/availability filters
```

Semantic search must degrade gracefully to keyword search when AI is unavailable.

---

## 11.3 Search Result Contract

Search should return app-level result models, not database rows.

Example:

```text
MediaSearchResult
- mediaItemID
- title
- year
- type
- poster
- matchReason
- availability
```

---

# 12. AI Architecture

## 12.1 AI Provider Interfaces

Required MVP interfaces:

```swift
protocol EmbeddingProvider {
    func embed(text: String) async throws -> EmbeddingVector
}

protocol ChatProvider {
    func complete(request: ChatRequest) async throws -> ChatResponse
}
```

MVP AI features:

- semantic search
- automatic tag suggestion

Beta AI features:

- subtitle summarization
- smart recommendations

Post-1.0:

- viewing analytics

---

## 12.2 Provider Types

Supported conceptually:

- local providers
- cloud providers
- disabled provider

Provider examples:

- Ollama
- LM Studio
- OpenAI-compatible endpoints
- Anthropic-compatible integration later if needed

Do not hard-code one vendor into domain logic.

---

## 12.3 Privacy Filter

Before any cloud request, data must pass through a privacy filter.

The filter must remove or transform:

- raw absolute paths
- NAS paths
- usernames in paths
- directory structures
- file hashes if not needed
- private notes if added later

Allowed by default:

- title
- year
- media type
- public metadata
- user-approved subtitle text

Forbidden by default:

- video file upload
- raw filesystem path upload
- automatic frame upload
- automatic thumbnail upload

---

## 12.4 AI Artifact Lifecycle

AI outputs are stored as `AiArtifact`.

Artifact invalidation triggers:

- metadata changed
- subtitle source changed
- provider changed
- model changed
- user manually requests refresh

AI artifacts must not be treated as authoritative metadata.

---

## 12.5 AI Error Handling

AI failures must be recoverable.

Allowed UI behavior:

- show unavailable state
- fall back to keyword search
- retry later
- ask user to configure provider

Forbidden behavior:

- block playback
- block scanning
- corrupt metadata
- silently upload more data to "fix" an error

---

# 13. Job Architecture

## 13.1 Job Types

MVP/Beta job types:

```text
scan_library
refresh_metadata
download_poster
search_subtitles
generate_embeddings
suggest_tags
export_json
```

---

## 13.2 Job Requirements

Jobs must support:

- progress
- cancellation
- error reporting
- retry policy where appropriate
- background execution without blocking UI

---

## 13.3 Job Isolation

Long-running jobs should be isolated from UI state.

The UI may observe job state but must not own job execution logic.

---

# 14. File and Path Handling

## 14.1 Path Storage

Store:

- root path in `LibraryFolder`
- relative path in `MediaFile`
- hash/redacted absolute path when needed

Avoid storing raw absolute paths in AI artifacts or logs.

---

## 14.2 Security-Scoped Access

For user-authorized folders:

- persist security-scoped bookmarks where applicable
- handle bookmark restoration failure
- ask user to re-authorize when needed

---

## 14.3 NAS Paths

NAS paths are treated as normal mounted paths.

If unavailable:

- mark folder unavailable
- mark files unavailable only after scan confirmation
- do not delete records

---

# 15. Error Handling Strategy

Errors should be typed and recoverable.

Recommended categories:

```text
PermissionError
FilesystemError
DatabaseError
PlaybackError
MetadataError
SubtitleError
AIError
ScanError
```

User-facing errors should be clear and actionable.

Internal errors should be logged with redacted paths.

---

# 16. Logging Strategy

Logs should help debug:

- scan results
- missing paths
- metadata matching
- playback failures
- AI provider failures

Logs must not include:

- raw cloud AI payloads
- raw absolute paths when avoidable
- API keys
- access tokens
- full subtitle text unless explicitly debug-enabled

---

# 17. Localization Architecture

UI must support Chinese and English.

Rules:

- no hard-coded user-facing strings in view logic
- use localization keys
- domain errors should map to localized UI messages
- logs may remain English initially

---

# 18. Testing Architecture

## 18.1 Required Tests

Domain tests:

- media identity
- movie parsing
- episode parsing
- tag model
- availability state

Persistence tests:

- migrations
- CRUD repositories
- playback history persistence
- media file availability updates
- FTS indexing

Scanner tests:

- new file
- renamed file
- moved file
- missing file
- duplicate file
- NAS unavailable

Metadata tests:

- candidate matching
- manual override preservation
- cache refresh

AI tests:

- privacy filtering
- provider disabled state
- artifact invalidation

---

## 18.2 Test Data

Use small fixture files or fake file entries.

Do not require large real media files in unit tests.

Playback smoke tests may use a small sample video if needed.

---

## 18.3 External API Tests

Tests must not depend on live external APIs.

Use:

- mocked TMDB responses
- mocked subtitle provider responses
- mocked AI providers

---

# 19. Performance Architecture

## 19.1 Principles

- UI must remain responsive
- scanning must be cancellable
- metadata fetching must be batched where possible
- poster loading must be cached
- SQLite writes should be transactional
- playback progress writes should be throttled

---

## 19.2 Expected Bottlenecks

Known risk areas:

- large folder scans
- poster cache growth
- subtitle search latency
- AI embedding generation
- metadata rate limits
- NAS disconnection

Architecture must isolate these risks into jobs/services.

---

# 20. Build Order

Strict recommended implementation order:

1. Domain module
2. SQLite schema and migrations
3. Persistence repositories
4. Library folder model
5. Scanner MVP
6. Media list query
7. SwiftUI shell
8. libmpv playback MVP
9. Playback history
10. TMDB metadata provider
11. Poster cache
12. FTS keyword search
13. Subtitle local/embedded support
14. Online subtitle search
15. JSON export
16. AI provider abstraction
17. Semantic search
18. AI tag suggestion

Do not start with AI, UI polish, subtitle downloads, or recommendations.

---

# 21. MVP Architecture Acceptance Criteria

MVP architecture is acceptable only if:

- the app can import a folder
- scanned files persist in SQLite
- media list survives restart
- playback works through libmpv
- playback progress persists
- metadata can be matched and refreshed
- keyword search works without AI
- AI can be disabled entirely
- NAS unavailable state does not delete data
- Domain and Persistence have tests

---

# 22. Explicitly Deferred Architecture

Do not design or implement these in MVP:

- multi-user accounts
- local HTTP API
- remote streaming
- cloud sync
- plugin runtime
- Mac App Store-specific architecture
- self-hosted server
- mobile companion app
- downloader subsystem
- DRM layer
- full automation framework
- real-time filesystem watcher

If needed later, these require separate architecture decision records.

---

# 23. Architecture Decision Records

Any major architectural change must be recorded as an ADR.

ADR examples:

```text
ADR-001-use-libmpv-as-only-playback-engine.md
ADR-002-use-sqlite-as-primary-store.md
ADR-003-local-first-ai-provider-boundary.md
ADR-004-single-library-mvp.md
```

Each ADR should include:

- context
- decision
- alternatives considered
- consequences
- migration impact

---

# 24. Claude Code Architecture Rules

When Claude Code modifies architecture-related code, it must:

- state the intended module affected
- state whether dependencies change
- keep changes within the current task
- add or update tests for Domain/Persistence changes
- avoid introducing new frameworks silently
- avoid broad rewrites

Claude Code must not:

- add server/API behavior
- add a plugin runtime
- add a second playback engine
- introduce cloud-first AI flows
- bypass privacy filtering
- make UI access SQLite directly
- remove manual override protections
- auto-delete missing media records

---

# 25. Decision Framework

When uncertain, choose:

- local over remote
- simple over abstract
- explicit over automatic
- durable data over convenience
- user control over silent mutation
- stable playback over feature richness
- testability over cleverness
- recoverable state over destructive cleanup

---

# End of Architecture
