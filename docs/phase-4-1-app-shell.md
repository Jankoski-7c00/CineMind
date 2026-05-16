# Phase 4.1 App Shell

Canonical file: `docs/phase-4-1-app-shell.md`

Phase 4.1 creates the first real macOS app shell. It proves app launch, dependency composition, local database creation, and the top-level SwiftUI navigation structure.

---

# 1. Goal

Build the minimal native app shell:

```text
SwiftUI app launches
  -> Application Support database path resolves
  -> CineMindStore opens or creates
  -> NavigationSplitView shell renders
  -> loading/ready/error states are visible
```

---

# 2. Scope

Implement only:

- `AppUI` target.
- `CineMindApp` executable target.
- SwiftUI app entry point.
- Static `NavigationSplitView` shell.
- App environment skeleton.
- Application Support path resolution.
- `CineMindStore` open/create.
- Startup loading, ready, and error states.
- Preservation of existing shell/spike targets.

Static sidebar sections:

- Library
- Movies
- TV Episodes
- Recently Played
- Needs Metadata
- Folders

The sidebar items may be non-functional placeholders in this phase.

---

# 3. Explicit Non-Goals

Do not implement:

- scanner workflow
- folder picker
- security-scoped bookmarks
- metadata refresh
- TMDB provider wiring
- poster image loading
- library list/grid browser
- playback
- libmpv integration
- embedded render surface
- playback controls
- persistence schema changes
- new migrations

---

# 4. Architecture

Target dependencies:

```text
AppUI
  -> Application
  -> Domain
  -> Shared

CineMindApp
  -> AppUI
  -> Application
  -> Persistence
  -> Shared
```

Phase 4.1 must not wire:

```text
CineMindApp -> Scanner
CineMindApp -> Metadata
CineMindApp -> Playback
CineMindApp -> LibMPVPlayback
```

The restriction on CineMindApp importing Scanner, Metadata, Playback, and LibMPVPlayback is a **Phase 4.1-only constraint**. Later phases will wire those modules into the composition root as their respective subplans require them.

AppUI must not import:

- `Persistence`
- `Scanner`
- `Metadata`
- `Playback`
- `LibMPVPlayback`

---

# 5. Responsibility Boundary

Phase 4.1 enforces a strict split between UI concerns and infrastructure concerns.

**AppUI owns:**
- SwiftUI views (sidebar, root view, loading/error states).
- View-level state (startup state as an observable model).
- The `AppShellViewModel` and `AppShellState` types.

**AppUI must NOT own:**
- Database path resolution.
- `CineMindStore` construction or references.
- Any `import Persistence`.
- Application Support directory creation.
- `ensureLibrary` calls.

**CineMindApp (the composition root) owns:**
- Application Support path resolution via `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)`.
- Creating the `CineMind` directory under Application Support if it does not exist.
- Constructing `CineMindStore(path:)` with the resolved database URL.
- Calling `ensureLibrary()` once after the store opens successfully.
- Surfacing the success or failure result to AppUI as a startup state value.

The data flow is one-way:

```text
CineMindApp resolves path
  -> creates directory
  -> opens CineMindStore
  -> calls ensureLibrary
  -> publishes startup state
  -> AppUI observes state and renders loading/ready/error
```

AppUI never sees a concrete `CineMindStore` and never resolves a file system path.

---

# 6. Expected File and Target Changes

Package changes:

- Add `AppUI` library product and target (with at least one source file; no empty targets).
- Add `CineMindApp` executable target (with at least `main.swift`; no empty targets).

Expected new app files:

```text
Sources/AppUI/
  AppShellState.swift         -- startup state enum: loading, ready, failed
  AppShellViewModel.swift     -- observable view model for the shell
  CineMindRootView.swift      -- root view: switch on startup state
  SidebarView.swift           -- static sidebar with six sections

Sources/CineMindApp/
  main.swift                                   -- @main SwiftUI App entry point
  CineMindAppEnvironmentFactory.swift           -- path resolution, store creation, ensureLibrary
```

Names may change if the implementation finds simpler local names, but responsibilities must remain separated.

Do not modify playback, metadata, scanner, or migration files.

---

# 7. App Environment Design

Create a minimal environment, not a service locator.

**AppUI-side state model (`AppShellState`):**

```text
AppShellState
  - loading
  - ready
  - failed(message: String)
```

**AppUI-side view model (`AppShellViewModel`):**

```text
AppShellViewModel : ObservableObject
  - state: AppShellState
```

`AppShellViewModel` is the single piece of observable state that AppUI observes. It does not hold database URLs, store references, or path logic.

**CineMindApp-side factory (`CineMindAppEnvironmentFactory`):**

The composition root resolves the database URL, creates the store, calls `ensureLibrary`, and sets `AppShellViewModel.state` to `.ready` or `.failed`. AppUI receives only the resulting state — it never sees how the store was created.

