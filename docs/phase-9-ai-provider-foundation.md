# Phase 9 Provider-Neutral AI Foundation and Global Opt-In

Canonical file: `docs/phase-9-ai-provider-foundation.md`

Planning date: 2026-06-14

Phase 9 establishes the optional AI boundary required before semantic search or
automatic tag suggestion can be implemented safely. It adds provider-neutral
contracts, privacy-safe request preparation, a global user opt-in, and a clear
default unavailable state.

This phase does not connect a concrete AI provider and does not add an AI
feature to library search or curation. It is a development plan only and does
not implement code.

---

# 1. Current Audit

## 1.1 Repository Baseline

Current repository state at planning time:

- The working tree is clean on `main`.
- `main` is aligned with `origin/main`.
- Latest commit: `9620b5e Add secure TMDB token settings`.
- Phase 6 implemented SQLite FTS5 keyword search.
- Phase 7 implemented durable manual tags, favorites, and collections.
- Phase 8 implemented versioned, privacy-projected basic JSON export.
- Current SQLite schema version is 6.
- Current package has no `AI` product, target, or test target.
- Current source search found no `EmbeddingProvider`, `ChatProvider`,
  `AIProvider`, `AiArtifact`, semantic-search, or AI-tag-suggestion
  implementation.
- Current AppUI forbidden import checks return no matches.
- Baseline `swift test` passed 449 tests with 0 failures.

Current completed user-facing foundations:

- local library folders and manual scanning
- movie and episode identity
- AVFoundation-compatible playback and playback history
- TMDB metadata, manual rematch, poster cache, and secure token settings
- local and embedded subtitles
- provider-neutral online subtitle search/download plumbing
- SQLite FTS5 keyword search, filters, and sorting
- manual tags, favorites, and collections
- basic versioned JSON export

## 1.2 Product and Architecture Signal

The next main phase should be Phase 9 Provider-Neutral AI Foundation because:

- `docs/product-scope.md` includes semantic search and automatic tag suggestion
  in the limited MVP AI scope.
- `docs/product-scope.md` requires AI to be optional, non-blocking, and
  user-controlled.
- `CLAUDE.md`, the highest-priority project rule, currently allows AI input
  from title and metadata only and forbids raw paths and video.
- `docs/architecture.md` places AI provider abstraction immediately after JSON
  export and before semantic search and AI tag suggestion.
- `docs/architecture.md` requires the app to behave correctly when no provider
  is configured, a provider is unavailable, a request fails, or AI is disabled.
- Phase 7 already created the durable manual tag model that future AI
  suggestions must respect.
- Phase 8 completed the final non-AI item in the architecture build order before
  provider abstraction.
- The latest secure TMDB settings work provides a useful local pattern for
  Application-facing configuration state, composition-root adapters, and
  AppUI-safe settings behavior.

Known project gaps that do not change the Phase 9 recommendation:

- Assigned tag names are not indexed into `media_search_fts`.
- Basic TV series/season grouping is not implemented beyond flat episode
  listing.
- No concrete online subtitle provider is approved or configured.
- Backdrop support remains optional.

These are valid independent follow-ups, but they must not be folded into the AI
foundation. The concrete subtitle provider is additionally blocked on provider
approval. TV grouping and tag-text FTS can be scheduled separately without
changing the provider-abstraction prerequisite for later AI work.

## 1.3 Provider Decision

Repository documentation and source contain no evidence that a concrete AI
provider has been approved.

Provider decision:

```text
Approved concrete AI provider: no
Phase 9 implementation mode: provider-neutral foundation
Production default: AI disabled and no provider configured
Automated provider behavior: fake providers only
```

Phase 9 must not assume or add:

- Ollama
- LM Studio
- OpenAI-compatible endpoints
- Anthropic-compatible endpoints
- Apple-hosted or cloud-hosted AI services
- a particular embedding model
- a particular chat model
- a provider endpoint URL
- an API token or credential format

A concrete provider decision is not required to implement Phase 9. It is
required before a future semantic-search phase can deliver a real workflow.

## 1.4 Existing AI-Adjacent Coverage

Existing code already provides several useful foundations:

