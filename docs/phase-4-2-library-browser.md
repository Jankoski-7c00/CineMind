# Phase 4.2 Library Browser

Canonical file: `docs/phase-4-2-library-browser.md`

Phase 4.2 adds read-only library browsing to the app shell created in Phase 4.1.

---

# 1. Goal

Display the persisted local library in a native macOS browser:

```text
Application read model
  -> Persistence summary/detail queries
  -> AppUI list/table
  -> selected item detail placeholder
```

This phase proves that the app can read real Phase 1-3 data without the UI directly accessing SQLite.

---

# 2. Scope

Implement:

- Application read models for library rows and item detail shell.
- Persistence read APIs needed by those Application read models.
- AppUI list/table browser.
- Sidebar section filtering for basic sections.
- Item selection.
- Detail placeholder fed by selected item identity.
- Empty, loading, and error states for browser content.

Initial browser sections:

- Library: all media items.
- Movies: media type movie.
- TV Episodes: media type episode.
- Recently Played: items with playback history ordered by recent activity.
- Needs Metadata: items whose metadata status is not complete.
- Folders: folder summary placeholder if full folder management is not ready.

---

# 3. Explicit Non-Goals

Do not implement:

- folder picker
- scanning
- security-scoped bookmarks
- poster image loading
- metadata refresh/rematch/override
- embedded playback
- playback controls
- FTS search
- grid view unless the table/list is already complete and stable
- schema migrations

---

# 4. Architecture

AppUI consumes Application DTOs only.

Recommended DTOs:

```text
LibraryBrowserSection
LibraryItemSummary
LibraryItemDetailShell
LibraryMediaSummarySnapshot
LibraryFolderSummarySnapshot
```

The DTOs should be display-oriented but not SwiftUI-specific.

Application owns:

- section query selection
- fallback display title logic
- availability summary mapping
- metadata presence status
- playback recency summary

Persistence owns:

- SQL joins
- efficient row fetching
- sorting/filtering primitives
- deterministic ordering and pagination normalization

AppUI owns:

- selection state
- loading/error presentation
- table/list rendering

---

# 5. Required Query and Mapping Semantics

Persistence read records must remain neutral data records:

- no display labels
- no UI strings
- no SwiftUI concepts
- no AppUI-facing convenience formatting

All read queries must normalize pagination consistently:

```text
limit <= 0 -> []
offset < 0 -> 0
```

Media summary query ordering:

```text
title COLLATE NOCASE ASC, id ASC
```

Recently Played ordering:

```text
latestPlayedAt DESC, id ASC
```

Metadata status semantics belong in Application:

```text
complete = hasMetadataItem && hasMetadataSourceRecord
partial = exactly one exists
missing = neither exists
needs metadata = not complete
```

AppUI constraints:

- AppUI consumes only Application DTOs/protocols.
- AppUI never consumes Persistence records.
- AppUI never sees `CineMindStore`.
- AppUI must not know `LibraryID`.
- AppUI must not know SQL semantics.

---

# 6. Ordered Implementation Tasks

## 4.2A Persistence Media Summary Query

Files/targets expected to change:

- `Sources/Persistence/LibraryMediaSummaryQueries.swift`
- `Tests/PersistenceTests/PersistenceRepositoryTests.swift` or focused Persistence test file
- Targets: `Persistence`, `PersistenceTests`

Exact APIs:

```swift
public struct PersistedMediaItemSummary: Sendable, Equatable {
    public let id: MediaItemID
    public let mediaType: MediaType
    public let title: String
    public let year: Int?
    public let seriesTitle: String?
    public let seasonNumber: Int?
    public let episodeNumber: Int?
    public let episodeTitle: String?
    public let totalFileCount: Int
    public let availableFileCount: Int
    public let unavailableFileCount: Int
    public let hasMetadataItem: Bool
    public let hasMetadataSourceRecord: Bool
    public let latestPlayedAt: Date?
}

extension CineMindStore {
    public func fetchMediaItemSummaries(
        mediaType: MediaType?,
        limit: Int,
        offset: Int = 0
    ) throws -> [PersistedMediaItemSummary]
}
```

Scope:

- Support only Library, Movies, and TV Episodes by using `mediaType == nil`, `.movie`, or `.episode`.
- Aggregate file availability, metadata presence, and latest playback date without per-row lookups.
- Sort by `title COLLATE NOCASE ASC, id ASC`.
- Return `[]` for `limit <= 0`; treat `offset < 0` as `0`.

Explicit non-goals:

