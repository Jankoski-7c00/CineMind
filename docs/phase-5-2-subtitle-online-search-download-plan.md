# Phase 5.2 Subtitle Online Search and Download Plan

Canonical plan file: `docs/phase-5-2-subtitle-online-search-download-plan.md`

Phase 5.2 adds the UI and Application plumbing for user-triggered online subtitle
search and download while preserving the local-first subtitle system from Phase
5.1. This phase must not require a concrete third-party provider unless provider
selection is explicitly approved before implementation.

---

# 1. Current Audit

Provider approval status:

- Approved concrete provider: no evidence found in the current repository docs or
  composition root.
- Existing provider-neutral types exist in `Sources/Subtitle/Subtitle.swift`:
  `SubtitleSearchQuery`, `SubtitleSearchResult`, `SubtitleDownloadResult`, and
  `SubtitleSearchProviding`.
- `docs/phase-5-subtitle-system.md` explicitly keeps a concrete third-party
  subtitle provider out of scope until provider choice is approved.
- Implementation default: provider-neutral plumbing plus unavailable state.
  Do not add OpenSubtitles, SubDB, Bazarr, or any other concrete service in this
  phase unless provider approval is given first.

Storage model status:

- `SubtitleAssetSource` already supports `.downloaded`.
- `subtitle_assets` already stores `source`, `library_folder_id`,
  `relative_path`, `media_file_id`, format, language, display name,
  availability, and timestamps.
- `CineMindStore.saveSubtitleAsset(_:)` and fetch methods already support
  source-aware downloaded records.
- Playback menu selection currently requires a usable folder root. In
  `PlaybackSubtitleAsset.isSelectable`, an external/downloaded subtitle is only
  selectable when it is available, parser-supported, and `folderRootPath` is not
  empty.
- Therefore downloaded subtitles must map to a real file under an existing
  library folder root, or the current playback selection path cannot use them.

Boundary status:

- `AppUI` currently imports `Application`, `Domain`, and `SwiftUI` for the
  detail view path.
- Current forbidden import checks for `Sources/AppUI` return no direct matches
  for `Subtitle`, `Persistence`, `Playback`, `PlaybackAVFoundation`,
  `AVFoundation`, `AVKit`, `AppKit`, `SQLite`, `CineMindStore`, or
  `SubtitleSearchProviding`.
- Phase 5.2 must keep that boundary: AppUI receives only Application-facing
  DTOs, protocols, status messages, and commands.

Migration decision:

- Migration required: no, if downloaded subtitles are saved as existing
  `subtitle_assets` rows and the downloaded files are stored below an existing
  library folder root.
- Migration required: maybe, only if the product rejects library-folder-backed
  subtitle files and instead requires App Support or another absolute storage
  root to be selectable by playback.

New Persistence API required: no, based on current discovery. Existing APIs cover
the expected write/read path:

- `fetchMediaFile(id:)` gives media item ID, library folder ID, relative path,
  folder availability, and folder root path.
- `fetchMediaItem(id:)` gives title/query context.
- `fetchSubtitleAsset(libraryFolderID:relativePath:source:)` can detect an
  existing downloaded record at a generated path.
- `saveSubtitleAsset(_:)` persists the downloaded record.
- `fetchPersistedSubtitleAssets(mediaFileID:)` feeds playback subtitle options.

Execution status:

- Discovery completed against the current worktree before code edits.
- Provider decision: no concrete provider is configured or approved.
- Implementation mode: provider-neutral Application/AppUI plumbing plus default
  unavailable state in the composition root.
- Storage decision: generated subtitle files are stored below the target library
  folder root so existing playback subtitle resolution can select them.
- Migration decision: no migration required unless this storage decision changes.
- Persistence API decision: no new Persistence API required unless a later test
  exposes an uncovered read/write need.

Implementation result:

- Provider-neutral download payloads are now content/metadata DTOs, not
  Persistence-owned `SubtitleAsset` rows.
