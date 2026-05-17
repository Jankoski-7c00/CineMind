---
name: sqlite-migration-guardian
description: Use for CineMind SQLite schema work, Persistence changes, Migrations.swift review, migration tests, persisted model changes, database initialization, WAL/read-only behavior, repository storage behavior, or deciding whether a change requires a migration.
---

# SQLite Migration Guardian

## Purpose

Use this skill to protect CineMind's SQLite persistence layer from unsafe schema changes and unnecessary migration edits.

This skill is intended to force an explicit migration decision before changing database schema, persisted representations, repository behavior, or database initialization.

## When to use

Use this skill when the task mentions or touches:

- SQLite
- schema
- migration
- `Migrations.swift`
- Persistence
- persisted models
- repository storage
- table definitions
- columns
- indexes
- database initialization
- WAL mode
- read-only database behavior
- migration tests
- existing database compatibility
- data backfill
- query failures caused by schema mismatch

Also use this skill when a task might accidentally require a migration, even if the user did not explicitly mention migrations.

## High-risk files and concepts

Treat these as high-risk:

- `Sources/Persistence/Migrations.swift`
- SQLite table definitions
- SQLite column names
- SQLite indexes
- schema versioning
- `PRAGMA user_version`
- database open/init logic
- WAL configuration
- read-only database mode
- repository write paths
- persisted row structs
- Codable/database mapping for stored fields
- migration tests
- fixtures containing old database versions

## Migration decision framework

Before editing migration code, classify the change.

### Class A: Query-only change

Examples:

- add a new read query using existing columns
- map existing columns into an Application model
- reuse existing persisted detail data

Migration required:

```text
No
```

### Class B: Application mapping change

Examples:

- convert persisted model to domain model differently
- add a UI-facing DTO from existing data
- combine existing fields

Migration required:

```text
No
```

### Class C: Repository behavior change without schema change

Examples:

- alter filtering logic
- fix ordering
- update transaction boundary
- add a write using existing columns

Migration required:

```text
Usually no
```

But tests are required.

### Class D: Persisted model shape change

Examples:

- add a field to a persisted row struct
- rename a persisted property
- change nullability assumptions
- change decoding behavior

Migration required:

```text
Maybe
```

Determine whether the database schema changed or only the Swift mapping changed.

### Class E: True schema change

Examples:

- add table
- drop table
- rename table
- add column
- drop column
- rename column
- change column type
- add index
- change constraints
- change foreign keys
- backfill stored values

Migration required:

```text
Yes
```

## Required discovery commands

Run the relevant subset from repository root.

```bash
git status --short
git diff --stat
rg "Migration|Migrations|migrate|schema|CREATE TABLE|ALTER TABLE|DROP TABLE|CREATE INDEX|DROP INDEX|PRAGMA|user_version" Sources/Persistence Tests || true
rg "Persisted[A-Za-z0-9_]*|Repository|Store|SQLite|Database|Transaction|WAL|read-only|readonly" Sources/Persistence Tests || true
rg "INSERT INTO|UPDATE|DELETE FROM|SELECT|JOIN|ORDER BY|GROUP BY" Sources/Persistence Tests || true
git diff -- Sources/Persistence/Migrations.swift
```

If a specific entity is involved, search for it:

```bash
rg "<EntityName>" Sources/Persistence Sources/Application Sources/Domain Tests || true
```

## Required questions

Answer these before editing:

1. Does the task require new stored data?
2. Does the task require a new table or column?
3. Does an existing column already contain the required data?
4. Is this only a read/query/mapping change?
5. Are persisted Swift structs changing independently of schema?
6. Are old databases expected to keep working?
7. Is a data backfill needed?
8. Are migration tests already present?
9. Is `Migrations.swift` currently clean in `git diff`?
10. Can the implementation avoid schema changes?

## Migration rules

### Rule 1: Do not edit migrations for read-only features

If existing tables and columns already provide the data, do not modify migrations.

State explicitly:

```text
No migration required because the change only reads existing persisted data.
```

