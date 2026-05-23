# Phase 4.5R Embedded Playback Integration

Canonical file: `docs/phase-4-5-embedded-playback-integration.md`

## Supersession

The previous Phase 4.5 production plan for embedded libmpv/OpenGL playback is
superseded. The libmpv/OpenGL work remains useful as experimental and spike
evidence, but it is no longer the production playback path for CineMind.

Phase 4.5R switches production playback to an AVFoundation-first strategy:

```text
selected media file
  -> MediaOpening protocol (OpenMediaUseCase conforms)
  -> PlaybackApplicationController
  -> PlaybackCoordinator
  -> PlaybackAVFoundationBackend
  -> AVPlayer
  -> AVPlayerView or AVPlayerLayer bridge owned by CineMindApp
  -> abstract SwiftUI playback surface injected into AppUI
```

VLCKit may be added in a later phase for broader format and subtitle
compatibility. It is not implemented in 4.5R unless explicitly approved.

## Production Decision

Use AVFoundation and AVKit as the primary embedded playback backend for macOS.

Rationale:

- Direct Metal through libmpv is blocked because the audited libmpv route does
  not expose a public direct Metal render API suitable for CineMind.
- Vulkan/macvk is not accepted for embedded production playback because the
  audited route is external/mpv-managed window behavior, not an app-owned
  embedded surface.
- The OpenGL fallback is deprecated on macOS and is no longer preferred for
  production.
- AVFoundation is native to macOS and Swift, supports app-owned playback
  lifecycle through `AVPlayer`, and supports embedded display through
  `AVPlayerView` or `AVPlayerLayer`.
- AVKit provides a macOS-native `AVPlayerView` that can be bridged into SwiftUI
  with `NSViewRepresentable`; `AVPlayerLayer` remains an option if CineMind
  needs a more custom surface later.

## Scope

Implement in 4.5R:

- Documentation rewrite for AVFoundation-first production playback.
- AVFoundation capability spike for local file playback.
- `PlaybackAVFoundation` backend target after the spike proves the approach.
- Status, duration, position, end, and failure mapping from AVFoundation into
  the existing Playback events.
- CineMindApp-owned AVKit/AppKit bridge for the player surface.
- AppUI playback controls and surface placement through existing Application
  facade and abstract surface slot.
- Format policy for initial AVFoundation-supported playback.
- Validation of boundaries, source builds, and manual playback behavior.

Do not implement in 4.5R:

- VLCKit fallback.
- previous libmpv/OpenGL integration.
- direct Metal libmpv route.
- Vulkan/macvk integration.
- broad MKV/ASS compatibility.
- new AppUI imports of concrete playback, AppKit, AVFoundation, AVKit,
  Persistence, Metadata, Scanner, VLCKit, or LibMPVPlayback.
- metadata, scanner, poster, or persistence schema work.

## Preserve and Quarantine

Keep these backend-neutral pieces from the previous 4.5 work:

| Keep | Reason |
| --- | --- |
| `MediaOpening` | Application-level media file resolution remains correct. |
| `OpenMediaUseCase` | Resolves `mediaFileID` to a checked local file URL and resume position. |
| `PlaybackApplicationController` | Keeps AppUI talking to an Application facade instead of a backend. |
| `PlaybackApplicationControlling` | UI-safe playback command surface. |
| `PlaybackApplicationStatus` | UI-safe status DTO. |
| `PlaybackProgressCoordinator` | Backend-neutral progress persistence policy. |
| `LibraryFileSummary.mediaFileID` | Lets AppUI identify which file to open without Persistence. |
| `LibraryFileSummary.isPlayable` | Keep the field, but evolve its meaning as described below. |
| AppUI `AnyView` playback surface slot | Keeps AppUI backend-agnostic and lets CineMindApp inject the concrete surface. |

Quarantine these pieces as experimental or historical:

| Quarantine | Reason |
| --- | --- |
| `LibMPVPlayback` | No longer the production Phase 4.5 backend. Keep for shell/spike work until removal is approved. |
| `CLibMPV` | Keep only for experimental libmpv targets. Do not require it for `CineMindApp` production playback. |
| `MPVOpenGLRenderAdapter` | OpenGL render path is deprecated and no longer preferred. |
| `PlaybackOpenGLRenderSurfaceView` | App playback surface should move to AVKit/AVFoundation. |
| local mpv and submodule plans | Not part of 4.5R production strategy. |
| OpenGL fallback implementation sections | Historical evidence only; do not present as the current playback plan. |

