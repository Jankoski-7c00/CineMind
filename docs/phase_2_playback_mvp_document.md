# Phase 2 Playback MVP

Canonical file: `docs/phase_2_playback_mvp_document.md`

## Phase 2: Playback MVP

This document defines the second development phase of CineMind.

Phase 2 introduces local video playback using libmpv while preserving the architectural constraints established in:

- `CLAUDE.md`
- `docs/PRODUCT_SCOPE.md`
- `docs/ARCHITECTURE.md`
- `docs/PHASE_1_LIBRARY_CORE.md`
- `docs/PHASE_1_COMPLETION_REPORT.md`

Phase 2 builds on the completed Phase 1 Library Core foundation.

---

# 1. Phase Goal

Build the minimal playback pipeline:

```text
Persisted MediaFile
  -> Application resolves playable file and resume state
  -> Playback opens a session
  -> libmpv plays local media
  -> Playback emits state/events
  -> Application throttles and persists progress
  -> reopen and resume
```

This phase is focused on:

- stable local playback
- strict libmpv integration boundaries
- architecture-correct Application orchestration
- playback state and event correctness
- durable playback history
- explicit failure recovery

This phase is not focused on:

- polished player UI
- metadata enrichment
- subtitle downloading
- AI features
- advanced playback workflows
- packaging a vendored mpv framework

---

# 2. Scope Definition

## Included

- Minimal `Application` module for playback use cases only.
- Pure Swift `Playback` module for state, commands, events, coordinator, sessions, and backend protocols.
- Concrete `LibMPVPlayback` adapter target for Homebrew/system libmpv.
- `OpenMediaUseCase` to resolve a persisted `MediaFile` into a `PlayableFile`.
- `PlaybackCoordinator` with one active session.
- `PlaybackSession`.
- `PlaybackState`, `PlaybackCommand`, `PlaybackEvent`, and `PlaybackError`.
- `PlaybackHistory` domain model.
- SQLite migration v2 for playback history.
- Playback progress persistence.
- Resume playback support for the same media file.
- Track enumeration and backend-level track selection commands.
- Minimal playback shell/harness.
- Fake-backend unit tests and persistence/application integration tests.
- Optional real-libmpv smoke validation when libmpv is installed.

---

## Explicitly Excluded

Do not implement:

- TMDB integration.
- Subtitle downloading/search.
- Local external subtitle discovery workflows.
- AI features.
- Recommendations.
- Playback queue.
- Next episode autoplay.
- Playlist management.
- PiP.
- AirPlay.
- HDR controls.
- OSC/player chrome polish.
- Plugin systems.
- IPC server.
- Remote playback.
- Streaming.
- Multi-window synchronization.
- Media server functionality.
- Mac App Store packaging work.
- Vendored `xcframework` packaging for mpv.
- Advanced subtitle rendering controls.
- Full SwiftUI/AppKit player chrome.

---

# 3. Architectural Direction

## New Targets

```text
Sources/
  Application/
  Playback/
  LibMPVPlayback/
  CineMindPlaybackShell/

Tests/
  ApplicationTests/
  PlaybackTests/
```

`Playback` is pure Swift and testable without libmpv.

`LibMPVPlayback` is the concrete C/libmpv adapter. It is part of the playback subsystem, but it must not be required by pure Playback tests.

---

## Dependency Rules

Allowed:

```text
CineMindPlaybackShell / future UI composition root
  -> Application
  -> Playback
  -> LibMPVPlayback

Application
  -> Domain
  -> Persistence
  -> Playback
  -> Shared

Playback
  -> Domain
  -> Shared

LibMPVPlayback
  -> Playback
  -> CLibMPV

Persistence
  -> Domain
  -> Shared
```

Forbidden:

```text
Domain -> Playback
Domain -> Persistence
Domain -> libmpv
Playback -> Persistence
Playback -> SQLite
Playback -> SwiftUI
Playback -> AppKit UI state
Persistence -> Playback internals
UI/Shell -> raw mpv APIs
UI/Shell -> SQLite queries outside Application/Persistence use cases
```

Composition root rule:

- The shell or future app target may wire concrete dependencies together.
- Application use cases should depend on explicit abstractions where practical.
- Playback must never resolve database records by itself.

---

# 4. Why Application Module Is Introduced

Phase 1 intentionally avoided an Application layer.

Phase 2 introduces a minimal Application module because playback requires orchestration between:

- persisted library records
- file path and availability resolution
- playback state
- resume state
- progress persistence
- future UI commands

The Application module must remain thin.

Responsibilities:

- resolve a `MediaFileID` into a playable local file.
- validate file and folder availability before playback.
- restore security-scoped access when bookmark data exists.
- fetch resume history.
- coordinate playback commands.
- subscribe to playback events.
- throttle and persist progress.
- map recoverable errors for shell/UI use.

The Application module must not become:

- a service locator.
- a UI state framework.
- a dumping ground.
- a place for raw mpv calls.

---

# 5. Open Media Contract

## Core Use Case

Phase 2 playback of library media must start through:

```text
OpenMediaUseCase.open(mediaFileID)
```

Application responsibilities:

1. Fetch `MediaFile`.
2. Fetch the owning `LibraryFolder`.
3. Reject unavailable media files.
4. Reject unavailable folders unless access can be restored.
5. Resolve the absolute local path from `LibraryFolder.rootPath + MediaFile.relativePath`.
6. Verify the file still exists.
7. Restore security-scoped bookmark access when `LibraryFolder.accessBookmark` is available.
8. Fetch `PlaybackHistory`.
9. Apply resume rules.
10. Build a `PlayableFile`.
11. Pass the `PlayableFile` to `PlaybackCoordinator`.

Playback must not:

- fetch `MediaFile` by ID.
- fetch `LibraryFolder`.
- inspect SQLite.
- restore bookmarks.
- decide library availability.

## PlayableFile

Playback receives a resolved value object:

```text
PlayableFile
- media_item_id
- media_file_id
- url
- display_name
- resume_position_ms
```

Rules:

- `url` must be a local file URL.
- `resume_position_ms` may be nil.
- Raw absolute paths must not be logged unless explicitly debug-enabled and redacted.
- Playback events should carry media IDs, not database rows.

---

# 6. Playback Architecture

## Core Components

### PlaybackCoordinator

Responsibilities:

- manage one active playback session.
- open a `PlayableFile`.
- issue playback commands.
- publish playback state/events.
- serialize backend callbacks into a predictable event stream.
- coordinate session lifecycle.
- close/destroy the backend cleanly.

Rules:

- Only one active session exists in Phase 2.
- Opening a new file stops the previous active session first.
- Backend callbacks must never write to SQLite directly.

---

### PlaybackSession

Represents a single playback lifecycle.

Contains:

- `PlayableFile`.
- current playback state.
- duration.
- current position.
- track metadata if available.
- selected track IDs if known.
- active playback backend.

It must not contain:

- raw mpv handles.
- SQLite connection or repositories.
- SwiftUI/AppKit presentation state.

---

### PlaybackBackend

Abstraction layer around playback engines.

Required because:

- tests must not depend on real mpv.
- `Playback` should remain buildable without Homebrew/system libmpv.
- playback state must not leak mpv internals.
- future embedding strategy should remain isolated.

Required operations:

```text
load(playableFile)
play()
pause()
seek(to_ms)
stop()
selectAudioTrack(track_id)
selectSubtitleTrack(track_id)
disableSubtitle()
shutdown()
```

Required event output:

```text
stateChanged
positionUpdated
durationUpdated
playbackEnded
playbackFailed
tracksDiscovered
```

---

### LibMPVPlayback Backend

Concrete playback backend implementation.

Responsibilities:

- create/destroy mpv handle.
- initialize player options.
- load a local file URL.
- issue mpv commands.
- observe mpv events/properties.
- map mpv events into `PlaybackEvent`.
- map mpv failures into `PlaybackError`.
- cleanup resources deterministically.

It must not:

- expose raw mpv handles outside `LibMPVPlayback`.
- import Persistence.
- import SwiftUI.
- own Application state.

---

# 7. Playback State Model

## PlaybackState

Required states:

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

`ready` means the file is loaded and duration/track metadata may be available, but playback is not currently running.

---

## State Transitions

Required transition behavior:

```text
idle -> loading              open
loading -> ready             backend loaded but not started
loading -> playing           backend loaded and auto-started
loading -> failed            load failure
ready -> playing             play
ready -> idle                stop
playing -> paused            pause
playing -> buffering         backend buffering event
playing -> ended             playback ended
playing -> failed            backend failure
playing -> idle              stop
paused -> playing            play
paused -> idle               stop
paused -> failed             backend failure
buffering -> playing         backend resumes
buffering -> paused          user pauses while buffering
buffering -> failed          backend failure
ended -> loading             open new media
ended -> idle                stop/close
failed -> loading            retry/open new media
failed -> idle               stop/close
```

Rules:

- Invalid commands must be ignored or reported as typed recoverable errors; they must not crash.
- `stop` should result in a final progress save request before the session returns to `idle`.
- `ended` is a terminal playback result for the current media unless a new file is opened.

---

