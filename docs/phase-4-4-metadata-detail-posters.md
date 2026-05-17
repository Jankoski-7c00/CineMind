# Phase 4.4 Metadata Detail and Posters

Canonical file: `docs/phase-4-4-metadata-detail-posters.md`

Phase 4.4 displays Phase 3 metadata and poster state in the app. It is read-only for metadata mutation workflows.

---

# 1. Summary

Phase 4.4 extends the selected item detail page into a read-only metadata and poster detail view.

The work is intentionally split into two surfaces:

- Metadata/poster text detail display.
- Local cached poster image decoding.

Application remains the source of truth for metadata/poster labels, status strings, and fallback decisions. AppUI renders Application DTOs and may load local cached poster image files, but it must not call TMDB, download posters, or import persistence/provider/playback modules.

---

# 2. Goals

- Display selected item metadata detail:
  - local title and type
  - metadata title
  - original title
  - summary
  - language
  - release date or air date
  - metadata status
- Display source record state:
  - provider
  - provider ID
  - provider media type
  - confidence
  - match source
  - manual match lock state
  - matched/refreshed dates
- Display selected poster state and a read-only poster asset list.
- Display deterministic poster placeholders before image decoding exists and whenever no local image is available.
- Load/decode selected poster image from `PosterAsset.localCachePath` only.
- Keep existing add-folder and scan controls working.
- Keep UI read-only except existing add-folder/scan controls.

---

# 3. Explicit Non-Goals

Do not implement:

- metadata refresh
- metadata rematch
- metadata field overrides
- poster selection
- remote poster downloading from UI
- TMDB direct calls from AppUI
- metadata provider calls from AppUI
- playback
- playback controls
- open/play buttons
- poster grid/browser/chooser
- schema migrations
- AppShellEnvironment growth for poster image loading unless implementation proves it is necessary
- AppUI ID boundary cleanup or removal of Domain imports unless required for compilation

---

# 4. Architecture Boundaries

Allowed AppUI dependencies remain:

```text
AppUI
  -> Application
  -> Domain
  -> Shared
```

Forbidden AppUI dependencies:

```text
AppUI -> Persistence
AppUI -> Metadata
AppUI -> Scanner
AppUI -> Playback
AppUI -> LibMPVPlayback
AppUI -> AppKit
```

Ownership:

- AppUI owns layout, placeholders, selection-driven loading state, and local poster image decoding.
- Application owns detail DTO composition, selected poster status, metadata status mapping, source labels, poster asset labels, and file/playback summary mapping.
- Persistence owns neutral metadata/poster/playback read APIs only.
- Metadata remains Persistence-free and AppUI-free.
- CineMindApp remains the composition root for concrete Application service wiring.

Poster image loading:

- Use local `PosterAsset.localCachePath` only.
- Do not construct remote image URLs in AppUI.
- Do not download posters in AppUI.
- Decode images outside SwiftUI view body.
- Publish loaded image state on the main actor.
- Keep image loader separate from metadata provider/cache logic.
- Prefer AppUI-local loader construction for 4.4 instead of adding the loader to `AppShellEnvironment`.

---

# 5. Current API Findings

Phase 4.4A audit completed.

Commands run:

```sh
rg "fetchMetadataItem|fetchMetadataSourceRecord|fetchPosterAssets|fetchMediaItemDetail" Sources
rg "import (Persistence|Metadata|Scanner|Playback|LibMPVPlayback|AppKit)" Sources/AppUI
git diff -- Sources/Persistence/Migrations.swift
```

Confirmed Persistence APIs:

```swift
public func fetchMediaItemDetail(id: MediaItemID) throws -> PersistedMediaItemDetail?

public func fetchMetadataItem(mediaItemID: MediaItemID) throws -> MetadataItem?

public func fetchMetadataSourceRecord(
    mediaItemID: MediaItemID,
    provider: MetadataProviderName
) throws -> MetadataSourceRecord?

public func fetchPosterAssets(mediaItemID: MediaItemID) throws -> [PosterAsset]
```

Confirmed current Application detail seam:

```swift
public protocol LibraryItemDetailBrowsing: Sendable {
    func fetchDetail(id: MediaItemID) async throws -> LibraryItemDetailShell?
}

public protocol ApplicationLibraryItemDetailStore: Sendable {
    func fetchMediaItemDetail(id: MediaItemID) throws -> PersistedMediaItemDetail?
}

public struct LibraryItemDetailUseCase: LibraryItemDetailBrowsing, Sendable
```

