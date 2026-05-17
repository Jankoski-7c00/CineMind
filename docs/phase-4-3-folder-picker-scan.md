# Phase 4.3 Folder Picker + Scan Plan

Canonical file: `docs/phase-4-3-folder-picker-scan.md`

## 1. Summary

Phase 4.3 adds a minimal app workflow to add a local folder, manually run a library-wide scan, show indeterminate scan status/results, and refresh the read-only browser. `Application` owns folder and scan protocols/DTOs, including the picker contract. `CineMindApp` owns the `NSOpenPanel` picker implementation, the Scanner-backed adapter, and concrete wiring. `AppUI` consumes only Application-facing protocols/DTOs.

Default decisions:

- `Application` must not depend on `Scanner` unless the integration audit proves there is no protocol-only path.
- Manual scan is library-wide.
- Adding a folder does not auto-scan.
- Scan progress is indeterminate because `LibraryScanner` is synchronous and has no callbacks.
- Scan cancellation is deferred.
- No schema migration is planned.

## 2. Goals

- Let users add one local folder at a time through a macOS folder picker.
- Persist the folder path, display name, and optional bookmark data.
- Let users manually run a library-wide scan.
- Show scan running/completed/failed state with counts and issue summaries.
- Refresh browser and folder summaries after add/scan.
- Preserve AppUI dependency boundaries and avoid migrations.

## 3. Explicit Non-Goals

- No auto-scan after add-folder.
- No per-folder scan command.
- No scan cancellation or per-file progress.
- No metadata refresh, metadata mutation, posters, playback, grid/search, folder removal, destructive cleanup, scheduled scans, filesystem watching, CoreData/SwiftData, server/API infrastructure, or migrations.
- No security-scoped bookmark restoration or `startAccessingSecurityScopedResource` in 4.3 unless SwiftPM/dev scan validation proves direct local paths fail.

## 4. Current Architecture Findings

- `LibraryScanner.scanLibrary(libraryID: String) throws -> ScanResult` is synchronous, library-wide, indeterminate, and already records scan counts/issues.
- Existing Persistence APIs cover library lookup, folder save/fetch, media reconciliation, scan runs/issues, and folder summaries.
- Current Application layer has read-only summary/detail/folder use cases but no add-folder or scan workflow.
- AppUI currently consumes Application DTOs only and must continue to avoid Scanner, Persistence, AppKit, Metadata, Playback, and LibMPVPlayback imports.
- CineMindApp is the composition root and already wires `CineMindStore`.
- 4.3A audit found no unavoidable reason for `Application` to import `Scanner`; a `LibraryScanRunning` protocol in `Application` can hide the Scanner-backed implementation in `CineMindApp`.

## 5. 4.3A Integration Point Audit Findings

Commands run:

```sh
rg "scanLibrary|ScanResult|ScanCounts|ScanIssue" Sources
rg "addLibraryFolder|fetchLibraryFolders|access_bookmark|ensureLibrary|fetchLibrary" Sources/Persistence Sources/Application
rg "import (Persistence|Scanner|AppKit|Metadata|Playback|LibMPVPlayback)" Sources/AppUI
```

Scanner API confirmed:

```swift
public final class LibraryScanner {
    public init(
        store: CineMindStore,
        fileSystem: any ScannerFileSystem = LocalScannerFileSystem(),
        now: @escaping () -> Date = { Date() },
        supportedExtensions: Set<String> = ["mp4", "mkv", "mov", "avi", "m4v"]
    )

    public func scanLibrary(libraryID: String) throws -> ScanResult
}

public struct ScanResult: Sendable, Equatable {
    public var scanRun: ScanRun
    public var counts: ScanCounts
    public var issues: [ScanIssue]
}

public struct ScanCounts: Sendable, Equatable {
    public var foldersScanned: Int
    public var filesDiscovered: Int
    public var mediaItemsCreated: Int
    public var mediaItemsUpdated: Int
    public var mediaFilesCreated: Int
    public var mediaFilesUpdated: Int
    public var filesMarkedUnavailable: Int
    public var issuesRecorded: Int
}
```

Domain scan shapes confirmed:

```swift
public struct ScanRun: Codable, Sendable, Equatable {
    public var id: ScanRunID
    public var libraryID: LibraryID
    public var startedAt: Date
    public var finishedAt: Date?
    public var status: ScanRunStatus
    public var filesSeen: Int
    public var filesAdded: Int
    public var filesUpdated: Int
    public var filesMissing: Int
    public var issuesCount: Int
}

public struct ScanIssue: Codable, Sendable, Equatable {
    public var id: ScanIssueID
    public var scanRunID: ScanRunID
    public var libraryFolderID: LibraryFolderID?
    public var pathHash: String?
    public var issueType: ScanIssueType
    public var message: String
    public var createdAt: Date
}
```

