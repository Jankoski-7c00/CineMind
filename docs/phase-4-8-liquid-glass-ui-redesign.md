# Phase 4.8 Liquid Glass UI Redesign

Canonical file: `docs/phase-4-8-liquid-glass-ui-redesign.md`

Phase 4.8 upgrades the existing macOS SwiftUI UI from a functional debug-style shell into a darker, more cinematic media-library interface. The implementation remains AppUI-first, keeps existing data flow intact, and avoids new infrastructure, database, playback, metadata, scanner, subtitle, or third-party UI dependencies.

---

# 1. Summary

V1 introduces a small Liquid Glass design system for CineMind and applies it to the highest-value UI surfaces:

- detail view header, poster presentation, metadata cards, advanced metadata controls, playback section, and files list
- browser toolbar, empty states, and table cell polish
- native sidebar styling with subtle dark material treatment
- low-cost hover, transition, and disclosure motion

The goal is a conservative visual refactor, not a product-scope expansion. All visible data continues to arrive through the existing Application layer protocols:

- `LibraryItemDetailBrowsing`
- `LibraryMediaSummaryBrowsing`
- `LibraryFolderSummaryBrowsing`
- `PlaybackApplicationControlling`
- `LibraryMetadataActionHandling`

New display needs that are not available through those protocols are deferred instead of reaching into lower layers.

---

# 2. Current UI Problems

Current AppUI observations from read-only inspection:

- `Sources/AppUI` is flat and has no reusable component or style directories.
- `LibraryItemDetailView.swift` is a large mixed-responsibility file with view model, layout, poster placeholder, playback controls, metadata actions, source rows, poster assets, file rows, and formatting helpers.
- The library browser is a six-column `Table` that reads like a database table.
- The sidebar is a plain `List` without `.sidebar` styling or a material-backed shell.
- The top Add Folder / Scan controls look like ordinary utility buttons in a full-width header.
- Detail content is a flat stack separated by dividers, so title, poster, metadata, playback, source details, and file actions all compete at the same visual weight.
- Metadata actions are always present near the top of the detail page; when TMDB actions are unavailable, disabled buttons still occupy the main visual area.
- Poster placeholders expose internal state: selected poster status, placeholder seed, cache-path absence, and raw placeholder reason labels.
- Main UI can show debug-oriented or raw/internal strings such as `Not provided`, `no cache path`, poster placeholder reasons, cache status strings, and ISO 8601 last-played timestamps.
- There is no shared typography, badge, button, card, hover, or motion treatment.
- `WindowGroup` uses the default title-bar/window presentation.

---

# 3. Design Goals

V1 should make CineMind feel like a native dark macOS media library:

- Liquid Glass and Obsidian Glass surfaces for navigation, metadata, action, and supporting panels.
- Solid poster/media artwork that is not itself treated as glass.
- A cinematic detail hierarchy: poster, title, badges, last-played state, summary, primary actions, then secondary information.
- Better scanability through badges, labels, section cards, and consistent empty-value formatting.
- Reduced debug leakage in normal UI.
- Native macOS behavior first, custom styling second.
- Small, reversible SwiftUI changes that continue to compile after each step.

The visual direction is deep dark mode with polished black glass: dark material fills, soft edge highlights, subtle depth, and restrained accent glow for primary actions.

---

# 4. Architecture Constraints

Allowed AppUI imports remain:

```text
SwiftUI
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
Metal
```

V1 constraints:

- Do not introduce third-party UI dependencies.
- Do not modify database schema or migrations.
- Do not modify playback backend behavior.
- Do not move metadata, scanner, playback, subtitle, or persistence implementation details into AppUI.
- Do not add Application or Persistence APIs only for visual decoration.
- Keep business rules and command legality in Application-facing controllers and protocols.
- Keep poster loading AppUI-local as already established; do not grow `AppShellEnvironment` for visual polish.
- If the UI wants data not currently exposed by Application, document it as deferred.