Audit findings:

- Existing Application/Persistence APIs are available for media item detail, metadata item, metadata source record, and poster assets.
- 4.4B can extend `LibraryItemDetailUseCase` without adding a new Persistence API.
- AppUI boundary is currently clean. The forbidden import check returned no matches.
- `Sources/Persistence/Migrations.swift` is unchanged.

---

# 6. Expected Module Changes

Application:

- Extend selected item detail DTOs to include metadata detail, source detail, selected poster state, and poster asset list.
- Extend the existing detail use case; do not create metadata mutation actions.

Persistence:

- No planned changes.
- No migration.
- Add a Persistence read helper only if 4.4B implementation proves existing reads are insufficient.

AppUI:

- First render read-only metadata/poster text panel with deterministic placeholders.
- Then add local poster image decoding from cache paths.
- Keep poster image loader local to AppUI for 4.4.

CineMindApp:

- No planned wiring change for poster image loading.
- Keep existing Application service wiring.

---

# 7. Application DTOs and Use Case

Extend the existing detail use case.

Proposed DTOs:

```swift
public struct LibraryMetadataDetail: Sendable, Equatable {
    public let statusLabel: String
    public let localTitle: String
    public let metadataTitle: String?
    public let originalTitle: String?
    public let summary: String?
    public let languageLabel: String?
    public let releaseOrAirDateLabel: String?
    public let source: LibraryMetadataSourceDetail?
}

public struct LibraryMetadataSourceDetail: Sendable, Equatable {
    public let providerLabel: String
    public let providerID: String
    public let providerMediaTypeLabel: String
    public let confidenceLabel: String
    public let matchSourceLabel: String
    public let manualMatchLockLabel: String
    public let matchedAtLabel: String
    public let refreshedAtLabel: String?
}

public struct LibraryPosterAssetDetail: Identifiable, Sendable, Equatable {
    public let id: PosterAssetID
    public let isSelected: Bool
    public let sourceLabel: String
    public let remotePath: String
    public let dimensionsLabel: String?
    public let preferredCacheSizeLabel: String
    public let localCachePath: String?
    public let cachedAtLabel: String?
    public let selectionSourceLabel: String
    public let statusLabel: String
}

public struct LibrarySelectedPosterDetail: Sendable, Equatable {
    public let asset: LibraryPosterAssetDetail?
    public let localCachePath: String?
    public let statusLabel: String
    public let placeholderSeed: String
}
```

Extend:

```swift
public struct LibraryItemDetailShell: Identifiable, Sendable, Equatable {
    public let id: MediaItemID
    public let displayTitle: String
    public let mediaTypeLabel: String
    public let yearOrEpisodeLabel: String?
    public let summary: String?
    public let availabilityLabel: String
    public let metadataLabel: String
    public let lastPlayedLabel: String?
    public let files: [LibraryFileSummary]
    public let metadataDetail: LibraryMetadataDetail
    public let selectedPoster: LibrarySelectedPosterDetail
    public let posterAssets: [LibraryPosterAssetDetail]
}
```

Expand the existing store protocol:

```swift
public protocol ApplicationLibraryItemDetailStore: Sendable {
    func fetchMediaItemDetail(id: MediaItemID) throws -> PersistedMediaItemDetail?
    func fetchMetadataItem(mediaItemID: MediaItemID) throws -> MetadataItem?
    func fetchMetadataSourceRecord(
        mediaItemID: MediaItemID,
        provider: MetadataProviderName
    ) throws -> MetadataSourceRecord?
    func fetchPosterAssets(mediaItemID: MediaItemID) throws -> [PosterAsset]
}
```

Mapping rules:

- Metadata status remains:
  - `complete` when metadata item and source record exist.
  - `partial` when exactly one exists.
  - `missing` when neither exists.
- Metadata title does not replace local title; both can be displayed.
- Date label uses release date first, then air date.
- Selected poster is the asset where `assetType == .poster && isSelected`.
- If no selected poster exists, do not auto-select one in 4.4.
- Poster asset list is read-only.

---

# 8. Persistence APIs

No new Persistence API is planned for 4.4B.

