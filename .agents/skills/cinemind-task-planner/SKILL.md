---
name: cinemind-task-planner
description: Use for CineMind task planning, phase planning, scoped implementation, audit planning, review planning, and any request that needs explicit goals, non-goals, allowed scope, forbidden scope, discovery commands, test strategy, acceptance criteria, and stop conditions.
---

# CineMind Task Planner

## Purpose

Use this skill before starting non-trivial work in the CineMind repository.

This skill is intended to prevent vague execution, accidental scope creep, unnecessary refactors, and premature code edits. It should be used whenever the task involves planning, phased work, audit work, architecture-sensitive changes, persistence-sensitive changes, or implementation work with unclear boundaries.

The output of this skill is a concrete execution plan that another Codex run can follow.

## When to use

Use this skill for requests like:

- "Plan Phase 4.4B"
- "Audit whether this can be implemented"
- "Review this phase before coding"
- "Implement this, but keep the diff minimal"
- "Do not modify migrations"
- "Check whether existing APIs cover this"
- "Make a step-by-step execution plan"
- "Prepare a Codex prompt for this task"
- "Define what files are allowed to change"

Also use this skill when the user gives constraints such as:

- audit only
- no source changes
- no test changes
- no migration changes
- no new Persistence API
- no AppUI boundary violations
- minimal diff
- phase-specific scope

## CineMind architecture assumptions

CineMind is treated as a layered Swift/SwiftPM application with these conceptual modules:

- `Domain`
- `Application`
- `Persistence`
- `AppUI`

Default boundary assumptions:

- `Domain` should not depend on infrastructure or UI.
- `Application` coordinates use cases and owns UI-facing orchestration.
- `Persistence` owns SQLite/database access and persisted representations.
- `AppUI` should consume Application-level use cases or protocols.
- `AppUI` should not directly import or depend on `Persistence`.
- New Persistence APIs should not be added until existing queries and repositories have been discovered.

## Required planning behavior

Before implementation, produce a plan containing:

1. **Goal**
   - What the task is expected to accomplish.
   - Use concrete acceptance language.

2. **Non-goals**
   - What must not be done.
   - Include unrelated refactors, broad cleanup, opportunistic API redesign, schema changes, and UI rewrites unless explicitly requested.

3. **Scope**
   - List likely affected modules.
   - List candidate files or directories.
   - Distinguish "likely to inspect" from "allowed to modify."

4. **Forbidden scope**
   - List files/directories that must not be modified.
   - Include `Sources/Persistence/Migrations.swift` unless a true schema change is required.
   - Include UI/Persistence cross-boundary changes unless the task explicitly requires them.

5. **Discovery**
   - Identify searches and commands needed before code edits.
   - Prefer `rg`, `swift test --list-tests`, `git diff --stat`, and focused file inspection.

6. **Implementation approach**
   - Describe the minimal code path.
   - Prefer narrow protocols, existing queries, and Application-level adaptation.
   - Avoid duplicate repository APIs.

7. **Test strategy**
   - Identify targeted tests first.
   - Identify final verification command.
   - Do not claim tests pass unless run in the current session.

8. **Acceptance criteria**
   - Define what must be true at the end.
   - Include architecture boundary checks where relevant.

9. **Stop conditions**
   - Conditions that should pause implementation and report back.
   - Examples: schema change required, unclear existing API coverage, test suite blocked, boundary violation discovered.

10. **Risk notes**
   - Include migration risk, module boundary risk, API duplication risk, and test coverage risk.

## Default discovery commands

Use the relevant subset of these commands from the repository root.

```bash
git status --short
git diff --stat
find Sources Tests -maxdepth 3 -type f | sort
rg "public func|func fetch|func list|func load|func save|func update|func delete" Sources Tests || true
rg "protocol .*Repository|struct .*Repository|class .*Repository|actor .*Repository" Sources Tests || true
rg "UseCase|Query|Queries|Store|Repository|Detail|Summary" Sources Tests || true
rg "import Persistence" Sources/AppUI Tests || true
rg "import AppUI" Sources/Persistence Sources/Application Sources/Domain Tests || true
rg "Migration|Migrations|CREATE TABLE|ALTER TABLE|PRAGMA|user_version" Sources/Persistence Tests || true
swift test --list-tests
```