- No detail query.
- No Recently Played / Needs Metadata filtered queries.
- No folder summaries.
- No migrations or index changes.
- No UI concepts.

Validation:

- `swift test --filter PersistenceRepositoryTests`
- Add tests for all media, movie-only, episode-only, availability aggregation, metadata presence, playback recency, deterministic ordering, limit, and offset normalization.
- Confirm `Sources/Persistence/Migrations.swift` is unchanged.

Rollback scope:

- Remove `LibraryMediaSummaryQueries.swift`.
- Remove only the new Persistence tests.

Risks:

- Directly joining files, metadata, and playback can multiply counts. Use grouped subqueries before joining `media_items`.
- Sorting must remain deterministic when titles differ only by case.

## 4.2B Application Summary DTO/Use Case

Files/targets expected to change:

- `Sources/Application/LibraryBrowserSummary.swift`
- `Tests/ApplicationTests/LibraryBrowserSummaryTests.swift`
- Targets: `Application`, `ApplicationTests`

Exact APIs:

```swift
public enum LibraryBrowserSection: Sendable, Equatable {
    case library
    case movies
    case tvEpisodes
}

public struct LibraryBrowserPage: Sendable, Equatable {
    public let limit: Int
    public let offset: Int
}

public struct LibraryItemSummary: Identifiable, Sendable, Equatable {
    public let id: MediaItemID
    public let displayTitle: String
    public let mediaTypeLabel: String
    public let yearOrEpisodeLabel: String?
    public let availabilityLabel: String
    public let metadataLabel: String
    public let lastPlayedLabel: String?
}

public struct LibraryMediaSummarySnapshot: Sendable, Equatable {
    public let section: LibraryBrowserSection
    public let items: [LibraryItemSummary]
    public let page: LibraryBrowserPage
}

public protocol LibraryMediaSummaryBrowsing: Sendable {
    func loadMediaSummary(
        section: LibraryBrowserSection,
        page: LibraryBrowserPage
    ) async throws -> LibraryMediaSummarySnapshot
}

public struct LibraryMediaSummaryUseCase: LibraryMediaSummaryBrowsing {
    public init(store: CineMindStore)
}
```

Scope:

- Map only `.library`, `.movies`, and `.tvEpisodes` to the 4.2A Persistence query.
- Application owns fallback title, media type labels, year/episode labels, availability labels, metadata labels, and playback recency labels.
- Metadata labels must follow the required complete/partial/missing semantics.
- Use a minimal summary browsing protocol; do not introduce a broad browser facade.

Explicit non-goals:

- No detail DTO/use case.
- No folder DTO/use case.
- No metadata mutation, playback, poster loading, scanning, or folder picker logic.
- AppUI must not consume `PersistedMediaItemSummary`.

Validation:

- `swift test --filter LibraryBrowserSummaryTests`
- `swift test --filter ApplicationTests`
- Tests cover section mapping, title fallback, movie/year labels, episode labels, availability label cases, metadata complete/partial/missing labels, and playback label presence.

Rollback scope:

- Remove `LibraryBrowserSummary.swift`.
- Remove summary use case tests.

Risks:

- Application already has wider module imports in other files. Keep this use case read-only and focused.
- Avoid speculative display formatting beyond what the Phase 4.2 table needs.

## 4.2C CineMindApp Browser Service Wiring

Files/targets expected to change:

- `Sources/AppUI/AppShellEnvironment.swift`
- `Sources/AppUI/AppShellViewModel.swift`
- `Sources/CineMindApp/CineMindAppEnvironmentFactory.swift`
- `Sources/CineMindApp/main.swift`
- Targets: `AppUI`, `CineMindApp`

Exact APIs:

```swift
public struct AppShellEnvironment {
    public let mediaSummaryBrowser: any LibraryMediaSummaryBrowsing
}

@MainActor
public final class AppShellViewModel: ObservableObject {
    @Published public private(set) var state: AppShellState
    @Published public private(set) var environment: AppShellEnvironment?

    public func markReady(environment: AppShellEnvironment)
}
```

`CineMindAppEnvironmentFactory` changes:

```swift
static func start() throws -> AppShellEnvironment
```

Scope:

- Factory still resolves Application Support path, opens `CineMindStore`, and calls `ensureLibrary`.
- Factory creates `LibraryMediaSummaryUseCase(store:)` and returns `AppShellEnvironment`.
- `CineMindRootView` keeps taking `AppShellViewModel`.
- Pass browser capability through `AppShellViewModel` or the small `AppShellEnvironment`, not by adding multiple root view parameters.

Explicit non-goals:

- No scanner, metadata provider, playback, LibMPV, folder picker, or poster wiring.
- No database path behavior changes except retaining the store through the use case.
- AppUI still does not see `CineMindStore`.

Validation:

- `swift build --target AppUI`
- `swift build --target CineMindApp`
- `rg "import (Persistence|Scanner|Metadata|Playback|LibMPVPlayback)" Sources/AppUI`
- `rg "import (Scanner|Metadata|Playback|LibMPVPlayback)" Sources/CineMindApp`

Rollback scope:

- Restore factory to startup-only behavior.
- Remove `AppShellEnvironment`.
- Restore `AppShellViewModel.markReady()` shape.

Risks:

- If the store is not retained by the use case, later UI reads will fail.
- `AppShellState` is currently `Equatable`; do not put existential services inside it.

## 4.2D AppUI Summary Table/List

Files/targets expected to change:

- `Sources/AppUI/CineMindRootView.swift`
- `Sources/AppUI/SidebarView.swift`
- `Sources/AppUI/LibraryBrowserViewModel.swift`
- `Sources/AppUI/LibraryBrowserView.swift`
- Target: `AppUI`

Exact APIs:

```swift
@MainActor
final class LibraryBrowserViewModel: ObservableObject {
    @Published private(set) var selectedSection: LibraryBrowserSection
    @Published private(set) var snapshot: LibraryMediaSummarySnapshot?
    @Published private(set) var isLoading: Bool
    @Published private(set) var errorMessage: String?
    @Published var selectedItemID: MediaItemID?

    init(mediaSummaryBrowser: any LibraryMediaSummaryBrowsing)
    func selectSection(_ section: LibraryBrowserSection)
    func load() async
}

public struct SidebarView: View {
    init(selection: Binding<LibraryBrowserSection>)
}

struct LibraryBrowserView: View {
    init(viewModel: LibraryBrowserViewModel)
}
```

Scope:

- Render only Library, Movies, and TV Episodes.
- Use a SwiftUI `Table` or list-style table with columns for title, type, year/episode, availability, metadata, and last played.
- Show loading, empty, and error states.
- Selection stores `MediaItemID` only; detail remains a placeholder until 4.2E.

Explicit non-goals:

- No detail query.
- No Recently Played, Needs Metadata, or Folders UI yet.
- No grid.
- No AppUI imports of Persistence, Scanner, Metadata, Playback, or LibMPVPlayback.
- No library ID or SQL semantics in AppUI.

Validation:

- `swift build --target AppUI`
- `swift build --target CineMindApp`
- `rg "import (Persistence|Scanner|Metadata|Playback|LibMPVPlayback)" Sources/AppUI`
- Manual: launch app, confirm empty/loading/error table states and section switching for the first three sections.

Rollback scope:

- Remove `LibraryBrowserViewModel.swift` and `LibraryBrowserView.swift`.
- Restore placeholder `CineMindRootView` and static `SidebarView`.

Risks:

- SwiftUI `Table` selection with optional string IDs can be awkward; keep selection state simple.
- Avoid triggering loads from body recomputation; use `.task` and explicit section-change handling.

## 4.2E Detail Query And Detail Placeholder

Files/targets expected to change:

- `Sources/Persistence/LibraryMediaDetailQueries.swift`
- `Sources/Application/LibraryBrowserDetail.swift`
- `Sources/AppUI/AppShellEnvironment.swift`
- `Sources/CineMindApp/CineMindAppEnvironmentFactory.swift`
- `Sources/AppUI/LibraryBrowserViewModel.swift`
- `Sources/AppUI/LibraryItemDetailView.swift`
- Related Persistence/Application tests
- Targets: `Persistence`, `Application`, `AppUI`, `CineMindApp`

Exact APIs:

```swift
public struct PersistedMediaFileSummary: Sendable, Equatable {
    public let id: MediaFileID
    public let relativePath: String
    public let fileName: String
    public let fileExtension: String
    public let fileSizeBytes: Int64
    public let isAvailable: Bool
    public let libraryFolderDisplayName: String
    public let libraryFolderIsAvailable: Bool
}

public struct PersistedMediaItemDetail: Sendable, Equatable {
    public let summary: PersistedMediaItemSummary
    public let files: [PersistedMediaFileSummary]
}

extension CineMindStore {
    public func fetchMediaItemDetail(id: MediaItemID) throws -> PersistedMediaItemDetail?
}
```