Persistence APIs confirmed:

```swift
public func ensureLibrary(name: String = "CineMind Library") throws -> Library
public func fetchLibrary() throws -> Library?
public func fetchLibrary(id: LibraryID) throws -> Library?
public func addLibraryFolder(_ folder: LibraryFolder) throws
public func fetchLibraryFolders(libraryID: LibraryID) throws -> [LibraryFolder]
public func createScanRun(libraryID: LibraryID, startedAt: Date = Date()) throws -> ScanRun
public func finishScanRun(...)
public func saveScanRun(_ run: ScanRun) throws
public func fetchScanRun(id: ScanRunID) throws -> ScanRun?
public func fetchScanRuns(libraryID: LibraryID) throws -> [ScanRun]
public func recordScanIssue(_ issue: ScanIssue) throws
public func saveScanIssue(_ issue: ScanIssue) throws
public func fetchScanIssues(scanRunID: ScanRunID) throws -> [ScanIssue]
```

Additional audit notes:

- `library_folders.access_bookmark` already exists and maps to `LibraryFolder.accessBookmark`; no migration is needed.
- `AppUI` forbidden import boundary is clean: the AppUI `rg` command returned no matches.
- `Sources/AppUI/AppShellEnvironment.swift` currently imports only `Application`.

## 6. Proposed Module/Target Changes

- `Application`: add add-folder workflow, scan workflow, and picker protocol/DTO contracts. Do not add a Scanner dependency unless a later audit contradicts 4.3A.
- `CineMindApp`: add Scanner target dependency and provide Scanner-backed adapter plus AppKit `NSOpenPanel` picker adapter.
- `AppUI`: consume new Application protocols/DTOs only.
- `Persistence`: no schema changes; add only small read helper APIs if duplicate detection cannot be implemented with `fetchLibraryFolders`.

## 7. Exact Files Expected To Change

- `docs/phase-4-3-folder-picker-scan.md`
- `Package.swift`
- `Sources/Application/LibraryFolderWorkflow.swift`
- `Sources/Application/LibraryScanWorkflow.swift`
- `Sources/AppUI/AppShellEnvironment.swift`
- `Sources/AppUI/LibraryBrowserViewModel.swift`
- `Sources/AppUI/LibraryBrowserView.swift`
- `Sources/AppUI/CineMindRootView.swift`
- `Sources/CineMindApp/CineMindAppEnvironmentFactory.swift`
- `Sources/CineMindApp/AppKitLibraryFolderPicker.swift`
- `Sources/CineMindApp/ScannerLibraryScanRunner.swift`
- `Tests/ApplicationTests/LibraryFolderWorkflowTests.swift`
- `Tests/ApplicationTests/LibraryScanWorkflowTests.swift`

Expected unchanged:

- `Sources/Persistence/Migrations.swift`
- Scanner internals
- Metadata, Playback, LibMPVPlayback modules

## 8. Task Breakdown

### 4.3A Integration Point Audit

Files/targets expected to change:

- Documentation only.

Exact APIs:

- None.

Explicit non-goals:

- No code implementation.
- No target dependency changes.
- No source edits outside docs.

Validation:

- Confirm current Scanner entrypoint: `LibraryScanner.scanLibrary(libraryID:)`.
- Confirm Persistence APIs: `fetchLibrary`, `ensureLibrary`, `addLibraryFolder`, `fetchLibraryFolders`, scan issue/run APIs.
- Confirm AppUI import boundary with `rg`.

Rollback scope:

- Revert only the docs plan update.

Risks:

- 4.3A found no current blocker requiring `Application` to import `Scanner`; if a future implementation step contradicts that, document the exact signature/type conflict before changing dependencies.

### 4.3B Application Add-Folder Workflow

Files/targets expected to change:

- `Sources/Application/LibraryFolderWorkflow.swift`
- `Tests/ApplicationTests/LibraryFolderWorkflowTests.swift`
- Possibly a tiny Persistence helper only if duplicate detection cannot be implemented with `fetchLibraryFolders`.

Exact APIs:

`PickedLibraryFolder` and `LibraryFolderPicking` belong in `Application` as the folder workflow picker contract. `Application` defines this protocol only; `CineMindApp` implements it with AppKit.