- `TagSource.aiSuggested` exists in Domain.
- The `tags` table accepts `ai_suggested` as a source.
- Manual curation is durable and exposed through Application use cases.
- `LibrarySearchSnapshot` and `LibraryItemSummary` provide an Application-safe
  search result shape.
- `PersistedMediaSearchResult.matchReason` is reserved but currently unused.
- Metadata and media summaries contain title, year, media type, and public
  metadata fields that can later feed a privacy projection.
- Basic JSON export already demonstrates explicit privacy allowlisting.
- `TMDBReadTokenSettingsService` and `TMDBSettingsViewModel` demonstrate
  configuration state without exposing secrets to AppUI.

Existing code does not provide:

- provider-neutral embedding or chat contracts
- provider identity and capability descriptions
- AI-specific recoverable error mapping
- a global AI enabled/disabled preference
- an Application-facing AI settings/status facade
- a privacy-safe AI request projection
- a concrete AI provider
- an AI artifact persistence model
- semantic-search ranking or vector comparison
- automatic tag suggestion workflows

## 1.5 API Coverage Decision

Need:

- provider-neutral AI contracts
- global user opt-in and availability state
- privacy-safe request preparation
- a default no-provider composition state

Operation:

- local preference read/write
- provider capability/status read
- pure privacy projection
- no library-data mutation
- no AI network request in production

Existing API coverage:

```text
AI provider contracts: no coverage
AI settings/status facade: no coverage
AI privacy projection: no coverage
Persistence-backed AI artifact storage: intentionally not needed in Phase 9
```

Repository API decision:

```text
New Persistence API required: no
New Application API required: yes
New AI module API required: yes
```

Phase 9 should not use `CineMindStore` to persist a single application
preference. The global AI opt-in should use a narrow preference-store protocol
implemented in the composition root with `UserDefaults`.

Migration decision:

```text
Migration required: no
Migrations.swift should change: no
Current schema version should remain: 6
```

`AiArtifact` persistence belongs to a later phase that has a concrete artifact
consumer and can define invalidation, provider/model identity, vector storage,
and cleanup semantics from real requirements.

## 1.6 Boundary Baseline

Current boundary status is clean:

- `Sources/AppUI` does not import Persistence, provider modules, playback
  backends, AppKit, or AI.
- lower layers do not import or reference AppUI.
- Application contains no raw SQL or migration statements.
- `Package.swift` keeps AppUI limited to Application, Domain, and Shared.

Phase 9 must preserve this shape:

```text
AppUI -> Application
Application -> AI
CineMindApp -> AppUI / Application
AI -> Shared only, or no project target if Shared is unnecessary
```

The production composition root should avoid a direct `CineMindApp -> AI`
dependency while no concrete provider exists. Add that direct dependency only
in a later provider phase if composition genuinely requires it.

The new `AI` target must not depend on:

- AppUI
- Application
- Persistence
- Playback
- Metadata
- Subtitle
- Scanner
- concrete provider SDKs

## 1.7 Baseline Verification

Passed during planning:

- `swift test list`
  - package built and current tests were discovered.
- `swift test`
  - 449 tests, 0 failures.
- AppUI forbidden import grep
  - no matches.
- lower-layer AppUI reference grep
  - no matches.

This planning round does not modify production code and does not claim Phase 9
implementation verification.

---

# 2. Goal

Implement a provider-neutral AI foundation so CineMind can safely add semantic
search and automatic tag suggestion in later phases without making AI a core
dependency.

Phase 9 must let a user:

- see that AI features are optional
- explicitly enable or disable AI features globally
- see whether a provider is configured and available
- understand that no provider is configured in the default production build
- understand that keyword search, manual tags, playback, scanning, metadata,
  subtitles, and export continue to work without AI

Phase 9 must let later Application use cases:

- depend on stable embedding and chat provider protocols
- inspect provider identity and supported capabilities
- receive recoverable, provider-neutral errors
- prepare AI inputs through a privacy allowlist
- refuse AI work when the global opt-in is disabled
- refuse unsupported work when no provider or capability is available

Phase 9 must:

- add a narrow `AI` target and `AITests` target
- keep provider contracts independent from concrete vendors
- default AI to disabled
- default production provider status to not configured
- persist only the global enabled/disabled preference
- keep credentials and endpoint configuration out of this phase
- prevent raw paths, video data, file hashes, and subtitle text from
  entering prepared AI requests