Existing reads are sufficient for selected-item detail composition:

```swift
fetchMediaItemDetail(id:)
fetchMetadataItem(mediaItemID:)
fetchMetadataSourceRecord(mediaItemID:provider:)
fetchPosterAssets(mediaItemID:)
```

Do not add:

- schema migrations
- UI labels in Persistence records
- provider or TMDB logic in Persistence
- image blobs in SQLite

Optional fallback only if implementation proves it is necessary:

```swift
public func fetchSelectedPosterAsset(
    mediaItemID: MediaItemID,
    assetType: PosterAssetType
) throws -> PosterAsset?
```

---

# 9. Poster Image Loading Design

Poster image loading is intentionally separate from metadata text/detail display.

4.4C first renders poster placeholders and poster asset text state. 4.4D then adds a local image loader. 4.4E wires that loader into the detail view.

Preferred AppUI-local APIs:

```swift
enum PosterImagePlaceholderReason: Sendable, Equatable {
    case noPoster
    case noCachePath
    case fileMissing
    case decodeFailed
}

struct PosterImageCacheKey: Hashable, Sendable {
    let path: String
    let modifiedAt: Date?
    let fileSizeBytes: Int64?
}

struct LoadedPosterImage: @unchecked Sendable {
    let cacheKey: PosterImageCacheKey
    let cgImage: CGImage
}

enum PosterImageLoadResult: Sendable {
    case loaded(LoadedPosterImage)
    case placeholder(PosterImagePlaceholderReason)
}

protocol PosterImageLoading: Sendable {
    func loadPosterImage(localCachePath: String?) async -> PosterImageLoadResult
}

actor PosterImageMemoryCache

struct LocalPosterImageLoader: PosterImageLoading
```

Rules:

- Keep loader AppUI-local for 4.4.
- Do not add `PosterImageLoading` to `AppShellEnvironment` unless implementation proves it is necessary.
- Prefer `Foundation`, `CoreGraphics`, `ImageIO`, and `UniformTypeIdentifiers` if needed.
- Do not import AppKit in AppUI.
- Use fixed 2:3 poster dimensions in UI.
- Nil/empty path maps to placeholder.
- Missing path maps to placeholder.
- Decode failure maps to placeholder.
- Cache by local path plus modified date/file size when practical.
- Cancel or ignore stale loads when selection changes.

---

# 10. AppUI Detail Layout

The detail view should remain read-only and selection-driven.

Display:

- deterministic poster placeholder or decoded local poster image
- local title and type
- metadata title
- original title
- summary
- language
- release date or air date
- metadata status
- source record details
- manual lock state
- selected poster status
- read-only poster asset list
- files and availability
- existing last-played summary when available

Do not add:

- refresh button
- rematch button
- override UI
- poster selection UI
- play/open button
- playback surface or controls

Defer AppUI ID boundary cleanup and removal of Domain imports unless required for compilation.

---

# 11. CineMindApp Wiring

No planned CineMindApp wiring change for poster image loading.

Keep:

```text
CineMindApp
  -> creates Persistence-backed Application use cases
  -> returns AppShellEnvironment
```

Do not add poster image loader to `AppShellEnvironment` for 4.4 unless implementation proves AppUI-local construction is not viable.

Do not wire:

- metadata provider
- poster cache downloader
- refresh/rematch/override use cases
- poster selection use case
- playback services

---

# 12. Tests

Application tests:

- no metadata -> missing status, nil metadata fields, no selected poster
- metadata item only -> partial status
- source only -> partial status
- metadata item plus source -> complete status with source labels
- selected cached poster -> selected poster DTO has local path and selected status
- selected poster without cache path -> uncached/placeholder status
- multiple posters -> selected poster is selected asset and list remains read-only

Poster image loader tests, if feasible:

- nil path -> placeholder
- missing file -> placeholder
- valid tiny PNG/JPEG -> loaded
- corrupt file -> decode failed placeholder
- unchanged second load can use memory cache

No live TMDB calls in tests.

---

# 13. Manual Validation

Use pre-seeded metadata/poster records from Persistence tests, shell tools, or a development database. AppUI itself must not fetch metadata from TMDB.

Validate:

- item with metadata and selected cached poster
- item with metadata but missing cache file
- item with metadata but selected poster has no cache path
- item with no metadata
- item with multiple poster assets
- fast selection changes do not show stale poster images
- add-folder and scan controls still work
- relaunch preserves metadata/poster detail display

---

# 14. Risks

- `localCachePath` may point to missing, empty, or corrupt files.
- Image decoding can introduce Swift 6 sendability issues around `CGImage`.
- AppUI can accidentally duplicate Application fallback rules.
- AppUI can accidentally import forbidden modules while adding image loading.
- Detail use case will perform multiple selected-item reads. This is acceptable for 4.4 unless validation shows a real issue.
- Environment growth is already noticeable; do not grow `AppShellEnvironment` for an AppUI-local poster loader.

---

# 15. Incremental Task Breakdown

## 4.4A Metadata/Poster Read Audit

Status: completed.

Files expected to change:

- None.

Exact APIs:

- No new APIs.
- Confirm current availability of `fetchMediaItemDetail`, `fetchMetadataItem`, `fetchMetadataSourceRecord`, and `fetchPosterAssets`.

Non-goals:

- No implementation.
- No docs edits beyond recording audit notes.
- No target dependency changes.
- No migrations.

Validation commands:

```sh
rg "fetchMetadataItem|fetchMetadataSourceRecord|fetchPosterAssets|fetchMediaItemDetail" Sources
rg "import (Persistence|Metadata|Scanner|Playback|LibMPVPlayback|AppKit)" Sources/AppUI
git diff -- Sources/Persistence/Migrations.swift
```

Rollback scope:

- None.

Risks:

- Existing reads might be less optimized than a joined detail query, but selected-item detail reads are acceptable for 4.4.

## 4.4B Application Metadata/Poster DTO Extension

Files expected to change:

- `Sources/Application/LibraryItemDetail.swift`
- `Tests/ApplicationTests/LibraryItemDetailTests.swift`

Exact APIs:

- Add `LibraryMetadataDetail`.
- Add `LibraryMetadataSourceDetail`.
- Add `LibraryPosterAssetDetail`.
- Add `LibrarySelectedPosterDetail`.
- Extend `LibraryItemDetailShell`.
- Expand `ApplicationLibraryItemDetailStore` with metadata and poster read methods.

Non-goals:

- No TMDB calls.
- No poster downloads.
- No metadata refresh/rematch/override/select-poster.
- No playback.
- No migrations.
- No AppUI image decoding.

Validation commands:

```sh
swift test --filter LibraryItemDetailTests
swift test --filter ApplicationTests
rg "fetchImages|fetchDetails|MetadataProvider|TMDB" Sources/Application/LibraryItemDetail.swift
```

Rollback scope:

- Revert `LibraryItemDetail.swift` DTO/use-case changes.
- Revert related `LibraryItemDetailTests`.

Risks:

- Mapping can drift from existing 4.2 metadata status rules. Keep complete/partial/missing semantics in Application mapping.

## 4.4C AppUI Read-Only Metadata/Poster Text Panel With Placeholders

Files expected to change:

- `Sources/AppUI/LibraryItemDetailView.swift`

Exact APIs:

- No new environment APIs.
- Use the extended `LibraryItemDetailShell`.
- Render metadata/poster text state and deterministic poster placeholder from Application DTOs.

Non-goals:

- No real poster image decoding.
- No image loader.
- No TMDB calls.
- No downloads.
- No metadata mutation buttons.
- No playback buttons.
- No AppUI boundary cleanup unless compilation requires it.

Validation commands:

```sh
swift build --target AppUI
swift build --target CineMindApp
rg "import (Persistence|Metadata|Scanner|Playback|LibMPVPlayback|AppKit)" Sources/AppUI
rg "refresh|rematch|override|selectPoster|MetadataProvider|TMDB|fetchImages|download" Sources/AppUI
```

Rollback scope:

- Revert `LibraryItemDetailView.swift` to the previous detail layout.

Risks:

- Placeholder state can duplicate Application labels if AppUI invents status text. AppUI should render Application DTO labels wherever possible.

## 4.4D Local Poster Image Loader

Files expected to change:

- `Sources/AppUI/PosterImageLoader.swift`
- `Package.swift`, only if adding an `AppUITests` target
- `Tests/AppUITests/PosterImageLoaderTests.swift`, if feasible

Exact APIs:

- Add `PosterImagePlaceholderReason`.
- Add `PosterImageCacheKey`.
- Add `LoadedPosterImage`.
- Add `PosterImageLoadResult`.
- Add `PosterImageLoading`.
- Add `PosterImageMemoryCache`.
- Add `LocalPosterImageLoader`.

Non-goals:

- No environment wiring.
- No remote URL construction.
- No network.
- No Metadata import.
- No AppKit import.
- No downloads.
- No SQLite access.

Validation commands:

```sh
swift test --filter PosterImageLoaderTests
swift build --target AppUI
rg "import AppKit|import Persistence|import Metadata|import Scanner|import Playback|import LibMPVPlayback" Sources/AppUI
```

Rollback scope:

- Remove `PosterImageLoader.swift`.
- Remove related tests.
- Revert any `Package.swift` test target addition.

Risks:

- `CGImage` sendability needs care under Swift 6. Keep actor boundaries narrow and publish UI state on the main actor.

## 4.4E Wire Poster Image Loading Into Detail View

Files expected to change:

- `Sources/AppUI/LibraryItemDetailView.swift`
- Possibly `Sources/AppUI/PosterImageLoader.swift`

Exact APIs:

- Construct `LocalPosterImageLoader` inside AppUI.
- Do not add poster image loader to `AppShellEnvironment`.

Internal view-model state:

```swift
enum PosterImageState: Equatable {
    case idle
    case loading
    case loaded(CGImage)
    case placeholder(PosterImagePlaceholderReason)
}
```

Behavior:

- Load Application detail first.
- Start image load only from `detail.selectedPoster.localCachePath`.
- Ignore stale image results when selection changes.
- Keep placeholder visible for nil, missing, or failed poster paths.

Non-goals:

- No `AppShellEnvironment` growth.
- No CineMindApp wiring.
- No metadata actions.
- No playback.
- No AppUI ID boundary cleanup unless required.

Validation commands:

```sh
swift build --target AppUI
swift build --target CineMindApp
rg "PosterImageLoading" Sources/AppUI/AppShellEnvironment.swift Sources/CineMindApp || true
rg "import (Persistence|Metadata|Scanner|Playback|LibMPVPlayback|AppKit)" Sources/AppUI
```

Rollback scope:

- Revert image-state wiring in `LibraryItemDetailView.swift`.
- Keep 4.4C text panel if stable.

Risks:

- Fast selection changes can show stale images unless guarded by generation checks.
- Image loading must not happen in SwiftUI `body`.

## 4.4F Validation/Completion

Files expected to change:

- No planned source changes except scoped fixes from validation.

Exact APIs:

- No new APIs.

Non-goals:

- No migrations.
- No TMDB/provider calls.
- No poster downloads.
- No metadata mutations.
- No playback.
- No environment refactor.

Validation commands:

```sh
swift test
swift build --target AppUI
swift build --target CineMindApp
swift build --target CineMindShell
swift build --target CineMindPlaybackShell
swift build --target CineMindPlaybackSurfaceSpike
swift build --target CineMindMetadataShell
rg "import (Persistence|Metadata|Scanner|Playback|LibMPVPlayback|AppKit)" Sources/AppUI
rg "refresh|rematch|override|selectPoster|MetadataProvider|TMDB|fetchImages|download" Sources/AppUI
git diff -- Sources/Persistence/Migrations.swift
```

Rollback scope:

- Revert the smallest failed task first:
  - image wiring
  - loader
  - text panel
  - Application DTO extension

Risks:

- Manual validation requires seeded metadata/poster records from outside AppUI.
- AppUI must remain read-only even when selected items have missing, partial, or stale metadata/poster state.

---

# 16. Acceptance Criteria

Phase 4.4 is complete only if:

- Detail page displays metadata and poster state from Persistence via Application.
- Application owns metadata/poster labels and status mapping.
- AppUI displays deterministic placeholders before and after image loading failure.
- Poster image loads only from local cache path.
- Missing posters show placeholders.
- AppUI does not import Persistence, Metadata, Scanner, Playback, LibMPVPlayback, or AppKit.
- No TMDB calls are made by AppUI.
- No poster downloads are triggered by AppUI.
- No metadata mutation actions are present.
- No playback UI or playback behavior is introduced.
- No migrations are introduced.
- Existing tests pass.
