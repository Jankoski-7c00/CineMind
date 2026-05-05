# PRODUCT_SCOPE.md

## Project: CineMind

This document defines the **strict feature scope** of CineMind across
MVP, Beta, and Post-1.0 stages.

Its purpose is to prevent scope creep and ensure the project remains
feasible for a single developer.

------------------------------------------------------------------------

# 1. Product Definition

CineMind is a:

-   macOS-native
-   local-first
-   single-user

personal media library manager focused on:

-   organizing
-   playing
-   searching
-   lightly enhancing (via AI)

local movie and TV collections.

------------------------------------------------------------------------

# 2. Media Scope

## Supported Media Types

-   Movies
-   TV Series

Not supported:

-   Music
-   Photos
-   Short-form content
-   Streaming platforms

------------------------------------------------------------------------

## TV Series Support Strategy

### MVP

-   Detect season/episode via filename (SxxExx)
-   Basic grouping into seasons
-   Flat episode listing

### Beta+

-   Improved grouping
-   Season-level metadata

### Not in MVP

-   Complex episode merging
-   Multi-version episode mapping
-   Advanced airing order logic

------------------------------------------------------------------------

# 3. Feature Scope by Stage

------------------------------------------------------------------------

## 3.1 MVP (Must Have)

### Library

-   Single library only
-   Multiple folders (local + NAS)
-   Manual folder authorization
-   Persistent access

------------------------------------------------------------------------

### Scanning

-   Manual scan
-   Incremental scan
-   Missing file detection
-   Rename tolerance (basic)

------------------------------------------------------------------------

### Playback

-   libmpv playback
-   Resume playback
-   Audio/subtitle switching
-   Playback history

------------------------------------------------------------------------

### Metadata

-   TMDB provider
-   Poster + basic metadata
-   Manual rematch

------------------------------------------------------------------------

### Subtitle

-   Local subtitle support
-   Embedded subtitle support
-   Online subtitle search

------------------------------------------------------------------------

### Search

-   Keyword search (FTS)
-   Filter (year, type)
-   Sort (recent, title)

------------------------------------------------------------------------

### Tagging

-   Manual tags
-   Favorites / collections

------------------------------------------------------------------------

### AI (MVP Limited Scope)

Only the following are allowed:

-   Semantic search
-   Automatic tag suggestion

AI must be:

-   optional
-   non-blocking
-   user-controlled

------------------------------------------------------------------------

### Cover System

-   Poster
-   Backdrop (optional)
-   Local cache

------------------------------------------------------------------------

### Export

-   JSON export (basic)

------------------------------------------------------------------------

## 3.2 Beta (Should Have)

### Metadata

-   Improved matching
-   Better fallback handling

------------------------------------------------------------------------

### AI Features

-   Subtitle summarization
-   Smart recommendations

------------------------------------------------------------------------

### UI/UX

-   Better browsing
-   Improved filtering

------------------------------------------------------------------------

### Automation (Optional)

-   Scheduled scan (basic)

------------------------------------------------------------------------

## 3.3 Post-1.0 (Explicitly Deferred)

These are intentionally NOT part of MVP or Beta:

-   Multi-user system
-   Media server
-   Cloud sync
-   Remote streaming
-   Plugin system
-   Local HTTP API
-   DRM support
-   Downloader features
-   Real-time filesystem monitoring
-   Complex episode mapping
-   AI-based viewing analytics

------------------------------------------------------------------------

# 4. AI Scope Boundaries

AI is strictly limited to:

-   discovery (search)
-   light enrichment (tags, summary)

AI must NOT:

-   control playback
-   modify core data automatically
-   block user actions

------------------------------------------------------------------------

# 5. Non-Goals

CineMind is NOT:

-   Plex
-   Jellyfin
-   Kodi
-   a streaming platform
-   a media server
-   a downloader
-   a DRM player

------------------------------------------------------------------------

# 6. Scope Control Rules

When adding a new feature:

It must satisfy ALL:

-   Does not increase system complexity significantly
-   Does not require server architecture
-   Does not introduce persistent background services
-   Can be implemented within current architecture
-   Does not break local-first principle

If not, it is automatically deferred.

------------------------------------------------------------------------

# 7. Guiding Principle

CineMind is not about feature completeness.

It is about:

-   correctness
-   stability
-   clarity
-   long-term maintainability

------------------------------------------------------------------------

# End of Scope
