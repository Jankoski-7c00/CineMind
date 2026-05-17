# Phase 4.5 Embedded Playback Integration

Canonical file: `docs/phase-4-5-embedded-playback-integration.md`

Phase 4.5 brings embedded libmpv playback into the real app while preserving Playback module purity.

---

# 1. Goal

Integrate the proven Phase 2.1 embedded playback spike into the app:

```text
selected media file (isPlayable == true, with Play button)
  -> MediaOpening protocol (OpenMediaUseCase conforms)
  -> PlaybackApplicationController
  -> PlaybackCoordinator
  -> LibMPVPlaybackBackend
  -> AppKit render surface wrapped in SwiftUI
  -> status label in detail view
```

---

# 2. Scope

Implement:

- Production playback render surface API in LibMPVPlayback.
- Deferred embedded surface attachment (init backend without view; attach surface later).
- SwiftUI wrapper around an AppKit `NSOpenGLView`, owned in CineMindApp, not AppUI.
- `PlaybackApplicationController` in Application layer.
- Minimal open/stop lifecycle from the detail page.
- Embedded video display in the detail view.
- Playback status text display (state + file name).
- Progress persistence fanout wired to `PlaybackProgressCoordinator` (save on stop/shutdown).
- Safe teardown on window close, selection change, and app quit.

This phase exposes only `open` and `stop`. No play/pause toggle, no seek, no scrubber, no track menus.

---

# 3. Explicit Non-Goals

Do not implement:

- play/pause toggle
- scrubber
- seek
- persisted progress UI display
- audio/subtitle track menus
- playlists
- next episode autoplay
- PiP
- fullscreen polish
- alternate playback engine
- raw mpv calls from AppUI
- elaborate progress/resume UX (progress fanout wired, UX deferred to 4.6)
- any metadata, scanner, or poster work

---

# 4. Architecture

Playback core remains UI-free.

LibMPVPlayback owns:

- raw mpv symbols
- render context
- AppKit render adapter
- update callback handling

Application owns:

- `MediaOpening` protocol for media file resolution
- `OpenMediaUseCase` conforming to `MediaOpening`
- playback controller orchestration (depends on `any MediaOpening`, not concrete use case)
- event stream consumption/fanout policy
- user-facing playback errors
- progress persistence fanout through `PlaybackProgressCoordinator`

AppUI owns:

- playback surface placement as an abstract container
- open/stop user intent
- playback status presentation
- **Play button** on available file rows

CineMindApp wires:

- concrete `LibMPVPlaybackBackend`
- concrete store
- playback controller dependencies
- concrete SwiftUI/AppKit render wrapper (imports `LibMPVPlayback`)

---

# 5. Lifecycle and Teardown Rules (Mandatory)

These rules are mandatory for every task that touches playback lifecycle.

## Startup order

1. Create `PlaybackProgressUseCase` (Persistence-backed).
2. Create `PlaybackProgressCoordinator` (progress use case).
3. Create `LibMPVPlaybackBackend` in deferred-embedded mode (no view yet).
4. Create `PlaybackCoordinator` (backend).
5. Create `PlaybackApplicationController` (coordinator, progress coordinator, mediaOpening).
6. SwiftUI render view appears → `NSOpenGLView` created.
7. `backend.attachRenderSurface(openGLView:)` called → render adapter + context created.
8. `backend.prepareRenderSurface()` called → OpenGL context made current, mpv render context created, initial render.

## Teardown order

1. Cancel UI/event observation tasks.
2. Stop active playback (`controller.stop()`).
3. Close progress session (`progressCoordinator.closeSession()`).
4. Shutdown coordinator (`coordinator.shutdown()`).
5. Shutdown backend (`backend.shutdown()`).
   - Inside backend: clear update callback, free render context, stop event loop, destroy mpv runtime.
6. Release AppKit view references.
7. Release backend/coordinator references.

## Render callback rule

- The mpv update callback fires off-main.
- It schedules a render on `@MainActor` but does NOT call normal mpv APIs.
- It uses a lock to avoid duplicate scheduling.
- After `shutdown()` begins, scheduled renders are no-ops.

## NSOpenGLView rule

- `NSOpenGLView` must not host SwiftUI overlay subviews.
- Controls remain outside the render view.

---

# 6. Expected Module Changes

LibMPVPlayback:

- Generalize spike-only render surface naming into production naming.
- Add deferred embedded init without upfront view.
- Add `attachRenderSurface(openGLView:)` + `prepareRenderSurface()`.
- Preserve spike target compatibility.

Application:

- Add `MediaOpening` protocol (single-method: `open(mediaFileID:) throws -> PlayableFile`).
- Add `extension OpenMediaUseCase: MediaOpening`.
- Add `PlaybackApplicationController` with protocol, status types.
- Controller depends on `any MediaOpening`, not concrete `OpenMediaUseCase`.
- Map `Application.PlayableFile` to `Playback.PlayableFile`.
- Own one active playback session.
- Consume coordinator event stream; fan out to progress coordinator and status stream.
- Add `mediaFileID` and `isPlayable` to `LibraryFileSummary`.

Persistence:

- Add `fetchMediaFile(id:)` direct query.
- Add `PersistedMediaFile` DTO.
- Refactor `OpenMediaUseCase` to use direct lookup (remove O(n) scan).
- No migration.

AppUI:

- Add playback area in detail page (render surface slot + status label).
- Add Play button on available file rows.
- Do not import `Playback` or `LibMPVPlayback`.

CineMindApp:

- Wire playback concrete dependencies.
- Add the concrete SwiftUI/AppKit bridge (`PlaybackRenderSurfaceView`).
- Add `Playback` and `LibMPVPlayback` as target dependencies.
- Inject render view into detail page.

---

# 7. UI Rule: Available vs Unavailable Files

Each file row in the detail view shows:

- **Playable** (`LibraryFileSummary.isPlayable == true`): display a **Play** button.
- **Not playable** (`isPlayable == false`): no Play button; row remains text-only.

`isPlayable` is a boolean computed in Application mapping from `PersistedMediaFileSummary.isAvailable`.
AppUI must use `file.isPlayable` — never compare `availabilityLabel` strings.

Tapping Play sends `playbackController.open(mediaFileID:)` to the application controller.

No play/pause toggle in 4.5. Once open, the controller auto-plays. Stop is the only user-invoked lifecycle transition.

---

# 8. Risks

- SwiftUI may recreate representable views unexpectedly.
- OpenGL and `NSOpenGLView` are deprecated.
- Render callbacks can race with teardown.
- Existing `PlaybackCoordinator.events` is single-consumer.
- `PlaybackApplicationController.statusStream` is single-consumer for 4.5 (no fanout abstraction).
- CineMindApp newly depending on `LibMPVPlayback`/`CLibMPV` introduces a Homebrew mpv build-time and runtime requirement that previously only affected shell/spike targets. CI and build environments without `libmpv.dylib` will fail to link CineMindApp.
- AppUI Play button logic must not regress to string-based availability checks.

Mitigation:

- Keep render view identity stable (use `.id()` if needed).
- Keep playback event consumption centralized in the playback application controller.
- Treat AppKit render surface as isolated implementation detail.
- Guard scheduled renders after shutdown begins.
- Document `statusStream` as single-consumer; add fanout only if 4.6 proves it necessary.
- Gate CineMindApp mpv runtime with the existing `MPVEmbeddedRenderAvailabilityProbe` so the app can launch without mpv and surface a clear error instead of crashing.
- Use `LibraryFileSummary.isPlayable: Bool` for the Play button decision; never compare `availabilityLabel`.

---

# 9. Validation

Automated:

- Existing Playback tests remain passing.
- Application tests for controller state transitions with fake backend/open media/progress.
- Forbidden import grep on AppUI.

Manual:

- Open an available media file from detail via Play button.
- Video renders inside the app.
- Resize window.
- Move window between displays if available.
- Stop playback.
- Close window while playing.
- Quit app while playing.
- Confirm no crash or hung process.
- Play button only appears for available files.

---

# 10. Acceptance Criteria

Phase 4.5 is complete only if:

- Embedded video renders in the real app.
- Playback still flows through `PlaybackCoordinator`.
- AppUI does not import `LibMPVPlayback`, `Playback`, `AppKit`, `Persistence`, `Metadata`, `Scanner`, or raw mpv APIs.
- Raw mpv APIs remain isolated in `LibMPVPlayback`.
- Playback can be stopped and shut down cleanly.
- Progress fanout is wired (save on stop/shutdown).
- Existing shell/spike targets remain buildable.
- Existing tests pass.

User-visible for 4.5:

- Playable file rows (`isPlayable == true`) show a Play button.
- Non-playable file rows show no Play button.
- Play button decision uses `LibraryFileSummary.isPlayable`, not string comparison.
- Playback status text is visible (state label + file name).
- Stop button is available while playing.

Deferred to 4.6:

- Play/pause toggle, seek, scrubber, track menus.
- Persisted progress display.
- Resume position UX.

---

# 11. Current API Findings

Phase 4.5 audit completed.

Confirmed Playback APIs:

```swift
// Playback module (pure, no AppKit/SwiftUI)
public protocol PlaybackBackend: Sendable {
    var events: AsyncStream<PlaybackEvent> { get }
    func load(playableFile: PlayableFile) async throws
    func play() async throws
    func pause() async throws
    func seek(toMS: Int) async throws
    func stop() async throws
    func selectAudioTrack(trackID: String) async throws
    func selectSubtitleTrack(trackID: String) async throws
    func disableSubtitle() async throws
    func shutdown() async
}

public actor PlaybackCoordinator {
    public nonisolated let events: AsyncStream<PlaybackEvent>  // single-consumer
    public func send(_ command: PlaybackCommand) async
    public func open(_ playableFile: PlayableFile) async
    public func stop() async
    public func shutdown() async
}
```

Confirmed LibMPVPlayback APIs:

```swift
public final class LibMPVPlaybackBackend: PlaybackBackend, @unchecked Sendable {
    convenience init() throws                                          // standalone
    @MainActor convenience init(spikeOpenGLView: NSOpenGLView) throws  // embedded (spike)
    @MainActor func prepareSpikeRenderSurface() async throws
    @MainActor func renderSpikeSurfaceNow()
    func shutdown() async
}
```

Confirmed Application APIs:

```swift
public struct OpenMediaUseCase {
    public func open(mediaFileID: MediaFileID) throws -> PlayableFile  // Application.PlayableFile
}

public actor PlaybackProgressCoordinator {
    public func startSession(mediaItemID:mediaFileID:initialPositionMS:)
    public func handle(_ event: PlaybackEvent) throws
    public func closeSession() throws
}
```

Confirmed AppUI detail DTO:

```swift
public struct LibraryFileSummary: Sendable, Equatable {
    // Currently: fileName, fileExtension, fileSizeLabel, availabilityLabel
    // MISSING: mediaFileID, isPlayable
}
```

Planned new Application protocols:

```swift
// MediaOpening — protocol so PlaybackApplicationController depends on abstraction, not concrete use case.
// Tests inject a fake opener; production wires OpenMediaUseCase.
public protocol MediaOpening: Sendable {
    func open(mediaFileID: MediaFileID) throws -> Application.PlayableFile
}

extension OpenMediaUseCase: MediaOpening {}
```

Audit findings:

- `LibraryFileSummary` has no `mediaFileID` or `isPlayable`. Must add both.
- `OpenMediaUseCase` uses O(n) scan over `fetchMediaItems()` + `fetchMediaFiles()`. Must add `fetchMediaFile(id:)`.
- No `MediaOpening` protocol exists. Must add so controller is testable with a fake opener.
- No `PlaybackApplicationController` exists.
- No deferred embedded init in `LibMPVPlaybackBackend`.
- `CineMindApp` has no `Playback` or `LibMPVPlayback` dependency.
- AppUI forbidden import check is currently clean.

---

# 12. Incremental Task Breakdown

## 4.5A Direct Media File Lookup

Status: pending.

Goal: Add `fetchMediaFile(id:)` direct query in Persistence. Refactor `OpenMediaUseCase`
to use it (remove current O(n) scan over all items and files).

Pre-audit: The current `OpenMediaUseCase` iterates `fetchMediaItems()` then
`fetchMediaFiles(mediaItemID:)` to find a single `MediaFile`. The schema columns
must be verified before writing the query — do not assume `folder_available` or
`file_present` columns exist in `media_files`. Effective availability is computed
by joining `library_folders` and checking the actual column names on both tables.

Files expected to change:

- `Sources/Persistence/MediaFileQueries.swift` (NEW)
- `Sources/Application/Application.swift`

Exact APIs:

```swift
// Persistence — new DTO
public struct PersistedMediaFile: Sendable, Equatable {
    public let id: MediaFileID
    public let mediaItemID: MediaItemID
    public let libraryFolderID: LibraryFolderID
    public let fileName: String
    public let fileExtension: String
    public let fileSizeBytes: Int64
    public let relativePath: String
    public let isAvailable: Bool       // computed from file + folder state
    public let folderRootPath: String  // needed by OpenMediaUseCase to resolve absolute URL
}

// Persistence — new query on CineMindStore
extension CineMindStore {
    public func fetchMediaFile(id: MediaFileID) throws -> PersistedMediaFile?
}
```

SQL query approach (verify column names against existing schema before writing):

1. Read the current `media_files` table schema from `Sources/Persistence/Migrations.swift`
   or the SQLite schema definition to confirm actual column names.
2. Read the current `library_folders` table schema similarly.
3. Join on `media_files.library_folder_id = library_folders.id`.
4. Compute `isAvailable` from the file-is-present flag AND the folder-is-available flag.
5. Include `library_folders.root_path` so `OpenMediaUseCase` can resolve absolute file URLs
   without a second query.

Expected join shape (column names TBC after schema audit):

```sql
SELECT mf.id, mf.media_item_id, mf.library_folder_id,
       mf.file_name, mf.file_extension, mf.file_size_bytes,
       mf.relative_path,
       -- isAvailable: file must be present AND folder must be available
       (mf.<file_present_col> = 1 AND lf.<folder_available_col> = 1) AS is_available,
       lf.root_path AS folder_root_path
FROM media_files mf
JOIN library_folders lf ON mf.library_folder_id = lf.id
WHERE mf.id = ?
```

`OpenMediaUseCase` refactoring:

- Replace the O(n) `for item in store.fetchMediaItems()` / `for file in store.fetchMediaFiles(...)` loop
  with a single `store.fetchMediaFile(id: mediaFileID)` call.
- `fetchLibraryFolder(id:)` is no longer needed as a separate query — the root path is
  already on `PersistedMediaFile`.
- `fetchMediaItem` info (for displayName) still requires a lookup, but this can be
  fetched directly via an existing or new `fetchMediaItem(id:)` helper. If no direct
  `fetchMediaItem(id:)` exists yet, add one as part of this task.

Non-goals:

- No migration.
- No change to `PersistedMediaFileSummary` (used by detail queries).
- No metadata, scanner, or poster work.
- No playback logic.

Validation commands:

```sh
swift test --filter PersistenceTests
swift test --filter ApplicationTests
swift build --target Persistence
swift build --target Application
```

Rollback scope:

- Remove `MediaFileQueries.swift`.
- Revert `OpenMediaUseCase` to O(n) lookup.
- Revert any test changes.

Risks:

- `PersistedMediaFile` must not duplicate or conflict with `PersistedMediaFileSummary` which
  carries denormalized folder display data for detail views. Keep them as separate types.
- The `media_files` and `library_folders` schemas must be read first. Column names like
  `file_present`, `folder_available`, `is_available`, `root_path` may differ from the
  assumed names. **Write the query only after confirming actual column names.**
- The join may return NULL if a `library_folder` row is missing. The query must handle
  this: `LEFT JOIN` and coalesce `isAvailable` to false when folder data is absent.

---

## 4.5B File IDs and Playability in Detail DTO

Status: pending.

Goal: Add `mediaFileID: MediaFileID` and `isPlayable: Bool` to `LibraryFileSummary`
so AppUI can identify which file to open and whether to show a Play button — without
comparing `availabilityLabel` strings.

Files expected to change:

- `Sources/Application/LibraryItemDetail.swift`
- `Tests/ApplicationTests/LibraryItemDetailTests.swift`

Exact APIs:

```swift
public struct LibraryFileSummary: Sendable, Equatable {
    public let mediaFileID: MediaFileID   // ADDED
    public let isPlayable: Bool           // ADDED — true when file and folder are both available
    public let fileName: String
    public let fileExtension: String
    public let fileSizeLabel: String
    public let availabilityLabel: String  // kept for display text
}
```

Update `mapFile(_:)` to pass:
- `mediaFileID: file.id` from `PersistedMediaFileSummary.id`
- `isPlayable: file.isAvailable` from `PersistedMediaFileSummary.isAvailable`

`isPlayable` is the authoritative boolean for Play button visibility.
`availabilityLabel` remains the human-readable string ("available", "unavailable",
"folder unavailable").

AppUI Play button (wired in 4.5F) gates on `file.isPlayable`, never on
`file.availabilityLabel == "available"`.

Non-goals:

- No UI changes in this task (Play button wired in 4.5F).
- No playback integration.
- No metadata, scanner, or poster work.
- No migration.

Validation commands:

```sh
swift test --filter LibraryItemDetailTests
swift build --target Application
swift build --target AppUI
```

Rollback scope:

- Remove `mediaFileID` and `isPlayable` fields from `LibraryFileSummary`.
- Revert `mapFile` change.
- Revert test assertion updates.

Risks:

- `PersistedMediaFileSummary.isAvailable` already correctly accounts for both
  file presence and folder availability. The mapping is a simple pass-through.
- Tests must verify that `isPlayable` is `true` when `PersistedMediaFileSummary.isAvailable`
  is true, and `false` when false. No risk of string comparison drift.

---

## 4.5C PlaybackApplicationController Facade

Status: pending.

Goal: Create `MediaOpening` protocol so the controller depends on an abstraction,
not concrete `OpenMediaUseCase`. Create the Application-layer playback controller.
It consumes `PlaybackCoordinator.events`, fans them out to `PlaybackProgressCoordinator`
and a public `AsyncStream<PlaybackApplicationStatus>`, and exposes only
`open(mediaFileID:)` and `stop()`.

Files expected to change:

- `Sources/Application/MediaOpening.swift` (NEW — protocol + OpenMediaUseCase conformance)
- `Sources/Application/PlaybackApplicationController.swift` (NEW)
- `Tests/ApplicationTests/PlaybackApplicationControllerTests.swift` (NEW)

Exact APIs:

```swift
// Sources/Application/MediaOpening.swift (NEW)

public protocol MediaOpening: Sendable {
    func open(mediaFileID: MediaFileID) throws -> Application.PlayableFile
}

// Conformance — in same file or in Application.swift
extension OpenMediaUseCase: MediaOpening {}
```

```swift
// Sources/Application/PlaybackApplicationController.swift (NEW)
// In Application module — AppUI-safe (no Playback imports needed)

public struct PlaybackApplicationStatus: Sendable, Equatable {
    public let state: PlaybackApplicationState
    public let displayName: String?
    public let positionMS: Int
    public let durationMS: Int?

    public static let idle = PlaybackApplicationStatus(
        state: .idle, displayName: nil, positionMS: 0, durationMS: nil
    )
}

public enum PlaybackApplicationState: Sendable, Equatable {
    case idle
    case loading
    case ready
    case playing
    case paused
    case buffering
    case ended
    case failed(String)
}

public protocol PlaybackApplicationControlling: Sendable {
    /// Single-consumer stream for 4.5. The detail view model is the sole subscriber.
    /// If 4.6 requires multiple subscribers, add a fanout abstraction then.
    var statusStream: AsyncStream<PlaybackApplicationStatus> { get }
    func open(mediaFileID: MediaFileID) async
    func stop() async
}

public actor PlaybackApplicationController: PlaybackApplicationControlling {
    public nonisolated let statusStream: AsyncStream<PlaybackApplicationStatus>

    public init(
        coordinator: PlaybackCoordinator,
        progressCoordinator: PlaybackProgressCoordinator,
        mediaOpening: any MediaOpening
    )

    public func open(mediaFileID: MediaFileID) async
    public func stop() async
}
```

Internal behavior:

- `open(mediaFileID:)`:
  1. Stop current session if any.
  2. Resolve `Application.PlayableFile` via `mediaOpening.open(mediaFileID:)`.
  3. Map to `Playback.PlayableFile`.
  4. Call `progressCoordinator.startSession(...)`.
  5. `await coordinator.open(playableFile)`.
  6. On `.ready` event → auto-play (`await coordinator.play()`).
  7. Map error to status stream as `.failed(...)`.
- `stop()`:
  1. `await coordinator.stop()`.
  2. `try progressCoordinator.closeSession()`.
  3. Emit `.idle` status.
- Event loop (private task consuming `coordinator.events`):
  - Map `PlaybackEvent` → `PlaybackApplicationStatus`.
  - Yield to `statusStream` continuation.
  - Call `progressCoordinator.handle(event)`.
  - On `.playbackEnded` or `.stateChanged(.idle)` → close progress session.

Mapping `Application.PlayableFile` → `Playback.PlayableFile`:

```swift
private func mapToPlaybackPlayableFile(_ appFile: Application.PlayableFile) -> Playback.PlayableFile {
    Playback.PlayableFile(
        mediaItemID: appFile.mediaItemID,
        mediaFileID: appFile.mediaFileID,
        url: appFile.url,
        displayName: appFile.displayName,
        resumePositionMS: appFile.resumePositionMS
    )
}
```

Testing:

- Use `FakePlaybackBackend` (already in `Tests/PlaybackTests/` or extendable).
- Use a fake `MediaOpening` that returns a canned `Application.PlayableFile` (or throws).
  This replaces the previous approach of faking `OpenMediaUseCase` directly.