---

# 5. V1 Scope

## 4.8A Liquid Glass Foundation

Add reusable AppUI components and helpers:

- `LiquidGlassPanel`
- `LiquidGlassCard`
- `LiquidGlassBadge`
- `LiquidGlassButtonStyle`
- `PosterPlaceholderView`
- typography / foreground / empty-value helpers

## 4.8B Detail View Liquid Glass Refactor

Refactor `LibraryItemDetailView` presentation into:

```text
Backdrop layer
  -> static dark gradient or blurred poster-derived image where already loaded
Scroll content
  -> MediaDetailHeaderView
  -> primary action row
  -> playback card when active
  -> metadata card
  -> files/source cards
  -> Advanced Metadata disclosure
```

## 4.8C Lightweight Library Table Polish

Keep `Table`, increase row readability, and make cell text friendlier. Add a glass empty state.

## 4.8D Sidebar Polish

Use native sidebar list styling and subtle material/dark treatment. Keep all six existing sidebar items and symbols.

## 4.8E Floating Toolbar Polish

Restyle Add Folder / Scan as a compact floating glass toolbar without changing behavior.

## 4.8F Safe Motion

Add only lightweight hover, opacity, y-offset, and disclosure animations.

## 4.8G Basic Window Polish

Optionally try pure SwiftUI `.windowStyle(.hiddenTitleBar)` only if layout remains safe around traffic lights. Revert if overlap appears likely.

---

# 6. Explicitly Deferred from V1

V1 does not implement:

- Grid / poster-wall view.
- Table-to-List migration.
- Search field functional wiring.
- Sidebar count badges.
- Cursor-tracking radial highlight.
- Dynamic poster-color extraction for glow or refraction.
- Real dynamic refraction.
- Advanced morphing glass animation.
- AppKit `NSWindow` bridging.
- Full-size content view or custom traffic-light layout.
- Per-row continuous animation or looping glow.
- New Application/Persistence APIs for visual-only data.
- Metadata provider expansion, cast/crew, seasons, stills, or online metadata changes.

Rationale:

- These items add new behavior, new state, or cross-layer risk.
- Several require Application or Persistence data that is not currently exposed.
- V1 should be visual polish with a narrow AppUI blast radius.

---

# 7. Liquid Glass Design System

## Material Strategy

Use SwiftUI-native materials and dark translucent fills:

- panel surfaces: `.regularMaterial` or `.thinMaterial` over a dark tint
- small badges/buttons: `.ultraThinMaterial` or `.thinMaterial`
- root/detail fallback: deep dark gradient, not flat black

Do not use shader, Canvas refraction, real-time blur animation, or custom AppKit vibrancy in V1.

## Edge Highlight Strategy

Use rounded rectangles with layered overlays:

- top-leading edge: white at low opacity
- mid stroke: transparent
- bottom-trailing edge: near-black at low opacity

This simulates glass thickness without high-cost rendering.

## Shadow/Glow Strategy

Use very restrained depth:

- soft black outer shadow for elevation
- optional accent glow only on primary action buttons
- lower highlight/shadow intensity when `controlActiveState` is inactive

## Typography

Provide small view modifiers or helpers:

- detail title: title / large title, semibold
- section title: headline
- body: body
- secondary text: white opacity `0.5...0.7`
- captions: caption with subdued opacity
- empty values: `—`
- missing summary: `No summary available.`

Avoid relying on default gray as the only hierarchy tool on dark backgrounds.

## Badges

`LiquidGlassBadge` uses capsule shape, material fill, subtle border, optional SF Symbol, and readable labels:

- `Movie`
- `TV Episode`
- `Available`
- `Missing File`
- `Needs Metadata`
- `Matched`
- `Partial`
- `Local File`

Do not render field-style labels such as `Availability available`.

## Buttons

`LiquidGlassButtonStyle` provides primary and secondary variants:

- capsule or rounded-rectangle shape
- material background
- subtle border
- hover highlight and tiny scale
- restrained disabled opacity
- primary variant may use a mild accent glow

Buttons should remain normal SwiftUI `Button`s so keyboard, accessibility, and command behavior stay native.

## Poster Placeholder

`PosterPlaceholderView` replaces current placeholder content:

- film SF Symbol
- `No Poster`
- optional spinner while loading
- no UUID
- no cache path
- no `no cache path`
- no raw `PosterImagePlaceholderReason`

It uses a glass card-like surface but keeps real poster artwork solid.

---

# 8. Detail View Redesign

## New Layout Hierarchy

Target structure:

```text
ZStack
  Backdrop layer
    static blurred loaded poster or deep dark gradient
    dark overlay
  ScrollView
    VStack
      MediaDetailHeaderView
      primary action row
      active playback card
      metadata card
      files card
      source/poster assets cards inside Advanced Metadata
```

The backdrop must be static and cheap. If poster blur is awkward or expensive, use the gradient fallback for V1.

## Header Design

`MediaDetailHeaderView` owns the main cinematic presentation:

- left poster area
- right title, subtitle/year/episode, badge row, last played, summary
- badge row:
  - Movie / TV Episode
  - Available / Missing File / Partial Availability
  - Matched / Partial Metadata / Needs Metadata
- last-played formatting:
  - `Never played`
  - `Last played today at HH:mm`
  - `Last played yesterday at HH:mm`
  - `Last played on YYYY-MM-DD at HH:mm`
  - fallback to existing string or `—` when parsing fails

Do not display UUID, cache path, raw placeholder reason, or raw cache status in the header.

## Metadata Card

Wrap metadata fields in `LiquidGlassCard`:

- Status
- Local Title
- Matched Title
- Original Title
- Summary
- Language
- Release Date

Formatting:

- empty scalar values use `—`
- empty summary uses `No summary available.`
- no `Not provided`
- status is friendly-cased where possible

## Advanced Metadata Disclosure

Move current metadata action controls below the primary detail content:

```swift
DisclosureGroup("Advanced Metadata") {
    // refresh/search/rematch/overrides/source/poster assets
}
```

Rules:

- TMDB token missing state displays a glass callout:
  `Set CINEMIND_TMDB_READ_TOKEN to enable online metadata matching.`
  or the existing `AppShellEnvironment.metadataActionsUnavailableMessage`.
- Do not show a row of disabled refresh/search/save/clear buttons when actions are unavailable.
- Override fields remain available only inside Advanced Metadata.
- Search/rematch sheet remains functional and visually wrapped.
- Poster asset list remains functional but does not expose local cache paths in main UI.

## Debug Info Removal

Remove from ordinary UI:

- media UUID
- poster asset UUID
- poster placeholder seed
- poster cache path
- `no cache path`
- raw `PosterImagePlaceholderReason`
- `Not provided`
- raw internal cache/status strings

If needed later, this belongs in a V2 Debug Inspector, not V1 main UI.

---

# 9. Library Browser Polish

## Keep Table

V1 keeps SwiftUI `Table` for media and folders. This avoids rewriting selection, rows, and column behavior.

## Cell Enrichment Strategy

Media table polish:

- increase perceived row height with vertical padding
- title cell gets a small film placeholder icon
- type and metadata cells use compact badge or icon+text
- availability text becomes friendlier:
  - `available` -> `Available`
  - `unavailable` / `no files` -> `Missing File`
  - `partially available` -> `Partial`
- metadata text becomes friendlier:
  - `complete` -> `Matched`
  - `partial` -> `Partial`
  - `missing` -> `Needs Metadata`
- last played uses existing Application label in V1, with optional UI-side friendly formatting if parseable

Folder table polish stays lighter because folder paths remain operational data.

## Empty State

Use a centered glass empty state:

- `No media yet`
- `Add a folder to start building your library.`
- Add Folder button when that action is available

For folders:

- `No folders yet`
- `Add a folder to start building your library.`

---

# 10. Sidebar Polish

V1 sidebar changes:

- apply `.listStyle(.sidebar)`
- keep the six current items and SF Symbols
- add subtle dark material/root background without fighting `NavigationSplitView`
- rely on native macOS selection behavior, with only light foreground/tint polish if needed

No sidebar count badges in V1 because aggregate counts are not exposed by Application.

---

# 11. Toolbar Polish

Replace the full-width utility header feel with a compact floating glass toolbar:

- Add Folder primary-ish glass button
- Scan secondary glass button
- progress indicator and workflow status remain visible but subdued
- scan summary becomes compact supporting text

No search field in V1.

---

# 12. Motion Guidelines

Allowed:

- hover scale `1.0 -> 1.015`
- hover opacity / highlight fade
- selected and hover highlight fade
- natural `DisclosureGroup` expansion/collapse
- detail content opacity plus slight y-offset transition

Forbidden:

- real-time blur animation
- continuous per-row animation
- shaders
- scrolling-time complex shadow recalculation
- looping glow
- large matched-geometry transitions
- morphing glass across view hierarchy

Motion must be low-cost and should not affect table scrolling performance.

---

# 13. Window Polish Boundaries

Allowed:

- pure SwiftUI `.windowStyle(.hiddenTitleBar)` only if the root layout stays clear of traffic lights
- deep dark root background

Forbidden:

- AppKit `NSWindow` bridging
- custom traffic-light positioning
- full-size content view
- `ignoresSafeArea` that risks `NavigationSplitView` overlap
- large `CineMindApp` entry refactor

If title-bar hiding creates overlap or uncertainty, V1 should keep default window chrome.

---

# 14. File Organization

Target AppUI organization:

```text
Sources/AppUI/
  Components/
    LiquidGlassPanel.swift
    LiquidGlassCard.swift
    LiquidGlassBadge.swift
    LiquidGlassButtonStyle.swift
    PosterPlaceholderView.swift
    MediaDetailHeaderView.swift
  Extensions/
    Typography+ViewModifiers.swift
  AppShellEnvironment.swift
  AppShellState.swift
  AppShellViewModel.swift
  CineMindRootView.swift
  LibraryBrowserView.swift
  LibraryBrowserViewModel.swift
  LibraryItemDetailView.swift
  PosterImageLoader.swift
  SidebarView.swift
```

`LibraryItemDetailView.swift` can keep its existing view model in V1, but visual subviews should move out where the new component boundary is clear.

---

# 15. Implementation Plan

## Step 1 - Add Design System Components

Modify:

- `Sources/AppUI/Components/LiquidGlassPanel.swift`
- `Sources/AppUI/Components/LiquidGlassCard.swift`
- `Sources/AppUI/Components/LiquidGlassBadge.swift`
- `Sources/AppUI/Components/LiquidGlassButtonStyle.swift`
- `Sources/AppUI/Components/PosterPlaceholderView.swift`
- `Sources/AppUI/Extensions/Typography+ViewModifiers.swift`

Run:

```bash
swift build --target AppUI
```

## Step 2 - Refactor Detail Header and Poster Placeholder

Modify:

- `Sources/AppUI/Components/MediaDetailHeaderView.swift`
- `Sources/AppUI/LibraryItemDetailView.swift`

Work:

- introduce cinematic header
- use poster placeholder component
- add friendly badges and last-played formatting
- remove UUID/cache path/raw placeholder reason from visible placeholder

Run:

```bash
swift build --target AppUI
```

## Step 3 - Refactor Metadata and Actions

Modify:

- `Sources/AppUI/LibraryItemDetailView.swift`
- related AppUI components only if needed

Work:

- wrap metadata in glass card
- replace `Not provided` with `—`
- replace missing summary with `No summary available.`
- collapse advanced metadata/actions
- show TMDB unavailable callout instead of disabled action rows

Run:

```bash
swift build --target AppUI
```

## Step 4 - Lightweight Browser / Sidebar / Toolbar Polish

Modify:

- `Sources/AppUI/LibraryBrowserView.swift`
- `Sources/AppUI/SidebarView.swift`
- possibly `Sources/AppUI/CineMindRootView.swift`

Work:

- floating toolbar
- glass empty state
- table cell friendly text/badges
- native sidebar list style

Run:

```bash
swift build --target AppUI
swift build --target CineMindApp
```

## Step 5 - Safe Motion and Optional Basic Window Polish

Modify:

- AppUI views/components
- optionally `Sources/CineMindApp/main.swift` for pure SwiftUI window style

Work:

- hover scale/fade on glass controls
- detail transition
- try title-bar polish only if safe

Run final verification.

---

# 16. Risk Matrix

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| AppUI imports infrastructure accidentally | Low | High | Run forbidden import grep after changes; keep all new files in AppUI dependent only on allowed modules. |
| `LibraryItemDetailView` refactor breaks playback controls | Medium | High | Keep view model and Application playback calls unchanged; build after each step. |
| Metadata unavailable state regresses actions | Medium | Medium | Hide action row only when `metadataActionsAvailable == false`; preserve sheet/mutation calls when available. |
| Empty-value formatting hides useful operational information | Low | Medium | Only replace debug-style placeholders in main UI; keep file names, sizes, availability, and actionable playability reasons. |
| Material styling becomes low contrast | Medium | Medium | Use dark overlays and white opacity hierarchy; keep text readable over backdrop. |
| Table polish disrupts selection or sorting behavior | Low | Medium | Keep `Table` and row model unchanged; only change cell contents/padding. |
| Hidden title bar overlaps traffic lights | Medium | Medium | Treat as optional; revert if layout is unsafe. No AppKit bridging. |
| Extra shadows hurt scrolling | Low | Medium | Use glass cards for large sections, not animated per-row shadows. |

---

# 17. Verification Plan

Required final commands:

```bash
swift test --list-tests
swift build --target AppUI
swift build --target CineMindApp
swift test
grep -R "import Persistence\|import PlaybackAVFoundation\|import Metadata\|import Subtitle\|import AI" Sources/AppUI/ || true
```

Expected forbidden import result:

- no forbidden AppUI imports

Intermediate compile gates:

- after Step 1: `swift build --target AppUI`
- after Step 2: `swift build --target AppUI`
- after Step 3: `swift build --target AppUI`
- after Step 4: `swift build --target AppUI` and `swift build --target CineMindApp`

If a build fails:

- fix the first meaningful compiler error
- rerun the failed command before proceeding

---

# 18. Completion Checklist

- [x] Design system components exist under `Sources/AppUI/Components`.
- [x] Typography helpers exist under `Sources/AppUI/Extensions`.
- [x] Detail view has backdrop, cinematic header, badge row, primary action row, and glass cards.
- [x] Poster placeholder shows only film icon and `No Poster`.
- [x] Main UI no longer shows UUID, cache paths, `no cache path`, raw placeholder reasons, `Not provided`, or raw internal status strings.
- [x] Metadata actions are under `Advanced Metadata`.
- [x] Missing TMDB token shows an actionable glass callout.
- [x] Library browser still uses `Table`.
- [x] Browser empty state uses glass treatment.
- [x] Sidebar uses native sidebar styling.
- [x] Add Folder / Scan use floating glass toolbar styling.
- [x] Motion remains lightweight and discrete.
- [x] No AppKit window bridging is introduced.
- [x] `swift test --list-tests` passes.
- [x] `swift build --target AppUI` passes.
- [x] `swift build --target CineMindApp` passes.
- [x] `swift test` passes.
- [x] Forbidden import check returns no AppUI boundary violations.

