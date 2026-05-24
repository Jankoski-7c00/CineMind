# Phase 4.7 Metadata Actions

Canonical file: `docs/phase-4-7-metadata-actions.md`

Phase 4.7 adds metadata mutation workflows after metadata display and posters are stable.

---

# 1. Goal

Expose Phase 3 metadata use cases in the app:

```text
metadata detail UI
  -> Application metadata use cases
  -> TMDB provider / poster cache where needed
  -> Persistence writes
  -> detail/browser refresh
```

---

# 2. Scope

Implement:

- refresh selected item
- search candidates
- manual rematch
- title/summary/language override
- clear override
- poster selection
- visible loading/error/success states
- detail/browser refresh after metadata writes

---

# 3. Explicit Non-Goals

Do not implement:

- provider expansion beyond TMDB
- cast/person/crew model
- season model
- episode stills
- metadata conflict comparison UI
- bulk metadata job framework
- automatic metadata refresh after every scan
- FTS over metadata fields
- AI metadata features

---

# 4. Architecture

AppUI owns:

- action buttons and sheets
- candidate selection UI
- override edit UI
- action loading/error state

Application owns:

- search
- auto/manual match
- refresh
- override preservation
- poster selection
- transaction boundaries
- UI-facing result mapping

Metadata owns:

- TMDB provider
- provider response mapping
- metadata ranking policy
- poster cache helper

Persistence owns:

- metadata/source/external ID/poster storage

CineMindApp wires:

- TMDB provider
- poster cache
- metadata Application services

---

# 5. Expected Changes

Application:

- Add UI-facing metadata action facade if existing use cases are too granular for AppUI.
- Map existing Phase 3 errors to UI-safe action errors.

AppUI:

- Add refresh action.
- Add candidate search/rematch sheet.
- Add override editing controls.
- Add poster picker from existing poster assets.

CineMindApp:

- Wire TMDB token/language configuration.
- Wire poster cache root.
- Provide missing-token state.

Persistence/Metadata:

- Reuse existing Phase 3 APIs.
- Add only read helpers needed to refresh the UI after writes.

---

# 6. Action Behavior

Refresh:

- Enabled for selected item.
- Uses existing source record when present.
- Falls back to automatic match behavior when no source exists, matching existing Phase 3 semantics.

Manual rematch:

- Search candidates from selected item.
- User chooses candidate.
- Use manual match lock.
- Refresh detail and row after write.

Overrides:

- Allow title, summary, and language override.
- Clear only the selected override lock.
- Preserve existing Phase 3 override semantics.

Poster selection:

- Show persisted poster assets.
- Select one poster per media item and poster asset type.
- Do not construct remote image URLs in AppUI.

Missing TMDB token:

- Display actionable unavailable state.
- Do not crash or block local library browsing/playback.

---

# 7. Risks

- Live TMDB errors can create confusing UI states.
- Metadata actions can overwrite user edits if Phase 3 locks are bypassed.
- Poster cache failures should not roll back useful metadata writes unless the existing use case requires it.

Mitigation:

- Use existing Phase 3 Application use cases.
- Keep override behavior centralized in Application.
- Treat provider errors as action errors, not app startup failures.

---

# 8. Task Breakdown and Execution Plan

Discovery result:

- Existing Phase 3 Application use cases already cover search, refresh, manual match, metadata overrides, override clearing, and poster selection.
- Existing Persistence APIs already cover the required metadata and poster reads/writes.
- New Persistence API required: no.
- Migration required: no. Phase 4.7 uses existing metadata, source record, external ID, and poster asset tables.

## 4.7A Application Metadata Action Facade

Status: implemented.

Goal:

- Add an AppUI-safe Application facade for metadata actions.
- Keep Metadata provider types, TMDB details, and Persistence details out of AppUI.
- Map Application/Metadata errors to concise UI-safe action errors.

Plan:

1. Add UI-facing action DTOs for metadata candidates, action success messages, and action errors.
2. Wrap the existing Phase 3 use cases:
   - `SearchMetadataCandidatesUseCase`
   - `RefreshMetadataUseCase`
   - `ManualMatchMetadataUseCase`
   - `SetMetadataOverrideUseCase`
   - `ClearMetadataOverrideUseCase`
   - `SelectPosterAssetUseCase`
3. Add focused Application tests proving facade mapping, manual rematch locks, override preservation, and poster selection refresh semantics.

Acceptance:

- AppUI can call metadata actions without importing Metadata or Persistence.
- No automated test calls live TMDB.

## 4.7B CineMindApp TMDB Wiring

Status: implemented.

Goal:

- Wire TMDB token/language configuration and poster cache root at the composition root.
- Missing TMDB configuration must not block local browsing, scanning, or playback.

Plan:

1. Read `CINEMIND_TMDB_READ_TOKEN` and `CINEMIND_TMDB_LANGUAGE`.
2. Provide metadata actions only when a non-empty token is configured.
3. Provide a visible unavailable message when actions are disabled.
4. Use an app-local poster cache root under Application Support.

Acceptance:

- App startup succeeds without TMDB configuration.
- Metadata action controls show an actionable unavailable state when no token is configured.

## 4.7C Detail View Metadata Actions

Status: implemented.

Goal:

- Add selected-item metadata action workflows to the detail surface.

Plan:

1. Add refresh action state with loading, success, and error display.
2. Add candidate search and manual rematch sheet.
3. Add title, summary, and language override editing controls.
4. Add per-field clear override actions.
5. Add poster selection actions for persisted poster assets.

Acceptance:

- User can refresh metadata, search/rematch, set/clear supported overrides, and select a persisted poster asset from the selected item detail view.
- AppUI still renders existing read-only metadata and poster state.

## 4.7D Detail and Browser Refresh

Status: implemented.

Goal:

- Refresh the selected detail and current browser row after metadata writes.

Plan:

1. Reload selected detail after every successful metadata write.
2. Notify the shell after successful metadata mutation.
3. Reload the current browser section so table metadata labels reflect persisted changes.

Acceptance:

- Detail metadata/poster state updates after each successful action.
- Browser rows refresh after metadata writes without changing the selected item.

## 4.7E Verification

Status: implemented.

Goal:

- Prove Phase 4.7 behavior without live TMDB calls in automated tests.

Plan:

1. Run targeted Application tests for metadata use cases/facade.
2. Build AppUI and CineMindApp to verify module wiring.
3. Run the full SwiftPM test suite.
4. Run boundary checks for AppUI imports.

Acceptance:

- `swift test` passes.
- `Sources/AppUI` has no Metadata or Persistence imports.

Current verification:

- `swift test --filter MetadataUseCaseTests`
- `swift build --target AppUI`
- `swift build --target CineMindApp`
- `swift test`
- `rg -n "^import (Metadata|Persistence)" Sources/AppUI`
- `rg -n "MetadataProvider|TMDB|fetchImages|fetchDetails|PosterCache|SQLite|CineMindStore" Sources/AppUI`
- `git diff -- Sources/Persistence/Migrations.swift`

# 9. Validation

Automated:

- Existing Application metadata use case tests remain passing.
- Add UI-facing facade tests if a facade is introduced.
- No automated tests should call live TMDB.

Manual:

- Missing token state.
- Search candidates for a movie.
- Manual rematch.
- Refresh existing matched item.
- Set and clear title override.
- Refresh after override and verify preservation.
- Select poster and verify detail/browser update.

---

# 10. Acceptance Criteria

Phase 4.7 is complete only if:

- User can refresh metadata for selected item.
- User can search and manually rematch.
- User can set and clear supported overrides.
- User can select among persisted poster assets.
- Manual locks and override preservation remain intact.
- Local library browsing and playback work without TMDB configuration.
- AppUI does not import Metadata or Persistence.
- Existing tests pass.
