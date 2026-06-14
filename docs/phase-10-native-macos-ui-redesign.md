# Phase 10 Native macOS UI Redesign

Canonical file: `docs/phase-10-native-macos-ui-redesign.md`

Planning date: 2026-06-14

Status: plan only; no source or test implementation is included in this
planning round.

Phase 10 replaces the current custom dark-glass presentation with a
system-first macOS product interface. The phase preserves the existing
local-first workflows and Application contracts while restructuring the main
window around native sidebar, toolbar, search, browser, detail, inspector,
menu, and keyboard patterns.

This phase is an overall product UI refactor, not another visual polish pass.
The objective is to make CineMind behave and read like a native macOS media
library before adding more visual effects or new product features.

---

# 1. Phase Numbering Decision

Before this plan, the Phase 9 plan and completion report used Phase 10 as a
placeholder number for future semantic-search planning. No Phase 10 AI contract
or implementation existed. Those forward-looking AI roadmap references are
updated alongside this plan.

This document formally assigns Phase 10 to the native macOS UI redesign because:

- the current UI is the primary user-facing quality gap
- the redesign is broad enough to require its own phase contract
- the existing AI foundation remains provider-neutral and has no approved
  concrete provider
- semantic search and AI tag suggestion can remain deferred without blocking
  the UI work

Future AI implementation must receive a new phase number and a separate plan.
Phase 10 must not add a concrete AI provider, semantic search, AI tag
suggestion, AI persistence, or provider configuration.

---

# 2. Current Audit

## Repository State At Planning Time

- The working tree is clean on `main`.
- Current `HEAD` is `a12417f Implement phase 9 AI provider foundation`.
- `origin/main` is behind the current local `main` at planning time.
- The package deployment target is macOS 14.
- `AppUI` depends only on `Application`, `Domain`, and `Shared`.
- Existing library, search, curation, metadata, subtitle, playback, settings,
  and export workflows are implemented.
- Phase 4.8 added an AppUI-local custom Liquid Glass presentation.

## Current UI Structure

The main window currently uses:

```text
WindowGroup
  -> CineMindRootView
    -> NavigationSplitView
      -> SidebarView
      -> LibraryBrowserView
      -> LibraryItemDetailView
```

This is the correct high-level desktop structure, but the presentation and
interaction model currently work against native macOS conventions:

- `CineMindRootView` forces `.preferredColorScheme(.dark)`.
- `SidebarView` uses a native sidebar list but paints custom capsule selection,
  hover material, custom white foreground opacity, and a custom material
  background over it.
- `LibraryBrowserView` places title, Add Folder, Scan, search, filters, sort,
  progress, and workflow messages inside a large custom content header.
- Search is a hand-built field instead of container-level `.searchable`.
- Filters and sorting occupy a permanent full-width panel rather than native
  toolbar, menu, or popover affordances.
- The media browser remains a multi-column `Table`, which is useful for
  operational data but makes the main media library feel like a database tool.
- Folder browsing correctly benefits from `Table` and should remain table-first.
- Custom `LiquidGlassPanel`, `LiquidGlassCard`, `LiquidGlassBadge`, and
  `LiquidGlassButtonStyle` types add repeated gradients, strokes, shadows,
  tinting, hover scaling, and fixed white text.
- `LibraryItemDetailView.swift` is approximately 2,243 lines and owns detail
  presentation, playback controls, curation editing, metadata actions,
  subtitle search, sheets, file rows, formatters, and status mapping.
- The detail surface presents most information and editing actions as a long
  vertical sequence of custom glass cards.
- AppUI has almost no explicit accessibility coverage beyond the poster
  placeholder label.
- AppUI tests currently focus on settings and one detail-view-model behavior;
  there is no focused coverage for browser presentation state or the planned
  inspector organization.

## Existing Data And API Coverage

Current Application summary coverage:

- `LibraryItemSummary` exposes title, media type, year or episode, availability,
  metadata state, last played, favorite state, and tags.
- It does not expose selected poster cache information.

Current Persistence summary coverage:

- `PersistedMediaItemSummary` exposes the fields required by the current table.
- The common summary query joins file counts, playback history, metadata
  presence, favorites, and tags.
- It does not join the selected poster asset.

Current detail coverage:

- `LibraryItemDetailShell` exposes selected-poster local cache path and all
  existing detail, curation, playback-facing, metadata, subtitle, and file
  information needed for the current detail surface.

Poster-grid coverage classification:

```text
Need:
- Selected local poster path for every visible media summary.

Operation:
- Read-only list/search projection.

Existing coverage:
- Single-item detail: full coverage.
- List/search summary: partial coverage, missing selected-poster relationship.

Coverage classification:
- Partial relationship gap.

Recommendation:
- Extend the existing media-summary projection and common summary query.
- Reuse all existing summary fetch method signatures.
- Do not fetch one detail record per visible grid item.

New Persistence API required:
- no

Existing Persistence query/projection modification required:
- yes

Migration required:
- no
```

The selected poster already exists in `poster_assets`; the phase must not add a
new table, column, index, or migration only to render the poster grid.

---

# 3. Product And Design Classification

## Product Type

CineMind is a desktop product UI:

- local media browsing and discovery
- operational folder and scan management
- detail inspection and editing
- playback control
- settings and provider configuration

It is not a marketing surface and should not optimize for decorative novelty.

## Primary User

The primary user is one person managing and watching a local movie and TV
library on macOS.

The interface should help that user:

- understand the shape and health of the library quickly
- find a movie or episode with minimal friction
- visually browse media through artwork
- play or resume the selected item
- inspect and edit metadata, tags, collections, subtitles, and files without
  overwhelming the main detail surface