```swift
public struct PickedLibraryFolder: Sendable, Equatable {
    public let rootPath: String
    public let displayName: String?
    public let accessBookmark: Data?
}

public protocol LibraryFolderPicking: Sendable {
    @MainActor func pickLibraryFolder() async throws -> PickedLibraryFolder?
}

public struct AddLibraryFolderRequest: Sendable, Equatable {
    public let rootPath: String
    public let displayName: String?
    public let accessBookmark: Data?
}

public struct AddedLibraryFolder: Sendable, Equatable, Identifiable {
    public let id: LibraryFolderID
    public let displayName: String
    public let rootPath: String
}

public protocol LibraryFolderAdding: Sendable {
    func addFolder(_ request: AddLibraryFolderRequest) async throws -> AddedLibraryFolder
}

public enum LibraryFolderWorkflowError: Error, Sendable, Equatable, LocalizedError {
    case invalidFolderPath
    case folderUnavailable(String)
    case duplicateFolder(String)
    case libraryUnavailable
}
```

Store protocol:

```swift
public protocol ApplicationLibraryFolderMutationStore: Sendable {
    func fetchLibrary() throws -> Library?
    func ensureLibrary(name: String) throws -> Library
    func fetchLibraryFolders(libraryID: LibraryID) throws -> [LibraryFolder]
    func addLibraryFolder(_ folder: LibraryFolder) throws
}
```

Path standardization behavior:

```swift
let standardizedRootPath = URL(fileURLWithPath: rootPath).standardizedFileURL.path
```

- Persist `standardizedRootPath` as the folder `rootPath`.
- Compare standardized existing folder paths against `standardizedRootPath` for duplicate detection.
- Symlink-equivalent and case-equivalent duplicate detection is deferred.

Explicit non-goals:

- No folder picker implementation.
- No Scanner dependency.
- No auto-scan.
- No bookmark restoration.
- No folder removal or edit UI.

Validation:

- Add-folder creates/uses current library.
- Invalid path and non-directory path fail.
- Duplicate standardized path fails.
- Symlink-equivalent or case-equivalent paths are not treated as duplicates in 4.3 unless direct validation proves this is necessary.
- Bookmark data is stored when provided.
- `swift test --filter LibraryFolderWorkflowTests`.

Rollback scope:

- Remove new workflow file/tests and any tiny Persistence helper if added.

Risks:

- `FileManager` checks in Application are acceptable for local folder validation, but must remain UI-independent.
- Duplicate detection by standardized path may not catch symlink-equivalent or case-equivalent paths; defer realpath/case-fold policy unless needed.

### 4.3C Application Scan Workflow Protocol/Use Case

Files/targets expected to change:

- `Sources/Application/LibraryScanWorkflow.swift`
- `Tests/ApplicationTests/LibraryScanWorkflowTests.swift`

Exact APIs:

```swift
public struct LibraryScanCountSummary: Sendable, Equatable {
    public let foldersScanned: Int
    public let filesDiscovered: Int
    public let mediaItemsCreated: Int
    public let mediaItemsUpdated: Int
    public let mediaFilesCreated: Int
    public let mediaFilesUpdated: Int
    public let filesMarkedUnavailable: Int
    public let issuesRecorded: Int
}

public struct LibraryScanIssueSummary: Sendable, Equatable {
    public let typeLabel: String
    public let message: String
}

public struct LibraryScanResultSummary: Sendable, Equatable {
    public let scanRunID: ScanRunID
    public let statusLabel: String
    public let counts: LibraryScanCountSummary
    public let issues: [LibraryScanIssueSummary]
}

public protocol LibraryScanRunning: Sendable {
    func runScan(libraryID: LibraryID) throws -> LibraryScanResultSummary
}

public protocol LibraryScanning: Sendable {
    func scanLibrary() async throws -> LibraryScanResultSummary
}

public enum LibraryScanWorkflowError: Error, Sendable, Equatable, LocalizedError {
    case libraryUnavailable
    case noLibraryFolders
    case scanFailed(String)
}
```

Store protocol:

```swift
public protocol ApplicationLibraryScanStore: Sendable {
    func fetchLibrary() throws -> Library?
    func fetchLibraryFolders(libraryID: LibraryID) throws -> [LibraryFolder]
}
```

Explicit non-goals:

- No `import Scanner` in Application.
- No cancellation.
- No per-file progress.
- No bookmark restore or `startAccessingSecurityScopedResource`.
- No metadata refresh.

