# Phase 4.6 Playback Controls

Canonical file: `docs/phase-4-6-playback-controls.md`

Phase 4.6 turns embedded playback into a usable MVP player by adding controls and durable progress behavior.

---

# 1. Goal

Add app-facing playback control:

```text
playback events
  -> playback view model
  -> controls and progress UI
  -> PlaybackCoordinator commands
  -> PlaybackProgressCoordinator persistence
```

---

# 2. Scope

Implement:

- play/pause
- stop
- seek forward/back
- scrubber
- elapsed and duration labels
- progress persistence
- resume behavior through existing policy
- playback error presentation
- audio/subtitle track menus where already supported by Playback
- teardown validation

---

# 3. Explicit Non-Goals

Do not implement:

- playlists
- queue
- next episode autoplay
- PiP
- AirPlay
- subtitle download/search
- advanced subtitle styling
- HDR controls
- fullscreen polish beyond basic window behavior
- second playback backend

---

# 4. Architecture

Application playback controller owns:

- active playback state
- one event consumer from `PlaybackCoordinator`
- progress coordinator integration
- command validation
- mapping playback errors to UI-safe messages

AppUI owns:

- controls layout
- disabled/enabled state presentation
- scrubber gesture state
- user intent dispatch

Playback owns:

- state machine
- backend protocol
- commands/events

Persistence owns:

- playback history storage through existing APIs

---

# 5. Expected Changes

Application:

- Extend playback controller with play/pause/stop/seek/track commands.
- Integrate `PlaybackProgressCoordinator`.
- Expose UI-facing playback snapshot.

AppUI:

- Add playback controls view outside the render surface.
- Add scrubber state that does not fight position updates while dragging.
- Add menus for audio/subtitle tracks if tracks are available.

Persistence:

- Reuse playback history APIs.
- Add only direct lookup improvements required by playback open/resume.

---

# 6. Control Behavior

Minimum command behavior:

- Ready/paused/buffering -> play enabled.
- Playing/buffering -> pause enabled.
- Active session -> stop enabled.
- Ready/playing/paused/buffering with duration or known position -> seek enabled.
- Failed/idle/loading -> controls disabled except stop when shutdown is needed.

Scrubber behavior:

- Display event-driven position.
- While user drags, show preview position.
- On commit, send seek and notify progress coordinator.
- Clamp target to `0...duration` when duration is known.

Progress behavior:

- Start progress session when media opens.
- Persist periodic progress through existing throttling.
- Persist seek and close events.
- Close progress session before backend shutdown.

---

# 7. Risks

- Event updates can fight scrubber dragging.
- Progress persistence can be lost if shutdown order is wrong.
- Track selection commands can be invalid in some playback states.

Mitigation:

- Keep transient scrubber drag state in AppUI.
- Keep progress session lifecycle in Application controller.
- Reuse PlaybackCoordinator state validation.

---

# 8. Validation

Automated:

- Application controller tests with fake playback backend.
- Progress persistence tests remain passing.
- Playback module tests remain passing.

Manual:

- Open media with no history.
- Play/pause.
- Seek forward/back.
- Drag scrubber.
- Stop and reopen.
- Quit while playing and verify progress saved.
- Reopen media and verify resume behavior.
- Switch audio/subtitle tracks when available.

---

# 9. Acceptance Criteria

Phase 4.6 is complete only if:

- User can control playback from the app.
- Progress persists and resume works after relaunch.
- Closing/quitting during playback does not lose expected progress.
- Playback controls are disabled in invalid states.
- AppUI does not call raw mpv.
- Existing tests pass.