- manage folders and scans when needed

## Primary Actions

Primary actions:

- search or browse media
- select media
- play or resume media

Secondary actions:

- favorite or organize media
- inspect and edit metadata
- inspect subtitles and files
- add folders and scan

The new hierarchy must visually and structurally reflect this priority order.

## Visual Direction

Target direction:

```text
calm native macOS media library
```

Characteristics:

- system-adaptive
- artwork-led
- quiet chrome
- clear hierarchy
- restrained color
- dense where operational, spacious where browsing
- native pointer, keyboard, menu, toolbar, and inspector behavior

The redesign must not attempt to imitate a streaming-service landing page,
create a custom borderless player shell, or apply glass material to every
surface.

---

# 4. Goal

Refactor CineMind into a coherent native macOS media-library interface so that:

- the main window follows system Light and Dark appearance
- navigation remains stable and selection-driven
- search and global actions live in the window toolbar
- media browsing supports an artwork-led grid and a compact list
- folder browsing remains an operational table
- the detail surface prioritizes artwork, title, summary, playback state, and
  primary actions
- editing and technical information move into a native inspector
- important actions are discoverable through toolbar, menus, contextual menus,
  and keyboard shortcuts
- custom visual chrome is removed where system controls already solve the
  problem
- `LibraryItemDetailView` is split into focused, testable components
- existing behavior, data ownership, and module boundaries remain intact

---

# 5. Non-Goals

Do not implement in Phase 10:

- a concrete AI provider
- semantic search
- AI tag suggestion
- AI artifact persistence
- subtitle summarization
- recommendations
- new metadata providers
- new subtitle providers
- scanner behavior changes
- playback backend changes
- new media codec support
- new export or import behavior
- background services or scheduled scanning
- multi-window media browsing
- a separate full-screen player window
- custom traffic-light placement
- a borderless main window
- custom titlebar drag regions
- AppKit window mutation from `AppUI`
- third-party UI dependencies
- a new design-token framework
- shaders, Canvas refraction, animated blur, or continuous glow effects
- a deployment-target increase
- changes to `Sources/Persistence/Migrations.swift`

Do not use the redesign as an opportunity for unrelated Domain, Persistence,
Application, metadata, subtitle, playback, scanner, AI, or export cleanup.

---

# 6. Architecture Constraints

## Required Dependency Direction

```text
AppUI
  -> Application
  -> Domain

Persistence
  -> Domain

CineMindApp
  -> composition and concrete macOS adapters
```

Allowed AppUI imports remain:

```text
SwiftUI
Foundation
CoreGraphics
ImageIO
Application
Domain
Shared
```

Forbidden AppUI imports remain:

```text
Persistence
Playback
PlaybackAVFoundation
Metadata
Subtitle
AI
AVFoundation
AVKit
AppKit
SQLite
SQLite3
```

## Ownership Rules

- Application remains the source of truth for UI-facing workflow state,
  command legality, DTO labels, and action results.
- AppUI owns layout, presentation state, selection presentation, inspector
  visibility, view mode, disclosure state, and local image decoding.
- Playback command legality remains in `PlaybackApplicationController` or its
  existing Application-facing contract.
- AppUI must not infer backend playback capability from file extensions beyond
  existing Application DTOs.
- Poster loading remains AppUI-local and must not trigger metadata or network
  actions.
- CineMindApp remains the owner of AppKit adapters and concrete playback
  surface creation.
- Settings remain a dedicated `Settings` scene.

## Persistence And Migration Decision

```text
New Persistence API required: no
Existing Persistence projection/query modification required: yes, for poster grid
Migrations.swift changed: no
Schema change required: no
```

Stop and report before implementation if poster-grid support cannot be added by
extending the existing summary projection and existing summary query path.

---

# 7. Native macOS Design Rules

## System Structure First

Use standard SwiftUI desktop structures before custom components:

- `WindowGroup`
- `Settings`
- `NavigationSplitView`
- `.toolbar`
- `.searchable`
- `.inspector`
- `Table`
- `ScrollView` plus `LazyVGrid`
- `Form`
- `LabeledContent`
- `Menu`
- contextual menus
- sheets and alerts
- commands and keyboard shortcuts

Do not rebuild system sidebars, toolbars, search fields, inspectors, sheets, or
buttons from scratch.

## Appearance

- Remove forced `.preferredColorScheme(.dark)`.
- Use semantic styles such as `.primary`, `.secondary`, `.tertiary`,
  `.quaternary`, and `.tint`.
- Let root panes and sidebar use system-provided backgrounds.
- Use material only when it communicates hierarchy or overlays content.
- Keep real artwork opaque and visually stable.
- Avoid fixed white foreground opacity as the primary hierarchy system.
- Avoid hardcoded black root backgrounds.
- Preserve sufficient contrast in both Light and Dark appearance.

## Typography

- Window and browser titles: system title or title2 hierarchy.
- Selected-media title: large title or title, depending on width.
- Section headings: headline.
- Primary body text: body.
- Supporting metadata: subheadline or callout in `.secondary`.
- Operational status: caption or callout, never tiny low-contrast text.
- Use weight and spacing sparingly; do not make every label semibold.

## Color And Icons

- Accent color communicates selection, focus, or primary action.
- Green, yellow, and red communicate meaningful state only.
- State must not rely on color alone; pair it with icon or text.
- Use SF Symbols consistently and avoid decorative icons on every section.
- Toolbar icons must have labels or help text where the meaning is ambiguous.

## Motion

- Use system transitions and control animations by default.
- Keep custom motion limited to selection, appearance, disclosure, and
  inspector presentation.
- Respect Reduce Motion.
- No hover scaling on ordinary toolbar, sidebar, table, or inspector controls.
- No continuous or decorative animation.