- `LibrarySubtitleActionService` owns search/download orchestration, generated
  library-folder-backed file placement, downloaded `SubtitleAsset` persistence,
  path sanitization, and user-safe error mapping.
- `PlaybackApplicationController` exposes a narrow external-subtitle refresh
  capability so active playback can show newly downloaded subtitles without a
  restart.
- AppUI exposes an Advanced Subtitles surface using only Application DTOs and
  shows the default unavailable state when no provider is configured.
- CineMindApp composition keeps concrete provider integration disabled by
  default because no provider choice is approved.
- No new Persistence API or migration was added.

Verification result:

- `swift test --filter SubtitleTests`
- `swift test --filter LibrarySubtitleActionTests`
- `swift test --filter PlaybackApplicationControllerTests`
- `swift build --target AppUI`
- `swift build --target CineMindApp`
- `swift test --filter PersistenceRepositoryTests`
- `swift test`
- AppUI forbidden import/reference greps returned no matches.
- `git diff -- Sources/Persistence/Migrations.swift` returned no diff.

---

# 2. Goal

Implement Phase 5.2 so a user can open a media detail page, request online
subtitle search, view results, download a supported subtitle, and have the
downloaded subtitle become a local `SubtitleAsset(source: .downloaded)` that can
appear in the existing playback subtitle menu and render through the existing
external subtitle parser/overlay.

When no concrete provider is configured, the UI must show a clear unavailable
state. Local sidecar subtitles, embedded subtitles, scanning, metadata actions,
and playback must continue to work.

---

# 3. Non-Goals

- Do not implement a concrete third-party subtitle provider unless approved
  before implementation.
- Do not add automatic subtitle download.
- Do not add subtitle editing, timing correction, style controls, or ASS/SSA
  rendering.
- Do not add a local HTTP API, server workflow, plugin system, or downloader
  daemon.
- Do not move provider, persistence, playback backend, or subtitle parser types
  into AppUI.
- Do not rewrite the existing playback menu, overlay, scanner, or metadata
  action flows beyond the minimum needed for 5.2.
- Do not edit `Sources/Persistence/Migrations.swift` unless the storage decision
  changes and a true schema change becomes unavoidable.

---

# 4. Scope

Inspect before code:

- `docs/phase-5-subtitle-system.md`
- `Sources/Subtitle/Subtitle.swift`
- `Sources/Application/PlaybackSubtitleSupport.swift`
- `Sources/Application/PlaybackApplicationController.swift`
- `Sources/Application/LibraryMetadataActions.swift`
- `Sources/Application/Application.swift`
- `Sources/Persistence/SubtitleAssetQueries.swift`
- `Sources/Persistence/MediaFileQueries.swift`
- `Sources/Persistence/Migrations.swift`
- `Sources/AppUI/AppShellEnvironment.swift`
- `Sources/AppUI/LibraryItemDetailView.swift`
- `Sources/CineMindApp/CineMindAppEnvironmentFactory.swift`
- Existing Application, Subtitle, Persistence, and playback controller tests.

Likely implementation files:

- `Sources/Subtitle/Subtitle.swift`
- `Sources/Application/LibrarySubtitleActions.swift` (new)
- `Sources/Application/PlaybackApplicationController.swift`
- `Sources/Application/PlaybackSubtitleSupport.swift`
- `Sources/AppUI/AppShellEnvironment.swift`
- `Sources/AppUI/LibraryItemDetailView.swift`
- `Sources/CineMindApp/CineMindAppEnvironmentFactory.swift`
- `Tests/SubtitleTests/SubtitleTests.swift`
- `Tests/ApplicationTests/LibrarySubtitleActionTests.swift` (new)
- `Tests/ApplicationTests/PlaybackApplicationControllerTests.swift`
- `Tests/PersistenceTests/PersistenceRepositoryTests.swift` only for focused
  downloaded-asset coverage if needed.