- Use a fake `PlaybackProgressStore` for progress coordinator isolation.
- Test state transitions: idle → loading → ready → playing on open.
- Test idle → loading → ready → playing → idle on open-then-stop.
- Test open failure (fake `MediaOpening` throws) maps to `.failed(errorString)` in status stream.
- Test that stop during loading cancels the session.
- Test that progress coordinator receives start/close session calls.
- Test that multiple opens stop the previous session before starting a new one.

Non-goals:

- No render surface.
- No AppUI changes.
- No CineMindApp wiring.
- No play/pause toggle (auto-play only; stop is the user action).
- No seek, no scrubber, no track menus.
- No persisted progress display.
- No status fanout abstraction — `statusStream` is single-consumer for 4.5.

Validation commands:

```sh
swift test --filter PlaybackApplicationControllerTests
swift test  # all existing tests continue passing
swift build --target Application
```

Rollback scope:

- Remove `MediaOpening.swift`.
- Remove `extension OpenMediaUseCase: MediaOpening`.
- Remove `PlaybackApplicationController.swift`.
- Remove `PlaybackApplicationControllerTests.swift`.

Risks:

- `PlaybackCoordinator.events` is single-consumer. The controller must be the sole
  consumer and fan out internally. This is the intended design.
- `statusStream` is single-consumer for 4.5. If a second consumer is needed in 4.6
  (e.g., a scrubber observing position), add an `AsyncStream` fanout helper then.
  Do not build it in 4.5.
- The mapping between `Application.PlayableFile` and `Playback.PlayableFile` must
  preserve all fields correctly. The only semantic difference is that `Application.PlayableFile`
  validates `url.isFileURL` in its init.
- Fake `MediaOpening` must simulate both success and failure paths for meaningful controller tests.
- Fake backend must simulate realistic event sequences (`loading` → `ready` →
  `playing` on play; position updates while playing).

---

## 4.5D LibMPVPlayback Production Embedded API

Status: pending.

Goal: Production-rename spike surface APIs. Add deferred embedded mode init
that creates the backend without a view, then attach the surface later when
the `NSOpenGLView` exists.

Files expected to change:

- `Sources/LibMPVPlayback/LibMPVPlayback.swift`
- `Sources/LibMPVPlayback/MPVOpenGLRenderAdapter.swift`
- `Sources/CineMindPlaybackSurfaceSpike/main.swift`

Exact APIs:

```swift
// LibMPVPlaybackBackend — renamed and new APIs

public final class LibMPVPlaybackBackend: PlaybackBackend, @unchecked Sendable {

    // Existing standalone init — unchanged
    convenience init() throws

    // Deferred embedded init — NEW
    // Creates MPVRuntime(mode: .embedded) but defers render adapter creation.
    @MainActor convenience init(embedded: Void) throws

    // Attach an NSOpenGLView and create the render adapter — NEW
    // Must be called once, on MainActor, after the view's OpenGL context exists.
    // Calls renderAdapter.prepare() internally.
    @MainActor func attachRenderSurface(openGLView: NSOpenGLView) async throws

    // Prepare the render surface (make GL context current, create mpv render context)
    // Typically called after attachRenderSurface or after view resize.
    @MainActor func prepareRenderSurface() async throws

    // Trigger render — called from mpv update callback path or on-demand
    @MainActor func renderSurfaceNow()

    // Renamed from spike — DEPRECATED, kept as convenience forwarders
    // (or removed outright if spike target is updated in this task)
    @MainActor func prepareSpikeRenderSurface() async throws   // → prepareRenderSurface()
    @MainActor func renderSpikeSurfaceNow()                    // → renderSurfaceNow()

    func shutdown() async
}
```

Deferred embedded init internals:

```swift
@MainActor convenience init(embedded: Void) throws {
    let runtime = MPVRuntime(mode: .embedded)
    self.init(runtime: runtime, renderAdapter: nil)  // renderAdapter = nil
    self.renderMode = .deferredEmbedded
}
```

`attachRenderSurface`:

```swift
@MainActor func attachRenderSurface(openGLView: NSOpenGLView) async throws {
    guard renderAdapter == nil else {
        throw LibMPVPlaybackError.renderSurfaceAlreadyAttached
    }
    let adapter = MPVOpenGLRenderAdapter(openGLView: openGLView, runtime: runtime)
    self.renderAdapter = adapter
    try await adapter.prepare()
}
```

`MPVOpenGLRenderAdapter` (production-rename from spike class name):

- Keep existing logic unchanged.
- Rename internal class only if needed for clarity; the spike naming is
  acceptable for now.

Spike target update:

- `CineMindPlaybackSurfaceSpike` switches from `init(spikeOpenGLView:)` to
  `init(embedded:)` + `attachRenderSurface(openGLView:)`.

Non-goals:

- No Metal render backend.
- No render API redesign beyond renaming and deferred attach.
- No AppUI or CineMindApp integration.
- No playback controller changes.

Validation commands:

```sh
swift build --target LibMPVPlayback
swift build --target CineMindPlaybackSurfaceSpike
swift build --target CineMindPlaybackShell
```

Rollback scope:

- Revert `LibMPVPlayback.swift` to spike-named APIs.
- Revert `CineMindPlaybackSurfaceSpike/main.swift`.

Risks:

- Deferred embedded init creates `MPVRuntime(mode: .embedded)` but does not
  set up the render adapter. The backend's `load`, `play`, `pause`, `stop`
  methods must still work (they touch only `MPVRuntime`, not the render adapter).
