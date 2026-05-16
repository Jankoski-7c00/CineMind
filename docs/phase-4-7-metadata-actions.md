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

# 8. Validation

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

# 9. Acceptance Criteria

Phase 4.7 is complete only if:

- User can refresh metadata for selected item.
- User can search and manually rematch.
- User can set and clear supported overrides.
- User can select among persisted poster assets.
- Manual locks and override preservation remain intact.
- Local library browsing and playback work without TMDB configuration.
- AppUI does not import Metadata or Persistence.
- Existing tests pass.

