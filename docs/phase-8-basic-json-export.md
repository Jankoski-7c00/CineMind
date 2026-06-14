# Phase 8 Basic JSON Export

Canonical file: `docs/phase-8-basic-json-export.md`

Planning date: 2026-06-14

Phase 8 adds a basic, user-triggered JSON export of the current local library.
The export is a versioned, readable snapshot of durable user-visible library
state. It is not a database backup, restore format, or sync protocol.

This document is a development plan only. It does not implement code.

---

# 1. Current Audit

## 1.1 Repository Baseline

Current repository state at planning time:

- The working tree is clean on `main`.
- `main` is aligned with `origin/main`.
- Latest commit: `07f3564 Implement phase 7 user curation`.
- Phase 6 implemented SQLite FTS5 keyword search.
- Phase 7 implemented durable manual tags, favorites, and collections.
- Current SQLite schema version is 6.
- Current package has no AI target and no export-specific target.
- Current source and test search found no library JSON export implementation.
- Current AppUI forbidden import checks return no matches.

Current completed user-facing foundations:

- library folders and manual scanning
- movie and episode identity
- AVFoundation-compatible playback and playback history
- TMDB metadata, manual rematch, metadata overrides, and poster cache
- local and embedded subtitles
- provider-neutral online subtitle search/download plumbing
- keyword search, filters, and sorting
- manual tags, favorites, and collections

## 1.2 Product and Architecture Signal

The next main phase should be Phase 8 Basic JSON Export because:

- `docs/product-scope.md` lists basic JSON export as an MVP requirement.
- `docs/architecture.md` places JSON export before AI provider abstraction,
  semantic search, and AI tag suggestion.
- `docs/architecture.md` requires JSON export to work without AI.
- Phase 7 completed the durable user-curation data that should be represented
  before defining the first export format.
- No export contract exists yet, so this phase can define a stable version 1
  format before AI artifacts or later Beta data complicate the snapshot.

Known project gaps that do not change the Phase 8 recommendation:

- Phase 7 deferred assigned tag text in FTS to a focused Phase 7.x search pass.
- Product scope still calls for basic TV series/season grouping beyond the
  current flat episode listing.
- Semantic search and automatic tag suggestion remain later AI phases.
- Backdrop support is optional and is not required for Phase 8.

These gaps must not be folded into Phase 8.

## 1.3 Existing Data Coverage

The current durable library state spans:

- `libraries`
- `library_folders`
- `media_items`
- `media_files`
- `playback_history`
- `metadata_items`
- `metadata_external_ids`
- `metadata_source_records`
- `poster_assets`
- `subtitle_assets`
- `tags`
- `media_item_tags`
- `favorite_media_items`
- `collections`
- `collection_items`

The following are implementation details or transient records and should not be
part of the version 1 user-facing export:

- `schema_migrations`
- `media_search_fts` and its shadow tables
- scan runs and scan issues
- SQLite WAL or database files
- poster image file contents
- subtitle file contents
- security-scoped bookmark data
- provider raw payload JSON

## 1.4 Existing API Fit

Existing APIs cover many individual reads:

- library and folder reads
- media item and media file reads
- per-item playback history reads
- per-item metadata, external ID, source record, and poster reads
- per-item subtitle reads
- tag and collection reads
- per-item curation reads

Existing APIs do not provide:

- one consistent, transaction-scoped snapshot across all exportable state
- bulk playback-history export
- bulk tag-assignment, favorite, and collection-membership export
- an export-specific privacy projection
- a versioned JSON wire contract
- a macOS save destination workflow

API coverage classification:

```text
Need: one read-only, batch/aggregate library export snapshot
Existing coverage: partial relationship and batch gap
Mapping-only solution: insufficient because it would require N+1 reads and
  would not guarantee one point-in-time snapshot
Recommendation: add one narrow export snapshot query with tests
```

Repository API decision:

```text
New Persistence API required: yes
```

The new Persistence API should be one narrow, read-only export snapshot query.
It should not add general-purpose repository methods only to assemble export
data outside a transaction.

Migration decision:

```text
Migration required: no
Migrations.swift should change: no
```

Phase 8 exports existing durable data and does not require new stored state.

---

# 2. Goal

Implement a basic JSON export so a user can:

