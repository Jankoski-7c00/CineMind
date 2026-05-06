# PHASE_2_PLAYBACK_MVP.md

## Phase 2: Playback MVP

This document defines the second development phase of CineMind.

Phase 2 introduces local video playback using libmpv while preserving the architectural constraints established in:

- CLAUDE.md
- docs/PRODUCT_SCOPE.md
- docs/ARCHITECTURE.md
- docs/PHASE_1_LIBRARY_CORE.md

Phase 2 builds on the completed Phase 1 Library Core foundation.

---

# 1. Phase Goal

Build the minimal playback pipeline:

```text
Persisted MediaFile
  → open playback session
  → libmpv playback
  → playback state/events
  → persist playback progress
  → reopen and resume
```

This phase is focused on:

- stable local playback
- architecture correctness
- playback state management
- durable playback history
- libmpv integration boundaries

This phase is NOT focused on:

- polished player UI
- metadata enrichment
- subtitle downloading
- AI features
- advanced playback workflows

---

# 2. Scope Definition

## Included

- Playback module
- Minimal Application module
- libmpv integration
- PlaybackCoordinator
- PlaybackSession
- Playback state/events
- PlaybackHistory domain model
- SQLite migration v2
- Playback progress persistence
- Resume playback support
- Minimal playback shell/harness
- Playback tests

---

## Explicitly Excluded

Do NOT implement:

- TMDB integration
- subtitle downloading/search
- AI features
- recommendations
- playback queue
- next episode autoplay
- playlist management
- PiP
- AirPlay
- HDR controls
- OSC/player chrome polish
- plugin systems
- IPC server
- remote playback
- streaming
- multi-window synchronization
- media server functionality
- Mac App Store packaging work
- advanced subtitle rendering controls

---

# 3. Architectural Direction

## New Modules

```text
Sources/
  Application/
  Playback/

Tests/
  PlaybackTests/
  ApplicationTests/
```

---

## Dependency Rules

Allowed:

```text
Shell/UI
  ↓
Application
  ↓
Playback
  ↓
Domain

Application
  ↓
Persistence
```

Forbidden:

```text
Domain -> Playback
Playback -> SwiftUI
Playback -> AppKit UI state
UI -> raw mpv APIs
Persistence -> Playback internals
```

---

# 4. Why Application Module Is Introduced

Phase 1 intentionally avoided an Application layer.

Phase 2 introduces a minimal Application module because playback requires orchestration between:

- Playback
- Persistence
- Domain
- future UI

The Application module must remain thin.

Responsibilities:

- playback use cases
- progress persistence coordination
- playback resume coordination
- shell/UI-safe orchestration

The Application module must NOT become:

- a service locator
- a UI state framework
- a dumping ground

---

# 5. Playback Architecture

## Core Components

### PlaybackCoordinator

Responsibilities:

- manage one active playback session
- open media files
- issue playback commands
- publish playback state/events
- coordinate lifecycle
- coordinate progress persistence callbacks

---

### PlaybackSession

Represents a single playback lifecycle.

Contains:

- MediaFile reference
- current playback state
- duration
- current position
- track metadata if available
- active playback backend

---

### PlaybackBackend

Abstraction layer around libmpv.

Required because:

- tests must not depend on real mpv
- future backend evolution should remain isolated
- playback state should not leak mpv internals

---

### LibMPVBackend

Concrete playback backend implementation.

Responsibilities:

- create/destroy mpv handle
- initialize player
- load file
- observe events
- map events into PlaybackEvent
- cleanup resources

---

# 6. Playback State Model

## PlaybackState

Required states:

```text
idle
loading
playing
paused
buffering
ended
failed
```

---

## PlaybackCommand

Required commands:

```text
open
play
pause
seek
stop
```

---

## PlaybackEvent

Required events:

```text
stateChanged
positionUpdated
durationUpdated
playbackEnded
playbackFailed
tracksDiscovered
```

---

## PlaybackError

Required categories:

```text
fileMissing
permissionDenied
unsupportedFormat
mpvError
unknown
```

Playback errors must be recoverable.

Playback failure must never crash the app.

---

# 7. libmpv Integration Strategy

## Selected Strategy

Phase 2 will use:

```text
Homebrew/system libmpv during development
```

Reasoning:

- fastest integration path
- lowest Phase 2 complexity
- avoids premature packaging work
- enables rapid playback validation

Vendored xcframework packaging is deferred.

---

## Integration Constraints

Do NOT:

- expose raw mpv handles outside Playback
- let UI call mpv directly
- let Domain import mpv headers
- couple playback logic to UI frameworks

---

## Hardware Decode

Phase 2 may enable basic hardware decode through standard mpv configuration.

No advanced GPU/HDR tuning is included in this phase.

---

# 8. Playback Persistence

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

---

## SQLite Migration v2

Add table:

```text
playback_history
```

Rules:

- playback history survives rescans
- playback history survives unavailable files
- playback history is never automatically deleted
- migration must remain idempotent

---

## Progress Persistence Rules

Selected behavior:

```text
save every 5 seconds
save immediately on:
- pause
- stop
- playback end
```

---

## Resume Rules

When reopening media:

```text
if progress exists and playback not completed:
  resume from last position
```

Phase 2 does NOT require:

- smart resume prompts
- cross-file resume
- episode continuation logic

---

# 9. Track Handling

## Selected Scope

Phase 2 includes:

```text
read audio/subtitle track list
```

Phase 2 excludes:

```text
track switching UI
subtitle downloads
subtitle management workflows
```

Track information may be exposed through PlaybackEvent only.

---

# 10. Minimal Playback Harness

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

- avoids polluting Phase 1 shell
- isolates playback experiments
- keeps library-core verification separate

---

## PlaybackShell Responsibilities

Allowed:

- open a local file
- start playback
- print playback state/events
- print progress updates
- validate playback history save/load

Forbidden:

- polished UI
- media browser
- playlist management
- metadata display
- AI workflows

---

# 11. Persistence Coordination

## Selected Architecture

Playback must not directly own SQLite persistence logic.

Playback progress persistence should be coordinated through Application-level use cases.

Recommended pattern:

```text
PlaybackCoordinator
  ↓ events
Application use case
  ↓
Persistence APIs
```

---

# 12. Phase 2 Task Breakdown

## Task 1: Phase 2 Documentation

Create:

```text
docs/PHASE_2_PLAYBACK_MVP.md
```

---

## Task 2: Application Module Skeleton

Add:

```text
Sources/Application
Tests/ApplicationTests
```

Responsibilities:

- playback orchestration only
- no UI framework state

---

## Task 3: Playback Domain + Persistence v2

Implement:

- PlaybackHistory domain model
- migration v2
- playback history repository APIs
- persistence tests

---

## Task 4: Playback Module Skeleton

Implement:

- PlaybackCoordinator
- PlaybackSession
- PlaybackState
- PlaybackCommand
- PlaybackEvent
- PlaybackError
- PlaybackBackend protocol

Use fake backend tests first.

---

## Task 5: libmpv Backend

Implement:

```text
LibMPVBackend
```

Responsibilities:

- initialize mpv
- load media file
- playback commands
- observe events
- cleanup

---

## Task 6: Playback Harness

Create:

```text
CineMindPlaybackShell
```

Capabilities:

- play one local media file
- print state changes
- print progress updates

No UI.

---

## Task 7: Playback Progress Persistence

Implement:

- throttled progress saving
- pause/end save
- resume playback
- persistence integration tests

---

# 13. Test Plan

## PlaybackTests

Required:

- playback state transitions
- fake backend behavior
- playback command handling
- event propagation
- playback failure handling
- progress throttling behavior

---

## PersistenceTests

Required:

- migration v2 creation
- playback history persistence
- playback history update
- playback history survives unavailable files

---

## ApplicationTests

Required:

- playback use-case orchestration
- progress save coordination
- resume behavior

---

## Manual Validation

Required:

```text
play local file
pause
seek
resume
close playback
reopen playback
verify progress restored
```

---

# 14. Explicitly Deferred

Deferred beyond Phase 2:

```text
TMDB
subtitle downloads
AI
playlist system
next episode autoplay
recommendation engine
advanced player UI
streaming/server features
plugin runtime
real-time sync
```

---

# 15. Success Criteria

Phase 2 is complete only if:

```text
✅ libmpv playback works
✅ PlaybackCoordinator manages lifecycle
✅ playback events flow correctly
✅ playback progress persists
✅ resume playback works
✅ no UI coupling to libmpv
✅ tests pass
✅ no out-of-scope features added
```

---

# 16. Future Direction

After Phase 2, likely next phases:

```text
Phase 3 → Metadata MVP (TMDB)
Phase 4 → Search + FTS
Phase 5 → Subtitle system
Phase 6 → AI semantic search
```

Playback must remain stable and isolated before metadata/AI expansion.

---

# End of Phase 2