## Accessibility

- All icon-only actions require labels or help text.
- Poster tiles require meaningful accessibility labels and values.
- Grid and list selection must remain keyboard reachable.
- Inspector controls must have visible labels.
- Focus order must follow visual order.
- Loading, error, unavailable, and success states must be represented by text,
  not color alone.
- Verify Light, Dark, Increase Contrast, Reduce Transparency, and Reduce Motion.

---

# 8. Target Main Window Information Architecture

## Scene Model

Keep one primary `WindowGroup` and the existing dedicated `Settings` scene.

Do not introduce a document model or additional utility windows in Phase 10.

## Main Window Structure

```text
WindowGroup
  Main toolbar
    Sidebar toggle
    Contextual title/status
    Search
    Filter menu
    Sort menu
    Grid/List switch
    Add Folder
    Scan
    Inspector toggle

  NavigationSplitView
    Sidebar
      Library
      Movies
      TV Episodes
      Recently Played
      Needs Metadata
      Favorites
      Folders
      Collections

    Browser
      Poster grid for media sections
      Compact list for media sections
      Table for folders

    Detail
      Selected media overview and playback

  Optional trailing inspector
    Info
    Organize
    Files
    Subtitles
    Advanced Metadata
```

## Window State Ownership

Use the narrowest state owner:

- selected sidebar section: existing `LibraryBrowserViewModel`
- selected media item: existing `LibraryBrowserViewModel`
- loaded detail and command state: existing `LibraryItemDetailViewModel`
- media browser grid/list mode: scene-scoped presentation state
- inspector visibility: scene-scoped presentation state
- inspector selected section: scene-scoped presentation state
- search and filters: existing browser view model because they drive data loads
- app-wide settings: existing settings services and `Settings` scene

Prefer `@SceneStorage` for view mode and inspector visibility only after
verifying the value types serialize cleanly. Do not add persistence tables for
presentation preferences.

## Width Behavior

Wide window:

- sidebar, browser, and detail remain visible
- inspector can remain visible when opened

Medium window:

- browser and detail remain useful
- inspector can overlay or collapse through system behavior
- toolbar labels may become icons where system placement does so naturally

Narrow window:

- system split-view collapsing behavior remains functional
- browser controls remain reachable from toolbar menus
- no content requires horizontal scrolling solely because of fixed filter
  controls

Do not hardcode one display size or assume a single monitor.

---

# 9. Surface Specifications

## 9.1 Sidebar

Keep all existing sections and collection rows.

Target behavior:

- native `.listStyle(.sidebar)`
- flat `Label` rows
- native selection highlight
- one leading SF Symbol
- one title line
- optional collection count only if already exposed by Application
- no custom capsule background
- no custom hover state
- no fixed white foreground
- no custom material painted behind the sidebar

Sidebar selection must continue to clear stale media selection and load the
chosen section through the existing view model.

## 9.2 Toolbar

Move global and browser-level actions out of `LibraryBrowserView` content.

Required toolbar groups:

- library actions:
  - Add Folder
  - Scan
- browser controls:
  - grid/list mode
  - filter menu
  - sort menu
- detail control:
  - inspector toggle

Search:

- attach `.searchable` at the split-view or main-window hierarchy where it
  applies to the entire current media browser
- bind to existing search text
- keep search active-state behavior consistent with existing filters
- preserve clear-search behavior

Workflow status:

- busy state should disable conflicting Add Folder and Scan actions
- scanning progress should use a compact toolbar or content status treatment
- detailed scan results and errors should appear as concise content feedback,
  not permanently expand the toolbar

Folders:

- view-mode control is unavailable or hidden in the Folders section
- folder-specific operational actions remain available

## 9.3 Media Poster Grid

Media sections use poster grid as the default presentation:

- Library
- Movies
- TV Episodes
- Recently Played
- Needs Metadata
- Favorites
- Collections
- search results over media

Tile hierarchy:

```text
poster artwork or deterministic placeholder
title
year or episode label
compact state indicator only when actionably important
```

Tile rules:

- preserve a consistent 2:3 poster ratio
- use `LazyVGrid` with adaptive columns
- maintain stable item identity by `MediaItemID`
- do not place multiple inline buttons on every tile
- favorite state may use one restrained symbol
- availability or metadata warning may use one compact symbol plus
  accessibility value
- title and secondary text must remain readable at common widths
- selection must remain visible without relying only on hover
- double-click may play or resume only if the existing Application contract can
  determine a safe primary playable file without adding UI business logic;
  otherwise double-click opens or focuses detail only
- contextual menu exposes appropriate existing actions

Poster loading:

- extend the existing AppUI-local poster-loading approach
- do not decode images in `body`
- add cancellation and reuse appropriate for scrolling grids
- avoid one detail request per tile
- avoid network requests from AppUI
- use deterministic placeholders when the selected poster is absent or cannot
  load

## 9.4 Media Compact List

Compact list is the alternate media presentation for users who prefer density.

The list should:

- preserve selection and detail behavior
- show title as the primary field
- show year or episode, media type, availability, metadata status, last played,
  and optional tags with restrained hierarchy
- avoid custom card containers per row
- support contextual menus
- remain keyboard navigable

Implementation choice:

- prefer a native `Table` if it preserves the desired compact behavior
- a native `List` is acceptable only if it materially improves selection,
  contextual actions, and narrow-width behavior

Do not create two independent data-loading pipelines for grid and list.

## 9.5 Folder Browser

Folders are operational data and should remain table-first.

Keep:

- name
- path
- availability
- file count
- last seen
- last scan

Improve only through native table behavior and semantic formatting.