- keep all failures non-blocking and user-safe
- keep AppUI dependent only on Application-facing settings/status models
- add no migration and no Persistence API

---

# 3. Non-Goals

Do not implement in Phase 9:

- a concrete AI provider
- live AI network calls
- local model process management
- Ollama integration
- LM Studio integration
- OpenAI-compatible endpoint integration
- Anthropic-compatible endpoint integration
- API key or AI credential settings
- provider endpoint settings
- model discovery or model download
- model selection UI
- semantic search
- vector similarity search
- embedding generation for library items
- embedding generation for user queries
- automatic tag suggestion
- tag suggestion acceptance or rejection UI
- automatic tag assignment
- subtitle summarization
- recommendations
- smart collections
- AI jobs or a general job framework
- `AiArtifact` Domain models
- `ai_artifacts` tables
- vector tables, vector extensions, or vector indexes
- AI artifact export
- JSON export format changes
- Phase 7.x tag-text FTS work
- TV series/season grouping
- concrete online subtitle provider integration
- playback, scanner, metadata, subtitle, or export behavior changes
- broad settings redesign
- broad AppUI redesign
- third-party dependencies

Do not add AppUI dependencies on:

- `AI`
- `Persistence`
- `Metadata`
- `Subtitle`
- `Playback`
- `PlaybackAVFoundation`
- `AVFoundation`
- `AVKit`
- `AppKit`
- concrete provider types
- provider SDKs
- `UserDefaults`
- Keychain or Security APIs

Do not store in `UserDefaults`:

- API tokens
- provider secrets
- raw AI prompts
- AI responses
- media paths
- subtitle text
- provider endpoint credentials

---

# 4. Scope

## 4.1 Inspect Before Implementation

- `CLAUDE.md`
- `docs/product-scope.md`
- `docs/architecture.md`
- `docs/phase-6-library-search-fts.md`
- `docs/phase-6-completion-report.md`
- `docs/phase-7-user-curation-tags-favorites-collections.md`
- `docs/phase-7-completion-report.md`
- `docs/phase-8-basic-json-export.md`
- `docs/phase-8-completion-report.md`
- `Package.swift`
- `Sources/Domain/Models.swift`
- `Sources/Application/LibrarySearch.swift`
- `Sources/Application/LibraryCuration.swift`
- `Sources/Application/TMDBReadTokenSettings.swift`
- `Sources/AppUI/TMDBSettingsView.swift`
- `Sources/AppUI/AppShellEnvironment.swift`
- `Sources/CineMindApp/CineMindAppEnvironmentFactory.swift`
- `Sources/CineMindApp/KeychainTMDBReadTokenStore.swift`
- `Sources/CineMindApp/main.swift`
- `Sources/Persistence/Migrations.swift`
- `Tests/ApplicationTests/TMDBReadTokenSettingsServiceTests.swift`
- `Tests/AppUITests/TMDBSettingsViewModelTests.swift`

## 4.2 Likely Implementation Files

- `Package.swift`
- `Sources/AI/AI.swift` (new)
- `Sources/Application/AISettings.swift` (new)
- `Sources/AppUI/AISettingsView.swift` (new)
- `Sources/CineMindApp/UserDefaultsAISettingsStore.swift` (new)
- `Sources/CineMindApp/CineMindAppEnvironmentFactory.swift`
- `Sources/CineMindApp/main.swift`
- `Tests/AITests/AIModuleTests.swift` (new)
- `Tests/ApplicationTests/AISettingsServiceTests.swift` (new)
- `Tests/AppUITests/AISettingsViewModelTests.swift` (new)

## 4.3 Modify Only If Discovery Proves Necessary

- `Sources/AppUI/TMDBSettingsView.swift`
  - Only if a small shared settings composition view is needed.
- `Sources/AppUI/AppShellEnvironment.swift`
  - Expected no change if AI settings remain owned by the macOS Settings scene.
- `Sources/Application/Application.swift`
  - Expected no change; keep AI settings in a focused file.
- `Sources/Shared/Shared.swift`
  - Only if an existing truly shared primitive is needed. Do not turn Shared
    into an AI utility container.