Window polish note:

- Optional `.windowStyle(.hiddenTitleBar)` was not applied in V1. The SwiftPM product currently launches as a raw executable rather than a `.app` bundle in local smoke, so there was not enough foreground window-layout evidence to verify traffic-light safety.

---

## Phase 4.8H — Detail Header, Browser Semantics, and Glass Depth Polish

Phase 4.8H is a low-risk polish pass on top of the completed V1 Liquid Glass refactor. It does not rewrite the app shell, browser architecture, Application protocols, playback controller, metadata actions, or persistence model.

### Current Completion Snapshot

Read-only inspection of the current tree shows:

- `Sources/AppUI/Components/` exists and contains `LiquidGlassPanel`, `LiquidGlassCard`, `LiquidGlassBadge`, `LiquidGlassButtonStyle`, `PosterPlaceholderView`, and `MediaDetailHeaderView`.
- `Sources/AppUI/Extensions/Typography+ViewModifiers.swift` exists and provides shared display text and typography helpers.
- `LibraryItemDetailView` now uses a backdrop, `MediaDetailHeaderView`, primary action row, glass cards, and collapsed advanced metadata/subtitle sections.
- `LibraryBrowserView` still uses `Table`, which is correct for V1, and already has icon/status text polish.
- `SidebarView` uses `.listStyle(.sidebar)`.
- Current AppUI import check is clean for the forbidden infrastructure modules listed in this document.

The remaining issues are visual hierarchy, safe-area handling, and semantic polish rather than architecture gaps.

### Current Problems To Address

From the latest screenshot and code inspection:

- Detail content may sit too close to the titlebar/safe-area top because the detail `ScrollView` relies on a generic `.padding(20)` and the background/content safe-area responsibilities are not explicit.
- `MediaDetailHeaderView` renders `badgeRow` before the media title, which can make `Movie` or `TV Episode` feel like the primary heading.
- `PosterPlaceholderView` uses a simple `film` symbol on a mostly empty glass surface; it has little poster-card depth and can look visually hollow.
- `LiquidGlassPanel` has one gradient stroke and one shadow, but no inset highlight or subtle secondary glow, so larger cards can read as black rounded rectangles.
- `detailBackdrop` is a single linear gradient from black to dark gray to black, so the detail column lacks cinematic depth.
- The media table still includes `Year / Episode`, which often displays `—`, while metadata status and last-played semantics are not prominent enough.
- The files card still uses one horizontal row that resembles a table tail; status, resume text, and play actions need clearer grouping.
- The metadata card remains `LabeledContent`-heavy, uses a text status instead of a badge, and repeats summary already shown in the header.
- The browser toolbar is a floating action capsule on a hard black background and does not say `Library` or `Local library`.
- Sidebar selection is mostly the system gray selected state; it needs a slightly more glass-like selected row without breaking `NavigationSplitView` selection.

### Implementation Scope

Modify only AppUI and this document:

- Detail safe-area/top clipping protection.
- Header hierarchy: title first, badges second, last played and summary below.
- Poster placeholder visual depth while preserving 2:3 poster ratio.
- Static glass-depth improvements for `LiquidGlassPanel` and `LiquidGlassCard`.
- Static cinematic detail background.
- Files card row grouping and button styling.
- Metadata card status badge and reduced summary duplication.
- Lightweight media table semantic polish while keeping `Table`.
- Browser header with `Library`, `Local library` or existing count-derived text, and Add Folder / Scan actions.
- Sidebar selected/hover polish while keeping the existing six sidebar items.

No new Application data is required for the planned V1.5 polish. If a desired label cannot be derived from the current AppUI view models and Application DTOs, keep the existing safe text or mark it deferred.

### Explicitly Deferred From 4.8H

Do not implement:

- Grid / poster wall.
- `Table` to `List` migration.
- Search field functional wiring.
- Sidebar count badges.
- Cursor-tracking radial highlight.
- Dynamic poster color extraction.
- Real refraction, shader, or Canvas effect.
- Advanced morphing glass.
- AppKit `NSWindow` bridging.
- Custom traffic-light layout.
- Full-size content view.
- Per-row continuous animation.
- Looping glow animation.
- Any changes in `Domain`, `Application`, `Persistence`, `Playback`, `Metadata`, `Subtitle`, or `AI`.

### Expected File Modifications

Allowed source files:

- `Sources/AppUI/CineMindRootView.swift`
- `Sources/AppUI/LibraryItemDetailView.swift`
- `Sources/AppUI/LibraryBrowserView.swift`
- `Sources/AppUI/SidebarView.swift`
- `Sources/AppUI/Components/LiquidGlassPanel.swift`
- `Sources/AppUI/Components/LiquidGlassCard.swift`
- `Sources/AppUI/Components/LiquidGlassBadge.swift`
- `Sources/AppUI/Components/LiquidGlassButtonStyle.swift`
- `Sources/AppUI/Components/MediaDetailHeaderView.swift`
- `Sources/AppUI/Components/PosterPlaceholderView.swift`
- `Sources/AppUI/Extensions/Typography+ViewModifiers.swift`

Allowed documentation:

- `docs/phase-4-8-liquid-glass-ui-redesign.md`

Forbidden source files:

- `Sources/Domain/**`
- `Sources/Application/**`
- `Sources/Persistence/**`
- `Sources/Playback/**`
- `Sources/PlaybackAVFoundation/**`
- `Sources/Metadata/**`
- `Sources/Subtitle/**`
- `Sources/AI/**`
- `Package.swift`, unless a future separate task explicitly needs package-level work

### Implementation Plan

1. Detail safe-area and clipping pass.
   - Inspect `CineMindRootView`, `NavigationSplitView`, and `LibraryItemDetailView.detailContent`.
   - Make the background responsible for any safe-area ignoring, if needed.
   - Keep foreground content inside safe area with `safeAreaPadding(.top)` or explicit top padding.
   - Do not add AppKit bridging or titlebar customization.
   - Run `swift build --target AppUI`.

2. Header hierarchy pass.
   - In `MediaDetailHeaderView`, move `Text(detail.displayTitle)` above badge row.
   - Keep `Movie` / `TV Episode` as badges or secondary subtitle only.
   - Use metadata and availability badges under the title.
   - Keep last played as secondary text.
   - Keep summary in the header, capped by line limit.
   - Run `swift build --target AppUI`.

3. Poster placeholder pass.
   - Preserve 2:3 sizing at call sites.
   - Use macOS 14-safe symbols such as `film`, `photo`, or `rectangle.stack`.
   - Add a static diagonal/radial gradient and stronger edge highlight.
   - Keep visible text to `No Poster` or `Loading Poster`; never show UUID, cache path, or placeholder reason.
   - Run `swift build --target AppUI`.

4. Glass-depth pass.
   - Enhance `LiquidGlassPanel` with a clearer top-leading to bottom-trailing gradient stroke.
   - Add an inset stroke or inner-highlight approximation.
   - Add subtle outer separation: black shadow plus very low white/accent glow.
   - Keep active/inactive window opacity adjustment through `controlActiveState`.
   - Avoid heavy per-row card effects in tables.
   - Run `swift build --target AppUI`.

5. Cinematic detail background pass.
   - Replace the single linear backdrop with layered static gradients.
   - Use very low-opacity blue/purple/white glow and a dark overlay.
   - Allow only the background layer to fill the available area; keep content safe-area protected.
   - Run `swift build --target AppUI`.