## Architecture

Playback core remains UI-free. The production backend changes, but the UI-facing
architecture should remain stable:

```text
AppUI
  imports Application only for playback facade/status
  receives optional abstract playback surface

Application
  owns MediaOpening, PlaybackApplicationController, user-safe status mapping,
  and progress fanout

Playback
  owns PlaybackBackend, PlaybackCoordinator, PlaybackEvent, PlaybackState,
  and PlaybackError

PlaybackAVFoundation
  imports Playback, AVFoundation, AVKit as needed
  owns AVPlayer, AVPlayerItem, observation, and backend event mapping

CineMindApp
  composes Persistence, Application, PlaybackCoordinator, PlaybackAVFoundation,
  and the concrete AVPlayerView/AVPlayerLayer SwiftUI bridge
```

Target production flow:

```text
AppUI play button
  -> LibraryItemDetailViewModel.playFile(mediaFileID:)
  -> PlaybackApplicationControlling.open(mediaFileID:)
  -> MediaOpening.open(mediaFileID:)
  -> PlaybackCoordinator.open(Playback.PlayableFile)
  -> PlaybackAVFoundationBackend.load(playableFile:)
  -> AVPlayerItem/AVPlayer
```

Surface ownership:

- AppUI owns placement only.
- CineMindApp owns the concrete SwiftUI/AppKit bridge.
- The AVFoundation backend owns `AVPlayer` and exposes enough surface state for
  CineMindApp to attach `AVPlayerView` or `AVPlayerLayer`.
- AppUI must not import AVFoundation, AVKit, AppKit, VLCKit, LibMPVPlayback,
  Playback, Persistence, Metadata, or Scanner.

## AVFoundation Backend Notes

The AVFoundation backend should conform to the existing `PlaybackBackend` for
4.5R. Do not introduce a v2 playback abstraction until the AVFoundation spike
shows a concrete mismatch or the VLCKit fallback phase needs backend capability
selection.

Expected backend mapping:

- `load(playableFile:)`
  - Validate local file URL and readability.
  - Create `AVPlayerItem` for the URL.
  - Replace the current player item.
  - Observe item/player status.
  - Emit `.stateChanged(.loading)` through the coordinator path already used by
    `PlaybackCoordinator.open`.
- `AVPlayerItem.status == .readyToPlay`
  - Emit `.durationUpdated` when duration is finite.
  - Seek to resume position if present.
  - Emit `.stateChanged(.ready)`.
- `play()`
  - Call `AVPlayer.play()`.
  - Emit `.stateChanged(.playing)` based on rate/time-control observation.
- `pause()`
  - Call `AVPlayer.pause()`.
  - Emit `.stateChanged(.paused)`.
- `seek(toMS:)`
  - Seek with `CMTime`.
  - Emit `.positionUpdated` when the seek completes or the periodic observer
    reports the new time.
- periodic time observer
  - Emit `.positionUpdated`.
- end notification
  - Emit `.playbackEnded(finalPositionMS:durationMS:)`.
- item/player failure
  - Emit `.playbackFailed(.unsupportedFormat)` or `.playbackFailed(.unknown(...))`
    through a user-safe mapping in Application.

`AVPlayerView` is the preferred first implementation because it gives a native
macOS playback view and lowers surface risk. `AVPlayerLayer` is acceptable later
if CineMind needs fully custom controls or composition.

## Format Policy

Initial production playback supports AVFoundation-compatible local files first:

- MP4
- MOV
- M4V
- other files only when the system AVFoundation stack can play their container
  and codecs

Initially unsupported or deferred:

- MKV
- ASS/SSA-heavy subtitle workflows
- non-system codecs
- broad anime/media-server compatibility expectations

`LibraryFileSummary.isPlayable` must evolve from availability-only to:

```text
file and folder are available
AND the selected production playback policy considers the file supported
```

The initial policy can be conservative and extension-based for UI gating, with
the AVFoundation backend still reporting load failures safely. A later backend
capability policy should support AVFoundation plus VLCKit selection without
leaking backend details into AppUI.

## Task Breakdown

### 4.5R-A Documentation Rewrite

Goal: rewrite playback planning docs to make AVFoundation/AVKit the production
Phase 4.5R path and quarantine the previous libmpv/OpenGL plan.

Modify only:

- `docs/phase-4-5-embedded-playback-integration.md`
- `docs/phase-4-library-ui-mvp.md`
- `docs/architecture.md`
- `docs/product-scope.md`