## 4.4 Forbidden Unless Explicitly Approved

- `Sources/Persistence/Migrations.swift`
- `Sources/Persistence/**`
- `Sources/Domain/Models.swift`
- `Sources/Metadata/**`
- `Sources/Subtitle/**`
- `Sources/Playback/**`
- `Sources/PlaybackAVFoundation/**`
- `Sources/Scanner/**`
- new concrete provider targets
- new provider SDK dependencies
- new network clients
- new background-job targets
- new AI artifact storage
- direct AppUI AI/provider imports
- direct AppUI preference storage
- direct AppUI network access
- direct AppUI Keychain access
- broad composition-root refactor

---

# 5. Discovery Commands

Run before implementation:

```sh
git status --short --branch
git diff --stat
git log --oneline --decorate -10
rg -n -i "AI|Embedding|ChatProvider|AiArtifact|semantic|tag suggestion|suggest_tags" Sources Tests Package.swift docs
rg -n "TagSource|ai_suggested|LibrarySearchRequest|LibrarySearchSnapshot|matchReason" Sources Tests
rg -n "Settings|ConfigurationStatus|RuntimeConfiguring|UserDefaults|AppStorage|Keychain" Sources Tests
rg -n "public func|func fetch|func list|func load|func save|func update|func delete|func insert|func upsert" Sources/Persistence Sources/Application Tests
rg -n "CREATE TABLE|CREATE VIRTUAL TABLE|schema_migrations|version[0-9]Statements" Sources/Persistence/Migrations.swift
rg -n "^import (Persistence|Metadata|Subtitle|Playback|PlaybackAVFoundation|AVFoundation|AVKit|AppKit|AI)" Sources/AppUI || true
rg -n "SQLite|CineMindStore|UserDefaults|Keychain|EmbeddingProvider|ChatProvider|AIProvider" Sources/AppUI || true
rg -n "^import AppUI|AppUI\\." Sources/Persistence Sources/Application Sources/Domain Sources/AI Tests || true
swift test list
```

Questions to answer before code:

- Can the `AI` target remain dependency-free, or does it need only `Shared`?
- Which provider capabilities are needed now to avoid redesign before future
  semantic-search work without adding speculative provider features?
- Can a privacy-safe request type make raw paths and file hashes
  unrepresentable?
- Should chat and embedding requests share a common approved-text wrapper, or
  should the privacy projector produce separate request inputs?
- Can the global AI preference use a narrow `UserDefaults` adapter without
  changing AppUI or Persistence?
- Can the existing Settings scene add a small AI section without a broad
  settings refactor?
- Can provider availability be represented without constructing a production
  provider?
- Do all user-safe error messages avoid provider credentials, endpoints, raw
  prompts, and raw responses?

---

# 6. Architecture and Ownership

## 6.1 AI Target Ownership

The new `AI` target should own provider-neutral AI primitives and contracts.

Expected concepts:

- provider identity
- provider capabilities
- embedding request/response primitives
- chat request/response primitives
- provider-neutral recoverable errors
- privacy-approved text or request input
- disabled/unavailable provider behavior where useful

Candidate API shape:

```swift
public struct AIProviderDescriptor: Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let capabilities: Set<AIProviderCapability>
}

public enum AIProviderCapability: String, Sendable, Equatable, Hashable {
    case embeddings
    case chat
}

public protocol EmbeddingProvider: Sendable {
    var descriptor: AIProviderDescriptor { get }
    func embed(_ input: ApprovedAIText) async throws -> EmbeddingVector
}

public protocol ChatProvider: Sendable {
    var descriptor: AIProviderDescriptor { get }
    func complete(_ request: ChatRequest) async throws -> ChatResponse
}
```

This is a candidate shape, not a requirement to preserve exact names. Discovery
may refine it. The final API must remain narrow and must not encode one vendor's
request or response schema.

The AI target must not know:

- `MediaItem`
- `LibraryItemSummary`
- persisted rows
- SQLite
- SwiftUI
- AppKit
- Keychain
- `UserDefaults`
- library paths
- concrete provider credentials

## 6.2 Privacy Projection

Phase 9 must establish a real privacy boundary, not only a documentation
promise.

The preferred design is an allowlisted structured input that can contain only:

- title
- year
- media type
- public metadata

The input must not have fields for:

- absolute paths
- relative paths
- NAS paths
- filenames or directory structure
- file hashes
- bookmarks
- video bytes
- poster bytes
- subtitle text
- raw provider payloads
- private notes

The privacy projector must:

- produce deterministic prepared text
- omit absent fields cleanly
- enforce reasonable size limits
- exclude subtitle text entirely in Phase 9
- avoid logging full prepared prompts or responses
- be pure and unit-testable

Although `docs/architecture.md` describes user-approved subtitle text as a
future possibility, `CLAUDE.md` currently limits allowed AI input to title and
metadata. Subtitle text therefore requires a later explicit scope decision and
must not enter Phase 9 requests.

If implementation cannot make unsafe fields structurally unavailable, stop and
document the weaker design before continuing.

## 6.3 Application Ownership

Application should own the user-facing AI policy and settings facade.

Candidate concepts:

- `AISettingsStoring`
- `AISettingsManaging`
- `AIConfigurationStatus`
- `AISettingsService`
- `AIProviderAvailability`
- `AIFeaturePolicy`

Application responsibilities:

- default global AI opt-in to disabled
- read and write the global opt-in through a narrow protocol
- combine user opt-in and provider availability into a UI-safe status
- prevent future AI work when disabled
- distinguish disabled, not configured, unavailable, and ready states
- expose no provider credentials or provider-specific configuration
- map storage/provider failures into concise user-safe messages

Suggested status semantics:

```text
disabledByUser
noProviderConfigured
providerUnavailable
ready(providerLabel, capabilities)
error(userSafeMessage)
```

The settings facade should be usable without importing `AI` from AppUI. AppUI
receives only Application enums, strings, and protocols.

## 6.4 Preference Storage

The production global opt-in should be stored by a small composition-root
adapter backed by `UserDefaults`.

Rules:

- default value is `false`
- use one namespaced key
- store only the enabled/disabled boolean
- storage failures must not enable AI
- failure fallback is disabled
- do not use `CineMindStore`
- do not add a migration
- do not store provider credentials or request content

If a future concrete provider needs credentials, that later phase must use a
provider-specific secure storage design such as Keychain. It must not widen the
Phase 9 preference adapter.

## 6.5 AppUI Ownership

AppUI may add a compact AI settings view that shows:

- global AI enabled/disabled control
- current provider status
- supported capability labels when available
- a privacy explanation
- a clear default no-provider message

Recommended default message:

```text
No AI provider is configured. Keyword search and manual tags remain available.
```

AppUI must not:

- import `AI`
- create provider requests
- inspect provider descriptors directly
- know endpoint or credential details
- own preference storage
- enable semantic search controls
- expose tag suggestion controls

The existing Settings scene may compose TMDB and AI settings as separate compact
sections or tabs. Do not turn this into a general settings redesign.

## 6.6 Composition Root

`CineMindApp` should:

- construct the `UserDefaults` preference adapter
- construct the Application settings service
- inject no concrete AI provider
- report provider status as not configured
- pass only the settings manager to the AppUI settings view model
- preserve startup when preference storage fails

The default app must launch and all existing features must work with:

```text
AI enabled preference: false
Embedding provider: none
Chat provider: none
Provider status: not configured
```

---

# 7. Error and Availability Semantics

Provider-neutral errors should distinguish at least:

- disabled
- not configured
- unavailable
- unsupported capability
- timeout
- rate limited
- invalid request
- invalid response
- cancelled
- request failed

Rules:

- provider errors must not block non-AI workflows
- error descriptions must not expose credentials
- error descriptions must not expose endpoint URLs unless explicitly approved
- error descriptions must not expose raw prompts or raw responses
- cancellation is not a failure alert by default
- no-provider and disabled states are normal availability states, not startup
  failures

Phase 9 automated tests should use fake providers to prove error mapping. The
production composition root must not make a provider call.

---

# 8. Persistence and Migration Decision

Phase 9 adds no durable AI artifacts.

Do not add:

- `ai_artifacts`
- embedding blobs
- model IDs in Persistence
- provider configuration tables
- vector indexes
- artifact invalidation triggers
- artifact cleanup APIs