6. Files and metadata card pass.
   - Rework file rows so filename/size are left aligned and status/action groups are visually separated.
   - Present availability as a badge and resume position as secondary text or compact badge.
   - Apply `LiquidGlassButtonStyle` to play/resume where appropriate.
   - In metadata, change `Status` to `Match Status` and present it as a badge.
   - Avoid repeating the same summary prominently in both header and metadata card; if summary remains in metadata, move it to lower visual priority.
   - Continue using `—` for empty values and never show `Not provided`.
   - Run `swift build --target AppUI`.

7. Browser semantic polish pass.
   - Keep `Table`.
   - Replace or demote the `Year / Episode` column because it often produces empty cells.
   - Prefer showing metadata state in a `Metadata` column using existing `LibraryItemSummary.metadataLabel`.
   - Improve title cell with icon, title, and optional secondary line if it remains readable in table cells.
   - Keep row height around 44-56 through padding, not custom row containers.
   - Run `swift build --target AppUI`.

8. Browser header / toolbar polish pass.
   - Replace the hard black toolbar area with a browser header.
   - Show `Library` and `Local library` unless a current snapshot/folder count is already available.
   - Keep Add Folder / Scan actions on the right or in a clearly grouped action cluster.
   - Do not add search UI.
   - Run `swift build --target AppUI`.

9. Sidebar selected/hover polish pass.
   - Keep existing sidebar sections and `.listStyle(.sidebar)`.
   - Add a small reusable sidebar row only if it preserves `List(selection:)` tags.
   - Add capsule-like selected highlight and subtle hover brighten.
   - Do not add count badges or cursor tracking.
   - Run `swift build --target AppUI`.

10. Final verification.
    - Run the full verification plan below.
    - If any UI polish requires unsupported data, document it as deferred instead of fabricating values.

### Risk And Mitigation

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Safe-area fix causes new spacing regressions | Medium | Prefer local content padding and `safeAreaPadding`; avoid window/titlebar APIs. |
| Header refactor breaks poster layout | Medium | Preserve fixed 2:3 poster frame and top-aligned `HStack`. |
| Glass depth becomes too heavy | Medium | Keep new effects static and apply to section cards, not every table row. |
| Table semantic polish disrupts selection | Medium | Keep `Table`, `ForEach`, and `TableRow` unchanged; only adjust columns/cell views. |
| Metadata/file polish leaks business logic into AppUI | High | Use existing labels from Application DTOs; only friendly-case or badge those labels. |
| Sidebar custom row breaks selection | Medium | Keep tags attached to rows and revert to native `.listStyle(.sidebar)` if selection behavior changes. |
| AppUI imports drift | High | Run forbidden import grep after changes. |

### Verification Commands

Intermediate command after each large step:

```bash
swift build --target AppUI
```

Final commands:

```bash
swift test --list-tests
swift build --target AppUI
swift build --target CineMindApp
swift test
grep -R "import Persistence\|import PlaybackAVFoundation\|import Metadata\|import Subtitle\|import AI" Sources/AppUI/ || true
```

Expected forbidden import result:

- no output from the forbidden AppUI import check

### Phase 4.8H Acceptance Criteria

- Detail header is not clipped by the titlebar or safe area.
- Poster placeholder icon and text are fully visible.
- Header's primary title is `detail.displayTitle`, not media type.
- `Movie` / `TV Episode`, availability, and metadata status are auxiliary badges.
- Poster placeholder remains 2:3 and visually richer without debug text.
- Header, metadata, and files cards have visible but restrained glass thickness.
- Detail background has static cinematic depth instead of a flat black wall.
- Files card groups file identity, status, resume information, and actions clearly.
- Metadata card uses a badge for match status and avoids prominent summary duplication.
- Browser table no longer emphasizes an often-empty `Year / Episode` column.
- Browser table expresses metadata status using existing `metadataLabel`.
- Browser header communicates `Library` / `Local library` and groups Add Folder / Scan cleanly.
- Sidebar selected row reads more like a glass selection while preserving native selection behavior.
- AppUI boundary remains clean.
- All final verification commands pass.