Validation:

- Scan fails with no library.
- Scan fails with zero folders.
- Scan runner success maps counts/issues.
- Runner failure maps to localized error.
- `swift test --filter LibraryScanWorkflowTests`.
- `rg "import Scanner" Sources/Application` must return no matches unless 4.3A documented unavoidable need.

Rollback scope:

- Remove scan workflow file/tests.

Risks:

- DTO mapping must not expose Scanner types across Application API.
- The runner protocol is synchronous because Scanner is synchronous; async boundary stays in Application use case.

### 4.3D CineMindApp Picker/Scanner Adapters And Wiring

Files/targets expected to change:

- `Package.swift`
- `Sources/CineMindApp/AppKitLibraryFolderPicker.swift`
- `Sources/CineMindApp/ScannerLibraryScanRunner.swift`
- `Sources/CineMindApp/CineMindAppEnvironmentFactory.swift`

Exact APIs:

- `AppKitLibraryFolderPicker`: implements the Application-defined `LibraryFolderPicking` protocol, imports AppKit in CineMindApp only, uses `NSOpenPanel`, returns `nil` on cancel, and creates optional bookmark data when possible.
- `ScannerLibraryScanRunner`: conforms to `LibraryScanRunning`, imports Scanner in CineMindApp only, wraps `LibraryScanner.scanLibrary(libraryID:)`, and maps Scanner `ScanResult` into Application `LibraryScanResultSummary`.

Explicit non-goals:

- No AppKit in AppUI/Application.
- No Scanner import in AppUI/Application.
- No bookmark restore or `startAccessingSecurityScopedResource`.
- No target changes for Metadata/Playback/LibMPVPlayback.

Validation:

- `swift build --target CineMindApp`
- `rg "import AppKit" Sources/AppUI Sources/Application` returns no matches.
- `rg "import Scanner" Sources/AppUI Sources/Application` returns no matches.
- `rg "import (Persistence|Scanner|AppKit|Metadata|Playback|LibMPVPlayback)" Sources/AppUI` returns no matches.

Rollback scope:

- Remove new adapter files.
- Revert Package and factory wiring changes.

Risks:

- Adding Scanner dependency to CineMindApp requires a Package target update.
- Bookmark creation behavior may vary by run context; bookmark remains optional.
- Bookmark restoration and `startAccessingSecurityScopedResource` remain deferred unless SwiftPM/dev scan validation proves direct local paths fail.

### 4.3E AppUI Add/Scan Controls And Status

Files/targets expected to change:

- `Sources/AppUI/AppShellEnvironment.swift`
- `Sources/AppUI/LibraryBrowserViewModel.swift`
- `Sources/AppUI/LibraryBrowserView.swift`
- `Sources/AppUI/CineMindRootView.swift`

Exact APIs:

```swift
public struct AppShellEnvironment {
    public let mediaSummaryBrowser: any LibraryMediaSummaryBrowsing
    public let itemDetailBrowser: any LibraryItemDetailBrowsing
    public let folderSummaryBrowser: any LibraryFolderSummaryBrowsing
    public let folderPicker: any LibraryFolderPicking
    public let folderAdder: any LibraryFolderAdding
    public let libraryScanner: any LibraryScanning
}
```

View-model state additions:

```swift
@Published public private(set) var isAddingFolder: Bool
@Published public private(set) var isScanning: Bool
@Published public private(set) var workflowMessage: String?
@Published public private(set) var workflowErrorMessage: String?
@Published public private(set) var lastScanResult: LibraryScanResultSummary?
```

View-model actions:

```swift
public func addFolder() async
public func scanLibrary() async
```

UI:

- Command row with Add Folder and Scan.
- Disable Add Folder and Scan while either workflow is running.
- Show indeterminate progress while scanning.
- Show compact result summary after scan.
- Show localized error text on failure.

Explicit non-goals:

- No AppUI imports of Scanner, Persistence, AppKit, Metadata, Playback, LibMPVPlayback.
- No cancellation button.
- No auto-scan.
- No folder management UI beyond add and manual scan.

Validation:

- `swift build --target AppUI`
- AppUI import boundary `rg`.
- Manual: controls appear in all six sections and disabled state works.

Rollback scope:

- Revert AppUI environment/view/view-model changes only.

Risks:

- Avoid triggering add/scan from SwiftUI body recomputation; actions must be button-driven.
- Status UI should not hide the existing browser table unnecessarily except during clear loading states.
- `AppShellEnvironment` service growth is a Phase 4.4+ refactor risk; do not introduce a container refactor in 4.3 unless the environment becomes unworkable.

