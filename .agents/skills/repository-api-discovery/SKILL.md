---
name: repository-api-discovery
description: Use before adding new CineMind Persistence APIs, repository methods, queries, stores, public functions, or use-case protocols; use to determine whether existing APIs already cover requested read/write needs.
---

# Repository API Discovery

## Purpose

Use this skill before adding any new repository, query, store, or public Persistence API in CineMind.

This skill exists to prevent duplicate APIs, unnecessary public surface area, and architecture drift. It forces discovery of existing capabilities before design or implementation.

## When to use

Use this skill when the task involves:

- adding a repository method
- adding a Persistence query
- adding a store API
- exposing data to AppUI
- deciding whether existing APIs are sufficient
- reading library item details
- reading metadata
- reading poster assets
- reading playback history
- writing scan results
- changing Application use cases that depend on Persistence
- "Do we need a new API?"
- "Can existing APIs cover this?"

Also use this skill when the user says:

- "No new Persistence API unless needed"
- "Audit existing APIs"
- "Check coverage"
- "Reuse existing query if possible"
- "Narrow read protocol"
- "Existing Persistence APIs should cover this"

## Default principle

Do not add a new public API until discovery proves the existing API surface cannot satisfy the need.

Prefer this order:

1. Existing Application use case
2. Existing Application protocol
3. Existing Persistence query/repository
4. Narrow extension to an existing use case/protocol
5. New narrow Persistence API only if necessary
6. Broad repository redesign only if explicitly requested

## Required discovery commands

Run relevant commands from the repository root.

```bash
git status --short
git diff --stat
rg "public func|func fetch|func list|func load|func save|func update|func delete|func insert|func upsert" Sources/Persistence Sources/Application Tests || true
rg "protocol .*Repository|protocol .*Reading|protocol .*Writing|struct .*Repository|class .*Repository|actor .*Repository" Sources Tests || true
rg "MediaItem|MediaFile|Library|Folder|Metadata|Poster|Playback|Scan|Episode|Detail|Summary" Sources/Persistence Sources/Application Sources/Domain Tests || true
rg "Query|Queries|UseCase|Store|Repository|Detail|Summary|DTO|Mapper" Sources/Persistence Sources/Application Tests || true
```

For task-specific discovery, search exact entity and likely variants.

Examples:

```bash
rg "MediaItemDetail|LibraryItemDetail|fetchMediaItemDetail|PersistedMediaItemDetail" Sources Tests || true
rg "MetadataItem|MetadataSource|Poster|PosterAsset|Artwork" Sources Tests || true
rg "PlaybackHistory|latestPlayed|playedAt|resume" Sources Tests || true
rg "ScanRun|ScanIssue|Scanner" Sources Tests || true
```

## Required analysis questions

Answer these before proposing an API:

1. What exact data does the caller need?
2. Is the operation read-only or write?
3. Is the operation single-item, batch, list, search, or aggregate?
4. Does an existing Application use case already expose this?
5. Does an existing Persistence query already return this data?
6. Does an existing persisted detail model contain the fields?
7. Is the missing piece only mapping or filtering?
8. Can the caller use a narrow Application protocol?
9. Would adding a new Persistence API create duplicate behavior?
10. Is a new API truly necessary?
11. If necessary, what is the narrowest method signature?
12. Which tests should prove coverage?

## API coverage categories

Classify existing coverage as one of these.

### Full coverage

Existing API returns all required data with acceptable semantics.

Recommendation:

```text
Use existing API. No new API required.
```

### Partial coverage: mapping gap

Existing API returns raw data, but Application needs to map/combine it.

Recommendation:

```text
Add or adjust Application mapping/use case. No new Persistence API required.
```

### Partial coverage: query parameter gap

Existing API almost works but lacks a small filter/sort/limit parameter.

Recommendation:

```text
Consider narrow extension to existing API.
```

### Partial coverage: missing relationship

Existing APIs return individual pieces but not the required relationship or join.

Recommendation:

```text
Consider a new narrow query if composition is inefficient or semantically wrong.
```

### No coverage

No existing API returns the needed data.

Recommendation:

```text
Add the narrowest necessary API with tests.
```

## API design rules

If a new API is required:

### Keep it narrow

Prefer:

```swift
func fetchMediaItemDetail(id: MediaItemID) throws -> PersistedMediaItemDetail?
```

Avoid:

```swift
func fetchEverythingForUI(id: MediaItemID) throws -> Any
```

### Use domain-safe identifiers

