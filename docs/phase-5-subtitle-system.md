# Phase 5 Subtitle System

Canonical file: `docs/phase-5-subtitle-system.md`

Phase 5 adds subtitle support without changing the local-first product shape or
leaking concrete subtitle, playback, or provider details into AppUI.

---

# 1. Goal

Add a subtitle system in two steps:

```text
5.1 local + embedded subtitles
  -> sidecar discovery
  -> subtitle persistence
  -> parser/cue timeline
  -> Application playback subtitle state
  -> AppUI overlay/track selection

5.2 online subtitle search/download
  -> provider contract
  -> configuration/unavailable state
  -> downloaded subtitle records
```

---

# 2. Scope

Implement in 5.1:

- External sidecar subtitle discovery for `.srt`, `.vtt`, `.ass`, and `.ssa`.
- SRT and WebVTT parsing into a cue timeline.
- Persistent external/downloaded subtitle records through SQLite schema v4.
- Scanner association of sidecar subtitles to the nearest media file or media item.
- Missing sidecar detection on later scans.
- Embedded subtitle discovery/selection where AVFoundation exposes legible tracks.
- Source-aware Application subtitle options.
- External subtitle cue rendering over the existing playback surface.

Implement in 5.2:

- Provider-neutral online subtitle search and download contracts.
- Composition-root unavailable state when no provider is configured.
- Downloaded subtitle records using the same subtitle persistence surface.

---

# 3. Explicit Non-Goals

Do not implement:

- VLCKit or a second production playback backend.
- Backend auto-selection or broad MKV/non-system-codec compatibility.
- ASS/SSA rendering in the external overlay.
- Subtitle editing or timing adjustment UI.
- AI subtitle summarization.
- Streaming/server subtitle APIs.
- Automatic online subtitle download.
- A concrete third-party subtitle provider before provider choice is approved.

---

# 4. Architecture

AppUI owns:

- overlay placement
- menu rendering
- user intent dispatch

Application owns:

- source-aware subtitle options
- active external subtitle cue state
- external subtitle file loading/parsing orchestration
- user-safe no-op behavior for invalid subtitle commands

Subtitle owns:

- sidecar matching
- language inference
- SRT/WebVTT parsing
- provider contracts

Persistence owns:

- `subtitle_assets`
- subtitle asset reads/writes
- migration v4

CineMindApp owns:

- concrete playback backend
- concrete subtitle provider configuration when 5.2 is implemented
- unavailable messages

---

# 5. Data Model

`subtitle_assets` stores local and downloaded subtitle files:

- stable subtitle asset ID
- media item ID
- optional media file ID
- optional library folder ID
- relative path
- file name and extension
- format (`srt`, `vtt`, `ass`, `ssa`)
- optional language code
- optional display name
- source (`external`, `downloaded`)
- availability and timestamps

Embedded runtime tracks remain playback events and are not persisted in 5.1.

Migration required: yes, schema v4.

---

# 6. Behavior

Scanner:

- Media-file counts remain media-file counts; subtitle files are tracked by
  subtitle-specific counters.
- Sidecars are matched by same directory and media basename.
- `Movie.en.srt` infers language `en`; `Movie.zh-Hans.vtt` infers `zh-Hans`.
- `.ass` and `.ssa` are discovered but treated as unsupported for external
  overlay selection.
- Subtitle scan failures must not fail the library scan.

Playback:

- Embedded subtitle options forward to the playback backend.
- External SRT/WebVTT options are parsed and rendered by AppUI over the
  playback surface.
- Selecting external subtitles disables embedded subtitles when needed.
- Disabling subtitles clears embedded and external subtitle selection.
- Invalid state or missing-track subtitle commands are silent no-ops.

Online search:

- User-triggered only.
- Non-blocking and cancellable.
- Provider errors do not block playback, scanning, metadata display, or local
  subtitle use.
- Downloaded subtitles become local `subtitle_assets`.

---

# 7. Verification

Automated:

```sh
swift test --filter SubtitleTests
swift test --filter PersistenceRepositoryTests
swift test --filter ScannerTests
swift test --filter PlaybackApplicationControllerTests
swift test --filter PlaybackAVFoundationTests
swift build --target AppUI
swift build --target CineMindApp
swift test
```

Architecture checks:

```sh
rg -n "^import (Subtitle|Persistence|Playback|PlaybackAVFoundation|AVFoundation|AVKit|AppKit)" Sources/AppUI
rg -n "AVPlayer|AVFoundation|AVKit|SQLite|CineMindStore|SubtitleSearchProviding" Sources/AppUI
git diff -- Sources/Persistence/Migrations.swift
```

Manual:

- Scan a folder containing media plus `.en.srt`.
- Play the media and select the external subtitle.
- Verify cue text appears and changes with playback position.
- Disable subtitles and verify overlay clears.
- Open media with embedded legible tracks if available and switch tracks.
- Re-scan after removing a sidecar and verify it becomes unavailable.

---

# 8. Acceptance Criteria

Phase 5 is complete only if:

- Local sidecar subtitles persist and survive restart.
- SRT and WebVTT external subtitles can render over playback.
- Unsupported ASS/SSA sidecars are discovered without breaking scan/playback.
- Embedded AVFoundation legible tracks appear when available and can be selected.
- AppUI remains free of concrete subtitle, persistence, and playback backend imports.
- No online provider is required for local/embedded subtitle use.
- Existing tests pass.
