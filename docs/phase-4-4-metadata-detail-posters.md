# Phase 4.4 Metadata Detail and Posters

Canonical file: `docs/phase-4-4-metadata-detail-posters.md`

Phase 4.4 displays Phase 3 metadata and poster state in the app. It is read-only for metadata mutation workflows.

---

# 1. Goal

Show a useful detail page:

```text
selected media item
  -> metadata item/source/poster records
  -> poster image service
  -> metadata detail UI
```

---

# 2. Scope

Implement:

- Metadata detail display.
- Selected poster display.
- Poster placeholder states.
- Poster image loading from local cache paths.
- Metadata status labels.
- File availability and playback history summary in detail.
- Detail refresh after library browser selection changes.

Display fields:

- local title and type
- metadata title
- original title
- summary
- language
- release date or air date
- match source
- manual match lock state
- selected poster state
- files and availability
- last played/progress summary when available

---

# 3. Explicit Non-Goals

Do not implement:

- metadata refresh
- metadata rematch
- metadata field overrides
- poster selection
- remote poster downloading from UI
- TMDB direct calls from AppUI
- playback
- grid poster browser unless the detail image path is already stable

---

# 4. Architecture

AppUI owns:

- detail layout
- image placeholder presentation
- selection-driven loading state

Application owns:

- detail DTO composition
- selected poster decision
- metadata status mapping
- file/playback summary mapping

Persistence owns:

- metadata/poster/playback read APIs

Poster image loading:

- Use local `PosterAsset.localCachePath` when present.
- Decode images outside view body.
- Publish loaded images on the main actor.
- Keep image loader separate from metadata provider logic.

Metadata remains Persistence-free. AppUI must not import Metadata.

---

# 5. Expected Changes

Application:

- Expand item detail DTOs to include metadata and selected poster state.
- Add read use case for detail metadata/poster state.

Persistence:

- Add missing efficient read methods for selected poster and metadata source if needed.

AppUI:

- Replace detail placeholder with metadata detail page.
- Add poster image view with fixed aspect ratio.
- Add image loading state.

CineMindApp:

- Wire any new Application read service dependencies.

---

# 6. Image Loading Strategy

Use an app-level image loading service:

```text
PosterImageService
  -> load local file URL/path
  -> decode NSImage
  -> memory cache by local path + modified date if practical
  -> return loading/success/failure
```

Rules:

- No image blobs in SQLite.
- No remote URL construction in AppUI.
- Fixed poster aspect ratio to avoid layout jumps.
- Placeholder for missing, uncached, or failed images.
- Cancel previous image load when selection changes.

---

# 7. Risks

- Local cache path may point to a missing file.
- Large posters can increase memory pressure.
- Detail UI can accidentally duplicate metadata fallback rules.

Mitigation:

- Treat missing poster files as placeholder state.
- Add modest in-memory cache only after basic loading works.
- Keep fallback display rules in Application DTO mapping.

---

# 8. Validation

Automated:

- Application tests for metadata detail DTO mapping.
- Image loader tests for missing/local file paths if feasible without UI.
- Existing metadata and persistence tests remain passing.

Manual:

- Select item with no metadata.
- Select item with metadata but no poster.
- Select item with selected cached poster.
- Delete cached poster file and verify placeholder.
- Relaunch and verify metadata detail still displays.

---

# 9. Acceptance Criteria

Phase 4.4 is complete only if:

- Detail page displays metadata and poster state from Persistence via Application.
- Poster image loads from local cache path.
- Missing posters show placeholders.
- AppUI does not import Metadata or Persistence.
- No metadata mutation actions are present.
- Existing tests pass.