Do not force folders into poster tiles or decorative cards.

## 9.6 Detail Overview

The detail column becomes an overview, not the home for every editing control.

Required hierarchy:

```text
poster and media identity
title, year/episode, availability, metadata state
summary
primary Play/Resume action
active playback surface and transport controls when relevant
small amount of useful supporting information
```

Keep on the main detail surface:

- selected poster
- title and primary metadata
- summary
- play or resume
- favorite toggle if it remains compact and discoverable
- active playback surface and controls
- concise current playback and subtitle state

Move out of the main detail surface:

- tag creation and rename forms
- collection creation and rename forms
- full file list and technical information
- subtitle online search management
- metadata refresh, rematch, overrides, source details, and poster asset list

The detail surface should not become a vertical stack of equally weighted
cards.

## 9.7 Inspector

Use a native trailing inspector associated with the selected media item.

Recommended inspector sections:

```text
Info
  metadata summary and status

Organize
  favorite
  tags
  collections

Files
  file identity, availability, size, resume state, play action

Subtitles
  available subtitle state and online search action

Advanced Metadata
  refresh
  candidate search/rematch
  overrides
  provider source
  poster asset selection
```

Inspector rules:

- use standard controls, `Form`, `Section`, `LabeledContent`, `Menu`, buttons,
  and disclosure where appropriate
- use compact control sizes
- keep destructive actions labeled and separated
- avoid nested custom glass panels
- show unavailable-state explanations instead of rows of disabled controls
- preserve all existing action semantics and Application calls
- close or show an empty state when no item is selected

If one inspector becomes too dense, use a small native segmented selection or
top-level inspector section selector. Do not build a second sidebar inside the
inspector.

## 9.8 Playback

Playback behavior must remain unchanged.

The redesign may:

- improve control grouping
- use native buttons and slider appearance
- improve current-time and duration layout
- improve track menu placement
- keep subtitle overlay legible

The redesign must not:

- change command legality
- infer playback state in SwiftUI
- add unsupported format messaging outside approved Application state
- change resume policy
- change backend or surface ownership

Playback remains a high-risk regression area and requires focused tests plus
real-app smoke.

## 9.9 Sheets, Alerts, And Settings

Metadata and subtitle candidate selection:

- retain sheets
- use native list, selection, progress, empty, error, and Done/Cancel behavior
- remove custom material backgrounds unless they provide required hierarchy

Settings:

- retain the dedicated `Settings` scene
- retain Metadata and AI tabs
- apply only small native spacing and labeling improvements required for
  consistency
- do not redesign settings into the main window

Alerts:

- retain concise success and failure feedback
- avoid alerts for routine non-destructive state changes

## 9.10 Loading, Empty, Error, And Unavailable States

Each primary surface must define:

- loading
- empty library
- empty section
- no search matches
- load error
- unavailable action
- busy action
- success feedback

Prefer native `ContentUnavailableView` where available on the macOS 14 target.

Empty states must offer the next valid action:

- empty library or folders: Add Folder
- no search matches: Clear Search
- unavailable metadata actions: Open Settings guidance
- unavailable subtitle search: explain that local and embedded subtitles remain
  available

---

# 10. Desktop Interaction Contract

## Menu And Keyboard Coverage

Required or preserved menu/keyboard actions:

- focus search
- add folder
- scan library
- toggle grid/list presentation
- toggle inspector
- play or pause
- seek backward and forward
- export library

Implementation must inspect existing command ownership before adding shortcuts.
Do not create duplicate shortcuts or move playback command legality into AppUI.

## Contextual Menus

Media tile/list row contextual menu may expose existing safe actions:

- Play or Resume
- Favorite or Unfavorite
- Add to Collection
- metadata refresh or inspector reveal where appropriate

Folder contextual actions remain deferred unless an existing safe workflow
already exists.

## Selection

- Sidebar selection changes browser scope.
- Browser selection changes detail and inspector content.
- Grid/list mode changes must preserve the current selected media item when it
  remains visible.
- Search/filter changes may clear selection using the current view-model
  behavior.
- Inspector presentation must not own or duplicate item selection.

## Focus

- Search field must be keyboard reachable.
- Grid/list selection must receive visible focus.
- Inspector controls must have a predictable tab order.
- Escape should dismiss sheets and popovers through system behavior.

---

# 11. Data And API Plan

## 11.1 Poster Summary Projection

Extend `PersistedMediaItemSummary` with:

```swift
public let selectedPosterLocalCachePath: String?
```

Extend the existing common summary SQL with a selected-poster relationship,
preferably through a narrow CTE or left join that returns at most one selected
poster per media item.

Extend `LibraryItemSummary` with:

```swift
public let selectedPosterLocalCachePath: String?
```

Naming may be adjusted during implementation if an existing convention is
clearer, but the value must remain:

- optional
- read-only
- selected-poster only
- local cache path only
- free of provider URL construction

The summary change must flow through:

- normal section browsing
- favorites and collections
- search results

Do not add:

- a poster-wall repository
- a UI-named Persistence method
- a batch detail-fetch API
- per-tile detail fetching
- poster download behavior in AppUI

## 11.2 Existing Application Actions

Reuse existing Application contracts for:

- browsing
- search
- folder add and scan
- detail loading
- playback
- metadata actions
- curation
- subtitles

Add a new Application API only if a native interaction requires a behavior that
cannot be expressed through an existing contract without duplicating business
logic in AppUI.

Any proposed new API must receive a focused discovery pass and be documented
before implementation.

## 11.3 Presentation State

Grid/list mode and inspector visibility are presentation concerns.

They must not:

- enter Domain
- enter Persistence
- add migrations
- be added to library export
- broaden Application protocols

