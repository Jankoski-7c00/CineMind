# Phase 2 Completion Report

## Phase Name

Phase 2 Playback MVP

## Implementation Summary

Phase 2 delivered the playback MVP while preserving the project dependency boundaries and avoiding UI scope creep.

- Application playback use cases for opening playable media and coordinating persisted playback progress.
- Playback pure Swift coordinator/state/event model with backend abstraction and fake-backend test coverage.
- LibMPVPlayback backend for concrete libmpv playback, event mapping, track discovery, duration, position, and state updates.
- CineMindPlaybackShell harness for direct-file smoke playback and library-backed playback validation.
- Playback progress persistence with resume policy, throttled position saves, completion handling, and once-per-session play count updates.

## Architecture Compliance

- Playback does not depend on Persistence.
- LibMPVPlayback isolates raw mpv symbols inside the backend implementation.
- Shell uses Application/Persistence use cases, not raw SQLite.
- No SwiftUI/AppKit UI added.

## Scope Compliance

Phase 2 stayed within the Playback MVP scope. It does not include TMDB, subtitles, AI, playlist, streaming, plugin, media server, or polished UI work.

## Test Results

- `swift build` passed.
- `swift test` passed.
- Latest full suite: 95 tests passed.

## Manual Smoke Validation

Command:

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

## Accepted Limitation: Visible Video Window

CineMindPlaybackShell --file successfully loads media, emits playback events, discovers tracks, plays audio, and advances position, but Homebrew/libmpv does not create a visible standalone video window in the current macOS CLI environment, even with force-window=yes, video=auto, vo=gpu-next, and vo=gpu fallback.

This is accepted as a Phase 2 limitation. Future visible playback should use an app-owned AppKit/SwiftUI render surface instead of relying on a standalone libmpv-created window.

## Known Issues

- Homebrew libmpv deployment-target warning remains development-only.
- CLI shell commands are line-based and may visually interleave with position output.
- OpenMediaUseCase media-file lookup is still temporary O(n).
- Resume threshold is duplicated defensively between Application policy and MPVRuntime.
- Standalone CLI video window is not reliable.

## Deferred Follow-up

Phase 2.1 / Phase 3 prerequisite: Embedded Playback Surface Spike

Goal:

- Minimal AppKit NSView or SwiftUI wrapper.
- App-owned render surface.
- mpv render context.
- No polished player chrome yet.

## Verdict

- Phase 2 is complete with accepted visible-video limitation.
- Do not continue trying to fix standalone CLI window with more mpv options.
- Next step after checkpoint: plan Embedded Playback Surface Spike or Phase 3 Metadata MVP.
