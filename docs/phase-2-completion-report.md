# Phase 2 Completion Report

## Phase Name

Phase 2 Playback MVP

## Implementation Summary

Phase 2 delivered the playback MVP while preserving the project dependency boundaries and avoiding UI scope creep.

- Application playback use cases for opening playable media and coordinating persisted playback progress.
- Playback pure Swift coordinator/state/event model with backend abstraction and fake-backend test coverage.
- LibMPVPlayback backend for concrete libmpv playback, event mapping, track discovery, duration, position, and state updates.
- CineMindPlaybackShell harness for direct-file smoke playback and library-backed playback validation.
- CineMindPlaybackSurfaceSpike embedded playback spike using an app-owned NSOpenGLView render surface.
- Playback progress persistence with resume policy, throttled position saves, completion handling, and once-per-session play count updates.

## Phase 2.1 Embedded Playback Surface Result

Phase 2.1 proved visible embedded playback with an app-owned macOS render surface.

- CineMindPlaybackSurfaceSpike renders visible video successfully inside an app-owned NSOpenGLView.
- Playback still flows through PlaybackCoordinator and the LibMPVPlayback backend abstraction.
- The previous CLI standalone visible-window limitation is resolved for embedded playback.
- NSOpenGLView/OpenGL is spike-only and is not the final polished player UI.
- Final player surface architecture remains deferred.

## Architecture Compliance

- Playback does not depend on Persistence.
- LibMPVPlayback isolates raw mpv symbols inside the backend implementation.
- Shell uses Application/Persistence use cases, not raw SQLite.
- Playback core remains AppKit-free; AppKit/OpenGL is limited to the Phase 2.1 surface spike.

## Scope Compliance

Phase 2 stayed within the Playback MVP scope. It does not include TMDB, subtitles, AI, playlist, streaming, plugin, media server, or polished UI work.

## Test Results

- `swift build` passed.
- `swift test` passed.
- Latest full suite: 95 tests passed.

## Manual Smoke Validation

Playback shell command:

```sh
swift run CineMindPlaybackShell --file Tests/Fixtures/Videos/Please_stop_buying_the_wrong_SSD.mp4
```

- Media loaded successfully.
- State reached playing.
- Duration detected: 07:41.
- Audio track discovered: 1.
- Subtitle tracks: 0.
- Position advanced.
- Audio playback worked.

Embedded surface command:

```sh
swift run CineMindPlaybackSurfaceSpike --file Tests/Fixtures/Videos/Please_stop_buying_the_wrong_SSD.mp4
```

- Minimal AppKit window appeared.
- Video rendered visibly inside the app-owned NSOpenGLView.
- State reached ready, then playing.
- Position advanced.
- Closing the window exited cleanly.

## Accepted Limitation: Standalone CLI Visible Video Window

CineMindPlaybackShell --file successfully loads media, emits playback events, discovers tracks, plays audio, and advances position, but Homebrew/libmpv does not create a visible standalone video window in the current macOS CLI environment, even with force-window=yes, video=auto, vo=gpu-next, and vo=gpu fallback.

This remains accepted for the CLI harness. Phase 2.1 resolves visible playback for embedded playback by rendering into an app-owned NSOpenGLView, while the final polished player surface architecture remains deferred.

## Known Issues

- Homebrew libmpv deployment-target warning remains development-only.
- CLI shell commands are line-based and may visually interleave with position output.
- OpenMediaUseCase media-file lookup is still temporary O(n).
- Resume threshold is duplicated defensively between Application policy and MPVRuntime.
- Standalone CLI video window is not reliable; use the embedded surface spike for visible playback validation.

## Deferred Follow-up

Phase 2.1 / Phase 3 prerequisite: Embedded Playback Surface Spike

Result:

- Minimal AppKit NSOpenGLView app-owned render surface validated.
- mpv render context path validated through LibMPVPlayback.
- No polished player chrome added.

Remaining deferred work:

- Final player surface architecture and polished UI.

## Verdict

- Phase 2 is complete, and Phase 2.1 resolves visible playback for embedded playback.
- Do not continue trying to fix standalone CLI window with more mpv options.
- Next step after checkpoint: final player surface architecture planning or Phase 3 Metadata MVP.
