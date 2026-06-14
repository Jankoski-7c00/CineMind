# Phase 9 Provider-Neutral AI Foundation Completion Report

Completion date: 2026-06-14

## Completion Verdict

Phase 9 is complete.

The implementation adds a provider-neutral AI foundation, privacy-safe request
preparation, Application-owned global opt-in and availability policy, and a
compact macOS AI settings surface. It does not add a concrete provider,
semantic search, AI tag suggestion, or AI artifact persistence.

Required decisions:

```text
Approved concrete AI provider: no
Production AI default: disabled and not configured
New Persistence API required: no
Migrations.swift changed: no
Schema version: 6
```

## Implemented Scope

- Added dependency-free `AI` and `AITests` targets.
- Added provider identity and `embeddings` / `chat` capability contracts.
- Added embedding and chat request/response primitives and provider protocols.
- Added recoverable provider-neutral errors and unavailable-provider behavior.
- Added allowlisted privacy input and deterministic prepared-text projection.
- Added Application-owned global opt-in, provider availability, and policy gate.
- Added a composition-root `UserDefaults` adapter that stores one boolean.
- Added a compact AI Settings tab alongside existing TMDB settings.
- Added focused AI, Application, and AppUI tests.

## AI Target API Summary

The `AI` target owns:

- `AIProviderDescriptor`
- `AIProviderCapability`
- `EmbeddingProvider` and `ChatProvider`
- embedding and chat request/response value types
- `AIProviderError`
- `UnavailableAIProvider`
- privacy input, approved text, and privacy projector types

The target has no project-target dependency and no provider SDK or network
client.

## Privacy Projection Summary

Prepared AI input can represent only:

- title
- year
- media type
- allowlisted public metadata fields

There are no fields for paths, filenames, hashes, bookmarks, video, poster
data, subtitle text, prompts, responses, or private notes. The projector also
rejects obvious raw path and long hexadecimal hash content if it is mistakenly
placed in an allowed text field. Projection is deterministic, omits empty
fields, and applies a deterministic length limit.

## Application Settings and Policy Summary

`AISettingsService` owns:

- global enabled/disabled state
- provider availability mapping
- disabled, not-configured, unavailable, ready, and safe error states
- required-capability readiness checks
- one policy gate for future AI work
- disabled fallback on preference read/write failure

AppUI receives only Application-owned settings snapshots, status strings, and
the settings manager protocol.

## AppUI and Composition Root Summary

- `AISettingsViewModel` delegates all state changes to Application.
- `AISettingsView` shows the global toggle, policy status, provider status,
  capability labels when available, and the privacy boundary.
- The existing Settings scene now uses compact Metadata and AI tabs.
- `CineMindApp` constructs `UserDefaultsAISettingsStore` and
  `AISettingsService`.
- Production composition injects `notConfigured` and no concrete provider.
- The preference adapter uses only
  `com.cinemind.settings.ai.enabled` and stores only a boolean.

## Persistence and Migration Decision

No Persistence source file or API changed. No migration, AI artifact table,
vector table, model identifier, or provider configuration table was added.
`Migrations.swift` still ends at version 6.

## Boundary Audit

Boundary status: clean.

- AppUI has no direct import of AI, Persistence, Metadata, Subtitle, Playback,
  PlaybackAVFoundation, AVFoundation, AVKit, or AppKit.
- AppUI has no `UserDefaults`, provider protocol, or AI target usage.
- Application depends on AI for provider-neutral contracts.
- AI has no dependency on Application, AppUI, Persistence, or unrelated
  service modules.
- CineMindApp does not directly depend on the AI target.
- No migration/schema logic appears in AI, Application, or AppUI.
- No Phase 9 diff touches Persistence, Domain, Metadata, Subtitle, Playback,
  PlaybackAVFoundation, or Scanner.

The AppUI storage grep still finds two pre-existing TMDB copy strings that
mention macOS Keychain; they are display text, not Keychain API access.

## Verification

Baseline before implementation:

- `swift test list` - passed; discovered 449 tests.
- `swift test` - passed; 449 tests, 0 failures.

Targeted tests:

- `swift test --filter AIModuleTests` - passed; 8 tests, 0 failures.
- `swift test --filter AISettingsServiceTests` - passed; 9 tests, 0 failures.
- `swift test --filter AISettingsViewModelTests` - passed; 5 tests, 0 failures.

Sequential target builds:

- `swift build --target AI` - passed.
- `swift build --target Application` - passed.
- `swift build --target AppUI` - passed.
- `swift build --target CineMindApp` - passed.

Full verification:

- `swift test` - passed; 471 tests, 0 failures.
- `git diff --check` - passed.
- Phase 9 boundary greps - passed with only the documented pre-existing TMDB
  Keychain display-text matches.
- Schema audit - version remains 6.
- Network-source audit - no network client, URL, endpoint, concrete provider,
  or provider SDK appears in the Phase 9 implementation.

## Manual Smoke Status

Partially verified with an isolated disposable environment:

- Launched `CineMindApp` with
  `CFFIXED_USER_HOME=/private/tmp/cinemind-phase9-smoke.kXoJAn`.
- App startup succeeded and the isolated Application Support directory was
  created.
- Process-specific `lsof` inspection found no active network sockets.
- Settings visual inspection and toggle interaction were not verified because
  macOS denied Accessibility access to `osascript`.
- No real user preference state was modified.

## Deferred Work

Phase 9 intentionally does not include:

- a concrete AI provider or provider configuration
- credentials, endpoints, or model selection
- semantic search
- automatic tag suggestion
- AI artifact persistence or schema changes
- vector storage or similarity search
- subtitle summarization or recommendations

Roadmap update:

- The next AI phase requires a dedicated planning round, an assigned phase
  number, and an explicit concrete embedding-provider decision.
- Phase 10 is reserved for the native macOS UI redesign.