- invoke `Export Library...` from the macOS app
- choose a destination JSON file
- export the current durable library state without network access
- receive a clear success, cancellation, or failure result
- inspect a stable, readable, versioned JSON document

The export must:

- use an explicit version 1 export schema
- produce a transaction-consistent snapshot
- preserve stable IDs and relationships within the document
- use deterministic ordering for exported arrays
- use deterministic JSON formatting apart from the export timestamp
- exclude sensitive and machine-local fields by default
- run off the main thread
- write atomically to the selected destination
- work when metadata, subtitle, or AI providers are unavailable
- route the user workflow through Application-facing protocols
- keep AppUI free of Persistence, SQLite, and AppKit imports

---

# 3. Non-Goals

Do not implement in Phase 8:

- JSON import
- restore from export
- database backup or database file copying
- automatic scheduled export
- cloud sync
- export sharing
- archive or ZIP export
- poster image export
- subtitle file-content export
- video file export
- raw metadata provider payload export
- security-scoped bookmark export
- absolute library-folder path export
- absolute poster-cache path export
- API tokens or environment configuration export
- scan history or scan issue export
- FTS index export
- schema migration history export
- AI provider abstraction
- semantic search
- automatic tag suggestion
- AI artifact export
- Phase 7.x tag text FTS work
- TV series/season browser grouping
- backdrop support
- broad AppUI redesign
- new background job framework
- new third-party dependencies

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

## 4.1 Inspect Before Implementation

- `CLAUDE.md`
- `docs/product-scope.md`
- `docs/architecture.md`
- `docs/phase-6-completion-report.md`
- `docs/phase-7-user-curation-tags-favorites-collections.md`
- `docs/phase-7-completion-report.md`
- `Package.swift`
- `Sources/Domain/Models.swift`
- `Sources/Persistence/CineMindStore.swift`
- `Sources/Persistence/SQLiteConnection.swift`
- `Sources/Persistence/LibraryMediaSummaryQueries.swift`
- `Sources/Persistence/CurationQueries.swift`
- `Sources/Persistence/SubtitleAssetQueries.swift`
- `Sources/Persistence/Migrations.swift`
- `Sources/Application/LibraryFolderWorkflow.swift`
- `Sources/AppUI/AppShellEnvironment.swift`
- `Sources/AppUI/CineMindRootView.swift`
- `Sources/CineMindApp/AppKitLibraryFolderPicker.swift`
- `Sources/CineMindApp/CineMindAppEnvironmentFactory.swift`
- `Sources/CineMindApp/main.swift`
- `Tests/PersistenceTests/PersistenceRepositoryTests.swift`
- `Tests/ApplicationTests`

## 4.2 Likely Implementation Files

- `Sources/Persistence/LibraryExportSnapshotQueries.swift` (new)
- `Sources/Application/LibraryExport.swift` (new)
- `Sources/CineMindApp/AppKitLibraryExportDestinationPicker.swift` (new)
- `Sources/CineMindApp/CineMindAppEnvironmentFactory.swift`
- `Sources/CineMindApp/main.swift`
- `Tests/PersistenceTests/PersistenceRepositoryTests.swift`
- `Tests/ApplicationTests/LibraryExportTests.swift` (new)

## 4.3 Modify Only If Discovery Proves Necessary

- `Sources/Domain/Models.swift`
  - Expected no change. Export wire models should not become core Domain
    entities.
- `Sources/AppUI/AppShellEnvironment.swift`
  - Expected no change if export remains a global macOS command owned by
    `CineMindApp`.
- `Sources/AppUI/CineMindRootView.swift`
  - Change only if a small Application-facing export status surface is
    necessary.
- `Package.swift`
  - Expected no target or dependency changes.
- `Sources/Persistence/CineMindStore.swift`
  - Change only if a small shared read helper is required by the focused export
    snapshot query.

## 4.4 Forbidden Unless Explicitly Approved

- `Sources/Persistence/Migrations.swift`
- new Persistence tables or columns
- new AI targets
- new job-system targets
- third-party JSON or archive dependencies
- direct AppUI file-system writing
- direct AppUI AppKit save panels
- direct AppUI Persistence access
- metadata provider behavior changes
- subtitle provider behavior changes
- playback behavior changes
- scanner behavior changes
- search/FTS changes
- curation mutation behavior changes
- broad app-shell environment refactor

---

# 5. Discovery Commands

Run before implementation:

```sh
git status --short --branch
git diff --stat
rg -n -i "library export|json export|export_json|LibraryExport" Sources Tests Package.swift docs
rg -n "public func|func fetch|func list|func load|func save|func update|func delete|func insert|func upsert|func search" Sources/Persistence Sources/Application Tests
rg -n "protocol .*Repository|protocol .*Reading|protocol .*Writing|protocol .*Export|struct .*Repository|class .*Repository|actor .*Repository" Sources Tests
rg -n "CREATE TABLE|CREATE VIRTUAL TABLE|schema_migrations|version[0-9]Statements" Sources/Persistence/Migrations.swift
rg -n "accessBookmark|rootPath|absolutePathHash|rawPayloadJSON|localCachePath|relativePath" Sources Tests
rg -n "^import (Persistence|Metadata|Subtitle|Playback|PlaybackAVFoundation|AVFoundation|AVKit|AppKit|AI)" Sources/AppUI || true
rg -n "^import AppUI|AppUI\\." Sources/Persistence Sources/Application Sources/Domain Tests || true
swift test list
```

Questions to answer before code:

- Can the export snapshot be assembled entirely inside one
  `CineMindStore.withTransaction` call?
- Does `BEGIN IMMEDIATE` remain acceptable for a potentially long read-only
  export, or should the export query use a dedicated read transaction strategy?
- Which existing row mappers can be reused without widening unrelated public
  APIs?
- Can all exported relationship rows be sorted deterministically by stable IDs?
- Should the first export include timestamps for relationship rows?
- Can the first export avoid changing Domain models?
- Can the export command live entirely in `CineMindApp` so AppUI does not need
  another environment service?
- What is the smallest clear user feedback surface for success and failure?
- Does atomic replacement behave correctly when exporting over an existing
  file selected by `NSSavePanel`?

---

# 6. Export Contract

## 6.1 Format Identity

The top-level document should identify itself independently of the SQLite
schema:

```json
{
  "format": "cinemind-library-export",
  "formatVersion": 1,
  "exportedAt": "2026-06-14T00:00:00Z",
  "library": {},
  "folders": [],
  "mediaItems": [],
  "mediaFiles": [],
  "playbackHistory": [],
  "metadataItems": [],
  "metadataExternalIDs": [],
  "metadataSourceRecords": [],
  "posterAssets": [],
  "subtitleAssets": [],
  "tags": [],
  "mediaItemTags": [],
  "favorites": [],
  "collections": [],
  "collectionItems": []
}
```

Rules:

- `formatVersion` is the export wire-format version, not the database schema
  version.
- Version 1 fields must not silently change meaning after release.
- Future additive fields must remain backward-readable where practical.
- Breaking format changes require a new `formatVersion`.
- Export arrays must be sorted deterministically.
- Dates must use an explicit UTC ISO 8601 representation.
- JSON must use stable key ordering and readable indentation.

## 6.2 Version 1 Included Data

Include:

- library ID, name, and timestamps
- folder ID, library ID, display name, availability, scan timestamps, and row
  timestamps
- media item identity, media type, title fields, year, episode fields, and row
  timestamps
- media file identity, media item/folder relationships, relative path, file
  name, extension, size, availability, and row timestamps
- playback progress, completion, play count, and timestamps
- normalized metadata fields and manual override locks
- metadata external IDs
- sanitized metadata source identity and match state
- poster provider identity, remote path, dimensions, selected state, and
  selection source
- subtitle identity, relative path, language, format, source, and availability
- tags and tag source
- tag assignments
- favorite memberships
- collections and collection memberships

## 6.3 Version 1 Excluded Data

Exclude:

- `LibraryFolder.rootPath`
- `LibraryFolder.accessBookmark`
- `MediaFile.absolutePathHash`
- `MetadataSourceRecord.rawPayloadJSON`
- `PosterAsset.localCachePath`
- poster image bytes
- subtitle file contents
- video file contents
- database paths
- environment variables
- provider tokens
- schema migration records
- FTS rows and shadow tables
- scan runs and scan issues

The export should include `MediaFile.relativePath` and
`SubtitleAsset.relativePath` because they describe relationships inside a
user-selected library folder without exposing the absolute machine path.

Stop and report if implementation proves that excluding absolute folder paths
would make the version 1 contract misleading or unusable. Do not silently add
absolute paths.

## 6.4 Export Is Not Restore

