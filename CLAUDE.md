# CLAUDE.md (Production-Grade)

## Project: CineMind

CineMind is a macOS-native, local-first, single-user media library
application focused on stability, correctness, and long-term
maintainability.

This document defines **hard constraints** for architecture,
development, and AI collaboration.\
All contributors and AI agents must follow these rules strictly.

------------------------------------------------------------------------

# 0. Documentation Structure (CRITICAL)

All project constraints are distributed across multiple documents.

## Required Documents

/CLAUDE.md ← Global rules (this file) /docs/product-scope.md ← What to
build (feature boundary) /docs/architecture.md ← How to build (system
design)

------------------------------------------------------------------------

## Priority Order (MUST FOLLOW)

When documents conflict:

1.  CLAUDE.md
2.  product-scope.md
3.  architecture.md

------------------------------------------------------------------------

## Interpretation Rules

-   product-scope.md defines feature scope
-   architecture.md defines implementation structure
-   CLAUDE.md defines non-negotiable constraints

------------------------------------------------------------------------

## Critical Rule

Claude Code MUST:

-   read all three documents before changes
-   never implement features outside scope
-   never violate architecture
-   never override constraints

------------------------------------------------------------------------

# 1. Non-Negotiable Constraints

## Product Boundaries

-   macOS only (Apple Silicon)
-   Local-first
-   Single-user only
-   No server architecture
-   No DRM
-   No piracy
-   No downloading

## Engineering Boundaries

-   No cross-platform frameworks
-   No second playback engine
-   No distributed systems

------------------------------------------------------------------------

# 2. Architecture Constraints

Strict layering:

-   AppUI → Domain → Services → Persistence

Forbidden:

-   UI accessing DB directly
-   Playback in Domain
-   AI in core models

------------------------------------------------------------------------

# 3. Scope Enforcement

Before implementing:

-   Must exist in product-scope.md
-   Must match stage (MVP/Beta)

Reject immediately:

-   server features
-   plugins
-   API
-   DRM
-   realtime FS watch

------------------------------------------------------------------------

# 4. Data Model Invariants

-   MediaItem = logical media
-   MediaFile = physical file

Rules:

-   one MediaItem → many MediaFiles
-   never use path as identity

------------------------------------------------------------------------

# 5. Playback

-   libmpv only
-   coordinator controlled

------------------------------------------------------------------------

# 6. Metadata

-   TMDB only (MVP)
-   manual override required

------------------------------------------------------------------------

# 7. Subtitle

-   local + embedded + online
-   non-blocking

------------------------------------------------------------------------

# 8. AI Rules

-   optional only
-   async, cancellable

Allowed: - title, metadata

Forbidden: - raw paths, video

------------------------------------------------------------------------

# 9. Claude Code Rules

Must:

-   read all docs
-   explain plan

Must NOT:

-   expand scope
-   break architecture
-   add dependencies silently

------------------------------------------------------------------------

# 10. Development Order

1.  Domain
2.  Persistence
3.  Scanner
4.  Playback
5.  Metadata
6.  Search
7.  Subtitle
8.  AI

------------------------------------------------------------------------

# 11. Non-Goals

-   not Plex
-   not Jellyfin
-   not media server

------------------------------------------------------------------------

# 12. Decision Framework

-   simple \> complex
-   local \> cloud
-   stability \> features