Modify only if discovery proves necessary:

- `Sources/Persistence/SubtitleAssetQueries.swift`
- `Package.swift`
- Scanner code, only if generated downloaded-subtitle paths pollute scan results
  or are accidentally converted into `.external` assets.

Forbidden by default:

- `Sources/Persistence/Migrations.swift`
- Concrete network provider implementation
- AppUI imports of `Subtitle`, `Persistence`, `Playback`,
  `PlaybackAVFoundation`, `AVFoundation`, `AVKit`, `AppKit`, or concrete
  provider/client types.
- Broad UI redesign or unrelated playback control changes.

---

# 5. Architecture

Subtitle target owns provider-neutral contracts:

- Search query and result DTOs.
- Download payload metadata.
- Format classification.
- No local file-system placement policy.
- No database persistence.
- No AppUI types.

Application owns action orchestration:

- AppUI-safe facade, for example `LibrarySubtitleActionHandling`.
- Query construction from media item and media file context.
- Provider invocation.
- Downloaded file placement under an allowed library folder root.
- `SubtitleAsset(source: .downloaded)` creation and persistence.
- User-safe status and error message mapping.
- Optional playback subtitle option refresh after successful download.

Persistence owns existing storage:

- Continue using `subtitle_assets`.
- Continue using existing `saveSubtitleAsset` and source-aware fetch APIs.
- No schema change unless the file-location decision changes.

AppUI owns presentation only:

- Advanced Subtitles entry in the detail view.
- Search sheet/list.
- Download button and row-level status.
- Unavailable callout when no provider is configured.
- No concrete provider, Persistence, Subtitle parser, or playback backend import.

CineMindApp owns composition:

- Inject subtitle actions if a provider is configured.
- Return `nil` subtitle actions plus an unavailable message when provider
  selection/configuration is absent.
- If provider choice is unapproved, ship only the unavailable state and fake
  provider-backed tests.

---

# 6. Storage Plan

Downloaded subtitles need a concrete media file target, not only a media item.
The UI should resolve the target in this order:

1. Active playback file if it belongs to the displayed detail.
2. First playable local file in the detail.
3. Otherwise fail with a user-safe message such as "A playable local file is
   required before subtitles can be downloaded."

Recommended local path policy:

- Write downloaded subtitles under the media file's existing library folder root.
- Use a generated relative path outside the media file's own directory, for
  example:

```text
.cinemind/subtitles/<media-file-id>/<safe-result-id>.<srt|vtt>
```

Reasons:

- It satisfies the current `folderRootPath + relativePath` playback resolver.
- It avoids adding an absolute-path column or App Support root to
  `subtitle_assets`.
- It avoids placing generated downloads next to the movie file, where scanner
  sidecar matching could create a duplicate `.external` asset on the next scan.
- Scanner currently marks missing subtitle assets unavailable only for
  `source == .external`, so downloaded rows should survive rescans.

Required path safety:

- Folder root must be absolute and available.
- Generated relative path must not be absolute.
- Standardized resolved path must remain inside the folder root.
- Provider/result identifiers must be sanitized into filename-safe components.
- Existing downloaded record at the generated path should be reused or updated,
  not duplicated.
- File write should be atomic where practical.
- If the library folder is read-only or write fails, do not save the database
  record; surface a user-safe download failure.

Decision gate:

- If writing generated files under library folders is not acceptable, stop
  implementation. The existing model will not make App Support cached subtitles
  selectable without either schema changes or a new playback subtitle reader that
  can resolve non-library storage roots.

---

# 7. Task Breakdown

## Task 1: Provider-Neutral Contract Cleanup

Goal:

- Make provider contracts describe provider data, not local persistence rows.

Plan:

- Keep `SubtitleSearchProviding` provider-neutral.
- Replace or adapt the current `SubtitleDownloadResult(asset:)` shape so a
  provider returns subtitle content plus provider metadata, not a fully formed
  `SubtitleAsset`.