## Planning rules

### Rule 1: Audit-only means no writes

If the user asks for an audit, discovery, verification, or review without implementation, do not modify files.

The final report must explicitly include:

```text
Files modified: none
```

### Rule 2: Prefer existing APIs before new APIs

Before proposing a new repository, query, store, or Persistence method, inspect existing APIs.

The plan must include:

```text
New Persistence API required: unknown until discovery
```

or, after discovery:

```text
New Persistence API required: yes/no
```

### Rule 3: Treat migrations as high-risk

Do not plan to edit `Sources/Persistence/Migrations.swift` unless there is a true schema change.

If the task might touch stored data, include a migration decision point.

### Rule 4: Keep AppUI isolated

If the task involves UI-facing reads or presentation, route data through Application use cases or narrow protocols.

Do not plan to import Persistence from AppUI.

### Rule 5: Tests are part of the plan

Every implementation plan must include:

- targeted test command
- full verification command
- expected test scope
- what remains unverified if tests cannot run

## Output template

Use this structure.

```text
Goal:
- ...

Non-goals:
- ...

Scope:
- Inspect:
  - ...
- Modify only if needed:
  - ...

Forbidden:
- ...

Discovery:
- Commands:
  - ...
- Questions to answer:
  - ...

Implementation approach:
1. ...
2. ...
3. ...

Tests:
- Targeted:
  - ...
- Full:
  - ...

Acceptance criteria:
- ...

Stop conditions:
- ...

Risks:
- ...
```

## Example output

```text
Goal:
- Determine whether Phase 4.4B can be implemented using existing Persistence read APIs.

Non-goals:
- Do not implement UI changes.
- Do not add new Persistence APIs unless discovery proves a gap.
- Do not modify Migrations.swift.

Scope:
- Inspect:
  - Sources/Persistence
  - Sources/Application
  - Sources/AppUI
  - Tests
- Modify only if needed:
  - Sources/Application
  - Tests/ApplicationTests

Forbidden:
- Sources/Persistence/Migrations.swift
- Direct AppUI imports of Persistence
- Broad repository redesign

Discovery:
- Commands:
  - rg "MediaItemDetail|Metadata|Poster|Playback" Sources Tests
  - rg "public func fetch|func fetch" Sources/Persistence Sources/Application Tests
  - rg "import Persistence" Sources/AppUI Tests || true
  - git diff --stat
- Questions to answer:
  - Does an existing detail query already expose the required fields?
  - Can Application adapt existing persisted data?
  - Is any schema change required?

Implementation approach:
1. Identify existing read APIs and returned fields.
2. Define the narrow Application-facing protocol if needed.
3. Extend the use case using existing Persistence capabilities.
4. Add targeted Application tests.
5. Verify AppUI remains boundary-clean.

Tests:
- Targeted:
  - swift test --filter LibraryItemDetailUseCaseTests
- Full:
  - swift test

Acceptance criteria:
- Existing Persistence APIs are reused if sufficient.
- No AppUI direct Persistence dependency is introduced.
- Migrations.swift remains unchanged unless a schema gap is proven.
- Relevant tests pass.

Stop conditions:
- Required fields are not available from existing APIs.
- Schema migration appears necessary.
- Existing tests cannot run due to environment/toolchain failure.

Risks:
- Hidden dependency from AppUI to Persistence.
- Duplicating a query that already exists.
- Accidentally expanding public Persistence API surface.
```

## Final response requirements

When this skill is used, the final response must include:

- the plan
- any assumptions
- whether implementation should proceed
- commands recommended before edits
- known risks

Do not make code changes as part of this skill unless the user explicitly asks to implement after planning.