Do not add scanner, metadata, playback, poster, or job services in Phase 4.1.

---

# 8. View Hierarchy

Use SwiftUI:

```text
CineMindRootView
  -> startup switch
     -> LoadingView
     -> AppShellView
     -> StartupErrorView

AppShellView
  -> NavigationSplitView
     -> SidebarView
     -> PlaceholderContentView
     -> PlaceholderDetailView
```

The root view must show a clear error state if database startup fails.

---

# 9. Database Path Behavior

Startup behavior (all owned by CineMindApp, not AppUI):

1. Resolve the Application Support directory for CineMind using `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)`.
2. Append the `CineMind` subdirectory.
3. Create the directory if missing (using `FileManager.default.createDirectory`).
4. Use a stable database filename:

```text
CineMind.sqlite
```

5. Open `CineMindStore(path:)`.
6. Let existing migrations run.
7. Call `ensureLibrary(name:)` so the default library row exists on first launch.
8. Publish `ready` on success.
9. Publish `failed(message)` on path or store open failure.

No schema changes are allowed.

---

# 10. Risks

- SwiftPM executable app setup may differ from a bundled `.app` target.
- Application Support path behavior may differ between `swift run` and later packaged app execution.
- Synchronous store initialization can block briefly; do not add extra startup work.
- AppUI may accidentally import concrete infrastructure.
- Empty SwiftPM targets can cause confusing build warnings or failures.

Mitigation:

- Keep concrete dependency wiring inside `CineMindApp`.
- Keep AppUI imports narrow.
- Keep startup work minimal.
- Introduce each new target with at least one minimal source file — never create an empty target.

---

# 11. Validation

Automated:

- `swift build`
- `swift test`

Manual:

- `swift run CineMindApp`
- App window appears.
- Static sidebar renders.
- Placeholder content and detail render.
- Database file is created under Application Support.
- Relaunch reopens the same database.
- Startup error state can be exercised through a debug/preview initializer on `AppShellViewModel` that sets `.failed(...)` directly, or by pointing the store at an invalid path.
- Existing shell/spike targets still build.

---

# 12. Acceptance Criteria

Phase 4.1 is complete only if:

- `AppUI` target exists and builds.
- `CineMindApp` target exists and builds.
- The app launches as a native SwiftUI macOS app.
- `NavigationSplitView` renders.
- Static sidebar sections render.
- Application Support database path is resolved by CineMindApp only.
- `CineMindStore` opens or creates successfully.
- `ensureLibrary` succeeds.
- Loading, ready, and error states exist and render.
- AppUI does not import concrete infrastructure modules (no `import Persistence` in AppUI).
- AppUI does not own database path resolution or store construction.
- CineMindApp does not import Scanner, Metadata, Playback, or LibMPVPlayback (Phase 4.1 constraint only).
- Existing shell/spike targets remain unchanged.
- Existing tests pass.

---

# 13. Implementation Task Breakdown

## Task 4.1A — AppUI Target + Minimal Shell Views

**Goal:** Create the `AppUI` library target with all required SwiftUI views and state types. The target compiles but has no database awareness.

**Files to create:**
- `Sources/AppUI/AppShellState.swift`
- `Sources/AppUI/AppShellViewModel.swift`
- `Sources/AppUI/CineMindRootView.swift`
- `Sources/AppUI/SidebarView.swift`

**Package changes:**
- Add `.library(name: "AppUI", targets: ["AppUI"])` to products.
- Add `.target(name: "AppUI", dependencies: ["Application", "Domain", "Shared"])` to targets.

**Contents:**
- `AppShellState.swift`: Enum with `.loading`, `.ready`, `.failed(String)`.
- `AppShellViewModel.swift`: `ObservableObject` with a `@Published var state: AppShellState`. No database URL, no store reference, no path logic.
- `CineMindRootView.swift`: Observes `AppShellViewModel`. Switches on `state` to render `LoadingView`, `AppShellView`, or `StartupErrorView`. All subviews are private.
- `SidebarView.swift`: `List` with six static `Label` rows. No selection binding.

**Dependency rules:**
- AppUI may import: `SwiftUI`, `Application`, `Domain`, `Shared`.
- AppUI must not import: `Persistence`, `Scanner`, `Metadata`, `Playback`, `LibMPVPlayback`.

**Explicit non-goals:**
- No database path logic.
- No store creation or `import Persistence`.
- No selection state or navigation routing.
- No data loading from any service.

**Validation:**
- `swift build` compiles the AppUI target.
- `swift test` passes all existing tests.

**Rollback scope:** Delete the four source files and revert `Package.swift` additions.

**Dependencies:** None (first implementation task).