## 11.4 Poster Loading

Prefer extending or wrapping existing `PosterImageLoading` behavior with an
AppUI-local thumbnail loading abstraction.

Required characteristics:

- asynchronous decode
- main-actor publication
- cancellation for reused/disappearing tiles
- bounded in-memory reuse if needed
- no AppKit dependency in AppUI
- no metadata refresh or network behavior
- deterministic placeholder fallback

Stop if a thumbnail loader requires AppUI to know metadata-provider or
Persistence details.

---

# 12. Target File Organization

The implementation should split large views by responsibility while avoiding
unnecessary file moves.

Recommended end state:

```text
Sources/AppUI/
  AppShellEnvironment.swift
  AppShellState.swift
  AppShellViewModel.swift
  CineMindRootView.swift

  Browser/
    LibraryBrowserView.swift
    LibraryBrowserViewModel.swift
    LibraryPosterGridView.swift
    LibraryCompactListView.swift
    LibraryFolderTableView.swift
    LibraryBrowserToolbar.swift

  Detail/
    LibraryItemDetailView.swift
    LibraryItemDetailViewModel.swift
    LibraryItemOverviewView.swift
    LibraryPlaybackSection.swift
    LibraryItemInspector.swift
    LibraryInfoInspectorSection.swift
    LibraryCurationInspectorSection.swift
    LibraryFilesInspectorSection.swift
    LibrarySubtitleInspectorSection.swift
    LibraryMetadataInspectorSection.swift

  Components/
    PosterThumbnailView.swift
    PosterPlaceholderView.swift
    MediaStatusLabel.swift

  Support/
    PosterImageLoader.swift
    DisplayFormatting.swift

  SidebarView.swift
  AISettingsView.swift
  TMDBSettingsView.swift
```

This is a responsibility guide, not a requirement to move every existing file.

Rules:

- extract stable subviews before changing their behavior
- keep public type names stable where possible
- keep view models separate from large view composition files
- prefer dedicated subview types over many large computed `some View` blocks
- avoid passing the entire detail view model to every child when explicit data
  and action closures are sufficient
- keep AppKit escapes in `CineMindApp`, not in the new folders

---

# 13. Implementation Phases

Each subphase must be implemented and verified separately. Do not combine all
steps into one large unreviewable diff.

## Phase 10.1 - Baseline And Behavior-Preserving View Extraction

Goal:

- establish a safe baseline and split the largest AppUI responsibilities
  without intentionally changing visible behavior

Inspect:

- current AppUI file sizes and type ownership
- existing AppUITests and ApplicationTests
- current playback and metadata action flows

Likely modifications:

- split `LibraryItemDetailViewModel` from the detail view file
- extract focused detail sections into dedicated types
- split browser table/folder content into focused views where useful
- add focused tests for presentation-neutral view-model behavior where gaps are
  exposed

Do not:

- change data contracts
- change visual direction
- change playback behavior
- delete Liquid Glass components yet

Verification:

```sh
swift build --target AppUI
swift build --target CineMindApp
swift test --filter LibraryItemDetailTests
swift test --filter AppUITests
```

Acceptance:

- detail and browser behavior remain equivalent
- `LibraryItemDetailView.swift` no longer owns all detail responsibilities
- extracted types have explicit inputs and actions
- no boundary violations are introduced

Stop if:

- extraction requires changing playback or metadata action semantics
- unrelated user changes overlap the same code in a way that prevents safe
  extraction

## Phase 10.2 - Native Shell, Sidebar, Toolbar, And Adaptive Appearance

Goal:

- make the main window structurally native before changing browser content

Likely modifications:

- remove forced dark appearance
- remove custom root/browser/sidebar backgrounds that fight system materials
- simplify sidebar rows to native labels and selection
- move Add Folder, Scan, search, filters, sort, view mode, and inspector toggle
  into toolbar/search/menu surfaces
- preserve compact workflow feedback
- add scene-scoped presentation state

Likely files:

- `Sources/AppUI/CineMindRootView.swift`
- `Sources/AppUI/SidebarView.swift`
- browser composition and toolbar files
- `Sources/CineMindApp/main.swift` only for command or scene wiring proven
  necessary

Do not:

- hide the titlebar
- add AppKit window mutation
- add new backend APIs

Verification:

```sh
swift build --target AppUI
swift build --target CineMindApp
swift test --filter LibraryBrowserSummaryTests
swift test --filter LibrarySearchTests
```

Manual smoke:

- Light and Dark appearance
- sidebar selection
- search focus and clear
- Add Folder and Scan disabled/busy state
- toolbar behavior at wide and narrow widths

Acceptance:

- search no longer uses a hand-built content field
- global actions no longer live in a custom floating header panel
- sidebar selection is system-native
- UI remains usable in Light and Dark appearance

## Phase 10.3 - Native Browser Presentations

Goal:

- establish grid/list/folder presentation architecture before poster data is
  added

Likely modifications:

- introduce media browser presentation mode
- create poster-grid layout using placeholders initially if necessary
- create compact media list
- isolate folder table
- preserve one data-loading and selection path
- add contextual menu structure using existing safe actions only

Likely files:

- browser views and browser view model
- small AppUI presentation-state types

Do not:

- request detail for every tile
- add poster data APIs in this subphase
- change search semantics

Verification:

```sh
swift build --target AppUI
swift test --filter LibraryBrowserSummaryTests
swift test --filter LibrarySearchTests
```

Manual smoke:

- grid/list switching
- selection preservation
- search and filters in both modes
- folders remain table-only
- narrow-window behavior

Acceptance:

- media sections can switch between grid and compact list
- folders remain operational and table-first
- browser mode does not duplicate fetching or selection logic