### 4.3F Browser Refresh After Add/Scan

Files/targets expected to change:

- `Sources/AppUI/LibraryBrowserViewModel.swift`
- `Sources/AppUI/CineMindRootView.swift`
- Possibly `Sources/AppUI/LibraryItemDetailView.swift` only if existing detail reload API is insufficient.

Exact behavior:

- After successful add-folder: switch to `.folders`, reload folder snapshot, show success message.
- After successful scan: reload current section.
- If an item is selected after scan, reload its detail.
- Failed add/scan does not clear existing snapshot.

Explicit non-goals:

- No new Persistence queries.
- No pagination changes.
- No search/grid.
- No metadata/poster/playback refresh.

Validation:

- Manual add folder refreshes Folders section.
- Manual scan refreshes Library/Movies/Folders counts.
- Selected detail updates after scan.
- `swift build --target AppUI`
- `swift build --target CineMindApp`.

Rollback scope:

- Revert refresh wiring only.

Risks:

- Detail can remain stale if selected item reload is skipped.
- Folder section must reflect updated last scan date after scan.

### 4.3G Validation/Completion

Files/targets expected to change:

- No planned source changes except validation fixes scoped to prior tasks.

Exact APIs:

- No new APIs.

Explicit non-goals:

- No cleanup refactors outside 4.3 scope.
- No migrations.
- No Phase 4.4+ work.

Validation:

- `swift test`
- `swift build --target AppUI`
- `swift build --target CineMindApp`
- `swift build --target CineMindShell`
- `swift build --target CineMindPlaybackShell`
- `swift build --target CineMindPlaybackSurfaceSpike`
- `swift build --target CineMindMetadataShell`
- `rg "import (Persistence|Scanner|AppKit|Metadata|Playback|LibMPVPlayback)" Sources/AppUI`
- `rg "import Scanner" Sources/Application` must be empty unless documented by 4.3A.
- `git diff -- Sources/Persistence/Migrations.swift` must be empty.

Manual validation:

- Launch app with empty DB.
- Add `Tests/Fixtures/Videos`.
- Confirm Folders section shows the folder.
- Click Scan manually.
- Confirm indeterminate scanning state, completed count summary, zero-crash behavior.
- Confirm Library/Movies populate.
- Relaunch and confirm folder/media persist.
- Rescan and confirm no duplicate media rows.
- Temporarily make folder unavailable and confirm scan reports unavailable/non-destructive state.

Rollback scope:

- Revert smallest failed task first.
- Do not revert unrelated user changes.

Risks:

- Manual GUI validation from Phase 4.2 is still pending and may surface unrelated layout issues.
- Scanner can be slow on large directories; 4.3 accepts indeterminate, non-cancellable behavior.
- Direct local path scanning should work in SwiftPM/dev; if it does not, document evidence before adding bookmark restore/startAccessing.

## 9. Completion Status

Completed:

- Phase 4.3A plan/audit completed.
- Phase 4.3B Application add-folder workflow completed.
- Phase 4.3C Application scan workflow protocol/use case completed.
- Phase 4.3D CineMindApp AppKit picker and Scanner adapter wiring completed.
- Phase 4.3E AppUI Add Folder and Scan controls completed.
- Phase 4.3F refresh-after-add/scan completed.
- Phase 4.3G automated validation completed.

Automated validation:

- `swift test` passed: 274 tests.
- `swift build --target AppUI` passed.
- `swift build --target CineMindApp` passed.
- `swift build --target CineMindShell` passed.
- `swift build --target CineMindPlaybackShell` passed.
- `swift build --target CineMindPlaybackSurfaceSpike` passed.
- `swift build --target CineMindMetadataShell` passed.
- AppUI boundary checks passed.
- `Application` has no Scanner or AppKit imports.
- Migrations are unchanged.
- No automated regressions found.

Manual GUI validation remains pending because this session cannot interact with `NSOpenPanel` or the running UI.

Remaining manual validation:

- Launch app with an empty DB.
- Add `Tests/Fixtures/Videos`.
- Confirm Folders refreshes and shows the folder.
- Click Scan and confirm indeterminate scanning state plus completed count summary.
- Confirm Library and Movies populate.
- Relaunch and confirm folder/media persistence.
- Rescan and confirm no duplicate media rows.
- Confirm no playback, metadata, poster, or folder-management UI appeared.