- `renderSurfaceNow()` must be a no-op (or assert) when called before
  `attachRenderSurface`.
- The existing standalone init must not be broken by the new init overload.
  The compiler distinguishes them by argument label: `init()` (standalone)
  vs `init(embedded:)` (deferred embedded).
- `shutdown()` must handle the case where the render adapter was never attached.
- `LibMPVPlayback` links `CLibMPV` which requires `libmpv.dylib` at build time
  and runtime. Previously only shell/spike targets had this requirement. Once
  `CineMindApp` depends on `LibMPVPlayback` (wired in 4.5E), the main app target
  will also require Homebrew mpv to link. This means `swift build --target CineMindApp`
  will fail on machines without mpv installed. Mitigation: the build gate in
  4.5E must document this; runtime availability can be probed via
  `MPVEmbeddedRenderAvailabilityProbe` before attempting playback.

---

## 4.5E CineMindApp Render Surface and Composition Wiring

Status: pending.

Goal: Create the `NSViewRepresentable` playback render surface in CineMindApp.
Wire all playback dependencies in the composition root. Add `Playback` and
`LibMPVPlayback` as CineMindApp target dependencies.

Files expected to change:

- `Sources/CineMindApp/PlaybackRenderSurfaceView.swift` (NEW)
- `Sources/CineMindApp/CineMindAppEnvironmentFactory.swift`
- `Sources/AppUI/AppShellEnvironment.swift`
- `Package.swift`

Exact APIs:

```swift
// CineMindApp/PlaybackRenderSurfaceView.swift (NEW)

/// Owns NSOpenGLView lifecycle and bridges it into SwiftUI.
/// Lives in CineMindApp because it imports LibMPVPlayback.
struct PlaybackRenderSurfaceView: NSViewRepresentable {
    let backend: LibMPVPlaybackBackend

    func makeNSView(context: Context) -> NSOpenGLView
    func updateNSView(_ nsView: NSOpenGLView, context: Context)
    static func dismantleNSView(_ nsView: NSOpenGLView, coordinator: Coordinator)

    @MainActor class Coordinator: NSObject {
        init(backend: LibMPVPlaybackBackend)
        func prepare(openGLView: NSOpenGLView) async
        func shutdown() async
    }
}
```

`makeNSView` behavior:

1. Create `NSOpenGLPixelFormat` with `[.doubleBuffer, .accelerated]`.
2. Create plain `NSOpenGLView` (no custom subclass needed).
3. Set `wantsBestResolutionOpenGLSurface = true` (retina).
4. Store coordinator reference via `NSViewRepresentable.makeCoordinator()`.
5. Schedule `coordinator.prepare(openGLView:)` on next run loop tick so the
   OpenGL context is fully realized.

`dismantleNSView` behavior:

1. Call `coordinator.shutdown()` to tear down render adapter.

Coordinator behavior:

```swift
@MainActor class Coordinator: NSObject {
    let backend: LibMPVPlaybackBackend
    private var hasPrepared = false

    func prepare(openGLView: NSOpenGLView) async {
        guard !hasPrepared else { return }
        hasPrepared = true
        do {
            try await backend.attachRenderSurface(openGLView: openGLView)
            try await backend.prepareRenderSurface()
        } catch {
            // Surface preparation failure is non-fatal for the view;
            // playback will show .failed status when the user tries to play.
        }
    }

    func shutdown() async {
        // Backend shutdown is owned by the controller, not the view.
        // The view only detaches its reference.
        hasPrepared = false
    }
}
```

AppShellEnvironment extension:

```swift
// Sources/AppUI/AppShellEnvironment.swift

public struct AppShellEnvironment {
    // ... existing fields ...
    public let playbackController: (any PlaybackApplicationControlling)?  // nil until 4.5
}
```

CineMindAppEnvironmentFactory wiring:

```swift
// New playback section (after existing scanner wiring)

let backend = try LibMPVPlaybackBackend(embedded: ())
let coordinator = PlaybackCoordinator(backend: backend)
let progressUseCase = PlaybackProgressUseCase(store: store)
let progressCoordinator = PlaybackProgressCoordinator(
    progressUseCase: progressUseCase
)
let openMedia = OpenMediaUseCase(store: store)  // conforms to MediaOpening
let playbackController = PlaybackApplicationController(
    coordinator: coordinator,
    progressCoordinator: progressCoordinator,
    mediaOpening: openMedia                    // passed as any MediaOpening
)
```

Package.swift — CineMindApp target:

```swift
.executableTarget(
    name: "CineMindApp",
    dependencies: ["AppUI", "Application", "Persistence", "Scanner", "Shared",
                   "Playback", "LibMPVPlayback"]   // ADDED two deps
),
```

Non-goals:

- No AppUI changes beyond `AppShellEnvironment.playbackController` field.
- No detail view changes (Play button + surface placement are 4.5F).
- No playback controls (play/pause/seek/scrubber/track menus are 4.6).
- No metadata, scanner, or poster work.

Validation commands:

```sh
swift build --target CineMindApp
swift build --target CineMindPlaybackSurfaceSpike   # still builds
swift build --target CineMindPlaybackShell           # still builds
rg "import.*(LibMPVPlayback|Playback)" Sources/AppUI   # must be empty
```

Rollback scope:

- Remove `PlaybackRenderSurfaceView.swift`.
- Remove playback wiring from `CineMindAppEnvironmentFactory`.
- Remove `playbackController` from `AppShellEnvironment`.
- Revert `Package.swift` CineMindApp dependencies.
- Revert factory changes.