- Suggested provider download payload fields:
  - `resultID`
  - `suggestedFileName`
  - `languageCode`
  - `format`
  - subtitle text or bytes
- Keep supported MVP download formats to `.srt` and `.vtt` for parser/overlay
  use. Unsupported `.ass` and `.ssa` may appear in search results, but they
  should not be presented as usable overlay downloads unless a later renderer
  exists.

Tests:

- `SubtitleTests` for provider DTO equality/identity and supported format
  behavior if contract shape changes.

Stop conditions:

- Stop if preserving the existing provider ABI is required. In that case the
  provider must not be expected to manufacture local `SubtitleAsset` rows.

## Task 2: Application Subtitle Action Facade

Goal:

- Add an AppUI-safe action facade similar in shape to metadata actions.

Plan:

- Add `LibrarySubtitleActionHandling` in Application.
- Add AppUI-safe DTOs:
  - `LibrarySubtitleCandidate`
  - `LibrarySubtitleActionResult`
  - `LibrarySubtitleActionError`
- Add methods:

```swift
func searchSubtitles(mediaItemID: MediaItemID, mediaFileID: MediaFileID, languageCode: String?) async throws -> [LibrarySubtitleCandidate]
func downloadSubtitle(mediaItemID: MediaItemID, mediaFileID: MediaFileID, resultID: String) async throws -> LibrarySubtitleActionResult
```

- Add `LibrarySubtitleActionService` with injected:
  - narrow Application store protocol
  - optional provider-neutral `SubtitleSearchProviding`
  - downloaded subtitle file writer
  - clock
  - optional playback subtitle option refresher
- Store protocol should use existing Persistence methods through
  `CineMindStore`; no new Persistence API is expected.
- Search must validate that the media item and media file match.
- Download must:
  - validate target media file and folder availability
  - call provider for payload
  - validate/sanitize format and filename
  - write file under the generated library-folder-relative path
  - save `SubtitleAsset(source: .downloaded)`
  - return a user-safe success message
  - map provider, file-system, persistence, and unsupported-format errors to
    user-safe messages

Tests:

- Search maps fake provider results into AppUI-safe candidates.
- Search/download require matching media item and media file.
- Download writes a file under the library folder root and saves
  `SubtitleAsset(source: .downloaded)`.
- Existing downloaded asset at the generated path is updated instead of causing
  a unique constraint failure.
- Path traversal in provider result ID or filename is rejected/sanitized.
- Provider failure does not write a partial asset.
- File write failure does not save a database row.
- Unsupported format returns a user-safe error.

## Task 3: Playback Menu Refresh

Goal:

- Ensure a downloaded subtitle can appear in the current playback subtitle menu,
  not only after restarting playback.

Plan:

- Add a narrow Application-facing refresh capability, for example:

```swift
func reloadExternalSubtitleOptions(mediaFileID: MediaFileID) async
```

- Implement it in `PlaybackApplicationController`.
- If the active media file matches, reload external subtitle assets from
  `PlaybackSubtitleAssetReading`, merge them with embedded tracks, preserve any
  still-valid selected external subtitle, and emit current status.
- If the active media file does not match or playback is idle, make it a silent
  no-op.
- Have `LibrarySubtitleActionService` call this refresher after a successful
  download when available.

Tests:

- Active playback receives a new downloaded subtitle track after download refresh.
- Refresh is a no-op for inactive media files.
- Existing invalid-command no-op behavior remains unchanged.
- Existing external subtitle selection and disable behavior still pass.

## Task 4: AppUI Detail Experience

Goal:

- Add a discoverable, non-blocking subtitle action surface without leaking
  provider or Persistence types into AppUI.

Plan:

- Extend `AppShellEnvironment` with:
  - `subtitleActions: (any LibrarySubtitleActionHandling)?`
  - `subtitleActionsUnavailableMessage: String?`