Validation:

Run the validation commands requested for 4.5R-A and confirm that only docs
changed.

### 4.5R-B AVFoundation Capability Spike

Goal: prove local file playback with AVFoundation before creating the production
backend.

Scope:

- Spike `AVPlayer` local file playback for MP4/MOV/M4V.
- Spike embedded macOS display with `AVPlayerView` through
  `NSViewRepresentable`.
- Confirm status observation, duration, position, end, seek, and failure
  behavior.
- Confirm unsupported MKV or unsupported codec behavior maps cleanly to a
  failure.

Non-goals:

- No VLCKit.
- No AppUI backend imports.
- No Persistence changes.

### 4.5R-C PlaybackAVFoundation Backend and Status Mapping

Goal: add a production `PlaybackAVFoundation` target whose backend conforms to
the existing `PlaybackBackend`.

Scope:

- `PlaybackAVFoundationBackend`.
- `AVPlayer` and `AVPlayerItem` lifecycle.
- KVO/notification/time observer management.
- Mapping into `PlaybackEvent`.
- Unit tests with injectable observation seams where practical.

Acceptance:

- `Playback` remains pure Swift without Apple media framework imports.
- `Application` keeps using `PlaybackCoordinator`.
- `PlaybackApplicationController` remains useful without backend-specific
  branching.

### 4.5R-D CineMindApp and AppUI Integration

Goal: wire AVFoundation playback into the real app while preserving AppUI
boundaries.

Scope:

- CineMindApp constructs `PlaybackAVFoundationBackend`.
- CineMindApp owns the `AVPlayerView` or `AVPlayerLayer` bridge.
- CineMindApp injects the existing abstract playback surface into AppUI.
- AppUI uses `PlaybackApplicationControlling`, `PlaybackApplicationStatus`,
  `LibraryFileSummary.mediaFileID`, and `LibraryFileSummary.isPlayable`.
- Update playability mapping so `isPlayable` includes availability and
  production format policy.

Forbidden:

- No AppUI imports of AVFoundation, AVKit, AppKit, VLCKit, LibMPVPlayback,
  Playback, Persistence, Metadata, or Scanner.

### 4.5R-E Validation and Manual Pass

Goal: verify architecture, builds, and playback behavior.

Automated:

```sh
swift test
swift build --target AppUI
swift build --target CineMindApp
rg "import (AVFoundation|AVKit|AppKit|VLCKit|LibMPVPlayback|Playback|Persistence|Metadata|Scanner)" Sources/AppUI
rg "mpv_" Sources/AppUI
git diff -- Package.swift
git diff -- Sources/Persistence/Migrations.swift
```

Manual:

- MP4 local file plays embedded in the detail view.
- MOV or M4V local file plays if available.
- unsupported MKV or codec reports a user-safe failure.
- stop tears down playback without crashing.
- progress updates still persist through the Application progress coordinator.

### Future VLCKit Fallback Phase

Goal: add broader format and subtitle compatibility through VLCKit only after
AVFoundation-first playback is stable.

Future scope:

- Backend selection policy.
- Capability model for AVFoundation vs VLCKit.
- Packaging strategy.
- App signing and notarization review.
- Binary size and update-channel implications.
- Subtitle behavior review, especially ASS/SSA.

VLCKit remains deferred in 4.5R.

## Risks and Open Questions

- AVFoundation has container and codec limitations; MP4/MOV/M4V can still fail
  if codecs are not system-supported.
- Subtitle support is not equivalent to mpv/VLC; ASS/SSA-heavy workflows are
  deferred.
- `PlaybackApplicationController.statusStream` remains single-consumer.
- A future backend capability and selection policy is needed before VLCKit.
- VLCKit packaging, signing, notarization, binary size, and dependency
  management are deferred.
- The existing `PlaybackError` enum still has mpv-specific cases; clean that up
  only when code work begins and tests can protect the behavior.
- The current `LibraryFileSummary.isPlayable` implementation may still be
  availability-only until 4.5R-D changes source code.

## Boundary Requirements

- AppUI sees only Application playback facade types and an abstract SwiftUI
  surface slot.
- AppUI must not import AVFoundation, AVKit, AppKit, VLCKit, LibMPVPlayback,
  Playback, Persistence, Metadata, or Scanner.
- CineMindApp is the composition root for concrete playback backend and surface
  wiring.
- Playback backend implementations must not force Persistence or AppUI
  dependencies into `Playback`.
- No migration is required for 4.5R-A.