Reason:

- no concrete provider or model is approved
- no semantic-search or tag-suggestion consumer exists yet
- artifact identity and invalidation should be designed from the first real
  feature's requirements
- premature storage would create migration and export-contract obligations
  before the data has defined value

Decision:

```text
New Persistence API required: no
Migration required: no
Migrations.swift changed: no
Schema version after Phase 9: 6
```

---

# 9. Implementation Phases

## Phase 9.1 Preflight and Contract Freeze

1. Re-run discovery and boundary commands.
2. Confirm no concrete provider has been approved.
3. Confirm Phase 9 remains foundation-only.
4. Freeze the minimal provider capability set: embeddings and chat.
5. Freeze privacy allowlist fields.
6. Freeze global opt-in default: disabled.
7. Confirm no migration and no Persistence API.

Stop after this phase if a concrete provider, semantic search, or AI artifact
storage is requested as part of the same implementation.

## Phase 9.2 AI Target

1. Add the `AI` product and target.
2. Add provider descriptor and capability types.
3. Add embedding vector and request/response primitives.
4. Add chat request/response primitives.
5. Add provider protocols.
6. Add recoverable provider-neutral errors.
7. Add the privacy-safe input/projector.
8. Add disabled/unavailable behavior only if it simplifies later Application
   orchestration without pretending a provider exists.
9. Add focused `AITests`.

Expected result:

- provider-neutral contracts compile
- privacy projection is deterministic and tested
- the target has no concrete provider or infrastructure dependencies

## Phase 9.3 Application Policy and Settings

1. Add a narrow global preference-store protocol.
2. Add UI-safe settings/status models.
3. Add a settings service that combines opt-in and provider availability.
4. Default to disabled.
5. Treat no provider as a normal unavailable state.
6. Ensure storage failures fall back to disabled.
7. Ensure future AI actions can query one policy gate before provider use.
8. Add focused Application tests with fake stores/providers.

Expected result:

- Application owns AI availability and user-control semantics
- AppUI does not need AI target types
- no library data or Persistence API is involved

## Phase 9.4 macOS Settings and Composition

1. Add a `UserDefaults` preference adapter in `CineMindApp`.
2. Construct the settings service in the composition root.
3. Inject no concrete provider.
4. Add an AppUI settings view model and compact AI settings view.
5. Compose AI settings with the existing TMDB Settings scene.
6. Show a clear no-provider message.
7. Preserve all existing startup and settings behavior.
8. Add focused AppUI view-model tests.

Expected result:

- the user can control the global opt-in
- the app clearly reports that no provider is configured
- existing features remain available and unchanged

## Phase 9.5 Verification and Completion Report

1. Run targeted AI tests.
2. Run targeted Application settings tests.
3. Run targeted AppUI settings tests.
4. Build `AI`, `Application`, `AppUI`, and `CineMindApp`.
5. Run the full test suite.
6. Run boundary greps.
7. Verify schema version remains 6.
8. Launch the app and inspect Settings if a disposable/safe environment is
   available.
9. Write `docs/phase-9-completion-report.md`.

---

# 10. Test Strategy

## 10.1 AI Target Tests

Add focused tests for:

- target imports and builds
- provider capability identity and equality
- embedding vector validation
- deterministic privacy projection
- raw path and file-hash fields cannot enter the structured privacy input
- subtitle text cannot enter the structured privacy input
- input length limits are enforced deterministically
- disabled/unavailable providers return focused errors
- error descriptions do not expose raw request content

Targeted command:

```sh
swift test --filter AIModuleTests
```

## 10.2 Application Tests

Add focused tests for:

- global AI opt-in defaults to disabled
- stored enabled state is read correctly
- enable and disable writes update status
- storage failure falls back to disabled
- no provider produces a normal not-configured state
- unavailable provider produces a recoverable state
- a provider missing a required capability is not treated as ready
- ready status maps only provider label and capability labels
- settings errors are user-safe
- policy gate refuses AI work while disabled

Targeted command:

```sh
swift test --filter AISettingsServiceTests
```

## 10.3 AppUI Tests

Add focused view-model tests for:

- default disabled/not-configured display
- changing the toggle delegates to Application settings
- storage failure leaves the toggle disabled
- provider status updates do not expose provider internals
- the no-provider message preserves keyword-search and manual-tag guidance

Targeted command:

```sh
swift test --filter AISettingsViewModelTests
```

## 10.4 Build Verification

Run sequentially:

```sh
swift build --target AI
swift build --target Application
swift build --target AppUI
swift build --target CineMindApp
```

## 10.5 Full Verification

Run:

```sh
swift test
```

Expected scope:

- all existing tests remain green
- new AI, Application, and AppUI settings tests pass
- no live provider or network is required

## 10.6 Boundary Verification

Run:

```sh
rg -n "^import (Persistence|Metadata|Subtitle|Playback|PlaybackAVFoundation|AVFoundation|AVKit|AppKit|AI)" Sources/AppUI || true
rg -n "SQLite|CineMindStore|UserDefaults|Keychain|EmbeddingProvider|ChatProvider|AIProvider|AI\\." Sources/AppUI || true
rg -n "^import AppUI|AppUI\\." Sources/Persistence Sources/Application Sources/Domain Sources/AI Tests || true
rg -n "^import (Persistence|AppUI|Application|Playback|Metadata|Subtitle|Scanner)" Sources/AI || true
rg -n "CREATE TABLE|ALTER TABLE|PRAGMA|Migrations|Migration" Sources/AI Sources/Application Sources/AppUI || true
git diff --check
```

Expected:

- AppUI has no direct AI or infrastructure dependency.
- AI has no higher-layer or unrelated service dependency.
- no migration/schema logic appears outside Persistence.
- no Phase 9 diff touches Persistence migrations.

## 10.7 Manual Smoke

Use the real app only when it will not mutate unrelated user state unexpectedly.

Smoke steps:

1. Launch CineMind with no AI provider configured.
2. Open Settings.
3. Confirm AI is disabled by default for a fresh preference domain.
4. Confirm the no-provider message is clear.
5. Enable AI and confirm status remains no-provider rather than failing startup.
6. Disable AI and relaunch.
7. Confirm disabled state persists.
8. Confirm library browse, keyword search, manual tags, playback, metadata,
   subtitles, and export remain usable.
9. Confirm no network request is made by Phase 9 behavior.

If a disposable preference domain is not available, report manual smoke as
unverified rather than modifying the user's real preference state.

---

# 11. Acceptance Criteria

Phase 9 is complete only if:

- an `AI` target and `AITests` target exist
- provider-neutral embedding and chat contracts exist
- provider identity and capability contracts exist
- provider-neutral recoverable errors exist
- privacy-safe request preparation exists and is unit-tested
- raw filesystem paths, hashes, video data, and subtitle text are
  excluded from prepared AI inputs
- global AI opt-in defaults to disabled
- the global opt-in is persisted locally without using Persistence
- no provider configured is a normal supported state
- production composition injects no concrete provider
- AppUI shows a clear disabled/not-configured status through Application models
- AppUI does not import AI or infrastructure modules
- keyword search and manual curation remain fully functional without AI
- playback, scanning, metadata, subtitles, and export remain unaffected
- no live provider/network call is required
- no concrete provider SDK or third-party dependency is added
- no Persistence API is added
- no migration is added
- schema version remains 6
- targeted tests pass
- `swift build --target AI` passes
- `swift build --target AppUI` passes
- `swift build --target CineMindApp` passes
- full `swift test` passes
- boundary greps pass
- completion report is written

Required report statements:

```text
Approved concrete AI provider: no
Production AI default: disabled and not configured
New Persistence API required: no
Migrations.swift changed: no
Schema version: 6
```

---

# 12. Stop Conditions

Stop and report before continuing if:

- a concrete provider is requested without an explicit provider decision
- implementation starts adding semantic search or AI tag suggestion
- implementation requires AI artifact persistence
- implementation requires a schema change
- provider credentials or endpoints are proposed for `UserDefaults`
- a third-party dependency is required
- raw paths, hashes, video data, or subtitle text can enter provider
  requests
- AppUI needs to import `AI`, Persistence, provider modules, AppKit, or storage
  APIs
- the AI target needs to depend on Application, Persistence, AppUI, or unrelated
  service modules