- Extend `LibraryItemDetailViewModel` with:
  - subtitle action availability
  - subtitle search/download status
  - candidate list
  - per-result download state if needed
- Add an independent `Advanced Subtitles` disclosure block near
  `Advanced Metadata`.
- Add a search button that opens a subtitle result sheet.
- Sheet/list rows should show title, language, format, and download state.
- Download button should be disabled while its candidate is downloading and
  after success if the same result is already installed.
- When no provider is configured, show an understandable callout and keep all
  local/embedded subtitle and playback controls available.
- Use Application-provided messages only; AppUI should not switch on concrete
  provider errors.

Tests:

- Compile-time boundary checks through `swift build --target AppUI`.
- Add view-model focused tests only if existing AppUI test infrastructure is
  available; otherwise cover behavior through Application tests and build.

## Task 5: Composition Root

Goal:

- Wire unavailable state by default and provider-backed actions only when
  explicitly configured.

Plan:

- Add `makeSubtitleActions(...)` to `CineMindAppEnvironmentFactory`.
- If provider choice is not approved/configured, return:
  - `actions: nil`
  - unavailable message similar to "Subtitle search is not configured. Local and
    embedded subtitles are still available."
- If provider approval happens before implementation, add the concrete provider
  only in the composition root or provider-specific target, behind injectable
  HTTP/client abstractions and mocked tests.

Tests:

- Build `CineMindApp`.
- No live network provider test in automated verification.

## Task 6: Persistence Coverage

Goal:

- Prove existing `subtitle_assets` storage is sufficient for downloaded assets.

Plan:

- Prefer existing `saveSubtitleAsset`, `fetchSubtitleAsset(... source:
  .downloaded)`, and `fetchPersistedSubtitleAssets(mediaFileID:)`.
- Add focused Persistence test coverage only if Application tests cannot prove
  the downloaded-source path.
- Do not edit migrations.

Tests:

- Downloaded asset with `source == .downloaded` persists and is returned by
  playback subtitle fetch with folder root and usability.
- External missing-sidecar scan behavior remains source-limited to `.external`.

---

# 8. Discovery Commands Before Implementation

Run before code edits:

```sh
git status --short
git diff --stat
rg -n "SubtitleSearchProviding|SubtitleDownloadResult|SubtitleSearchResult|SubtitleAssetSource|saveSubtitleAsset|fetchPersistedSubtitleAssets" Sources Tests docs
rg -n "folderRootPath|isSelectable|resolvedSubtitleURL|reloadExternalSubtitle|selectSubtitleTrack|disableSubtitles" Sources/Application Tests/ApplicationTests
rg -n "metadataActions|LibraryMetadataActionHandling|Advanced Metadata|metadataCandidateSheet" Sources/AppUI Sources/Application Sources/CineMindApp Tests/ApplicationTests
rg -n "^import (Subtitle|Persistence|Playback|PlaybackAVFoundation|AVFoundation|AVKit|AppKit)" Sources/AppUI || true
rg -n "AVPlayer|AVFoundation|AVKit|SQLite|CineMindStore|SubtitleSearchProviding|SubtitleProvider|SubtitleAsset|SubtitleParser" Sources/AppUI || true
git diff -- Sources/Persistence/Migrations.swift
```

Questions to answer during implementation:

- Has a concrete subtitle provider been explicitly approved?
- Is writing generated subtitle files under the library folder root acceptable?
- Should search target the active playback file or the first playable file when
  both exist?
- Do unsupported provider formats appear in the result list as disabled rows or
  get filtered out?
- Is immediate playback-menu refresh required for inactive detail pages, or only
  for the active playback file?

---

# 9. Verification

Targeted:

```sh
swift test --filter SubtitleTests
swift test --filter PlaybackApplicationControllerTests
swift test --filter LibrarySubtitleActionTests
swift test --filter PersistenceRepositoryTests
```