### Rule 2: Do not edit migrations to fix architecture

Do not use schema changes to solve an Application/AppUI boundary issue.

### Rule 3: Add tests for true schema changes

If a migration is required, include tests that cover:

- migrating from the previous schema version
- resulting schema shape
- data preservation
- default/backfilled values
- idempotency or correct version gating

### Rule 4: Preserve compatibility

Migration must handle databases created by previous released schema versions.

Do not assume every user database is freshly created.

### Rule 5: Keep migration changes isolated

Avoid mixing migration changes with unrelated refactors.

Schema diff should be small and explicit.

### Rule 6: Report Migrations.swift status

Final report must say one of:

```text
Migrations.swift changed: yes
```

or

```text
Migrations.swift changed: no
```

## WAL and read-only checks

When work touches database open mode or file lifecycle, consider:

- WAL files (`-wal`, `-shm`)
- read-only behavior
- transaction boundaries
- concurrent reads/writes
- test database isolation
- cleanup of temporary database files

Do not change WAL/read-only behavior without targeted tests.

## Persisted model checks

When persisted Swift models change, verify:

- optionality matches database nullability
- default values are safe
- row decoding remains compatible
- enum/raw value decoding handles old values
- date encoding/decoding remains consistent
- IDs preserve type safety

## Output template

```text
Migration decision:
- Required / not required / inconclusive

Classification:
- Class A/B/C/D/E

Reasoning:
- ...

Existing schema/API evidence:
- ...

Migrations.swift:
- changed: yes/no
- current diff: clean/non-clean/not checked

Required tests:
- ...

Commands run:
- ...

Risks:
- ...

Recommended next step:
- ...
```

## Example: no migration required

```text
Migration decision:
- Not required

Classification:
- Class A: query-only change

Reasoning:
- The requested feature reads media item detail data that already exists in persisted tables.
- No new table, column, index, constraint, or backfill is required.
- The change can be implemented by adapting an existing Persistence query through Application.

Existing schema/API evidence:
- Existing detail query returns the needed local title, media type, year, summary, and file data.

Migrations.swift:
- changed: no
- current diff: clean

Required tests:
- Add or update Application use case tests.
- No migration test required.

Commands run:
- `rg "MediaItemDetail|fetchMediaItemDetail" Sources/Persistence Sources/Application Tests`
- `git diff -- Sources/Persistence/Migrations.swift`

Risks:
- Mapping may omit optional metadata fields if not covered by tests.

Recommended next step:
- Reuse the existing detail query and add targeted Application tests.
```

## Example: migration required

```text
Migration decision:
- Required

Classification:
- Class E: true schema change

Reasoning:
- The feature requires storing a new persistent `posterAspectRatio` field.
- No existing column stores this value.
- Existing databases need a default value or nullable column.

Existing schema/API evidence:
- No existing `posterAspectRatio` column or equivalent field was found.

Migrations.swift:
- changed: yes
- current diff: contains new migration version

Required tests:
- Migrate from previous schema version.
- Verify column exists after migration.
- Verify old rows receive nil/default value.
- Verify newly inserted rows preserve the field.

Commands run:
- `rg "posterAspectRatio|poster_aspect_ratio" Sources/Persistence Tests`
- `rg "CREATE TABLE|ALTER TABLE|user_version" Sources/Persistence Tests`
- `swift test --filter MigrationTests`

Risks:
- Existing user databases may contain rows without poster metadata.
- Backfill should not assume network metadata availability.
```

## What not to do

Do not:

- modify `Migrations.swift` speculatively
- add columns for values that can be derived from existing data
- rewrite old migrations without a compatibility rationale
- change persisted column names casually
- hide migration changes inside unrelated commits
- rely only on fresh database tests
- skip migration tests after true schema changes
- claim no migration is needed without checking existing schema/API coverage

## Final response requirements

When using this skill, always include:

- migration decision
- classification
- whether `Migrations.swift` changed
- whether schema changed
- whether migration tests are needed
- commands run
- risks and unverified assumptions