Version 1 must state through its contract and UI wording that:

- the JSON file is a readable data export
- it is not a complete backup
- it does not contain media, subtitle, or poster files
- it cannot currently be imported by CineMind

Do not add explanatory marketing text inside the primary app surface. A concise
save-panel message or success result is sufficient.

---

# 7. Persistence Plan

## 7.1 New Snapshot Type

Add an export-focused persisted snapshot in
`Sources/Persistence/LibraryExportSnapshotQueries.swift`.

Candidate shape:

```swift
public struct PersistedLibraryExportSnapshot: Sendable, Equatable {
    public let library: Library
    public let folders: [PersistedExportLibraryFolder]
    public let mediaItems: [MediaItem]
    public let mediaFiles: [PersistedExportMediaFile]
    public let playbackHistory: [PlaybackHistory]
    public let metadataItems: [MetadataItem]
    public let metadataExternalIDs: [MetadataExternalID]
    public let metadataSourceRecords: [PersistedExportMetadataSourceRecord]
    public let posterAssets: [PersistedExportPosterAsset]
    public let subtitleAssets: [SubtitleAsset]
    public let tags: [Tag]
    public let mediaItemTags: [MediaItemTag]
    public let favorites: [FavoriteMediaItem]
    public let collections: [MediaCollection]
    public let collectionItems: [CollectionItem]
}
```

The exact type names may change during implementation. The requirements are:

- Persistence returns typed data, not JSON strings.
- Sensitive fields are either omitted by the persisted export projection or
  removed by an explicit Application mapping step.
- Export DTOs must not expose SQLite statement types.
- The snapshot must be `Sendable` and testable.

## 7.2 New Query Surface

Add one narrow public entry point:

```swift
public func fetchLibraryExportSnapshot() throws -> PersistedLibraryExportSnapshot
```

Implementation rules:

- assemble the entire snapshot inside one transaction
- fail if no library exists
- use explicit SQL ordering for every array
- avoid N+1 per-media-item queries where a focused bulk query is simple
- reuse existing row mappers only when doing so does not widen unrelated APIs
- keep export SQL in the export query file
- do not expose a general raw-table dump API
- do not query FTS shadow tables
- do not mutate any row

## 7.3 Consistency Decision

The export must represent one coherent point-in-time view.

Recommended approach:

1. Enter one store transaction.
2. Fetch the library and every exportable collection in deterministic order.
3. Validate that relationship rows reference included parent IDs.
4. Return the typed snapshot.
5. Encode and write only after the transaction has completed.

Do not hold the SQLite transaction open while:

- presenting the save panel
- encoding JSON
- writing the destination file
- showing user feedback

Stop and report if the current `BEGIN IMMEDIATE` transaction behavior causes an
unacceptable write lock for realistic export sizes. If so, design a focused
read-snapshot strategy before continuing.

## 7.4 Migration Decision

No migration should be added.

The implementation must explicitly verify:

```text
Migrations.swift changed: no
New Persistence API required: yes
```

---

# 8. Application Plan

## 8.1 Application-Facing Protocol

Add `Sources/Application/LibraryExport.swift`.

Candidate command protocol:

```swift
public protocol LibraryExporting: Sendable {
    func exportLibrary(to destinationPath: String) async throws -> LibraryExportResult
}
```

Candidate result:

```swift
public struct LibraryExportResult: Sendable, Equatable {
    public let destinationPath: String
    public let exportedAt: Date
    public let mediaItemCount: Int
    public let byteCount: Int
}
```

Candidate store protocol:

```swift
public protocol ApplicationLibraryExportStore: Sendable {
    func fetchLibraryExportSnapshot() throws -> PersistedLibraryExportSnapshot
}
```

`CineMindStore` may conform to the narrow protocol.

## 8.2 Versioned Wire DTOs

Define export wire DTOs in Application, not Domain.

Reasons:

- the JSON contract is an application feature, not a core domain invariant
- export fields intentionally omit some Domain/Persistence fields
- future export versions must evolve independently of SQLite schema and Domain
  model changes

Candidate top-level type:

```swift
public struct LibraryExportDocumentV1: Codable, Sendable, Equatable {
    public let format: String
    public let formatVersion: Int
    public let exportedAt: Date
    public let library: LibraryExportLibraryV1
    public let folders: [LibraryExportFolderV1]
    public let mediaItems: [LibraryExportMediaItemV1]
    // Remaining version 1 collections.
}
```