Build:

```sh
swift build --target AppUI
swift build --target CineMindApp
```

Full:

```sh
swift test
```

Boundary checks:

```sh
rg -n "^import (Subtitle|Persistence|Playback|PlaybackAVFoundation|AVFoundation|AVKit|AppKit)" Sources/AppUI || true
rg -n "AVPlayer|AVFoundation|AVKit|SQLite|CineMindStore|SubtitleSearchProviding|SubtitleProvider|SubtitleAsset|SubtitleParser" Sources/AppUI || true
git diff -- Sources/Persistence/Migrations.swift
```

Manual smoke after implementation:

- Launch app with no subtitle provider configured.
- Open a media detail page and confirm Advanced Subtitles shows unavailable
  state without affecting playback or local/embedded subtitle menus.
- With a fake/local provider configuration if available in development, search
  subtitles for a playable file, download an SRT/VTT result, start or keep
  playback active, and verify the downloaded subtitle appears in the Subtitles
  menu.
- Select the downloaded subtitle and verify cue text renders through the
  existing overlay.
- Re-scan the folder and confirm downloaded subtitle rows are not marked
  unavailable as missing sidecars.

---

# 10. Acceptance Criteria

- Provider choice is explicitly handled:
  - unapproved provider means no concrete third-party integration
  - AppUI shows unavailable state
  - tests use fake providers only
- AppUI depends only on Application/Domain-safe subtitle action DTOs.
- Downloaded SRT/VTT subtitles are written to a safe local path under the target
  library folder root.
- Downloaded subtitles persist as `SubtitleAsset(source: .downloaded)`.
- Downloaded subtitles returned by `fetchPersistedSubtitleAssets(mediaFileID:)`
  have a non-empty `folderRootPath` when the library folder is available.
- Current playback subtitle menu can refresh to include a newly downloaded
  subtitle for the active media file.
- Existing local sidecar subtitles, embedded subtitles, playback controls,
  metadata actions, and scanner behavior continue to work.
- No migration is added unless the storage root decision changes.
- All targeted tests, AppUI build, CineMindApp build, full `swift test`, and
  AppUI forbidden import greps pass before phase completion.

---

# 11. Stop Conditions

Stop and report before implementation if:

- A concrete provider is requested but provider choice, auth model, rate-limit
  behavior, or terms-of-use constraints are not approved.
- Product direction rejects writing generated subtitle files under library
  folders.
- Existing `subtitle_assets` cannot represent the approved storage location.
- A migration becomes necessary.
- AppUI needs to import `Subtitle`, `Persistence`, playback backend, provider,
  or SQLite types to complete the UI.
- Downloaded subtitles cannot be mapped to a concrete media file.
- Immediate playback-menu refresh requires broad playback controller redesign.
- Automated tests reveal existing Phase 5 subtitle behavior is already failing
  before 5.2 code changes.

---

# 12. Risks

Storage location risk:

- This is the primary risk. The current playback resolver is library-folder
  based. App Support cached subtitles are not selectable without schema or
  playback-reader changes.

Provider boundary risk:

- The current `SubtitleDownloadResult(asset:)` shape is too local-storage-aware
  for a true third-party provider. Application should own `SubtitleAsset`
  creation.

Playback refresh risk:

- External subtitle options currently load during `open`. A post-download menu
  update needs a narrow refresh hook in Application.

Scanner interaction risk:

- Downloaded files placed next to media files could be discovered later as
  `.external` sidecars. Generated downloads should use a non-sidecar relative
  path, or scanner behavior must be adjusted.

File-system risk:

- Some library folders may be read-only, offline, or permission-restricted.
  Download failures must not create stale database rows.

Test coverage risk:

- AppUI may not have dedicated view tests. Application facade tests plus AppUI
  target build and forbidden import greps are required minimum coverage.
