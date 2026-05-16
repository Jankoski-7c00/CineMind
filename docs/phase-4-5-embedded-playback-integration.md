# Phase 4.5 Embedded Playback Integration

Canonical file: `docs/phase-4-5-embedded-playback-integration.md`

Phase 4.5 brings embedded libmpv playback into the real app while preserving Playback module purity.

---

# 1. Goal

Integrate the proven Phase 2.1 embedded playback spike into the app:

```text
selected media file
  -> OpenMediaUseCase
  -> PlaybackApplicationController
  -> PlaybackCoordinator
  -> LibMPVPlayback backend
  -> AppKit render surface wrapped in SwiftUI
```

---

# 2. Scope

Implement:

- Production playback render surface API in LibMPVPlayback.
- SwiftUI wrapper around an AppKit `NSOpenGLView`, owned outside AppUI if it imports concrete playback modules.
- `PlaybackApplicationController` in Application or AppUI-facing Application layer.
- Open selected media file from detail page.
- Embedded video display.
- Minimal start/stop lifecycle.
- Safe teardown on window close, selection change, and app quit.

This phase may expose only minimal UI commands needed to open and stop playback safely. Full controls are Phase 4.6.

---

# 3. Explicit Non-Goals

Do not implement:

- full playback control bar
- scrubber
- persisted progress UI
- audio/subtitle track menus
- playlists
- next episode autoplay
- PiP
- fullscreen polish
- alternate playback engine
- raw mpv calls from AppUI

---

# 4. Architecture

Playback core remains UI-free.

LibMPVPlayback owns:

- raw mpv symbols
- render context
- AppKit render adapter
- update callback handling

Application owns:

- media file resolution through `OpenMediaUseCase`
- playback controller orchestration
- event stream consumption/fanout policy
- user-facing playback errors

AppUI owns:

- playback surface placement as an abstract container
- open/stop user intent
- playback status presentation

CineMindApp wires:

- concrete `LibMPVPlaybackBackend`
- concrete store
- playback controller dependencies
- concrete SwiftUI/AppKit render wrapper if that wrapper imports `LibMPVPlayback`

---

# 5. Expected Changes

LibMPVPlayback:

- Generalize spike-only render surface naming into production naming.
- Preserve spike target compatibility or update spike minimally to use the production surface API.
- Keep raw mpv APIs internal.

Application:

- Add `PlaybackApplicationController` or equivalent facade.
- Map Application playable files to Playback playable files.
- Own one active playback session.

AppUI:

- Add playback area in detail page.
- Do not import `Playback` or `LibMPVPlayback`.

CineMindApp:

- Wire playback concrete dependencies.
- Add the concrete SwiftUI/AppKit bridge when it needs `LibMPVPlayback`.
- Inject or compose the concrete surface into the app shell without changing AppUI dependency rules.

Persistence:

- Add direct media-file lookup if still missing and needed to remove current O(n) open path.

---

# 6. Render Lifecycle Rules

Rules:

- Create render context only after the AppKit view and OpenGL context exist.
- Schedule rendering on the main actor from mpv update callbacks.
- Do not call normal mpv APIs from render callbacks.
- Guard scheduled renders after shutdown begins.
- Teardown order:
  1. cancel UI/event tasks
  2. stop active playback if needed
  3. shutdown coordinator/backend
  4. free render context
  5. release AppKit view references

`NSOpenGLView` must not host SwiftUI overlay subviews. Controls remain outside the render view.

---

# 7. Risks

- SwiftUI may recreate representable views unexpectedly.
- OpenGL and `NSOpenGLView` are deprecated.
- Render callbacks can race with teardown.
- Existing `PlaybackCoordinator.events` is not designed for arbitrary multi-consumer use.

Mitigation:

- Keep render view identity stable.
- Keep playback event consumption centralized in the playback application controller.
- Treat AppKit render surface as isolated implementation detail.

---

# 8. Validation

Automated:

- Existing Playback tests remain passing.
- Application tests for playable file mapping and controller state where fake backend is practical.

Manual:

- Open an available media file from detail.
- Video renders inside the app.
- Resize window.
- Move window between displays if available.
- Stop playback.
- Close window while playing.
- Quit app while playing.
- Confirm no crash or hung process.

---

# 9. Acceptance Criteria

Phase 4.5 is complete only if:

- Embedded video renders in the real app.
- Playback still flows through `PlaybackCoordinator`.
- AppUI does not import `LibMPVPlayback` or `Playback`.
- Raw mpv APIs remain isolated.
- Playback can be stopped and shut down cleanly.
- Existing shell/spike validation path remains usable.
- Existing tests pass.