```swift
public struct LibraryFileSummary: Identifiable, Sendable, Equatable {
    public let id: MediaFileID
    public let displayName: String
    public let relativePath: String
    public let folderName: String
    public let availabilityLabel: String
    public let fileSizeLabel: String
}

public struct LibraryItemDetailShell: Sendable, Equatable {
    public let id: MediaItemID
    public let displayTitle: String
    public let mediaTypeLabel: String
    public let yearOrEpisodeLabel: String?
    public let availabilityLabel: String
    public let metadataLabel: String
    public let lastPlayedLabel: String?
    public let files: [LibraryFileSummary]
}

public protocol LibraryItemDetailBrowsing: Sendable {
    func loadItemDetail(mediaItemID: MediaItemID) async throws -> LibraryItemDetailShell?
}

public struct LibraryItemDetailUseCase: LibraryItemDetailBrowsing {
    public init(store: CineMindStore)
}
```

`AppShellEnvironment` becomes:

```swift
public struct AppShellEnvironment {
    public let mediaSummaryBrowser: any LibraryMediaSummaryBrowsing
    public let itemDetailBrowser: any LibraryItemDetailBrowsing
}
```

Scope:

- Selecting a row loads detail shell asynchronously.
- Detail placeholder displays identity/title/type/year-or-episode/availability/metadata/last played/files.
- File paths stay relative/display-only.

Explicit non-goals:

- No playback/open-file action.
- No absolute path resolution.
- No poster decoding.
- No metadata mutation.
- No folder management.

Validation:

- `swift test --filter PersistenceRepositoryTests`
- `swift test --filter LibraryBrowser`
- `swift build --target AppUI`
- `swift build --target CineMindApp`
- Manual: select movie and episode rows; unavailable files/folders show unavailable in detail.

Rollback scope:

- Remove detail query file/API.
- Remove detail DTO/use case.
- Restore `AppShellEnvironment` to summary-only.
- Remove `LibraryItemDetailView` and selection-triggered detail loading.

Risks:

- Detail reads can be separate from list reads, but must not leak into list rendering.
- Avoid introducing playback-oriented file resolution.

## 4.2F Extra Sections: Recently Played, Needs Metadata, Folders

Files/targets expected to change:

- `Sources/Persistence/LibraryMediaSummaryQueries.swift`
- `Sources/Persistence/LibraryFolderSummaryQueries.swift`
- `Sources/Application/LibraryBrowserSummary.swift`
- `Sources/Application/LibraryFolderSummary.swift`
- `Sources/AppUI/AppShellEnvironment.swift`
- `Sources/CineMindApp/CineMindAppEnvironmentFactory.swift`
- `Sources/AppUI/SidebarView.swift`
- `Sources/AppUI/LibraryBrowserViewModel.swift`
- `Sources/AppUI/LibraryBrowserView.swift`
- Related tests
- Targets: `Persistence`, `Application`, `AppUI`, `CineMindApp`

Exact APIs:

```swift
extension CineMindStore {
    public func fetchRecentlyPlayedMediaItemSummaries(
        limit: Int,
        offset: Int = 0
    ) throws -> [PersistedMediaItemSummary]

    public func fetchMediaItemSummariesNeedingMetadata(
        limit: Int,
        offset: Int = 0
    ) throws -> [PersistedMediaItemSummary]
}

public struct PersistedLibraryFolderSummary: Sendable, Equatable {
    public let id: LibraryFolderID
    public let displayName: String
    public let rootPath: String
    public let isAvailable: Bool
    public let lastSeenAt: Date?
    public let lastScanAt: Date?
    public let mediaFileCount: Int
    public let unavailableMediaFileCount: Int
}

extension CineMindStore {
    public func fetchLibraryFolderSummaries(
        libraryID: LibraryID,
        limit: Int,
        offset: Int = 0
    ) throws -> [PersistedLibraryFolderSummary]
}
```

```swift
public enum LibraryBrowserSection: Sendable, Equatable {
    case library
    case movies
    case tvEpisodes
    case recentlyPlayed
    case needsMetadata
    case folders
}

public struct LibraryFolderSummary: Identifiable, Sendable, Equatable {
    public let id: LibraryFolderID
    public let displayName: String
    public let availabilityLabel: String
    public let fileCountLabel: String
    public let lastScanLabel: String?
}

public struct LibraryFolderSummarySnapshot: Sendable, Equatable {
    public let folders: [LibraryFolderSummary]
    public let page: LibraryBrowserPage
}

public protocol LibraryFolderSummaryBrowsing: Sendable {
    func loadFolderSummary(page: LibraryBrowserPage) async throws -> LibraryFolderSummarySnapshot
}

public struct LibraryFolderSummaryUseCase: LibraryFolderSummaryBrowsing {
    public init(store: CineMindStore)
}
```