## PlaybackCommand

Required commands:

```text
open(playable_file)
play
pause
seek(to_ms)
stop
select_audio_track(track_id)
select_subtitle_track(track_id)
disable_subtitle
```

Track selection commands are backend capabilities in Phase 2. A polished track-switching UI is deferred.

---

## PlaybackEvent

Required events:

```text
stateChanged(state)
positionUpdated(position_ms)
durationUpdated(duration_ms)
playbackEnded(final_position_ms, duration_ms)
playbackFailed(error)
tracksDiscovered(audio_tracks, subtitle_tracks)
```

Event ordering must be deterministic in tests with the fake backend.

---

## PlaybackError

Required categories:

```text
fileMissing
permissionDenied
unsupportedFormat
mpvUnavailable
mpvError
invalidState
unknown
```

Playback errors must be recoverable.

Playback failure must never crash the app.

---

# 8. libmpv Integration Strategy

## Selected Strategy

Phase 2 uses:

```text
Homebrew/system libmpv during development
```

Reasoning:

- fastest integration path.
- lowest Phase 2 complexity.
- avoids premature packaging work.
- enables rapid playback validation.

Vendored `xcframework` packaging is deferred.

---

## Build Contract

Target layout:

```text
Playback           pure Swift protocol/state/coordinator target
CLibMPV            system library target
LibMPVPlayback     concrete backend target depending on Playback + CLibMPV
```

SPM direction:

```text
.systemLibrary(
    name: "CLibMPV",
    pkgConfig: "mpv",
    providers: [
        .brew(["mpv"])
    ]
)
```

Implementation notes:

- Keep fake-backend tests independent from `LibMPVPlayback`.
- Do not make `PlaybackTests` require Homebrew mpv.
- Real mpv smoke validation may require `PKG_CONFIG_PATH` for Homebrew installations.
- Record the local `mpv --version` in manual validation notes when running smoke tests.
- If libmpv is unavailable, pure Swift tests must still run.

---

## Rendering Strategy

Phase 2 uses a minimal mpv-owned playback window for manual smoke validation.

Rules:

- No polished player chrome.
- No SwiftUI player UI.
- No AppKit UI state inside Playback.
- Future embedded rendering must be introduced through a separate design decision.
- If an embedded render target is needed later, the UI/harness owns the native view and Playback receives an opaque render target abstraction.

Manual validation must confirm visible video output, not only event logs.

---

## Hardware Decode

Phase 2 may enable basic hardware decode through standard mpv configuration.

No advanced GPU/HDR tuning is included in this phase.

---

# 9. Playback Persistence

## New Domain Model

### PlaybackHistory

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

- `position_ms` must be non-negative.
- `duration_ms` must be non-negative when known.
- `play_count` must be non-negative.
- One Phase 2 history row is stored per `(media_item_id, media_file_id)`.
- `media_item_id` preserves logical continuity.
- `media_file_id` keeps resume behavior file-specific.
- Playback history survives rescans.
- Playback history survives unavailable files.
- Playback history is never automatically deleted.

---

## SQLite Migration v2

Add table:

```text
playback_history
```

Required constraints/indexes:

```text
PRIMARY KEY(id)
FOREIGN KEY(media_item_id) REFERENCES media_items(id) ON DELETE RESTRICT
FOREIGN KEY(media_file_id) REFERENCES media_files(id) ON DELETE RESTRICT
UNIQUE(media_item_id, media_file_id)
INDEX(media_item_id)
INDEX(media_file_id)
INDEX(last_played_at)
```

Migration rules:

- New databases must apply v1 then v2.
- Existing Phase 1 databases must upgrade to v2 without data loss.
- Reopening an already migrated database must be idempotent.
- Read-only store open must not attempt migration.
- Migration failure must rollback partial v2 changes.

---

## Repository APIs

Required Persistence APIs:

```text
fetchPlaybackHistory(mediaItemID, mediaFileID)
fetchMostRecentPlaybackHistory(mediaItemID)
savePlaybackHistory(history)
savePlaybackProgress(mediaItemID, mediaFileID, positionMS, durationMS, completed, playedAt)
incrementPlaybackCount(mediaItemID, mediaFileID, playedAt)
```

Rules:

- Progress save should upsert into the unique `(media_item_id, media_file_id)` row.
- `play_count` increments once per successful playback session start, not on every progress save.
- Persistence should not decide whether a position is resumable; Application owns resume policy.

---

## Progress Persistence Rules

Selected behavior:

```text
save every 5 seconds while playing
save immediately on:
- pause
- seek completed
- stop
- playback end
- application/session close
```

Additional rules:

- Do not write if position did not materially change.
- Do not save progress for failed loads.
- On `stop`, save the latest known position unless the session already ended.
- On `playbackEnded`, save `completed = true`.
- SQLite writes must be coordinated by Application, not mpv callbacks.

---

## Completion Rules

Mark playback completed when:

- a reliable `playbackEnded` event is received, or
- duration is known and the saved position is near the end.

Near-end threshold:

```text
remaining <= 120 seconds OR progress >= 95%
```

Rules:

- Completed media should reopen from the beginning in Phase 2.
- Seeking near the end should not crash or delete history.
- Future smart resume prompts are deferred.

---

## Resume Rules

When reopening media:

```text
if no history:
  start from beginning
else if history.completed:
  start from beginning
else if position < 10 seconds:
  start from beginning
else if duration known and remaining <= 120 seconds:
  start from beginning
else:
  resume from saved position
```

Phase 2 does not require:

- smart resume prompts.
- cross-file resume.
- episode continuation logic.
- next episode logic.

---

# 10. Track Handling

## Selected Scope

Phase 2 includes:

```text
read audio/subtitle track list
expose track metadata through PlaybackEvent
support backend commands to select/disable tracks
```

Phase 2 excludes:

```text
track switching UI
subtitle downloads
subtitle management workflows
advanced subtitle styling
```

Track model:

```text
PlaybackTrack
- id
- type
- language
- title
- is_default
- is_selected
```

Rules:

- Track IDs are backend IDs and must be treated as opaque.
- Missing language/title is allowed.
- Track discovery failure must not block basic playback.

---

# 11. Minimal Playback Harness

## Selected Direction

Create:

```text
CineMindPlaybackShell
```

Separate from:

```text
CineMindShell
```

Reasoning:

- avoids polluting Phase 1 shell.
- isolates playback experiments.
- keeps library-core verification separate.

---

## Harness Modes

### Direct File Smoke Mode

```text
CineMindPlaybackShell --file /path/to/video.mkv
```

Responsibilities:

- open one local file URL.
- start playback.
- print state changes.
- print progress updates.
- validate libmpv can produce visible playback.

No playback history is persisted in this mode because there is no `media_file_id`.

---

### Library-Backed Mode

```text
CineMindPlaybackShell --db /path/to/cinemind.sqlite --media-file-id <id>
```

Responsibilities:

- load database through Application/Persistence.
- resolve `MediaFile` and `LibraryFolder`.
- start playback through `OpenMediaUseCase`.
- print state changes.
- print progress updates.
- persist playback history.
- reopen and verify resume behavior.

---

## Harness Restrictions

Allowed:

- one active file/session.
- keyboard or command-line driven play/pause/seek/stop if practical.
- printed diagnostics.
- mpv-owned window for smoke validation.

Forbidden:

- polished UI.
- media browser.
- playlist management.
- metadata display.
- AI workflows.
- raw SQLite queries in shell code.
- raw mpv calls outside `LibMPVPlayback`.

---

# 12. Persistence Coordination and Concurrency

## Selected Architecture

Playback must not directly own SQLite persistence logic.

Playback progress persistence must be coordinated through Application-level use cases.

Required pattern:

```text
PlaybackCoordinator
  -> PlaybackEvent stream
Application progress coordinator
  -> throttling / resume policy / completion policy
Persistence APIs
```

---

## Threading Rules

- mpv callbacks must be converted into Playback events before leaving `LibMPVPlayback`.
- mpv callbacks must not write SQLite.
- `PlaybackCoordinator` must serialize state transitions through an actor or a private serial queue.
- Application progress saving must run through one controlled execution path.
- UI state updates in future app targets must hop to `MainActor`.
- Long-running or blocking file/database operations must not run on the main thread.

---

## Event Stream Contract

Recommended event delivery:

```text
AsyncStream<PlaybackEvent>
```

Equivalent callback-based delivery is acceptable if it preserves:

- deterministic ordering.
- cancellation.
- explicit lifecycle shutdown.
- testability with fake backend.

---

# 13. Phase 2 Task Breakdown

## Task 1: Phase 2 Documentation

Update:

```text
docs/phase_2_playback_mvp_document.md
```

This document is the implementation contract for Phase 2.

---

## Task 2: Package Target Topology

Add:

```text
Sources/Application
Sources/Playback
Sources/LibMPVPlayback
Sources/CineMindPlaybackShell
Tests/ApplicationTests
Tests/PlaybackTests
```

Update `Package.swift` without breaking Phase 1 targets.

---

## Task 3: Playback Domain + Persistence v2

Implement:

- `PlaybackHistory` domain model.
- migration v2.
- playback history repository APIs.
- persistence tests for new DB, Phase 1 upgrade, idempotent reopen, read-only open, unique upsert, and rollback.

---

## Task 4: Application Playback Use Cases

Implement:

- `OpenMediaUseCase`.
- `PlaybackProgressCoordinator`.
- resume policy.
- completion policy.
- typed error mapping for missing file, unavailable folder, permission failure, and unsupported format.

---

## Task 5: Pure Playback Module

Implement:

- `PlayableFile`.
- `PlaybackCoordinator`.
- `PlaybackSession`.
- `PlaybackState`.
- `PlaybackCommand`.
- `PlaybackEvent`.
- `PlaybackError`.
- `PlaybackTrack`.
- `PlaybackBackend` protocol.
- fake backend tests first.

---

## Task 6: libmpv Backend

Implement:

```text
LibMPVPlayback
```

Responsibilities:

- initialize mpv.
- load media file.
- playback commands.
- track commands.
- observe events/properties.
- cleanup.

---

## Task 7: Playback Harness

Create:

```text
CineMindPlaybackShell
```

Capabilities:

- `--file` direct smoke playback.
- `--db --media-file-id` library-backed playback.
- print state changes.
- print progress updates.
- validate visible playback manually.
- validate playback history save/load in library-backed mode.

---

## Task 8: Progress Persistence Integration

Implement:

- throttled progress saving.
- pause/seek/stop/end save.
- play count update once per session.
- resume playback.
- application integration tests with fake clock and fake backend.

---

# 14. Test Plan

## PlaybackTests

Required:

- state transition table.
- fake backend behavior.
- command handling.
- event propagation and ordering.
- playback failure handling.
- one-active-session lifecycle.
- seek behavior.
- track discovery.
- track selection command forwarding.
- shutdown cleanup.

---

## PersistenceTests

Required:

- migration v2 creation on new database.
- migration from Phase 1 v1 database to v2.
- migration idempotency across reopen.
- migration rollback on failure.
- read-only store does not attempt migration.
- playback history persistence.
- playback history update/upsert.
- unique `(media_item_id, media_file_id)` behavior.
- playback history survives unavailable files.

---

## ApplicationTests

Required:

- `OpenMediaUseCase` resolves a playable file from `media_file_id`.
- unavailable media file is rejected.
- unavailable folder is rejected or mapped to recoverable error.
- missing resolved file is rejected.
- no-history resume starts at beginning.
- completed-history resume starts at beginning.
- valid in-progress history resumes.
- near-beginning history starts at beginning.
- near-end history starts at beginning.
- progress save throttling.
- immediate save on pause/seek/stop/end.
- play count increments once per session.

---

## LibMPV Smoke Validation

Optional automated/manual smoke validation:

```text
CINEMIND_RUN_MPV_SMOKE=1
```

Rules:

- Real mpv smoke tests may be skipped when libmpv is unavailable.
- Unit tests must not require large media fixtures.
- A tiny local sample video may be used for manual validation if available.
- Manual validation must record whether visible video output was confirmed.

---

## Manual Validation

Required:

```text
confirm Homebrew/system libmpv is available
play local file with --file
confirm visible video output
pause
seek
resume
stop
play library media with --db --media-file-id
close playback
reopen same media
verify progress restored
play to end
reopen same media
verify completed media starts from beginning
```

---

# 15. Explicitly Deferred

Deferred beyond Phase 2:

```text
TMDB
subtitle downloads
local subtitle discovery workflows
AI
playlist system
next episode autoplay
recommendation engine
advanced player UI
embedded SwiftUI/AppKit player chrome
streaming/server features
plugin runtime
real-time sync
vendored mpv xcframework packaging
Mac App Store packaging
```

---

# 16. Success Criteria

Phase 2 is complete only if:

```text
libmpv playback works with visible video output
Playback target builds and tests without requiring real mpv
LibMPVPlayback isolates raw mpv APIs
OpenMediaUseCase resolves persisted MediaFile safely
PlaybackCoordinator manages one active lifecycle
playback state transitions are tested
playback events flow correctly
playback progress persists
resume playback works
completed playback starts from beginning
track list is discovered when available
backend track selection commands exist
no UI coupling to libmpv
no Playback -> Persistence dependency
tests pass
no out-of-scope features added
```

---

# 17. Future Direction

After Phase 2, likely next phases:

```text
Phase 3 -> Metadata MVP (TMDB)
Phase 4 -> Search + FTS
Phase 5 -> Subtitle system
Phase 6 -> AI semantic search
```

Playback must remain stable and isolated before metadata/AI expansion.

---

# End of Phase 2
