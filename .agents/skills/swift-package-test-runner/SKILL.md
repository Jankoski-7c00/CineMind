---
name: swift-package-test-runner
description: Use for SwiftPM build verification, XCTest execution, failing Swift tests, compile errors, test triage, regression verification, or any CineMind task where code changes must be validated with Swift package tests.
---

# Swift Package Test Runner

## Purpose

Use this skill to build and test CineMind consistently.

This skill exists to prevent false claims about test status, avoid incomplete verification, and establish a repeatable SwiftPM test workflow for implementation, review, and regression tasks.

## When to use

Use this skill when the user asks to:

- run tests
- verify changes
- check build status
- fix a failing test
- investigate a Swift compiler error
- confirm all tests pass
- run relevant tests after a code change
- review whether a phase is green
- perform final verification before merge

Also use this skill automatically after production code changes unless the user explicitly requests no test execution.

## Core rule

Never claim that tests pass unless the relevant test command was actually run in the current session.

If tests cannot be run, say exactly what was attempted and what remains unverified.

## Default environment assumption

CineMind is a Swift Package Manager project. Run commands from the repository root.

Default full verification command:

```bash
swift test
```

Default test discovery command:

```bash
swift test --list-tests
```

## Recommended workflow

### 1. Check repository state

Before running tests after edits:

```bash
git status --short
git diff --stat
```

### 2. Discover available tests

When target/test names are unknown:

```bash
swift test --list-tests
```

### 3. Run targeted tests

Run the narrowest relevant test set first when possible.

Examples:

```bash
swift test --filter LibraryItemDetailUseCaseTests
swift test --filter PersistenceTests
swift test --filter MigrationTests
```

Use the actual discovered test names. Do not invent test names.

### 4. Run full test suite

After production changes, run:

```bash
swift test
```

### 5. Report accurately

The final report must include:

- exact commands run
- pass/fail result for each command
- first meaningful failure if any
- whether full test suite was run
- unverified areas, if any

## Failure classification

When a command fails, classify the failure as one of:

1. **Compile failure**
   - syntax error
   - missing symbol
   - access control issue
   - module import issue
   - type mismatch
   - concurrency/sendability issue

2. **Test assertion failure**
   - expected value mismatch
   - nil/non-nil mismatch
   - ordering mismatch
   - count mismatch

3. **Fixture/setup failure**
   - missing file
   - bad test data
   - temporary directory issue
   - database setup issue

4. **Environment/toolchain failure**
   - Swift toolchain missing
   - package resolution failure
   - unavailable SDK
   - simulator/platform issue

5. **Timeout or resource failure**
   - slow test
   - deadlock
   - excessive IO
   - database lock

## Failure triage workflow

For failing tests:

1. Capture the failing command.
2. Identify the first meaningful compiler error or test assertion.
3. Avoid chasing cascading errors before fixing the first root cause.
4. Inspect the smallest relevant production and test files.
5. Apply the smallest fix.
6. Re-run the failing test.
7. Re-run full `swift test` after production code changes.

## What not to do

Do not:

- claim "all tests pass" based only on previous conversation history
- suppress failing output
- skip tests after production changes without saying so
- rewrite broad unrelated code to fix a narrow test
- add sleeps or timing hacks unless the test is explicitly about asynchronous behavior and the delay is justified
- modify tests to match broken production behavior
- delete tests because they fail
- hide warnings that indicate architecture or correctness issues

## Handling warnings

Warnings should be reported when they are relevant to:

- concurrency
- deprecated APIs
- unsafe operations
- unavailable APIs
- architecture/module imports
- SQLite behavior
- test flakiness

Do not block on unrelated harmless warnings unless the user requested warning-free builds.

## Verification levels

Use this vocabulary in the final report.

### Not verified

No test command was run.

### Partially verified

A targeted command was run, but not the full suite.

### Fully verified

The full intended verification command ran successfully.

For CineMind, "fully verified" usually means:

```bash
swift test
```

completed successfully.

## Output template

```text
Verification status:
- Fully verified / partially verified / not verified

Commands run:
- `<command>` — passed/failed

Result:
- ...

Failures:
- None / ...

Changes verified:
- ...

Not verified:
- ...

Notes:
- ...
```

## Example success report

```text
Verification status:
- Fully verified

Commands run:
- `swift test --filter LibraryItemDetailUseCaseTests` — passed
- `swift test` — passed

Result:
- All executed tests passed.

Changes verified:
- Application use case behavior.
- Persistence-backed detail read integration.
- Existing regression suite.

Not verified:
- Nothing known.

Notes:
- No migration tests were required because no schema change was made.
```

## Example failure report

```text
Verification status:
- Partially verified

Commands run:
- `swift test --filter LibraryItemDetailUseCaseTests` — failed

Result:
- Build failed before tests executed.

Failures:
- Compile failure in Sources/Application/LibraryItemDetailUseCase.swift.
- First meaningful error: cannot convert value of type `PersistedMediaItemDetail?` to expected return type `LibraryItemDetail`.

Changes verified:
- Not verified because compilation failed.

Not verified:
- Full test suite was not run.
- AppUI boundary checks were not re-run.

Notes:
- Next step is to fix the mapping mismatch, then rerun the targeted test.
```

## Final response requirements

When using this skill, always include:

- exact test commands
- pass/fail status
- whether the full test suite ran
- any unverified assumptions
- whether further action is needed

If no tests were run, say:

```text
Tests not run in this session.
```