Do not encode Domain models directly as the public export format. Their
`Codable` conformance is useful internally but does not define a stable,
privacy-reviewed wire contract.

## 8.3 Mapping and Privacy Projection

Application owns the explicit mapping from persisted snapshot to version 1
document.

The mapper must:

- omit sensitive and machine-local fields
- preserve stable IDs and relationships
- preserve user-owned curation state
- preserve manual metadata override locks
- normalize optional empty strings where the version 1 contract requires it
- sort arrays before encoding even if Persistence already orders them
- validate relationship integrity before producing bytes

The mapper must not:

- inspect SQLite directly
- include raw provider payloads
- include absolute paths
- call network providers
- mutate library state

## 8.4 Encoding

Recommended encoder configuration:

- `JSONEncoder`
- pretty printed
- sorted keys
- ISO 8601 dates
- no custom third-party dependency

Inject or isolate:

- current date provider
- encoder configuration
- file writer

This allows deterministic tests without writing to the user's filesystem.

## 8.5 File Writing

The Application use case should write the encoded data atomically after it has
assembled and encoded the snapshot.

Rules:

- reject an empty or non-file destination
- require a `.json` extension or add it in the destination picker
- write atomically
- do not leave a partial destination file on failure
- map filesystem and encoding errors to concise Application-facing errors
- do not overwrite unless the user approved replacement through the save panel

Do not add a general file-management service in Phase 8.

---

# 9. macOS App Integration Plan

## 9.1 Destination Picker

Add:

```text
Sources/CineMindApp/AppKitLibraryExportDestinationPicker.swift
```

Define an Application-facing picker protocol similar to the existing library
folder picker:

```swift
public protocol LibraryExportDestinationPicking: Sendable {
    @MainActor func pickLibraryExportDestination() async throws -> String?
}
```

The AppKit implementation should:

- use `NSSavePanel`
- default to a readable file name such as `CineMind-Library.json`
- restrict the selected content type to JSON where practical
- allow the user to cancel without producing an error
- return only the chosen destination path

AppUI must not import AppKit.

## 9.2 Command Placement

Recommended user entry:

- a macOS `Export Library...` command in the app menu

Prefer a global command over another browser-header button because export
applies to the whole library, not the currently selected browser section.

The command should:

1. reject duplicate starts while an export is already running
2. present the save panel on the main actor
3. treat cancellation as a silent no-op
4. call `LibraryExporting` off the main thread
5. present concise success or failure feedback

Do not add a new AppUI dependency or broad toolbar redesign solely for export.

## 9.3 Composition Root

`CineMindAppEnvironmentFactory` should construct:

- `LibraryExportUseCase`
- `AppKitLibraryExportDestinationPicker`

Prefer carrying the export workflow in `CineMindAppStartupEnvironment` rather
than adding it to `AppShellEnvironment`, unless implementation proves AppUI
must own the command.

This keeps:

- AppUI focused on library browsing and item workflows
- AppKit ownership in `CineMindApp`
- Persistence construction in the composition root

---

# 10. Implementation Phases

## Phase 8.1 Export Contract and Preflight

- Re-run discovery commands.
- Confirm version 1 included and excluded fields.
- Confirm absolute-path exclusion.
- Confirm export is not restore.
- Confirm no migration.
- Confirm no AppUI service is required.

Stop after this step if the privacy or consistency contract is unresolved.

## Phase 8.2 Persistence Snapshot

- Add the typed persisted export snapshot.
- Add one transaction-scoped export snapshot query.
- Add deterministic ordering.
- Add relationship integrity checks where appropriate.
- Add Persistence tests for complete and empty/minimal libraries.

Stop after targeted Persistence tests before Application work.

## Phase 8.3 Application Mapping and Encoding

- Add version 1 wire DTOs.
- Add privacy projection.
- Add deterministic encoder configuration.
- Add atomic writer abstraction or focused injected writer.
- Add Application-facing result and errors.
- Add Application tests for format identity, redaction, ordering, and failures.

Stop after targeted Application tests before app integration.

## Phase 8.4 macOS Export Workflow

- Add the AppKit save destination picker.
- Wire export services in the composition root.
- Add the global `Export Library...` command.
- Add busy-state protection.
- Add concise success/failure feedback.
- Preserve cancellation as a silent no-op.