`AppShellEnvironment` becomes:

```swift
public struct AppShellEnvironment {
    public let mediaSummaryBrowser: any LibraryMediaSummaryBrowsing
    public let itemDetailBrowser: any LibraryItemDetailBrowsing
    public let folderSummaryBrowser: any LibraryFolderSummaryBrowsing
}
```

Scope:

- Recently Played orders by `latestPlayedAt DESC, id ASC`.
- Needs Metadata returns items where metadata status is not complete.
- Folders renders read-only folder summaries.
- Application owns fetching the library ID for folder summaries; AppUI never sees `LibraryID`.

Explicit non-goals:

- No folder picker.
- No scanning.
- No folder mutation.
- No metadata refresh/rematch/override.
- No playback.
- No poster decoding.
- No migrations.

Validation:

- `swift test --filter PersistenceRepositoryTests`
- `swift test --filter LibraryBrowser`
- `swift build --target AppUI`
- `swift build --target CineMindApp`
- Manual: switch all six sidebar sections, confirm empty and populated states.

Rollback scope:

- Remove extra Persistence queries and folder summary query file.
- Remove extra Application section cases and folder use case.
- Restore AppUI sidebar to the first three sections.
- Restore `AppShellEnvironment` to summary/detail only.

Risks:

- Needs Metadata semantics must stay exactly `not complete`.
- Folder section can tempt management UI; keep it read-only.
- Recently Played must not duplicate rows for multiple playback history rows.

## 4.2G Regression Validation

Files/targets expected to change:

- No source changes expected.

Validation:

- `swift test`
- `swift build --target AppUI`
- `swift build --target CineMindApp`
- `swift build --target CineMindShell`
- `swift build --target CineMindPlaybackShell`
- `swift build --target CineMindPlaybackSurfaceSpike`
- `swift build --target CineMindMetadataShell`
- `rg "import (Persistence|Scanner|Metadata|Playback|LibMPVPlayback)" Sources/AppUI`
- `git diff -- Sources/Persistence/Migrations.swift` must be empty.

Manual validation:

- Launch app against an empty database.
- Launch app against a scanned database.
- Switch Library, Movies, TV Episodes, Recently Played, Needs Metadata, and Folders.
- Select movie and episode rows.
- Confirm unavailable files show as unavailable, not deleted.
- Relaunch and confirm library still displays.

Explicit non-goals:

- No cleanup refactors outside Phase 4.2 files.
- No migrations.
- No new dependencies.
- No scanner, folder picker, metadata mutation, playback, or poster work.

Rollback scope:

- Revert only the smallest failed task’s files first.
- Do not revert unrelated user changes.

Risks:

- Existing shell/spike targets may catch accidental API breakage.
- Manual app launch may expose SwiftUI lifecycle issues not covered by SwiftPM tests.

---

# 7. View and Data Flow

```text
Sidebar selection
  -> LibraryBrowserViewModel.load(section)
  -> Application section-specific read use case
  -> Persistence read APIs
  -> Application DTO snapshot
  -> SwiftUI table/list
```

```text
User selects row
  -> selected MediaItemID
  -> load detail shell
  -> detail placeholder displays title/type/files/metadata status summary
```

Use async view-model methods so database reads do not run directly in view body evaluation.

---

# 8. Risks

- Row data can trigger N+1 queries once metadata and playback state are included.
- Very large libraries can make naive full-list loading slow.
- AppUI could drift into Persistence imports for convenience.

Mitigation:

- Keep browser reads behind Application use cases.
- Start with bounded result sets or pagination-ready APIs even if the initial UI loads one page.
- Keep AppUI import checks part of review.

---

# 9. Validation

Automated:

- Unit tests for Application browser DTO mapping.
- Persistence tests for summary/detail queries.
- Existing tests remain passing.

Manual:

- Launch app against an empty database.
- Launch app against a scanned database.
- Switch each sidebar section.
- Select movie and episode rows.
- Confirm unavailable files show as unavailable, not deleted.
- Relaunch and confirm library still displays.

---

# 10. Acceptance Criteria

Phase 4.2 is complete only if:

- AppUI displays real persisted media items.
- AppUI does not import Persistence.
- Browser rows include media type, display title, year/episode marker, availability status, metadata presence, and playback recency when available.
- Selecting a row updates the detail placeholder.
- Empty/loading/error states are visible.
- Existing shell/spike targets still build.
- Existing tests pass.
