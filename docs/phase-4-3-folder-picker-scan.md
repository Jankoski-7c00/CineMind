# Phase 4.3 Folder Picker and Scan

Canonical file: `docs/phase-4-3-folder-picker-scan.md`

Phase 4.3 adds the first app-facing library mutation workflow: users can authorize folders and run manual scans from the macOS app.

---

# 1. Goal

Provide a native workflow:

```text
User picks folder
  -> app stores authorized library folder
  -> user runs manual scan
  -> scanner updates SQLite
  -> browser refreshes
```

---

# 2. Scope

Implement:

- macOS folder picker.
- Security-scoped bookmark acquisition.
- Library folder save workflow.
- Manual scan command.
- Scan status presentation.
- Scan result summary.
- Unavailable-folder state.
- Browser refresh after scan.

This phase may add Application use cases for folder and scan workflows.

---

# 3. Explicit Non-Goals

Do not implement:

- real-time filesystem watching
- scheduled scans
- background job framework
- metadata auto-refresh after scan
- playback
- folder removal/destructive cleanup
- advanced rename reconciliation UI
- NAS-specific UI beyond unavailable status

---

# 4. Architecture

AppUI owns:

- button/menu command presentation
- folder picker presentation
- scan progress/status display
- refresh trigger after scan completes

Application owns:

- add folder workflow
- bookmark restoration policy
- scan orchestration
- scan result mapping
- typed user-facing errors

Scanner owns:

- filesystem traversal
- parsing
- media item/file reconciliation

Persistence owns:

- folder/media/scan persistence

CineMindApp wires concrete `Scanner` and `Persistence` dependencies.

---

# 5. Expected Changes

Application:

- Add `AddLibraryFolderUseCase`.
- Add `RunLibraryScanUseCase`.
- Add scan status/result DTOs.
- Add bookmark restoration helpers only if they can stay UI-independent.

AppUI:

- Add folder picker trigger.
- Add scan button/menu command.
- Add scan state to browser shell.
- Show last scan summary and errors.

CineMindApp:

- Wire Scanner concrete implementation.
- Wire folder workflow dependencies.

Persistence:

- Reuse existing folder and scan APIs where possible.
- Add only missing direct APIs needed by Application workflows.

---

# 6. Folder Authorization Behavior

Folder picker behavior:

1. User chooses a directory.
2. App starts security-scoped access.
3. App creates bookmark data.
4. Application saves a `LibraryFolder`.
5. App stops security-scoped access when immediate work is done.

Scan behavior:

1. Restore bookmark access for each folder when bookmark data exists.
2. Run existing `LibraryScanner`.
3. Preserve unavailable records.
4. Do not delete missing files.
5. Report scan counts and issues.

If bookmark restoration fails:

- mark or present folder as needing reauthorization.
- do not delete folder or file records.

---

# 7. Risks

- Security-scoped bookmark APIs are AppKit/Foundation boundary-sensitive.
- Scanner is synchronous and can block if called on the main actor.
- NAS/unmounted folders can produce confusing user states.

Mitigation:

- Keep picker presentation in AppUI/CineMindApp, workflow policy in Application.
- Run scans off the main actor.
- Show unavailable state explicitly.

---

# 8. Validation

Automated:

- Application tests for add-folder workflow with fake bookmark data.
- Application tests for scan orchestration using fake scanner filesystem where practical.
- Existing Scanner/Persistence tests remain passing.

Manual:

- Add a local folder.
- Run scan.
- Relaunch and verify folder persists.
- Remove or rename a media file, rescan, and verify missing state.
- Unmount/unavailable folder case does not delete records.
- Browser refreshes after scan.

---

# 9. Acceptance Criteria

Phase 4.3 is complete only if:

- User can add a folder from the app.
- Folder authorization/bookmark data is persisted when available.
- User can manually scan.
- Scan results appear in the app.
- Browser updates after scan.
- Unavailable folders are visible and non-destructive.
- Scans do not run on the main actor.
- Existing tests pass.