## Phase 10.4 - Poster Summary Contract And Thumbnail Loading

Goal:

- supply poster artwork to list/search summaries without boundary violations or
  N+1 detail requests

Likely modifications:

- extend `PersistedMediaItemSummary`
- extend common media-summary SQL
- extend `LibraryItemSummary`
- update summary and search mappers/tests
- add AppUI-local thumbnail loading and poster tile rendering

Likely files:

- `Sources/Persistence/LibraryMediaSummaryQueries.swift`
- `Sources/Persistence/LibrarySearchQueries.swift` only if its shared summary
  path requires an adjustment
- `Sources/Application/LibraryBrowserSummary.swift`
- browser poster views and poster loader support
- focused Persistence/Application/AppUI tests

Forbidden:

- `Sources/Persistence/Migrations.swift`
- new public Persistence fetch method
- direct AppUI Persistence imports
- network requests from AppUI

Targeted verification:

```sh
swift test --filter PersistenceRepositoryTests
swift test --filter LibraryBrowserSummaryTests
swift test --filter LibrarySearchTests
swift build --target AppUI
```

Performance smoke:

- scroll a populated poster grid
- switch sections repeatedly
- switch grid/list repeatedly
- verify tile image tasks cancel or reuse safely
- verify no one-detail-request-per-tile behavior

Acceptance:

- visible media summaries can render selected cached posters
- absent or invalid poster paths produce deterministic placeholders
- summary fetch method signatures remain unchanged
- no migration is added
- no N+1 detail fetch path is introduced

Stop if:

- existing summary query cannot safely return one selected poster per media item
- search and normal browsing would require divergent poster logic
- the query introduces duplicate media rows

## Phase 10.5 - Detail Overview And Native Inspector

Goal:

- reduce the main detail surface to media overview and playback while moving
  editing and technical information into the inspector

Likely modifications:

- create the selected-media overview
- keep primary play/resume and active playback prominent
- add native inspector and section organization
- move curation, files, subtitles, and advanced metadata into inspector
- simplify metadata and subtitle candidate sheets
- preserve all existing action calls and status feedback

Likely files:

- detail and inspector views
- detail view model only where presentation-neutral state organization is
  needed
- candidate sheet views

Do not:

- change Application command legality
- change metadata/subtitle/curation behavior
- add new data APIs solely for layout

Targeted verification:

```sh
swift test --filter LibraryItemDetailTests
swift test --filter LibraryCurationTests
swift test --filter PlaybackApplicationControllerTests
swift build --target AppUI
swift build --target CineMindApp
```

Manual smoke:

- select and switch media rapidly
- play, pause, resume, seek, stop
- select audio and subtitle tracks when available
- favorite, add/remove tags, and add/remove collections
- open files and subtitle sections
- refresh/rematch metadata and select poster
- inspect unavailable metadata and subtitle states

Acceptance:

- main detail no longer presents every editor as a full-width card
- inspector follows current selection
- all current editing and playback workflows remain reachable
- no state or action logic is duplicated in inspector views

## Phase 10.6 - Desktop Interaction And Accessibility

Goal:

- make the redesigned interface complete for pointer, keyboard, menus, and
  assistive settings

Likely modifications:

- add or refine commands and keyboard shortcuts
- add contextual menus
- add icon-only accessibility labels and help
- improve focus and selection affordances
- improve loading, empty, error, and unavailable states
- add focused AppUI tests for presentation state and command routing where
  feasible

Do not:

- create shortcuts that bypass Application command legality
- introduce hover-only actions

Verification:

```sh
swift build --target AppUI
swift build --target CineMindApp
swift test --filter AppUITests
swift test --filter PlaybackApplicationControllerTests
```

Manual accessibility smoke:

- keyboard-only navigation
- VoiceOver labels for poster tiles and icon-only actions
- Increase Contrast
- Reduce Transparency
- Reduce Motion
- Light and Dark appearance

Acceptance:

- primary actions are reachable without a pointer
- contextual actions are discoverable
- status is not communicated by color alone
- accessibility settings do not make content unreadable

## Phase 10.7 - Retire Custom Glass System And Final Visual Polish

Goal:

- remove obsolete custom chrome after all replacement surfaces are in place

Likely modifications:

- remove unused `LiquidGlass*` components
- remove fixed-white typography helpers or replace them with semantic display
  helpers
- remove obsolete gradients, strokes, shadows, hover scaling, and custom
  background treatments
- retain only small reusable components that still serve a real product need
- run an unused-symbol and file audit

Do not:

- delete a component until all live call sites have migrated
- replace the old custom system with a second custom design system

Verification:

```sh
rg -n "LiquidGlass|liquidGlass|preferredColorScheme|Color\\.white|Color\\.black" Sources/AppUI
swift build --target AppUI
swift build --target CineMindApp
swift test
git diff --check
```

Acceptance:

- system controls and semantic styles define the primary visual language
- obsolete Liquid Glass files and call sites are removed
- no forced dark mode remains
- the UI remains visually coherent in Light and Dark appearance

## Phase 10.8 - Final Audit And Real-App Validation

Goal:

- prove the redesigned app works as a complete macOS product surface

Automated verification:

```sh
swift test list
swift test --filter PersistenceRepositoryTests
swift test --filter LibraryBrowserSummaryTests
swift test --filter LibrarySearchTests
swift test --filter LibraryItemDetailTests
swift test --filter LibraryCurationTests
swift test --filter PlaybackApplicationControllerTests
swift test --filter AppUITests
swift build --target AppUI
swift build --target CineMindApp
swift test
swift build
git diff --check
```

Boundary verification:

```sh
rg -n "^import (Persistence|Metadata|Subtitle|Playback|PlaybackAVFoundation|AVFoundation|AVKit|AppKit|AI|SQLite|SQLite3)" Sources/AppUI || true
rg -n "SQLite|CineMindStore|Migrations|Migration|CREATE TABLE|ALTER TABLE|PRAGMA|Persistence\\." Sources/AppUI || true
rg -n "^import AppUI|AppUI\\." Sources/Persistence Sources/Application Sources/Domain || true
git diff -- Sources/Persistence/Migrations.swift
```

Expected:

- no forbidden AppUI imports
- no lower-layer AppUI imports
- no `Migrations.swift` diff

Real-app validation must use a real foreground `.app` bundle when window chrome,
toolbar placement, traffic lights, focus, restoration, and accessibility are
being judged. A raw `swift run CineMindApp` launch is useful for startup smoke
but is not sufficient evidence for final window-layout acceptance.

Required real-app scenarios:

- first launch or empty library
- populated movie and TV library
- poster grid with cached and missing posters
- compact list
- folders table
- search with filters and sort
- favorites and collections
- item detail and inspector
- active playback and track selection
- metadata actions available and unavailable
- subtitle search available and unavailable
- Settings scene
- Light and Dark appearance
- narrow, medium, and wide main window

Acceptance:

- all automated gates pass
- architecture boundary remains clean
- no schema migration was introduced
- real-app smoke records the required scenarios
- remaining visual or interaction defects are documented before phase closure

---

# 14. Allowed Scope

## Inspect

- `docs/product-scope.md`
- `docs/architecture.md`
- existing Phase 4, 6, 7, 8, and 9 plans/reports
- `Package.swift`
- `Sources/AppUI/**`
- `Sources/Application/LibraryBrowserSummary.swift`
- `Sources/Application/LibrarySearch.swift`
- `Sources/Application/LibraryItemDetail.swift`
- `Sources/Application/LibraryCuration.swift`
- existing playback Application facade
- `Sources/Persistence/LibraryMediaSummaryQueries.swift`
- `Sources/Persistence/LibrarySearchQueries.swift`
- related tests
- `Sources/CineMindApp/main.swift`
- `Sources/CineMindApp/CineMindAppEnvironmentFactory.swift`

## Modify During Implementation

Expected:

- `Sources/AppUI/**`
- focused AppUI, Application, and Persistence tests
- `Sources/Application/LibraryBrowserSummary.swift`
- `Sources/Persistence/LibraryMediaSummaryQueries.swift`

Only if discovery proves necessary:

- `Sources/Persistence/LibrarySearchQueries.swift`
- `Sources/Application/LibrarySearch.swift`
- `Sources/CineMindApp/main.swift`
- `Sources/CineMindApp/CineMindAppEnvironmentFactory.swift`
- `Package.swift` for file/target changes that SwiftPM cannot infer; no new
  dependency is expected

## Forbidden

- `Sources/Persistence/Migrations.swift`
- schema version changes
- new third-party dependencies
- direct AppUI infrastructure dependencies
- `Sources/AI/**`
- concrete AI provider work
- metadata provider behavior changes
- subtitle provider behavior changes
- scanner behavior changes
- playback backend behavior changes
- unrelated export changes
- product-scope expansion

---

# 15. Discovery Commands Before Implementation

Run at the start of every implementation subphase:

```sh
git status --short
git diff --stat
```

Run before shell and view refactoring:

```sh
find Sources/AppUI -maxdepth 3 -type f | sort
wc -l Sources/AppUI/*.swift Sources/AppUI/Components/*.swift 2>/dev/null | sort -nr
rg -n "\\.toolbar|\\.searchable|\\.inspector|contextMenu|keyboardShortcut|FocusedValue|SceneStorage|AppStorage" Sources/AppUI Sources/CineMindApp
rg -n "LiquidGlass|liquidGlass|preferredColorScheme|Color\\.white|Color\\.black" Sources/AppUI
```

Run before poster-summary changes:

```sh
rg -n "PersistedMediaItemSummary|LibraryItemSummary|mediaItemSummaryCommonCTESQL|mediaItemSummarySelectColumnsSQL|mapMediaItemSummary" Sources Tests
rg -n "PosterAsset|poster_assets|is_selected|localCachePath|selectedPoster" Sources/Persistence Sources/Application Tests
rg -n "fetchMediaItemSummaries|fetchRecentlyPlayedMediaItemSummaries|fetchFavoriteMediaItemSummaries|collectionID" Sources/Persistence Sources/Application Tests
```

Run before detail/inspector changes:

```sh
rg -n "LibraryItemDetailViewModel|LibraryItemDetailView|PlaybackApplicationControlling|LibraryMetadataActionHandling|LibraryCurationHandling|LibrarySubtitleActionHandling" Sources Tests
rg -n "playFile|togglePlayPause|seekRelative|selectAudioTrack|selectSubtitleTrack|disableSubtitles" Sources/AppUI Sources/Application Tests
```

Questions to answer before each code step:

- Is this behavior already available through an Application protocol?
- Is the change presentation-only?
- Is new data actually required, or can the layout use existing DTOs?
- Will the change create duplicate state ownership?
- Will the change add N+1 reads or image decodes?
- Can a system SwiftUI control replace a custom component?
- Does the change remain usable with keyboard and accessibility settings?
- Can the step be built and verified independently?

---

# 16. Test Strategy

## Automated Test Scope

Persistence tests:

- selected poster path maps into summary projection
- no selected poster maps to `nil`
- at most one summary row is returned per media item
- normal browse, search, favorites, and collection summary paths preserve
  poster projection
- no schema version change

Application tests:

- summary mapper exposes selected poster path
- existing summary labels and selection identifiers remain unchanged
- search summary mapping remains correct
- detail, curation, subtitle, and playback action behavior remains unchanged

AppUI tests:

- presentation-state behavior where practical
- grid/list mode does not change data selection semantics
- detail view-model state remains stable through extraction
- inspector action routing delegates to the existing view model or action
  closures
- settings behavior remains unchanged

## Manual Test Scope

Manual validation is required because SwiftPM unit tests cannot prove:

- visual hierarchy
- toolbar placement
- sidebar appearance
- inspector ergonomics
- keyboard focus
- contextual menu discoverability
- system Light/Dark adaptation
- real window width behavior
- playback-surface integration inside the redesigned detail

Use an approved or disposable library for state-changing smoke.

---

# 17. Acceptance Criteria

Phase 10 is complete only when all of the following are true.

## Structure

- main window remains a stable `NavigationSplitView`
- search and global actions use native toolbar/search placement
- sidebar uses native selection and material behavior
- inspector is associated with current media selection
- Settings remains a dedicated scene

## Browser

- media sections support poster grid and compact list
- poster grid uses summary-projected selected poster paths
- folders remain a native operational table
- grid/list switching preserves selection where valid
- search, filters, and sorting work in both media presentations
- no N+1 detail fetching is used for poster tiles

## Detail And Inspector

- main detail prioritizes artwork, title, summary, playback, and primary action
- curation, files, subtitles, and advanced metadata are available in inspector
- all existing actions remain reachable
- playback behavior remains Application-owned and unchanged
- detail responsibilities are split into focused files/types

## Visual And Accessibility

- forced dark mode is removed
- Light and Dark appearance are both usable
- obsolete custom glass chrome is removed
- system semantic colors and controls define the primary presentation
- primary actions are keyboard reachable
- icon-only controls have accessible labels
- status is not communicated by color alone
- Reduce Motion and Reduce Transparency remain usable

## Architecture And Data

- AppUI has no forbidden infrastructure imports
- no new third-party dependency is added
- no migration or schema change is added
- summary query signatures remain narrow
- no public Persistence API is added solely for UI convenience
- existing search, curation, metadata, subtitle, playback, settings, and export
  behavior remains intact

## Verification

- all targeted tests pass
- `swift build --target AppUI` passes
- `swift build --target CineMindApp` passes
- full `swift test` passes
- full `swift build` passes
- `git diff --check` passes
- boundary checks pass
- real `.app` validation records all required scenarios

---

# 18. Stop Conditions

Pause implementation and report before continuing if:

- a schema migration appears necessary
- poster grid requires one detail fetch per media item
- a new public Persistence method appears necessary
- AppUI would need to import Persistence, Metadata, Subtitle, Playback,
  PlaybackAVFoundation, AI, AppKit, AVFoundation, AVKit, SQLite, or SQLite3
- native inspector behavior cannot preserve current action state safely
- view extraction changes playback, metadata, subtitle, or curation semantics
- toolbar/search placement would require unsupported behavior on macOS 14
- a proposed new API duplicates an existing use case
- a real `.app` smoke reveals titlebar, traffic-light, focus, or restoration
  issues that cannot be resolved with existing SwiftUI scene APIs
- full tests expose unrelated failures that make regression status ambiguous
- user-owned worktree changes overlap the planned files and cannot be safely
  preserved

---

# 19. Risk Matrix

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Broad UI refactor breaks existing workflows | High | High | Split into independently verified subphases; preserve view models and Application calls first. |
| Poster grid creates N+1 detail reads | Medium | High | Extend existing summary projection and shared query; prohibit per-tile detail fetches. |
| Selected-poster join duplicates media summary rows | Medium | High | Join only selected poster; add Persistence tests for one-row-per-item behavior. |
| Detail extraction changes playback timing or state ownership | Medium | High | Treat extraction as behavior-preserving; run playback-focused tests and exact interaction smoke. |
| Inspector hides important actions | Medium | Medium | Keep primary play/resume and favorite discoverable; add toolbar/contextual/menu paths where appropriate. |
| Native toolbar becomes crowded | Medium | Medium | Group actions, move secondary filters/sort into menus, validate narrow widths. |
| Removing forced dark mode exposes low-contrast text | High | Medium | Replace fixed white opacity with semantic styles before deleting old helpers; smoke Light and Dark appearance. |
| Grid scrolling becomes expensive | Medium | Medium | Use lazy layout, async decode, cancellation, and bounded AppUI-local reuse; avoid heavy per-tile effects. |
| Custom glass removal creates temporary mixed UI | High | Low | Retire old components only after replacement surfaces are complete. |
| AppUI boundary drifts during poster work | Medium | High | Keep data path AppUI -> Application -> existing Persistence summary query; run boundary checks each subphase. |
| macOS 14 lacks a desired newer UI API | Medium | Medium | Use mature macOS 14 SwiftUI controls; require availability guards and separate approval for newer APIs. |
| Real app differs from raw SwiftPM executable | Medium | High | Require final validation in a real foreground `.app` bundle. |

---

# 20. Completion Deliverables

Required deliverables:

- native main-window shell and toolbar
- simplified native sidebar
- poster grid and compact media list
- preserved folder table
- selected-poster summary projection
- AppUI-local thumbnail loading
- focused detail overview
- native inspector with existing editing workflows
- desktop commands, contextual menus, and accessibility pass
- retired obsolete Liquid Glass components
- focused automated tests
- final architecture boundary audit
- real `.app` smoke record
- Phase 10 completion report

Phase 10 must not be declared complete from screenshots alone. Completion
requires behavior verification, architecture verification, automated tests, and
real-app validation.