**Risks:**
- Low. Pure SwiftUI views with no data dependencies.
- `NavigationSplitView` API on macOS 14: use the simplest two-column initializer `NavigationSplitView { sidebar } content: { ... } detail: { ... }`.

---

## Task 4.1B — CineMindApp Target + Minimal SwiftUI App

**Goal:** Create the `CineMindApp` executable target with a minimal `@main` SwiftUI app. Initially use a placeholder startup state to prove the app launches before wiring real store startup in Task 4.1C.

**Files to create:**
- `Sources/CineMindApp/main.swift`

**Package changes:**
- Add `.executable(name: "CineMindApp", targets: ["CineMindApp"])` to products.
- Add `.executableTarget(name: "CineMindApp", dependencies: ["AppUI", "Application", "Persistence", "Shared"])` to targets.

**Contents:**
- `main.swift`: `@main struct CineMindApp: App` with a `WindowGroup` containing `CineMindRootView()`. Inject an `AppShellViewModel` as an environment object. Initially set the view model state to `.ready` (placeholder) so the shell renders. Real startup wiring replaces this in Task 4.1C.

**Dependency rules:**
- CineMindApp may import: `AppUI`, `Application`, `Persistence`, `Shared`, `SwiftUI`.
- For Phase 4.1 only: CineMindApp must not import `Scanner`, `Metadata`, `Playback`, or `LibMPVPlayback`. This is a phase-specific constraint, not a permanent roadmap rule.

**Explicit non-goals:**
- No Application Support path resolution yet.
- No CineMindStore creation yet.
- No `ensureLibrary` call yet.
- No scanner, metadata, playback, or libmpv wiring.

**Validation:**
- `swift build` compiles the CineMindApp target.
- `swift run CineMindApp` opens a minimal window with the sidebar shell (placeholder ready state).
- `swift test` passes all existing tests.

**Rollback scope:** Delete `main.swift` and revert `Package.swift` additions.

**Dependencies:** Task 4.1A (AppUI target must exist with views).

**Risks:**
- Medium. `WindowGroup` with `@main` on macOS requires correct `NSApplication` lifecycle. Use the simplest `@main struct CineMindApp: App` pattern. No `NSApplicationDelegate` adaptor needed in Phase 4.1.

---

## Task 4.1C — App Data Path + Store Startup

**Goal:** Wire real database startup in the composition root. CineMindApp resolves the Application Support path, creates directories, opens CineMindStore, and calls ensureLibrary. AppUI remains unaware of all of this.

**Files to create or change:**
- `Sources/CineMindApp/CineMindAppEnvironmentFactory.swift` (new)
- `Sources/CineMindApp/main.swift` (update to call factory)

**Contents of `CineMindAppEnvironmentFactory.swift`:**
- Resolve `~/Library/Application Support/CineMind/CineMind.sqlite` using `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)`.
- Append `CineMind` subdirectory.
- Create the directory tree with `FileManager.default.createDirectory(at:withIntermediateDirectories:)` if it does not exist.
- Construct `CineMindStore(path:)`.
- Call `store.ensureLibrary(name:)`.
- Set `AppShellViewModel.state` to `.ready` on success or `.failed(message)` on error.
- This is the only file that imports `Persistence` in the CineMindApp target.

**Changes to `main.swift`:**
- Replace the placeholder `.ready` state with a call into the factory.
- Run startup on app launch (synchronously during init or via a `Task` if startup blocking is a concern).

**Explicit non-goals:**
- Do not add path resolution or store logic to any file under `Sources/AppUI/`.
- Do not import Persistence in AppUI.
- Do not wire Scanner, Metadata, Playback, or LibMPVPlayback.

**Validation:**
- First launch: `swift run CineMindApp` creates `~/Library/Application Support/CineMind/CineMind.sqlite`.
- Relaunch: same database is reused; `ensureLibrary` finds the existing row.
- `swift build` compiles.
- `swift test` passes.

**Rollback scope:** Delete `CineMindAppEnvironmentFactory.swift`, revert `main.swift` changes.

**Dependencies:** Task 4.1B (CineMindApp target and `main.swift` must exist).

**Risks:**
- Medium. Path resolution behavior under `swift run` may differ from a bundled `.app`. Mitigation: `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)` is consistent in both contexts.
- Synchronous store init blocks the main thread briefly. Mitigation: acceptable for Phase 4.1 startup only; future phases can move to a background `Task`.

---

## Task 4.1D — Startup State Plumbing

**Goal:** Complete the loading/ready/error state display. Wire observable state through `AppShellViewModel` so the root view correctly transitions through all three states. Keep the error state testable without CLI flags.

**Files likely to change:**
- `Sources/AppUI/CineMindRootView.swift` — ensure all three states render correctly.
- `Sources/AppUI/AppShellViewModel.swift` — ensure state transitions are observable.
- `Sources/CineMindApp/CineMindAppEnvironmentFactory.swift` — ensure state is published correctly.

