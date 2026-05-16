# Phase 4.2 Library Browser

Canonical file: `docs/phase-4-2-library-browser.md`

Phase 4.2 adds read-only library browsing to the app shell created in Phase 4.1.

---

# 1. Goal

Display the persisted local library in a native macOS browser:

```text
Application read model
  -> Persistence summary/detail queries
  -> AppUI list/table
  -> selected item detail placeholder
```

This phase proves that the app can read real Phase 1-3 data without the UI directly accessing SQLite.

---

# 2. Scope

Implement:

- Application read models for library rows and item detail shell.
- Persistence read APIs needed by those Application read models.
- AppUI list/table browser.
- Sidebar section filtering for basic sections.
- Item selection.
- Detail placeholder fed by selected item identity.
- Empty, loading, and error states for browser content.

Initial browser sections:

- Library: all media items.
- Movies: media type movie.
- TV Episodes: media type episode.
- Recently Played: items with playback history ordered by recent activity.
- Needs Metadata: items without metadata item or source record.
- Folders: folder summary placeholder if full folder management is not ready.

---

# 3. Explicit Non-Goals

Do not implement:

- folder picker
- scanning
- security-scoped bookmarks
- poster image loading
- metadata refresh/rematch/override
- embedded playback
- playback controls
- FTS search
- grid view unless the table/list is already complete and stable
- schema migrations unless an index is demonstrably required for the read queries

---

# 4. Architecture

AppUI consumes Application DTOs only.

Recommended DTOs:

```text
LibrarySection
LibraryItemSummary
LibraryItemDetailShell
LibraryBrowserSnapshot
```

The DTOs should be display-oriented but not SwiftUI-specific.

Application owns:

- section query selection
- fallback display title logic
- availability summary mapping
- metadata presence status
- playback recency summary

Persistence owns:

- SQL joins
- efficient row fetching
- sorting/filtering primitives

AppUI owns:

- selection state
- loading/error presentation
- table/list rendering

---

# 5. Expected Changes

Application:

- Add library browser read use cases.
- Add store protocols for browser reads.
- Add DTOs for row and detail shell data.

Persistence:

- Add summary/detail read methods.
- Prefer joined queries over N+1 row assembly.
- Add direct `fetchMediaFile(id:)` only if needed for detail shell or future playback preparation.

AppUI:

- Replace placeholder content with a read-only browser.
- Keep detail view as a placeholder with selected item summary.

CineMindApp:

- Wire concrete store into the Application browser service.

---

# 6. View and Data Flow

```text
Sidebar selection
  -> LibraryBrowserViewModel.load(section)
  -> Application library browser use case
  -> Persistence read APIs
  -> LibraryBrowserSnapshot
  -> SwiftUI table/list
```

Selection flow:

```text
User selects row
  -> selected MediaItemID
  -> load detail shell
  -> detail placeholder displays title/type/files/metadata status summary
```

Use async view-model methods so database reads do not run directly in view body evaluation.

---

# 7. Risks

- Row data can trigger N+1 queries once metadata and playback state are included.
- Very large libraries can make naive full-list loading slow.
- AppUI could drift into Persistence imports for convenience.

Mitigation:

- Keep browser reads behind Application use cases.
- Start with bounded result sets or pagination-ready APIs even if the initial UI loads one page.
- Keep AppUI import checks part of review.

---

# 8. Validation

Automated:

- Unit tests for Application browser DTO mapping.
- Persistence tests for summary/detail queries.
- Existing tests remain passing.

Manual:

- Launch app against an empty database.
- Launch app against a scanned database.
- Switch each sidebar section.
- Select movie and episode rows.
- Confirm unavailable files show as unavailable, not deleted.
- Relaunch and confirm library still displays.

---

# 9. Acceptance Criteria

Phase 4.2 is complete only if:

- AppUI displays real persisted media items.
- AppUI does not import Persistence.
- Browser rows include media type, display title, year/episode marker, availability status, metadata presence, and playback recency when available.
- Selecting a row updates the detail placeholder.
- Empty/loading/error states are visible.
- Existing shell/spike targets still build.
- Existing tests pass.

