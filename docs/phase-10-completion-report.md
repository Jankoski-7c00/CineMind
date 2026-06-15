# Phase 10 Native macOS UI Redesign Completion Report

Completion date: 2026-06-15

## Completion Verdict

Phase 10 is source-complete and passes the automated build, test, migration,
and architecture boundary audit.

The real foreground `.app` smoke verified the redesigned library shell,
artwork-led grid, native toolbar and search placement, adaptive light
appearance, command availability, and the complete native Inspector
presentation. Release-level manual coverage remains pending for the scenarios
listed in this report.

## Implemented Scope

- Reorganized the main window around the existing native
  `NavigationSplitView`.
- Moved global library actions, search, presentation controls, and Inspector
  access into the native toolbar and application commands.
- Added artwork-led grid, compact list, and folder-table browser
  presentations.
- Extended the existing media summary projection with selected poster cache
  paths without adding a new repository API or migration.
- Split browser and detail responsibilities into focused AppUI files and view
  models.
- Reduced the main detail surface to artwork, overview, playback, and primary
  actions.
- Moved curation, files, subtitles, and advanced metadata into a native
  Inspector.
- Added an Inspector snapshot boundary so the detail column and Inspector do
  not independently observe the same detail model during AppKit layout.
- Added library menu commands, keyboard shortcuts, contextual Inspector
  actions, icon help text, and focused command-routing tests.
- Removed the obsolete custom Liquid Glass components, forced dark
  presentation, fixed-white typography helpers, and decorative detail chrome.
- Added a reproducible real `.app` build-and-run script and Codex run action.

## Subphase Audit

| Subphase | Result | Evidence |
| --- | --- | --- |
| 10.1 View and state decomposition | Complete | Browser/detail files and view models are split into focused AppUI ownership. |
| 10.2 Native shell, toolbar, and search | Complete | Native sidebar, `.searchable`, toolbar actions, focused scene commands, and keyboard shortcuts build and run. |
| 10.3 Browser presentation modes | Complete | Artwork grid, compact list, and folder table are implemented. |
| 10.4 Poster summary projection | Complete | Existing summary projection exposes selected poster cache path; no new Persistence API or migration. |
| 10.5 Detail and Inspector | Complete | Main detail is focused; native Inspector contains Info, Organize, Files, Subtitles, and Advanced Metadata sections. |
| 10.6 Commands and accessibility | Complete by code/test | Menu commands, contextual Inspector actions, accessibility labels/hints, help text, and command tests are present. |
| 10.7 Retire custom glass | Complete | Obsolete `LiquidGlass*`, poster placeholder, custom detail sections, and typography helper files are removed. |
| 10.8 Final audit | Complete with release smoke pending | Full automated matrix and boundary audit pass; real `.app` core shell and Inspector smoke pass. |

## Inspector Runtime Decision

Attaching a native Inspector directly to the detail column is required for it
to present correctly in the three-column split view.

The Inspector must not independently observe the same
`LibraryItemDetailViewModel` used by the detail column during layout. The final
implementation therefore:

- keeps observation in the window root
- synchronizes immutable detail and curation snapshots
- renders the Inspector from those snapshots
- routes mutations through an action relay to the existing detail view model

This preserves one behavior owner and avoids the layout recursion reproduced
when the detail column and Inspector both observed the same model.

## Architecture and Persistence Audit

Boundary status: clean.

- AppUI imports remain limited to allowed presentation-facing modules.
- AppUI has no direct Persistence, Metadata, Subtitle, Playback, AVFoundation,
  AVKit, AppKit, AI, SQLite, or migration dependency.
- Persistence, Application, and Domain do not import AppUI.
- No direct SQLite, store, schema, or migration reference appears in AppUI.
- `Sources/Persistence/Migrations.swift` has no diff.
- No schema version or new third-party dependency was introduced.

## Verification

Targeted tests:

- `swift test --filter PersistenceRepositoryTests` - 62 passed.
- `swift test --filter LibraryBrowserSummaryTests` - 19 passed.
- `swift test --filter LibrarySearchTests` - 7 passed.
- `swift test --filter LibraryItemDetailTests` - 15 passed.
- `swift test --filter LibraryCurationTests` - 2 passed.
- `swift test --filter PlaybackApplicationControllerTests` - 45 passed.
- `swift test --filter AppUITests` - 17 passed.

Build and full-suite verification:

- `swift test list` - passed.
- `swift build --target AppUI` - passed.
- `swift build --target CineMindApp` - passed.
- `swift test` - 479 tests passed, 0 failures.
- `swift build` - passed.
- `git diff --check` - passed.
- Phase 10 boundary greps - no forbidden matches.
- Migration diff audit - no diff.

## Real App Smoke

The smoke used the foreground bundle staged by:

```sh
./script/build_and_run.sh --verify
```

Verified:

- real `.app` bundle launches successfully
- native window chrome, traffic lights, split-view sidebar, toolbar, and
  container search are visible
- persisted populated library renders in the artwork grid
- missing poster states remain legible
- toolbar presentation, folder, scan, refresh, and Inspector affordances are
  visible
- Library menu commands become enabled through focused scene command routing
- main detail empty state remains readable at narrow width
- native Inspector opens from the Library command
- Inspector shows its section menu and empty-selection state
- Inspector remains a trailing detail-column panel rather than a custom card
- light appearance uses semantic system colors without forced dark mode

Observed runtime note:

- macOS 26.5.1 logs one AppKit `layoutSubtreeIfNeeded` warning while opening the
  full native Inspector inside the three-column split view. The Inspector
  remains visible and usable, the app does not crash, and the warning does not
  reproduce in automated tests.

## Release Smoke Still Required

Before a user-facing release, manually record:

- cached poster rendering with representative poster files
- compact list and folders table interaction
- search with filters and sort
- favorites and collections mutation
- selected-item Inspector switching across all five sections
- active playback, seeking, and track selection
- metadata actions in configured and unavailable states
- subtitle search in configured and unavailable states
- Settings scene
- Dark appearance
- Increase Contrast, Reduce Transparency, and Reduce Motion
- keyboard-only and VoiceOver navigation
- narrow, medium, and wide window layouts

These are release-smoke gaps, not known source or automated-test failures.

## Completion Decision

Phase 10 can be treated as source-complete, automated-test-complete, and
architecture-complete for the native macOS UI redesign.

Run the remaining release smoke checklist before cutting a user-facing
release.