- the settings change becomes a broad app-settings redesign
- AI-disabled or no-provider state blocks startup or any non-AI feature
- provider errors expose raw prompts, responses, credentials, or endpoints
- tests reveal the current baseline is failing before Phase 9 changes
- manual smoke would modify the user's real preference state without approval

---

# 13. Risks

## 13.1 Abstraction Risk

Provider abstraction can become speculative and too broad before a real provider
is selected.

Mitigation:

- support only the architecture-required embedding and chat capabilities
- keep vendor-specific configuration out
- prefer small value types and protocols
- stop before adding provider-specific options

## 13.2 Privacy Risk

A generic text API can accidentally receive raw paths or private content.

Mitigation:

- establish an allowlisted structured privacy projection
- make unsafe fields unavailable where practical
- exclude subtitle text entirely in Phase 9
- test deterministic exclusion behavior
- avoid logging request or response bodies

## 13.3 Optionality Risk

An AI foundation can accidentally become required during startup or settings
construction.

Mitigation:

- default disabled
- treat no provider as normal
- make storage/provider failures recoverable
- test all existing features without a provider

## 13.4 Settings Ownership Risk

Direct AppUI use of `UserDefaults` or provider types would weaken boundaries.

Mitigation:

- Application owns settings protocols and status models
- CineMindApp owns the production storage adapter
- AppUI consumes only Application-facing APIs

## 13.5 Credential Risk

Later provider work may try to reuse the Phase 9 preference store for secrets.

Mitigation:

- document and test that the adapter stores only a boolean
- require future credentials to use provider-specific secure storage

## 13.6 Migration Risk

Premature `AiArtifact` storage would create an unnecessary schema and export
contract.

Mitigation:

- explicitly forbid Persistence changes
- keep schema version 6
- defer artifact storage until a real feature defines lifecycle requirements

## 13.7 UI Scope Risk

Adding AI settings could turn into a general settings redesign.

Mitigation:

- add one compact AI section or tab
- preserve the existing TMDB settings behavior
- avoid changing the main library UI

## 13.8 Future Compatibility Risk

A future AI phase may discover that a chosen provider needs details not
represented by the Phase 9 contracts.

Mitigation:

- model only stable cross-provider concepts
- allow concrete adapters to own provider-specific configuration
- do not expose vendor request payloads through the common contracts

---

# 14. Completion Report Requirement

When implementation is complete, write:

```text
docs/phase-9-completion-report.md
```

The report must include:

- implemented scope
- provider decision
- AI target API summary
- privacy projection summary
- Application settings/policy summary
- AppUI and composition-root summary
- Persistence and migration decision
- boundary audit
- verification commands and results
- manual smoke status
- known deferred work
- completion verdict

The report must explicitly state that no concrete provider, semantic search, AI
tag suggestion, or AI artifact persistence was added.

---

# 15. Follow-Up Roadmap

After Phase 9, semantic search remains the next AI capability, but its phase
number is unassigned. It must begin only after a dedicated planning round
answers:

- Which concrete embedding provider is approved?
- Is the first provider local, cloud, or both?
- How are provider credentials or endpoint settings stored safely?
- What model identity and vector dimension rules are required?
- How are media embedding source texts built and invalidated?
- Does vector comparison stay in process or require a SQLite/vector extension?
- What `AiArtifact` schema and cleanup policy are required?
- How does semantic search fall back to keyword search?
- How are semantic results combined with current filters and sorting?

A later AI phase may then add automatic tag suggestion using the Phase 7
curation model and the Phase 9 chat/provider boundary.

Independent non-AI follow-ups remain:

- Phase 7.x assigned-tag text FTS
- basic TV series/season grouping
- concrete online subtitle provider after explicit approval

Do not bundle those independent follow-ups into Phase 9 or a future AI phase.

---

# 16. Recommended Implementation Start

Start Phase 9 implementation with a short contract preflight:

1. Re-run Section 5 discovery commands.
2. Confirm no concrete AI provider has been approved.
3. Confirm `AI` depends on at most `Shared`.
4. Freeze the privacy allowlist and default-disabled policy.
5. Add the AI target and focused tests first.
6. Stop after `swift test --filter AIModuleTests` and boundary checks before
   adding Application settings or AppUI wiring.