Risks:

- **CineMindApp newly depends on `LibMPVPlayback` and `CLibMPV`.** Previously,
  only `CineMindPlaybackShell` and `CineMindPlaybackSurfaceSpike` had this dependency.
  `LibMPVPlayback` links `libmpv.dylib` via `CLibMPV` (Homebrew mpv), so
  `swift build --target CineMindApp` will now require `libmpv.dylib` at link time.
  On machines without `brew install mpv`, CineMindApp will fail to build.
  `MPVEmbeddedRenderAvailabilityProbe` can gate runtime availability, but build-time
  availability is now mandatory for the main target.
- `NSViewRepresentable` identity must be stable across SwiftUI redraws. Use
  `.id()` on the view if SwiftUI recreates it unexpectedly.
- The backend reference is shared between the controller (for command dispatch)
  and the render view (for surface management). Both hold strong references.
  The controller outlives the view; teardown is controller-driven.

---

## 4.5F AppUI Minimal Playback Integration

Status: pending.

Goal: Add Play button on available file rows. Add render surface placeholder
and playback status label to the detail page. Wire open/stop through the
Application controller protocol. Keep AppUI free of Playback/LibMPVPlayback
imports.

Files expected to change:

- `Sources/AppUI/LibraryItemDetailView.swift`
- `Sources/AppUI/LibraryItemDetailViewModel.swift` (extend, or new playback-aware VM)
- `Sources/CineMindApp/ContentView.swift` (or layout file that composes the detail view)

Exact APIs (in AppUI):

No new public protocols in AppUI. The detail view gains:

```swift
// LibraryItemDetailView — updated init
public struct LibraryItemDetailView: View {
    @ObservedObject var viewModel: LibraryItemDetailViewModel

    // Abstract playback surface from composition root.
    // AppUI does not know it contains NSOpenGLView/LibMPVPlayback internals.
    private let playbackSurface: AnyView?

    public init(
        viewModel: LibraryItemDetailViewModel,
        playbackSurface: AnyView? = nil
    )
}
```

LibraryItemDetailViewModel extensions or new view model:

```swift
@MainActor
public final class LibraryItemDetailViewModel: ObservableObject {
    // ... existing detail/state fields ...

    // Playback status for the status label — ADDED
    @Published public private(set) var playbackStatus: PlaybackApplicationStatus = .idle

    // Playback controller reference — SET by CineMindApp
    private var playbackController: (any PlaybackApplicationControlling)?
    private var statusTask: Task<Void, Never>?

    public func setPlaybackController(_ controller: any PlaybackApplicationControlling) {
        self.playbackController = controller
        observeStatus()
    }

    public func playFile(mediaFileID: MediaFileID) {
        guard let controller = playbackController else { return }
        Task {
            await controller.open(mediaFileID: mediaFileID)
        }
    }

    public func stopPlayback() {
        guard let controller = playbackController else { return }
        Task {
            await controller.stop()
        }
    }

    private func observeStatus() {
        statusTask?.cancel()
        guard let controller = playbackController else { return }
        statusTask = Task { @MainActor in
            for await status in controller.statusStream {
                playbackStatus = status
            }
        }
    }
}
```

Detail view layout changes (in `detailContent`):

1. If `playbackSurface != nil` AND `playbackStatus.state != .idle`:
   - Show render surface (16:9 aspect ratio placeholder until the surface
     is ready, then the actual surface).
   - Below it: status label (`playbackStatus.displayName` + state text).
   - Stop button (only when `state == .playing || .paused || .ready`).
2. In `filesBlock`:
   - Playable files (`file.isPlayable == true`) get a Play button next to the
     file name.
   - Tapping Play calls `viewModel.playFile(mediaFileID: file.mediaFileID)`.
   - Non-playable files show no button (unchanged from current layout).
   - **Never compare `file.availabilityLabel` to decide Play button visibility.**

Playback surface area layout:

```swift
// In detailContent, after poster row, before metadata:

if let playbackSurface, playbackStatus.state != .idle {
    VStack(spacing: 8) {
        playbackSurface
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 8))

        HStack {
            Circle()
                .fill(statusIndicatorColor)
                .frame(width: 8, height: 8)
            Text(playbackStatus.displayName ?? "")
                .font(.subheadline)
                .lineLimit(1)
            Spacer()
            Text(statusLabelText)
                .font(.caption)
                .foregroundColor(.secondary)
            if showStopButton {
                Button("Stop") {
                    viewModel.stopPlayback()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
```

CineMindApp wiring (in ContentView or equivalent):

```swift
// In the split view where detail is constructed:

LibraryItemDetailView(
    viewModel: detailViewModel,
    playbackSurface: playbackSurfaceView()
)

// Where playbackSurfaceView is:
func playbackSurfaceView() -> AnyView? {
    guard let backend = playbackBackend else { return nil }
    return AnyView(PlaybackRenderSurfaceView(backend: backend))
}
```

The `playbackBackend` is held by the composition root and passed to both
the controller (for commands) and the render view (for surface display).

Non-goals:

- No play/pause toggle (auto-play on open; Stop button only).
- No seek, scrubber, or track menus.
- No progress display.
- No metadata, scanner, or poster changes.
- No AppUI boundary growth beyond `playbackSurface: AnyView?`.
- No `AppShellEnvironment` growth beyond `playbackController`.

Validation commands:

```sh
swift build --target AppUI
swift build --target CineMindApp
swift test
rg "import.*(Playback|LibMPVPlayback|AppKit|Persistence|Metadata|Scanner)" Sources/AppUI  # must be empty
rg "mpv_" Sources/AppUI                                                                   # must be empty
rg "availabilityLabel\s*==\s*\"available\"" Sources/AppUI                                 # must be empty
```

Rollback scope:

- Revert detail view changes: remove playback surface slot, status label,
  Play button, Stop button.
- Revert view model playback extensions.
- Revert CineMindApp content view playback surface wiring.

Risks:

- `AnyView` erases the concrete type. SwiftUI identity may be lost across
  redraws, causing the `NSViewRepresentable` to be recreated. Mitigate by
  wrapping the `AnyView` content in a stable identity container (e.g., use
  `.id("playback-surface")` on the container).
- The status observation task must be cancelled on view model deinit or
  when `setPlaybackController` is called again with a new controller.
- Fast file selection changes may cause race conditions if the controller
  is still processing a previous `open`. The controller handles this
  internally (calls stop first, generation-guarded).
- Play button must not appear for non-playable files. The check uses
  `file.isPlayable` (a Boolean from Application mapping), never
  `file.availabilityLabel == "available"` (a display string).
- `isPlayable` is computed from `PersistedMediaFileSummary.isAvailable`
  which already accounts for both file presence and folder availability.
  No string comparison drift is possible.

---

## 4.5G Validation and Completion

Status: pending.

Goal: Run full automated validation. Perform manual GUI validation.
Fix any issues found. Ensure all architecture boundaries are intact.

Files expected to change:

- No planned source changes except scoped fixes from validation findings.

Exact APIs:

- No new APIs.

Manual validation checklist:

| # | Scenario | Expected result |
|---|---|---|
| 1 | Launch app with a library containing available media files | Detail view shows file rows with Play buttons |
| 2 | Tap Play on an available file | Render surface appears; video plays; status shows "Playing" |
| 3 | Tap Stop while playing | Surface clears; status shows "Idle" |
| 4 | Select a different item while playing | Previous session stops; surface clears; detail loads new item |
| 5 | Resize window while playing | Video scales correctly; no tearing or crash |
| 6 | Quit app while playing (Cmd+Q) | Clean exit; no crash; no hung mpv process |
| 7 | Close window while playing | No crash; no hung process |
| 8 | Tap Play on a file from an unavailable folder | Play button should not appear (or if it does, graceful error) |
| 9 | Item with no files | No file rows; no Play buttons |
| 10 | Relaunch app after playing a file | App starts normally |

Automated validation commands:

```sh
swift test                                                  # all tests pass
swift build --target AppUI                                   # builds
swift build --target CineMindApp                             # builds
swift build --target CineMindShell                           # builds
swift build --target CineMindPlaybackShell                   # builds
swift build --target CineMindPlaybackSurfaceSpike            # builds
swift build --target CineMindMetadataShell                   # builds
rg "import.*(Playback|LibMPVPlayback|AppKit|Persistence|Metadata|Scanner)" Sources/AppUI  # empty
rg "mpv_" Sources/AppUI                                      # empty (no raw mpv calls)
rg "availabilityLabel\s*==\s*\"available\"" Sources/AppUI     # empty (no string comparison)
```

Acceptance gate:

- All automated tests pass (including existing 286+ XCTest cases).
- All six shell/spike/app targets build.
- AppUI forbidden import grep returns no matches for: `Playback`, `LibMPVPlayback`, `AppKit`, `Persistence`, `Metadata`, `Scanner`.
- No raw `mpv_` calls in AppUI.
- No `availabilityLabel == "available"` string comparisons in AppUI.
- Play button visibility is gated on `LibraryFileSummary.isPlayable`.
- No metadata, scanner, or poster changes introduced.
- No migrations introduced.
- `git diff -- Sources/Persistence/Migrations.swift` is empty.

Non-goals:

- No metadata mutation actions.
- No full playback controls (play/pause, scrubber, seek, track menus).
- No progress display in UI.
- No resume position UX.
- No PiP, fullscreen, or alternate playback engine.
- No refactoring of existing detail view beyond the playback additions.

Rollback scope:

- Revert the smallest failed task first:
  - 4.5F (AppUI integration) → revert detail view changes
  - 4.5E (composition wiring) → revert factory + Package.swift
  - 4.5D (LibMPVPlayback API) → revert to spike APIs
  - 4.5C (controller) → remove controller + MediaOpening + tests
  - 4.5B (DTO) → remove `mediaFileID` and `isPlayable` from `LibraryFileSummary`
  - 4.5A (Persistence) → remove `fetchMediaFile(id:)`

Risks:

- Manual validation requires a library with seeded media files. Use the
  existing shell tools or add-folder UI to prepare test data.
- mpv.log may produce console noise. This is expected and not a 4.5 concern.
- `NSOpenGLView` deprecation warnings are expected from Xcode. These are
  informational; a Metal migration is a future concern.

---

# 13. Task Dependency Order

```text
4.5A (direct file lookup)  ──┐
4.5B (file IDs in DTO)    ──┤
                              ├──► 4.5C (controller facade) ──┐
4.5D (production embedded API) ──────────────────────────────┤
                                                              ├──► 4.5F (AppUI integration)
                                                              │
                                                       4.5E (render surface + wiring) ──┘
                                                                  │
                                                                  ▼
                                                             4.5G (validation)
```

4.5A, 4.5B, 4.5D can start in parallel.
4.5C depends on 4.5A + 4.5B.
4.5E depends on 4.5C + 4.5D.
4.5F depends on 4.5E.
4.5G depends on 4.5F.