## Phase 8.5 Verification and Completion Report

- Run targeted tests.
- Build AppUI and CineMindApp.
- Run full tests.
- Run boundary audits.
- Perform a manual export smoke with a disposable destination.
- Inspect the generated JSON for format, ordering, redaction, and valid
  relationships.
- Write the Phase 8 completion report.

---

# 11. Test Strategy

## 11.1 Persistence Tests

Add focused coverage for:

- minimal library exports successfully
- complete library exports all version 1 durable categories
- media item/file relationships are preserved
- playback history is included
- metadata, external IDs, and sanitized source records are included
- poster and subtitle records are included without file contents
- tags, assignments, favorites, collections, and memberships are included
- arrays are deterministically ordered
- export snapshot is transaction-scoped
- missing library produces a clear error
- read-only store can create an export snapshot
- schema version remains 6

Targeted command:

```sh
swift test --filter PersistenceRepositoryTests
```

If the Persistence test file becomes too large, a focused
`LibraryExportSnapshotTests.swift` test file may be added within the existing
PersistenceTests target.

## 11.2 Application Tests

Add `Tests/ApplicationTests/LibraryExportTests.swift`.

Cover:

- version 1 format identity
- fixed-clock deterministic export timestamp
- stable array ordering
- stable JSON key ordering
- ISO 8601 dates
- absolute folder paths are absent
- bookmark data is absent
- absolute path hashes are absent
- raw metadata provider payloads are absent
- local poster cache paths are absent
- media/subtitle/poster file contents are absent
- relative media and subtitle paths are preserved
- manual tags, favorites, collections, and memberships are preserved
- relationship validation rejects inconsistent snapshots
- empty destination is rejected
- cancellation is handled outside the export use case
- encoding failure maps to a clear error
- writer failure maps to a clear error
- partial files are not left behind by the writer contract
- result counts and byte count are correct

Targeted command:

```sh
swift test --filter LibraryExportTests
```

## 11.3 App and Boundary Verification

Build:

```sh
swift build --target AppUI
swift build --target CineMindApp
```

Boundary checks:

```sh
rg -n "^import (Persistence|Metadata|Subtitle|Playback|PlaybackAVFoundation|AVFoundation|AVKit|AppKit|AI)" Sources/AppUI || true
rg -n "SQLite|CineMindStore|JSONEncoder|NSSavePanel|Migrations|Migration|CREATE TABLE|ALTER TABLE|PRAGMA|Persistence\\." Sources/AppUI || true
rg -n "^import AppUI|AppUI\\." Sources/Persistence Sources/Application Sources/Domain Tests || true
rg -n "^import (SQLite|SQLite3|GRDB|FMDB)" Sources/AppUI Sources/Application Sources/Domain Tests || true
```

Expected:

- no forbidden AppUI imports
- no AppUI SQLite/store/save-panel references
- no lower-layer AppUI dependencies
- only expected Persistence test imports of SQLite

## 11.4 Full Verification

Run sequentially:

```sh
git diff --check
swift test --filter PersistenceRepositoryTests
swift test --filter LibraryExportTests
swift build --target AppUI
swift build --target CineMindApp
swift test
git diff --stat
git diff --name-only
```

Do not claim these pass unless they are run in the implementation session.

## 11.5 Manual Smoke

Use a disposable library database and destination.

Verify:

1. Launch the app.
2. Choose `Export Library...`.
3. Cancel and confirm no error or file.
4. Export to a new JSON file.
5. Confirm success feedback.
6. Confirm the JSON opens and parses.
7. Confirm version and timestamp fields.
8. Confirm media, metadata, playback, subtitle, and curation relationships.
9. Confirm no absolute folder paths, bookmark data, raw provider payloads, or
   local poster-cache paths.
10. Export over an existing file through save-panel approval.
11. Confirm the replacement is complete and not partial.
12. Confirm browsing, playback, metadata, subtitles, search, and curation still
    work after export.

---

# 12. Acceptance Criteria

Phase 8 is complete only if:

- The user can invoke `Export Library...` from the macOS app.
- Canceling the destination picker is a silent no-op.
- The app writes a valid `cinemind-library-export` version 1 JSON file.
- The export represents one transaction-consistent snapshot.
- Export arrays and keys are deterministic.
- Export dates use a documented UTC format.
- The export contains durable user-visible library, media, playback, metadata,
  subtitle, and curation state.
