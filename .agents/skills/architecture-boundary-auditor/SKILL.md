---
name: architecture-boundary-auditor
description: Use for CineMind module boundary audits, forbidden import checks, AppUI/Application/Persistence/Domain layering reviews, dependency direction checks, architecture regressions, or any task involving UI-to-persistence access.
---

# Architecture Boundary Auditor

## Purpose

Use this skill to verify that CineMind's module boundaries remain clean.

This skill is designed to catch architectural drift, especially direct UI-to-Persistence dependencies, circular dependencies, infrastructure leakage into Domain, and unnecessary public API exposure.

## When to use

Use this skill when the user asks about:

- architecture boundaries
- forbidden imports
- AppUI boundary cleanliness
- Persistence dependency direction
- Application use case boundaries
- whether UI can call a Persistence API
- whether a new protocol is needed
- phase reviews
- code reviews
- audits before implementation
- regressions involving imports or package dependencies

Also use this skill after code changes that touch:

- `Sources/AppUI`
- `Sources/Application`
- `Sources/Persistence`
- `Sources/Domain`
- `Package.swift`

## Expected architecture

CineMind should follow this dependency direction:

```text
AppUI
  ↓
Application
  ↓
Domain

Persistence
  ↓
Domain
```

Application may depend on protocols or abstractions that are implemented by Persistence, depending on the package structure. The critical rule is that UI-facing code should not directly depend on database implementation details.

## Boundary principles

### Domain

Domain should contain core concepts and business rules.

Domain should not know about:

- SQLite
- database rows
- migrations
- AppKit/SwiftUI UI concepts
- file system scanning implementation details beyond domain abstractions
- persistence infrastructure
- view models

### Application

Application should contain use cases and orchestration.

Application may:

- define narrow protocols
- map persisted data into UI-safe or domain-safe structures
- coordinate repositories
- expose use cases to AppUI

Application should avoid:

- raw SQL
- schema definitions
- database connection lifecycle
- UI rendering concerns

### Persistence

Persistence should contain:

- SQLite access
- migrations
- persisted models
- repositories
- query implementations
- storage lifecycle

Persistence should avoid depending on:

- AppUI
- UI view models
- SwiftUI rendering concepts

### AppUI

AppUI should contain:

- views
- view models
- UI state
- user interactions
- presentation formatting

AppUI should not directly import or call:

- Persistence repositories
- SQLite stores
- migration code
- persisted row models

## Required audit commands

Run the relevant subset from repository root.

```bash
git status --short
git diff --stat
rg "import Persistence" Sources/AppUI Tests || true
rg "import AppUI" Sources/Persistence Sources/Application Sources/Domain Tests || true
rg "import SQLite|import SQLite3|import GRDB|import FMDB" Sources/AppUI Sources/Application Sources/Domain Tests || true
rg "Migrations|Migration|CREATE TABLE|ALTER TABLE|PRAGMA" Sources/AppUI Sources/Application Sources/Domain Tests || true
rg "Persistence\." Sources/AppUI Tests || true
rg "AppUI\." Sources/Persistence Sources/Application Sources/Domain Tests || true
sed -n '1,260p' Package.swift
```

If the repository does not have one of these directories, adjust the command and report the adjustment.

## Package dependency review

When `Package.swift` is relevant, inspect:

- target dependencies
- test target dependencies
- product exports
- whether AppUI depends on Persistence
- whether Persistence depends on Application or AppUI
- whether Domain depends on any higher-level module

Red flags:

```text
.target(name: "AppUI", dependencies: ["Persistence", ...])
.target(name: "Domain", dependencies: ["Persistence", ...])
.target(name: "Persistence", dependencies: ["AppUI", ...])
```

Potentially acceptable, depending on design:

```text
.target(name: "Application", dependencies: ["Domain", ...])
.target(name: "Persistence", dependencies: ["Domain", ...])
.target(name: "AppUI", dependencies: ["Application", "Domain", ...])
```

## Analysis questions

Answer these in every audit:

1. Does `AppUI` import `Persistence` directly?
2. Does `AppUI` reference Persistence types indirectly by fully qualified names?
3. Does `Persistence` depend on `AppUI`?
4. Does `Domain` depend on infrastructure?
5. Does `Application` contain raw database or migration logic?
6. Does `Package.swift` encode the expected dependency direction?
7. Is the requested change possible through an Application use case?
8. Would a narrow protocol avoid a boundary violation?
9. Is any public API being exposed only to work around layering?

## Severity levels

Use these severity labels.

### Critical

- circular module dependency
- AppUI directly depends on Persistence for runtime data access
- Domain imports Persistence or UI
- Persistence imports AppUI
- migration/schema logic appears outside Persistence

### High

- Application contains raw SQL or migration code
- AppUI uses persisted row models directly
- tests enforce forbidden dependencies
- public Persistence API added only for UI convenience

### Medium

- boundary is technically clean but conceptually leaky
- Application protocol too broad
- UI model mirrors persistence row too closely
- package target dependency is broader than needed

### Low

- naming confusion
- documentation mismatch
- minor test-only dependency smell

## Recommended fix patterns

### Pattern 1: Route through Application

Use when AppUI needs data that Persistence can provide.

```text
AppUI → Application use case → narrow protocol → Persistence implementation
```

### Pattern 2: Define a narrow read protocol

Use when a use case needs a small subset of repository behavior.

```swift
protocol LibraryItemDetailReading {
    func fetchLibraryItemDetail(id: MediaItemID) throws -> LibraryItemDetail?
}
```

The protocol should be as narrow as possible.

### Pattern 3: Map persisted data before UI

Avoid exposing persisted row/detail types directly to AppUI.

Use Application or Domain-safe models.

### Pattern 4: Reuse existing Persistence APIs

Before creating new APIs, search for existing queries and repository methods.

## What not to recommend

Do not recommend:

- letting AppUI import Persistence "just for now"
- moving SQLite logic into Application
- exposing persisted row types as UI models
- adding a broad service locator to bypass boundaries
- weakening package boundaries to make one call compile
- editing migrations to fix a UI read problem

## Output template

```text
Boundary status:
- Clean / violated / inconclusive

Commands run:
- ...

Findings:
- Severity:
  Evidence:
  Impact:
  Recommendation:

Package dependency review:
- ...

AppUI boundary:
- ...

Persistence boundary:
- ...

Domain boundary:
- ...

Application boundary:
- ...

Recommended next step:
- ...

Files modified:
- none / ...
```

## Example clean report

```text
Boundary status:
- Clean

Commands run:
- `rg "import Persistence" Sources/AppUI Tests || true`
- `rg "import AppUI" Sources/Persistence Sources/Application Sources/Domain Tests || true`
- `sed -n '1,260p' Package.swift`

Findings:
- No direct AppUI import of Persistence found.
- No Persistence import of AppUI found.
- Package.swift keeps AppUI depending on Application rather than Persistence.

Package dependency review:
- AppUI dependency direction is acceptable.
- Persistence remains infrastructure-only.

Recommended next step:
- Continue implementing the UI-facing read through Application use cases.

Files modified:
- none
```

## Example violation report

```text
Boundary status:
- Violated

Commands run:
- `rg "import Persistence" Sources/AppUI Tests || true`

Findings:
- Severity: Critical
  Evidence: Sources/AppUI/LibraryDetailViewModel.swift imports Persistence.
  Impact: UI now depends directly on database implementation.
  Recommendation: Move the fetch behind an Application use case and inject a narrow read protocol.

Package dependency review:
- AppUI must not depend on Persistence.

Recommended next step:
- Remove direct Persistence import from AppUI.
- Define or reuse an Application-level use case.

Files modified:
- none
```

## Final response requirements

When this skill is used, the response must include:

- boundary status
- commands run
- evidence for each finding
- severity
- recommended fix
- whether files were modified

If this was an audit-only request, do not modify files.
