# Phase 4 Library UI MVP Roadmap

Canonical file: `docs/phase-4-library-ui-mvp.md`

Phase 4 introduces the first real CineMind desktop application layer. This document is the Phase 4 roadmap and index. It is not a single implementation task.

The seven executable subplans are:

1. [`Phase 4.1 App Shell`](phase-4-1-app-shell.md)
2. [`Phase 4.2 Library Browser`](phase-4-2-library-browser.md)
3. [`Phase 4.3 Folder Picker and Scan`](phase-4-3-folder-picker-scan.md)
4. [`Phase 4.4 Metadata Detail and Posters`](phase-4-4-metadata-detail-posters.md)
5. [`Phase 4.5 Embedded Playback Integration`](phase-4-5-embedded-playback-integration.md)
6. [`Phase 4.6 Playback Controls`](phase-4-6-playback-controls.md)
7. [`Phase 4.7 Metadata Actions`](phase-4-7-metadata-actions.md)

Phase 4 remains constrained by:

- `CLAUDE.md`
- `docs/product-scope.md`
- `docs/architecture.md`
- `docs/phase-1-library-core.md`
- `docs/phase-2-playback-mvp.md`
- `docs/phase-3-metadata-mvp.md`

---

# 1. Roadmap Goal

Build the first production-structured macOS UI layer on top of the completed Phase 1-3 foundations:

- Phase 1 Library Core: SQLite persistence, scanner models, library records, media items/files.
- Phase 2 Playback MVP: pure Playback coordinator, libmpv backend, playback progress persistence.
- Phase 3 Metadata MVP: TMDB metadata enrichment, metadata records, poster assets, poster cache.

Phase 4 must produce a usable local-first macOS library app without widening product scope.

---

# 2. Approved Architecture

The dependency direction remains:

```text
AppUI -> Application -> Domain + Persistence/Scanner/Playback/Metadata
```

Rules:

- AppUI must not call SQLite directly.
- AppUI must not call TMDB directly.
- AppUI must not call raw mpv APIs.
- Persistence remains network-free.
- Metadata remains Persistence-free.
- Playback core remains UI-free.
- PlaybackAVFoundation is the production playback backend for Phase 4.5R.
- LibMPVPlayback remains quarantined for experimental shell/spike work only.
- CineMindApp is the composition root that wires concrete modules.

Allowed AppUI dependencies:

```text
AppUI
  -> Application
  -> Domain
  -> Shared
```

Forbidden AppUI dependencies:

```text
AppUI -> Persistence
AppUI -> Scanner
AppUI -> Metadata
AppUI -> Playback
AppUI -> AVFoundation
AppUI -> AVKit
AppUI -> AppKit playback bridge code
AppUI -> LibMPVPlayback
```

Concrete composition root dependencies are introduced only as each subplan needs them:

```text
CineMindApp
  -> AppUI
  -> Application
  -> concrete infrastructure modules needed by the active phase
```

---

# 3. UI Technology Decision

Approved:

- SwiftUI for the app shell, sidebar, browser, detail screens, toolbar, commands, and presentation state.
- AVFoundation/AVKit for the initial embedded playback surface.
- `AVPlayerView` or `AVPlayerLayer` for display, bridged from SwiftUI at the composition root.
- If the bridge imports AVFoundation, AVKit, or AppKit, it belongs in CineMindApp, not in AppUI.

Do not rewrite the full app in AppKit.

Playback fallback rule:

- If SwiftUI lifecycle behavior destabilizes playback rendering, introduce an AppKit controller boundary around playback only.
- Keep the library browser and detail UI in SwiftUI.

---

# 4. Non-Goals

Phase 4 does not introduce:

- Electron, web UI, or cross-platform app stacks.
- SwiftData rewrite.
- CoreData migration.
- Server, sync, cloud, remote streaming, plugin, or local HTTP API architecture.
- A second playback engine.
- DRM or downloader behavior.
- Provider expansion beyond TMDB.
- A large background job framework.

---

# 5. Seven Subplans

## 4.1 App Shell

Prove the native app shell only:

```text
SwiftUI app launches
  -> database path resolves
  -> CineMindStore opens or creates
  -> NavigationSplitView shell renders
  -> loading/ready/error states work
```

No scanner, metadata, posters, playback, libmpv, or schema changes.

See: [`docs/phase-4-1-app-shell.md`](phase-4-1-app-shell.md)

## 4.2 Library Browser

Add read-only library browsing:

- Application read models.
- Persistence summary/detail queries.
- List/table UI.
- Selection and detail placeholder.

No folder picker, scanning, metadata actions, posters, or playback.

See: [`docs/phase-4-2-library-browser.md`](phase-4-2-library-browser.md)

## 4.3 Folder Picker and Scan

Add the first app-facing library mutation workflow:

- Folder picker.
- Security-scoped bookmark handling.
- Add folder workflow.
- Manual scan workflow.
- Unavailable-folder state.

No metadata actions or playback.

See: [`docs/phase-4-3-folder-picker-scan.md`](phase-4-3-folder-picker-scan.md)

## 4.4 Metadata Detail and Posters

Display Phase 3 metadata state:

- Metadata detail display.
- Selected poster display.
- Poster image loading service.
- Placeholder posters.
- Selected poster cache path usage.

No metadata mutation actions and no playback integration.

See: [`docs/phase-4-4-metadata-detail-posters.md`](phase-4-4-metadata-detail-posters.md)

## 4.5 Embedded Playback Integration

Bring AVFoundation-first embedded playback into the app:

- Production `PlaybackAVFoundation` backend.
- Composition-root SwiftUI wrapper around `AVPlayerView` or `AVPlayerLayer`.
- Playback application controller.
- Open selected media in embedded playback.
- AVFoundation-compatible local formats first, such as MP4, MOV, M4V, and system-supported codecs.

No full controls yet beyond the minimum needed to start and stop safely.
Broad MKV/ASS/non-system-codec compatibility is deferred to a future VLCKit
fallback phase.

See: [`docs/phase-4-5-embedded-playback-integration.md`](phase-4-5-embedded-playback-integration.md)

## 4.6 Playback Controls

Add usable player control:

- Play/pause/stop.
- Seek and scrubber.
- Progress persistence.
- Track menus where already supported.
- Teardown validation.

See: [`docs/phase-4-6-playback-controls.md`](phase-4-6-playback-controls.md)

## 4.7 Metadata Actions

Add metadata mutation workflows after metadata display is stable:

- Refresh.
- Rematch.
- Manual field overrides.
- Poster selection.

See: [`docs/phase-4-7-metadata-actions.md`](phase-4-7-metadata-actions.md)

---

# 6. Cross-Cutting Requirements

These requirements apply across the seven subplans. They are not an eighth subplan.

## Stability

- Every subplan must keep existing shell/spike targets building unless explicitly superseded by a later accepted phase.
- Every subplan must keep `swift test` passing.
- UI errors must be visible and recoverable where practical.
- Long-running work must not block the main actor.

## Performance

- Library queries should avoid obvious N+1 behavior once browser rows include metadata, posters, and playback status.
- Poster loading must use fixed dimensions and placeholders to prevent layout jumps.
- SQLite access should be serialized behind a narrow database access boundary once UI read workflows are introduced.
- Large-library optimization is applied incrementally when the relevant UI surface exists.

## Accessibility and Localization

- New user-facing controls should be named and keyboard-accessible when introduced.
- Localization scaffolding belongs near the first real user-facing screens, not in Phase 4.1 if it would distract from app-shell validation.

## Cancellation

- Scan, metadata refresh, poster loading, and playback observation must have explicit cancellation or teardown once those workflows exist.

---

# 7. Roadmap Acceptance

Phase 4 is complete only when all seven subplans are complete and manually validated together:

- App launches and persists its database.
- Library can be browsed after restart.
- Folders can be added and scanned from the app.
- Metadata and selected posters display.
- Embedded playback works in the app.
- Playback controls persist resume progress.
- Metadata refresh/rematch/override/poster selection are available.
- Existing architecture boundaries remain intact.

Phase 4.1 is the only immediate implementation phase. Later subplans must not be started until their prerequisites are complete.