**Error state testing (no CLI flags):**
The error state can be exercised through any of:
- A debug/preview initializer on `AppShellViewModel` that accepts `.failed("Simulated error")` directly.
- Temporarily pointing the database URL at an unwritable path (e.g., `/dev/null/CineMind.sqlite`) during manual testing.
- The factory throwing a descriptive error when directory creation or store open fails.

**Explicit non-goals:**
- No `--simulate-startup-failure` CLI argument.
- No scanner, metadata, playback, folder picker, or library browser wiring.
- No localization keys (deferred per Phase 4 spec).

**Validation:**
- Manual: launch succeeds and shows the ready shell.
- Manual: exercise error path via debug initializer or invalid path and confirm `StartupErrorView` renders.

**Rollback scope:** Revert view or view model changes.

**Dependencies:** Task 4.1C (real store startup must work).

**Risks:**
- Low. The state enum is already defined; this task is about confirming transitions render correctly.

---

## Task 4.1E — Existing Target Regression Check

**Goal:** Verify no existing targets were broken by Phase 4.1 changes.

**Existing targets to verify:**
- `CineMindShell`
- `CineMindPlaybackShell`
- `CineMindPlaybackSurfaceSpike`
- `CineMindMetadataShell`
- All test targets: `DomainTests`, `PersistenceTests`, `ScannerTests`, `ApplicationTests`, `PlaybackTests`, `MetadataTests`, `CineMindMetadataShellTests`

**Actions:**
1. `swift build` — all products compile.
2. `swift test` — all test suites pass.

**Explicit non-goals:**
- No source code changes to existing targets.
- No refactoring of existing shell/spike targets.

**Validation:** `swift build` and `swift test` exit with zero status.

**Rollback scope:** N/A (verification only; fix any regressions found).

**Dependencies:** Tasks 4.1A–4.1D must be complete.

**Risks:**
- Low. Phase 4.1 adds targets and source files without modifying existing code. Risk is minimal unless `Package.swift` changes inadvertently affect existing dependency declarations.

---

## Task 4.1F — Phase 4.1 Completion Checklist

**Goal:** Confirm every acceptance criterion is met. This is a verification gate, not a code task.

**Checklist:**

- [ ] `AppUI` library target exists and builds.
- [ ] `CineMindApp` executable target exists and builds.
- [ ] AppUI depends only on `Application`, `Domain`, `Shared`.
- [ ] AppUI does not import `Persistence`, `Scanner`, `Metadata`, `Playback`, or `LibMPVPlayback`.
- [ ] AppUI does not own database path resolution or store construction.
- [ ] CineMindApp depends only on `AppUI`, `Application`, `Persistence`, `Shared`.
- [ ] CineMindApp does not import `Scanner`, `Metadata`, `Playback`, or `LibMPVPlayback` (Phase 4.1 constraint only).
- [ ] No empty targets were created — each target was introduced with at least one source file.
- [ ] Application Support path is resolved inside CineMindApp only.
- [ ] Directory creation, `CineMindStore` open, and `ensureLibrary` all happen inside CineMindApp only.
- [ ] `NavigationSplitView` renders with sidebar, placeholder content, and placeholder detail.
- [ ] Loading state renders before the store is ready.
- [ ] Ready state renders the split view shell.
- [ ] Error state renders a human-readable failure message.
- [ ] Error state is testable without `--simulate-startup-failure` CLI flag.
- [ ] First launch creates `~/Library/Application Support/CineMind/CineMind.sqlite`.
- [ ] Relaunch reuses the same database.
- [ ] `swift build` compiles all targets, including pre-existing shell/spike targets.
- [ ] `swift test` passes all existing test suites.
- [ ] No schema changes.
- [ ] No new migrations.
- [ ] No files modified in Scanner, Metadata, Playback, LibMPVPlayback.
- [ ] No new dependencies added beyond those specified.

**Dependencies:** Tasks 4.1A–4.1E.

---

# 14. Recommended Execution Order

| Order | Task                                      | Depends On     |
|-------|-------------------------------------------|----------------|
| 1     | Task 4.1A: AppUI target + minimal views   | —              |
| 2     | Task 4.1B: CineMindApp target + main.swift | Task 4.1A      |
| 3     | Task 4.1C: App data path + store startup  | Task 4.1B      |
| 4     | Task 4.1D: Startup state plumbing         | Task 4.1C      |
| 5     | Task 4.1E: Existing target regression     | Tasks 4.1A–4.1D |
| 6     | Task 4.1F: Completion checklist           | Task 4.1E      |

Task 4.1A and 4.1B are deliberately separated so that the AppUI target can be validated independently before the executable is introduced. Task 4.1C is the critical integration point where the composition root meets Persistence — it is isolated to a single task so any issues are easy to roll back.
