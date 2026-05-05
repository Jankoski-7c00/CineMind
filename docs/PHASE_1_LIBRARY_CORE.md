# PHASE_1_LIBRARY_CORE.md

## Phase 1: Library Core MVP

This document defines the **first development phase** of CineMind.

The goal of this phase is to build a **stable, minimal, local media library core** before introducing playback, metadata providers, subtitles, or AI features.

This phase is **strictly constrained** by:

- CLAUDE.md
- docs/PRODUCT_SCOPE.md
- docs/ARCHITECTURE.md

---

# 1. Phase Goal

Build a working pipeline:

User selects a folder  
→ scan files  
→ identify media  
→ store in SQLite  
→ reload after restart  
→ rescan with reconciliation

---

# 2. Scope Definition

## Included

- Domain models
- SQLite persistence
- Migration system
- Scanner (MVP)
- Basic media identification
- Incremental scan
- Missing file handling
- Minimal debug listing

## Excluded

- Playback (libmpv)
- TMDB metadata
- Subtitle system
- AI features
- Plugin system
- Local HTTP API
- UI polish
- Real-time filesystem watcher

---

# 3. Module Scope

Only implement:

- Domain
- Persistence
- Scanner
- Shared

Optional minimal:

- AppUI (debug only)

Do NOT implement:

- Playback
- Metadata
- Subtitle
- AI
- Jobs (beyond basic scan execution)

---

# 4. Domain Model (Minimal)

## Required Entities

- Library
- LibraryFolder
- MediaItem
- MediaFile
- ScanRun
- ScanIssue

## Rules

- MediaItem = logical media
- MediaFile = physical file
- One MediaItem → multiple MediaFiles
- File path must NOT be identity
- Missing files must be representable

---

# 5. Persistence (SQLite)

## Required Tables

- libraries
- library_folders
- media_items
- media_files
- scan_runs
- scan_issues
- schema_migrations

## Rules

- Use migration versioning
- Use transactions
- Do NOT delete unavailable files
- Preserve future extensibility

---

# 6. Scanner MVP

## Responsibilities

- Traverse directory
- Detect video files
- Parse filenames
- Identify movie vs episode
- Create/update MediaFile
- Create/link MediaItem
- Detect missing files
- Record ScanRun

## Supported Formats

- .mp4
- .mkv
- .mov
- .avi
- .m4v

## Basic Parsing

- Movie: Title + optional year
- Episode: SxxExx pattern

---

# 7. Scanner Non-Goals

Do NOT implement:

- TMDB matching
- AI classification
- Subtitle linking
- Video fingerprinting
- ffprobe integration
- Real-time file watching

---

# 8. Task Breakdown (Claude Code)

## Task 1: Project Skeleton

- Create Swift package structure:
  - Domain
  - Persistence
  - Scanner
  - Shared
- Minimal App shell only

---

## Task 2: Domain Models

Implement:

- Library
- LibraryFolder
- MediaItem
- MediaFile
- ScanRun
- ScanIssue

Requirements:

- Pure Swift
- No external dependencies
- Add unit tests

---

## Task 3: SQLite Schema

- Implement schema
- Add migration system
- Create repository interfaces
- Add persistence tests

---

## Task 4: Scanner MVP

Implement:

- directory traversal
- file filtering
- filename parsing
- create/update records
- missing file marking

Add tests for:

- new file
- missing file
- duplicate file
- renamed file

---

## Task 5: Debug Listing

- Provide minimal output:
  - list media items
  - list associated files

Can be:

- simple SwiftUI list OR
- debug console output

---

# 9. Claude Code Usage Rules

Each task must:

- stay within defined scope
- avoid unrelated modules
- explain plan before coding
- generate tests for Domain/Persistence

Forbidden:

- adding playback
- adding metadata provider
- adding AI logic
- modifying architecture

---

# 10. Acceptance Criteria

Phase 1 is complete ONLY if:

- database initializes correctly
- folder can be added
- scan populates media
- rescan reconciles data
- missing files marked unavailable
- data persists across restart
- tests pass for Domain/Persistence/Scanner

---

# 11. Success Definition

This phase is NOT about UI or features.

It is about:

- correct data model
- stable persistence
- predictable scanning

---

# End of Phase 1