Prefer typed IDs over raw strings or integers.

### Avoid UI concepts in Persistence

Do not name Persistence APIs after views, screens, or UI interactions unless the concept is truly domain/persistence-level.

Avoid names like:

```swift
fetchLibraryDetailScreenData
fetchSidebarCardViewModel
```

Prefer names like:

```swift
fetchMediaItemDetail
fetchLibraryFolderChildren
fetchPosterAsset
```

### Separate read and write protocols

If Application needs only reads, define a reading protocol.

Example:

```swift
protocol MediaItemDetailReading {
    func fetchMediaItemDetail(id: MediaItemID) throws -> PersistedMediaItemDetail?
}
```

### Avoid duplicate methods

Do not create:

```swift
fetchMediaItemDetail2
loadMediaItemDetail
getMediaItemDetail
```

if an equivalent `fetchMediaItemDetail` already exists.

### Consider batch APIs carefully

Add batch APIs only when there is a concrete N+1 or performance issue.

## Application boundary guidance

If AppUI needs data:

1. AppUI should depend on Application.
2. Application should expose a use case or view-independent model.
3. Application may depend on a narrow protocol.
4. Persistence should implement that protocol or be adapted at composition root.
5. AppUI should not import Persistence.

## Persistence API decision template

Use this structure.

```text
Need:
- ...

Operation:
- read/write
- single/batch/list/search/aggregate

Existing APIs found:
- File:
  Symbol:
  Coverage:
  Notes:

Coverage classification:
- Full / partial mapping gap / partial parameter gap / partial relationship gap / no coverage

Gap:
- ...

Recommendation:
- ...

New API required:
- yes/no

Proposed narrow API, if required:
- ...

Tests:
- ...

Commands run:
- ...
```

## Example: existing API sufficient

```text
Need:
- AppUI needs media item detail including local title, type, year, summary, metadata flags, latest played date, and files.

Operation:
- read
- single item detail

Existing APIs found:
- File: Sources/Persistence/MediaItemDetailQueries.swift
  Symbol: fetchMediaItemDetail(id:)
  Coverage: Returns persisted detail data for one media item.
  Notes: Includes the required local and metadata-backed fields.

Coverage classification:
- Full coverage

Gap:
- No Persistence gap. Application may need mapping into a UI-safe detail model.

Recommendation:
- Reuse `fetchMediaItemDetail(id:)`.
- Extend the Application use case with a narrow read protocol if needed.
- Do not add a new Persistence API.

New API required:
- no

Tests:
- Add/update Application use case tests.
- No migration tests required.

Commands run:
- `rg "MediaItemDetail|fetchMediaItemDetail|PersistedMediaItemDetail" Sources Tests`
- `rg "public func|func fetch" Sources/Persistence Sources/Application Tests`
```

## Example: new API required

```text
Need:
- Application needs all poster assets for a list of media item IDs in display order.

Operation:
- read
- batch

Existing APIs found:
- File: Sources/Persistence/PosterAssetRepository.swift
  Symbol: fetchPosterAsset(mediaItemID:)
  Coverage: Single-item lookup only.
  Notes: Existing API would cause N+1 queries for the requested caller.

Coverage classification:
- Partial coverage: query parameter/batch gap

Gap:
- No batch lookup exists.

Recommendation:
- Add a narrow batch read API on the existing poster asset repository or query type.
- Keep return type persistence-level and map in Application.

New API required:
- yes

Proposed narrow API, if required:
- `func fetchPosterAssets(mediaItemIDs: [MediaItemID]) throws -> [MediaItemID: PersistedPosterAsset]`

Tests:
- Add Persistence tests for batch lookup.
- Add Application tests for mapping/order preservation if needed.

Commands run:
- `rg "Poster|PosterAsset|Artwork" Sources Tests`
- `rg "fetch.*Poster|Poster.*fetch" Sources/Persistence Sources/Application Tests`
```

## What not to do

Do not:

- add a new API without searching existing ones
- expose Persistence directly to AppUI
- duplicate a query under a new name
- add broad generic APIs for one narrow caller
- mix schema migration with API discovery unless a true persistence gap exists
- add UI-specific naming to Persistence
- use raw dictionaries or `Any` to avoid modeling
- change repository architecture opportunistically

## Final response requirements

When using this skill, always include:

- exact data need
- existing APIs found
- coverage classification
- gap analysis
- whether a new API is required
- proposed narrow API only if required
- tests needed
- commands run