- The export excludes absolute folder paths, bookmarks, absolute path hashes,
  raw provider payloads, and local cache paths.
- The export contains no media, poster, or subtitle file contents.
- The export is written atomically.
- Export runs without AI or network access.
- Export does not mutate the library.
- AppUI remains free of Persistence and AppKit dependencies.
- `Sources/Persistence/Migrations.swift` is unchanged.
- Targeted tests, target builds, full tests, and boundary checks pass.
- A disposable manual export smoke passes.
- A Phase 8 completion report is written.

---

# 13. Stop Conditions

Stop implementation and report before widening scope if:

- a schema migration appears necessary
- export requires direct AppUI Persistence access
- export requires AppUI to import AppKit
- a consistent snapshot cannot be produced without a broad Persistence
  redesign
- current transaction behavior blocks normal writes for an unacceptable time
- absolute folder paths appear necessary for the promised version 1 contract
- version 1 cannot exclude raw provider payloads or local cache paths cleanly
- a third-party serialization or archive dependency appears necessary
- implementation starts drifting into import, restore, backup, sync, or sharing
- implementation starts adding AI, job-system, search, TV grouping, or curation
  behavior
- full verification exposes unrelated baseline failures that cannot be
  separated from Phase 8 changes

---

# 14. Risks

## 14.1 Export Contract Risk

Risk:

- Encoding Domain models directly would accidentally make internal model
  changes into public export-format changes.

Mitigation:

- Use explicit versioned Application wire DTOs.

## 14.2 Privacy Risk

Risk:

- A naive row dump could expose absolute paths, security bookmarks, raw
  provider payloads, or local cache paths.

Mitigation:

- Use an allowlist-based export contract and explicit redaction tests.

## 14.3 Consistency Risk

Risk:

- Multiple independent reads could produce a mixed snapshot while curation,
  playback, or scanning writes occur.

Mitigation:

- Add one transaction-scoped Persistence snapshot query and finish the
  transaction before encoding or file writing.

## 14.4 Locking Risk

Risk:

- The current transaction helper uses `BEGIN IMMEDIATE`, which may reserve the
  write lock during a large export snapshot read.

Mitigation:

- Keep the transaction limited to typed reads, test realistic data volume, and
  stop for a focused read-snapshot design if locking becomes disruptive.

## 14.5 Memory Risk

Risk:

- Building and encoding the complete export in memory may become expensive for
  very large libraries.

Mitigation:

- Accept in-memory encoding for basic MVP export only after measuring a
  realistic library. Stop before adding a complex streaming encoder unless
  evidence proves it necessary.

## 14.6 API Duplication Risk

Risk:

- Export work could add many general-purpose bulk repository methods that
  duplicate existing APIs.

Mitigation:

- Add one focused export snapshot API and keep its query types export-specific.

## 14.7 UI Ownership Risk

Risk:

- Export could unnecessarily grow `AppShellEnvironment` or leak AppKit into
  AppUI.

Mitigation:

- Prefer a global command and save panel owned by `CineMindApp`.

## 14.8 Test Coverage Risk

Risk:

- Tests may prove valid JSON but miss sensitive fields or broken
  relationships.

Mitigation:

- Test both allowlisted data and explicitly forbidden keys/values, then inspect
  a real disposable export.

---

# 15. Completion Report Requirement

When implementation is complete, write:

```text
docs/phase-8-completion-report.md
```

The report must include:

- implemented scope
- export format version and included categories
- privacy/excluded-field summary
- transaction-consistency decision
- Persistence API summary
- Application API summary
- macOS app integration summary
- migration decision
- boundary audit
- verification commands and results
- manual export smoke status
- known deferred work
- completion verdict

The report must state:

```text
Migrations.swift changed: no
New Persistence API required: yes
```

---

# 16. Recommended Next Step

Start Phase 8 with a short implementation preflight:

1. Re-run Section 5 discovery commands.
2. Freeze the version 1 included/excluded field matrix.
3. Confirm the absolute-path exclusion policy.
4. Confirm the transaction and lock strategy with a focused Persistence spike
   or test.
5. Implement Phase 8.2 first: the typed, deterministic Persistence export
   snapshot.
6. Stop after targeted Persistence tests before adding encoding or macOS UI.
