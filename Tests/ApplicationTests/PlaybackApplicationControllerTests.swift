@testable import Application
import Domain
import Foundation
import Playback
import XCTest

final class PlaybackApplicationControllerTests: XCTestCase {
    func testOpenSuccessProducesLoadingReadyPlayingAndAutoPlay() async throws {
        let file = try makeApplicationPlayableFile("first", resumePositionMS: 12_000)
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        await fixture.controller.open(mediaFileID: file.mediaFileID)

        try await assertNextStatus(
            PlaybackApplicationStatus(
                state: .loading,
                mediaFileID: file.mediaFileID,
                displayName: file.displayName,
                positionMS: 12_000,
                durationMS: nil
            ),
            statuses: &statuses
        )
        await fixture.backend.waitForCommandCount(1)
        await assertCommands([.load(playbackPlayableFile(from: file))], backend: fixture.backend)

        fixture.backend.emit(.stateChanged(.ready))
        try await assertNextStatus(
            PlaybackApplicationStatus(
                state: .ready,
                mediaFileID: file.mediaFileID,
                displayName: file.displayName,
                positionMS: 12_000,
                durationMS: nil
            ),
            statuses: &statuses
        )
        await fixture.backend.waitForCommandCount(2)
        await assertCommands(
            [.load(playbackPlayableFile(from: file)), .play],
            backend: fixture.backend
        )

        fixture.backend.emit(.stateChanged(.playing))
        try await assertNextStatus(
            PlaybackApplicationStatus(
                state: .playing,
                mediaFileID: file.mediaFileID,
                displayName: file.displayName,
                positionMS: 12_000,
                durationMS: nil
            ),
            statuses: &statuses
        )

        XCTAssertEqual(fixture.mediaOpening.calls, [file.mediaFileID])
    }

    func testStatusTracksPositionAndDuration() async throws {
        let file = try makeApplicationPlayableFile("progress")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        await fixture.controller.open(mediaFileID: file.mediaFileID)
        try await discardNextStatus(statuses: &statuses)
        fixture.backend.emit(.stateChanged(.ready))
        try await discardNextStatus(statuses: &statuses)
        await fixture.backend.waitForCommandCount(2)
        fixture.backend.emit(.stateChanged(.playing))
        try await discardNextStatus(statuses: &statuses)

        fixture.backend.emit(.durationUpdated(durationMS: 600_000))
        try await assertNextStatus(
            PlaybackApplicationStatus(
                state: .playing,
                mediaFileID: file.mediaFileID,
                displayName: file.displayName,
                positionMS: 0,
                durationMS: 600_000
            ),
            statuses: &statuses
        )

        fixture.backend.emit(.positionUpdated(positionMS: 45_000))
        try await assertNextStatus(
            PlaybackApplicationStatus(
                state: .playing,
                mediaFileID: file.mediaFileID,
                displayName: file.displayName,
                positionMS: 45_000,
                durationMS: 600_000
            ),
            statuses: &statuses
        )
    }

    func testPauseForwardsCommandAndStatusTracksPaused() async throws {
        let file = try makeApplicationPlayableFile("pause")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        try await openAndReachPlaying(file: file, fixture: fixture, statuses: &statuses)

        await fixture.controller.pause()
        await fixture.backend.waitForCommandCount(3)
        await assertCommands(
            [.load(playbackPlayableFile(from: file)), .play, .pause],
            backend: fixture.backend
        )

        fixture.backend.emit(.stateChanged(.paused))
        try await assertNextStatus(
            PlaybackApplicationStatus(
                state: .paused,
                mediaFileID: file.mediaFileID,
                displayName: file.displayName,
                positionMS: 0,
                durationMS: nil
            ),
            statuses: &statuses
        )
    }

    func testResumeForwardsPlayCommandAndStatusTracksPlaying() async throws {
        let file = try makeApplicationPlayableFile("resume")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        try await openAndReachPlaying(file: file, fixture: fixture, statuses: &statuses)
        await fixture.controller.pause()
        fixture.backend.emit(.stateChanged(.paused))
        try await assertNextStatus(
            PlaybackApplicationStatus(
                state: .paused,
                mediaFileID: file.mediaFileID,
                displayName: file.displayName,
                positionMS: 0,
                durationMS: nil
            ),
            statuses: &statuses
        )

        await fixture.controller.resume()
        await fixture.backend.waitForCommandCount(4)
        await assertCommands(
            [.load(playbackPlayableFile(from: file)), .play, .pause, .play],
            backend: fixture.backend
        )

        fixture.backend.emit(.stateChanged(.playing))
        try await assertNextStatus(
            PlaybackApplicationStatus(
                state: .playing,
                mediaFileID: file.mediaFileID,
                displayName: file.displayName,
                positionMS: 0,
                durationMS: nil
            ),
            statuses: &statuses
        )
    }

    func testTogglePlayPauseWhilePlayingForwardsPauseCommand() async throws {
        let file = try makeApplicationPlayableFile("toggle-pause")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        try await openAndReachPlaying(file: file, fixture: fixture, statuses: &statuses)

        await fixture.controller.togglePlayPause()
        await fixture.backend.waitForCommandCount(3)
        await assertCommands(
            [.load(playbackPlayableFile(from: file)), .play, .pause],
            backend: fixture.backend
        )
    }

    func testTogglePlayPauseWhilePausedForwardsPlayCommand() async throws {
        let file = try makeApplicationPlayableFile("toggle-resume")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        try await openAndReachPlaying(file: file, fixture: fixture, statuses: &statuses)
        await fixture.controller.pause()
        fixture.backend.emit(.stateChanged(.paused))
        try await discardNextStatus(statuses: &statuses)

        await fixture.controller.togglePlayPause()
        await fixture.backend.waitForCommandCount(4)
        await assertCommands(
            [.load(playbackPlayableFile(from: file)), .play, .pause, .play],
            backend: fixture.backend
        )
    }

    func testTogglePlayPauseWhileIdleIsNoOp() async throws {
        let fixture = makeFixture(files: [:])
        let statuses = PlaybackStatusReader(fixture.controller.statusStream)

        await fixture.controller.togglePlayPause()

        await assertCommands([], backend: fixture.backend)
        try await assertNoStatus(statuses)
    }

    func testPauseResumeInIdleAreNoOps() async throws {
        let fixture = makeFixture(files: [:])
        let statuses = PlaybackStatusReader(fixture.controller.statusStream)

        await fixture.controller.pause()
        await fixture.controller.resume()

        await assertCommands([], backend: fixture.backend)
        try await assertNoStatus(statuses)
    }

    func testPauseResumeWhileLoadingAreNoOps() async throws {
        let file = try makeApplicationPlayableFile("loading-noop")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        await fixture.controller.open(mediaFileID: file.mediaFileID)
        try await discardNextStatus(statuses: &statuses)
        await fixture.controller.pause()
        await fixture.controller.resume()

        await assertCommands([.load(playbackPlayableFile(from: file))], backend: fixture.backend)
        try await assertNoStatus(PlaybackStatusReader(existingIterator: statuses))
    }

    func testPauseResumeWhileReadyAreNoOps() async throws {
        let file = try makeApplicationPlayableFile("ready-noop")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        await fixture.controller.open(mediaFileID: file.mediaFileID)
        try await discardNextStatus(statuses: &statuses)
        fixture.backend.emit(.stateChanged(.ready))
        try await discardNextStatus(statuses: &statuses)
        await fixture.backend.waitForCommandCount(2)

        await fixture.controller.pause()
        await fixture.controller.resume()

        await assertCommands(
            [.load(playbackPlayableFile(from: file)), .play],
            backend: fixture.backend
        )
        try await assertNoStatus(PlaybackStatusReader(existingIterator: statuses))
    }

    func testPauseResumeWhileBufferingAreNoOps() async throws {
        let file = try makeApplicationPlayableFile("buffering-noop")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        try await openAndReachPlaying(file: file, fixture: fixture, statuses: &statuses)
        fixture.backend.emit(.stateChanged(.buffering))
        try await assertNextStatus(
            PlaybackApplicationStatus(
                state: .buffering,
                mediaFileID: file.mediaFileID,
                displayName: file.displayName,
                positionMS: 0,
                durationMS: nil
            ),
            statuses: &statuses
        )

        await fixture.controller.pause()
        await fixture.controller.resume()

        await assertCommands(
            [.load(playbackPlayableFile(from: file)), .play],
            backend: fixture.backend
        )
        try await assertNoStatus(PlaybackStatusReader(existingIterator: statuses))
    }

    func testOpenFailureProducesUserSafeFailureWithoutLoadingBackend() async throws {
        let error = SecretOpeningError()
        let fixture = makeFixture(files: [:], openingError: error)
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        await fixture.controller.open(mediaFileID: "missing-file")

        let status = try await nextStatus(statuses: &statuses)
        guard case .failed(let message) = status.state else {
            return XCTFail("Expected failed status, got \(status)")
        }
        XCTAssertEqual(message, "Could not open media file.")
        XCTAssertFalse(message.contains(error.rawMessage))
        XCTAssertEqual(status.mediaFileID, "missing-file")
        XCTAssertNil(status.displayName)
        XCTAssertEqual(status.positionMS, 0)
        XCTAssertNil(status.durationMS)
        await assertCommands([], backend: fixture.backend)
        XCTAssertEqual(fixture.progressStore.operations, [])
    }

    func testOpenFailureWhileActivePlaybackPreservesCurrentSession() async throws {
        let file = try makeApplicationPlayableFile("preserve-current-on-open-failure")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        try await openAndReachPlaying(file: file, fixture: fixture, statuses: &statuses)

        await fixture.controller.open(mediaFileID: "missing-next-file")

        await assertCommands(
            [.load(playbackPlayableFile(from: file)), .play],
            backend: fixture.backend
        )
        XCTAssertEqual(fixture.mediaOpening.calls, [file.mediaFileID, "missing-next-file"])
        XCTAssertEqual(fixture.progressStore.saveCalls, [])
        try await assertNoStatus(PlaybackStatusReader(existingIterator: statuses))
    }

    func testPlaybackFailureProducesUserSafeFailure() async throws {
        let file = try makeApplicationPlayableFile("failure")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        await fixture.controller.open(mediaFileID: file.mediaFileID)
        try await discardNextStatus(statuses: &statuses)

        fixture.backend.emit(.playbackFailed(.mpvError("secret backend stack trace")))

        let status = try await nextStatus(statuses: &statuses)
        guard case .failed(let message) = status.state else {
            return XCTFail("Expected failed status, got \(status)")
        }
        XCTAssertEqual(message, "Playback failed.")
        XCTAssertFalse(message.contains("secret backend stack trace"))
        XCTAssertEqual(status.mediaFileID, file.mediaFileID)
        XCTAssertEqual(status.displayName, file.displayName)
    }

    func testStopEmitsIdleAndPersistsProgressOnce() async throws {
        let file = try makeApplicationPlayableFile("stop")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        await fixture.controller.open(mediaFileID: file.mediaFileID)
        try await discardNextStatus(statuses: &statuses)
        fixture.backend.emit(.stateChanged(.ready))
        try await discardNextStatus(statuses: &statuses)
        await fixture.backend.waitForCommandCount(2)
        fixture.backend.emit(.stateChanged(.playing))
        try await discardNextStatus(statuses: &statuses)
        fixture.backend.emit(.positionUpdated(positionMS: 20_000))
        try await discardNextStatus(statuses: &statuses)

        await fixture.controller.stop()

        try await assertNextStatus(.idle, statuses: &statuses)
        await assertCommands(
            [.load(playbackPlayableFile(from: file)), .play, .stop],
            backend: fixture.backend
        )
        XCTAssertEqual(fixture.progressStore.incrementCalls.map(\.mediaFileID), [file.mediaFileID])
        XCTAssertEqual(fixture.progressStore.saveCalls.map(\.positionMS), [20_000])
        XCTAssertEqual(fixture.progressStore.operations, [.increment, .save])
    }

    func testStopWhileAlreadyIdleReemitsIdleForStalePlaybackUI() async throws {
        let file = try makeApplicationPlayableFile("stop-idle-recovery")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        try await openAndReachPlaying(file: file, fixture: fixture, statuses: &statuses)

        await fixture.controller.stop()
        try await assertNextStatus(.idle, statuses: &statuses)

        await fixture.controller.stop()
        try await assertNextStatus(.idle, statuses: &statuses)

        await assertCommands(
            [.load(playbackPlayableFile(from: file)), .play, .stop],
            backend: fixture.backend
        )
    }

    func testShutdownStopsAndPersistsProgressBeforeBackendShutdown() async throws {
        let file = try makeApplicationPlayableFile("shutdown")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        try await openAndReachPlaying(file: file, fixture: fixture, statuses: &statuses)
        fixture.backend.emit(.positionUpdated(positionMS: 20_000))
        try await discardNextStatus(statuses: &statuses)

        await fixture.controller.shutdown()

        try await assertNextStatus(.idle, statuses: &statuses)
        let nextStatus = await statuses.next()
        XCTAssertNil(nextStatus)
        await fixture.backend.waitForCommandCount(4)
        await assertCommands(
            [.load(playbackPlayableFile(from: file)), .play, .stop, .shutdown],
            backend: fixture.backend
        )
        XCTAssertEqual(fixture.progressStore.incrementCalls.map(\.mediaFileID), [file.mediaFileID])
        XCTAssertEqual(fixture.progressStore.saveCalls.map(\.positionMS), [20_000])
        XCTAssertEqual(fixture.progressStore.operations, [.increment, .save])
    }

    func testMultipleOpensStopPreviousSessionBeforeLoadingNext() async throws {
        let first = try makeApplicationPlayableFile("first")
        let second = try makeApplicationPlayableFile("second")
        let fixture = makeFixture(files: [first, second])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        await fixture.controller.open(mediaFileID: first.mediaFileID)
        try await assertNextStatus(
            PlaybackApplicationStatus(
                state: .loading,
                mediaFileID: first.mediaFileID,
                displayName: first.displayName,
                positionMS: 0,
                durationMS: nil
            ),
            statuses: &statuses
        )

        await fixture.controller.open(mediaFileID: second.mediaFileID)

        try await assertNextStatus(.idle, statuses: &statuses)
        try await assertNextStatus(
            PlaybackApplicationStatus(
                state: .loading,
                mediaFileID: second.mediaFileID,
                displayName: second.displayName,
                positionMS: 0,
                durationMS: nil
            ),
            statuses: &statuses
        )
        await fixture.backend.waitForCommandCount(3)
        await assertCommands(
            [
                .load(playbackPlayableFile(from: first)),
                .stop,
                .load(playbackPlayableFile(from: second))
            ],
            backend: fixture.backend
        )
        XCTAssertEqual(fixture.mediaOpening.calls, [first.mediaFileID, second.mediaFileID])
    }

    func testOpeningNextMediaWhilePlayingKeepsNextSessionActive() async throws {
        let first = try makeApplicationPlayableFile("playing-first")
        let second = try makeApplicationPlayableFile("playing-second")
        let fixture = makeFixture(files: [first, second])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        try await openAndReachPlaying(file: first, fixture: fixture, statuses: &statuses)

        await fixture.controller.open(mediaFileID: second.mediaFileID)

        try await assertNextStatus(.idle, statuses: &statuses)
        try await assertNextStatus(
            PlaybackApplicationStatus(
                state: .loading,
                mediaFileID: second.mediaFileID,
                displayName: second.displayName,
                positionMS: 0,
                durationMS: nil
            ),
            statuses: &statuses
        )

        fixture.backend.emit(.stateChanged(.ready))
        try await assertNextStatus(
            PlaybackApplicationStatus(
                state: .ready,
                mediaFileID: second.mediaFileID,
                displayName: second.displayName,
                positionMS: 0,
                durationMS: nil
            ),
            statuses: &statuses
        )
        await fixture.backend.waitForCommandCount(5)
        await assertCommands(
            [
                .load(playbackPlayableFile(from: first)),
                .play,
                .stop,
                .load(playbackPlayableFile(from: second)),
                .play
            ],
            backend: fixture.backend
        )

        fixture.backend.emit(.stateChanged(.playing))
        try await assertNextStatus(
            PlaybackApplicationStatus(
                state: .playing,
                mediaFileID: second.mediaFileID,
                displayName: second.displayName,
                positionMS: 0,
                durationMS: nil
            ),
            statuses: &statuses
        )
    }

    func testRepeatedOpenForActiveMediaFileIsNoOp() async throws {
        let file = try makeApplicationPlayableFile("repeat-open")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        try await openAndReachPlaying(file: file, fixture: fixture, statuses: &statuses)

        await fixture.controller.open(mediaFileID: file.mediaFileID)

        await assertCommands(
            [.load(playbackPlayableFile(from: file)), .play],
            backend: fixture.backend
        )
        XCTAssertEqual(fixture.mediaOpening.calls, [file.mediaFileID])
        try await assertNoStatus(PlaybackStatusReader(existingIterator: statuses))
    }

    func testTrackDiscoveryEmitsApplicationStatusWithTracks() async throws {
        let file = try makeApplicationPlayableFile("tracks")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        await fixture.controller.open(mediaFileID: file.mediaFileID)
        try await discardNextStatus(statuses: &statuses)
        fixture.backend.emit(.stateChanged(.ready))
        try await discardNextStatus(statuses: &statuses)
        await fixture.backend.waitForCommandCount(2)
        fixture.backend.emit(.stateChanged(.playing))
        try await discardNextStatus(statuses: &statuses)

        fixture.backend.emit(
            .tracksDiscovered(
                audioTracks: [
                    PlaybackTrack(
                        id: "audio-1",
                        type: .audio,
                        language: "en",
                        title: "English",
                        isDefault: true,
                        isSelected: true
                    ),
                    PlaybackTrack(
                        id: "audio-2",
                        type: .audio,
                        language: nil,
                        title: "Commentary",
                        isDefault: false,
                        isSelected: false
                    )
                ],
                subtitleTracks: [
                    PlaybackTrack(
                        id: "subtitle-1",
                        type: .subtitle,
                        language: "es",
                        title: nil,
                        isDefault: false,
                        isSelected: true
                    )
                ]
            )
        )

        try await assertNextStatus(
            PlaybackApplicationStatus(
                state: .playing,
                mediaFileID: file.mediaFileID,
                displayName: file.displayName,
                positionMS: 0,
                durationMS: nil,
                audioTracks: [
                    PlaybackApplicationTrack(
                        id: "audio-1",
                        displayLabel: "English (Default)",
                        isDefault: true,
                        isSelected: true
                    ),
                    PlaybackApplicationTrack(
                        id: "audio-2",
                        displayLabel: "Commentary",
                        isDefault: false,
                        isSelected: false
                    )
                ],
                subtitleTracks: [
                    PlaybackApplicationTrack(
                        id: "subtitle-1",
                        displayLabel: "ES",
                        isDefault: false,
                        isSelected: true
                    )
                ]
            ),
            statuses: &statuses
        )
    }

    func testAudioTrackSelectionForwardsCommandAndUpdatesStatus() async throws {
        let file = try makeApplicationPlayableFile("audio-selection")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        try await openAndReachPlaying(file: file, fixture: fixture, statuses: &statuses)
        fixture.backend.emit(
            .tracksDiscovered(
                audioTracks: [
                    PlaybackTrack(
                        id: "audio-1",
                        type: .audio,
                        language: nil,
                        title: "Main",
                        isDefault: true,
                        isSelected: true
                    ),
                    PlaybackTrack(
                        id: "audio-2",
                        type: .audio,
                        language: nil,
                        title: "Commentary",
                        isDefault: false,
                        isSelected: false
                    )
                ],
                subtitleTracks: []
            )
        )
        try await discardNextStatus(statuses: &statuses)

        await fixture.controller.selectAudioTrack(trackID: "audio-2")
        await fixture.backend.waitForCommandCount(3)

        await assertCommands(
            [
                .load(playbackPlayableFile(from: file)),
                .play,
                .selectAudioTrack("audio-2")
            ],
            backend: fixture.backend
        )
        try await assertNextStatus(
            PlaybackApplicationStatus(
                state: .playing,
                mediaFileID: file.mediaFileID,
                displayName: file.displayName,
                positionMS: 0,
                durationMS: nil,
                audioTracks: [
                    PlaybackApplicationTrack(
                        id: "audio-1",
                        displayLabel: "Main (Default)",
                        isDefault: true,
                        isSelected: false
                    ),
                    PlaybackApplicationTrack(
                        id: "audio-2",
                        displayLabel: "Commentary",
                        isDefault: false,
                        isSelected: true
                    )
                ]
            ),
            statuses: &statuses
        )
    }

    func testSubtitleTrackSelectionAndDisableForwardCommandsAndUpdateStatus() async throws {
        let file = try makeApplicationPlayableFile("subtitle-selection")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        try await openAndReachPlaying(file: file, fixture: fixture, statuses: &statuses)
        fixture.backend.emit(
            .tracksDiscovered(
                audioTracks: [],
                subtitleTracks: [
                    PlaybackTrack(
                        id: "subtitle-1",
                        type: .subtitle,
                        language: "en",
                        title: nil,
                        isDefault: true,
                        isSelected: true
                    ),
                    PlaybackTrack(
                        id: "subtitle-2",
                        type: .subtitle,
                        language: nil,
                        title: "Director Notes",
                        isDefault: false,
                        isSelected: false
                    )
                ]
            )
        )
        try await discardNextStatus(statuses: &statuses)

        await fixture.controller.selectSubtitleTrack(trackID: "subtitle-2")
        await fixture.backend.waitForCommandCount(3)
        try await assertNextStatus(
            PlaybackApplicationStatus(
                state: .playing,
                mediaFileID: file.mediaFileID,
                displayName: file.displayName,
                positionMS: 0,
                durationMS: nil,
                subtitleTracks: [
                    PlaybackApplicationTrack(
                        id: "subtitle-1",
                        displayLabel: "EN (Default)",
                        isDefault: true,
                        isSelected: false
                    ),
                    PlaybackApplicationTrack(
                        id: "subtitle-2",
                        displayLabel: "Director Notes",
                        isDefault: false,
                        isSelected: true
                    )
                ]
            ),
            statuses: &statuses
        )

        await fixture.controller.disableSubtitles()
        await fixture.backend.waitForCommandCount(4)

        await assertCommands(
            [
                .load(playbackPlayableFile(from: file)),
                .play,
                .selectSubtitleTrack("subtitle-2"),
                .disableSubtitle
            ],
            backend: fixture.backend
        )
        try await assertNextStatus(
            PlaybackApplicationStatus(
                state: .playing,
                mediaFileID: file.mediaFileID,
                displayName: file.displayName,
                positionMS: 0,
                durationMS: nil,
                subtitleTracks: [
                    PlaybackApplicationTrack(
                        id: "subtitle-1",
                        displayLabel: "EN (Default)",
                        isDefault: true,
                        isSelected: false
                    ),
                    PlaybackApplicationTrack(
                        id: "subtitle-2",
                        displayLabel: "Director Notes",
                        isDefault: false,
                        isSelected: false
                    )
                ]
            ),
            statuses: &statuses
        )
    }

    func testTrackSelectionForMissingTrackIsNoOp() async throws {
        let file = try makeApplicationPlayableFile("missing-track")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        try await openAndReachPlaying(file: file, fixture: fixture, statuses: &statuses)

        await fixture.controller.selectAudioTrack(trackID: "missing-audio")
        await fixture.controller.selectSubtitleTrack(trackID: "missing-subtitle")
        await fixture.controller.disableSubtitles()

        await assertCommands(
            [.load(playbackPlayableFile(from: file)), .play],
            backend: fixture.backend
        )
        try await assertNoStatus(PlaybackStatusReader(existingIterator: statuses))
    }

    // MARK: - Seek

    func testSeekToValidPositionForwardsCommand() async throws {
        let file = try makeApplicationPlayableFile("seek-forward")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        try await openAndReachPlaying(file: file, fixture: fixture, statuses: &statuses)

        await fixture.controller.seek(toMS: 30_000)
        await fixture.backend.waitForCommandCount(3)
        await assertCommands(
            [.load(playbackPlayableFile(from: file)), .play, .seek(30_000)],
            backend: fixture.backend
        )
    }

    func testSeekWhileReadyForwardsCommand() async throws {
        let file = try makeApplicationPlayableFile("seek-ready")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        await fixture.controller.open(mediaFileID: file.mediaFileID)
        try await discardNextStatus(statuses: &statuses)
        fixture.backend.emit(.stateChanged(.ready))
        try await discardNextStatus(statuses: &statuses)

        await fixture.controller.seek(toMS: 30_000)
        await fixture.backend.waitForCommandCount(3)
        await assertCommands(
            [.load(playbackPlayableFile(from: file)), .play, .seek(30_000)],
            backend: fixture.backend
        )
    }

    func testSeekWhilePausedForwardsCommand() async throws {
        let file = try makeApplicationPlayableFile("seek-paused")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        try await openAndReachPlaying(file: file, fixture: fixture, statuses: &statuses)
        await fixture.controller.pause()
        fixture.backend.emit(.stateChanged(.paused))
        try await discardNextStatus(statuses: &statuses)

        await fixture.controller.seek(toMS: 30_000)
        await fixture.backend.waitForCommandCount(4)
        await assertCommands(
            [.load(playbackPlayableFile(from: file)), .play, .pause, .seek(30_000)],
            backend: fixture.backend
        )
    }

    func testSeekWhileBufferingForwardsCommand() async throws {
        let file = try makeApplicationPlayableFile("seek-buffering")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        try await openAndReachPlaying(file: file, fixture: fixture, statuses: &statuses)
        fixture.backend.emit(.stateChanged(.buffering))
        try await discardNextStatus(statuses: &statuses)

        await fixture.controller.seek(toMS: 30_000)
        await fixture.backend.waitForCommandCount(3)
        await assertCommands(
            [.load(playbackPlayableFile(from: file)), .play, .seek(30_000)],
            backend: fixture.backend
        )
    }

    func testSeekClampsNegativeToZero() async throws {
        let file = try makeApplicationPlayableFile("seek-negative")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        try await openAndReachPlaying(file: file, fixture: fixture, statuses: &statuses)

        await fixture.controller.seek(toMS: -5_000)
        await fixture.backend.waitForCommandCount(3)
        await assertCommands(
            [.load(playbackPlayableFile(from: file)), .play, .seek(0)],
            backend: fixture.backend
        )
    }

    func testSeekClampsPastDuration() async throws {
        let file = try makeApplicationPlayableFile("seek-past-duration")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        await fixture.controller.open(mediaFileID: file.mediaFileID)
        try await discardNextStatus(statuses: &statuses)
        fixture.backend.emit(.stateChanged(.ready))
        try await discardNextStatus(statuses: &statuses)
        await fixture.backend.waitForCommandCount(2)
        fixture.backend.emit(.stateChanged(.playing))
        try await discardNextStatus(statuses: &statuses)
        fixture.backend.emit(.durationUpdated(durationMS: 120_000))
        try await discardNextStatus(statuses: &statuses)

        await fixture.controller.seek(toMS: 200_000)
        await fixture.backend.waitForCommandCount(3)
        await assertCommands(
            [.load(playbackPlayableFile(from: file)), .play, .seek(120_000)],
            backend: fixture.backend
        )
    }

    func testSeekDoesNotEmitNewPositionBeforeBackendPositionUpdate() async throws {
        let file = try makeApplicationPlayableFile("seek-no-optimistic-status")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        try await openAndReachPlaying(file: file, fixture: fixture, statuses: &statuses)
        fixture.backend.emit(.positionUpdated(positionMS: 15_000))
        try await discardNextStatus(statuses: &statuses)

        await fixture.controller.seek(toMS: 30_000)
        fixture.backend.emit(.durationUpdated(durationMS: 120_000))
        try await assertNextStatus(
            PlaybackApplicationStatus(
                state: .playing,
                mediaFileID: file.mediaFileID,
                displayName: file.displayName,
                positionMS: 15_000,
                durationMS: 120_000
            ),
            statuses: &statuses
        )

        fixture.backend.emit(.positionUpdated(positionMS: 30_000))
        try await assertNextStatus(
            PlaybackApplicationStatus(
                state: .playing,
                mediaFileID: file.mediaFileID,
                displayName: file.displayName,
                positionMS: 30_000,
                durationMS: 120_000
            ),
            statuses: &statuses
        )
    }

    func testSeekIdleIsNoOp() async throws {
        let fixture = makeFixture(files: [:])
        let statuses = PlaybackStatusReader(fixture.controller.statusStream)

        await fixture.controller.seek(toMS: 30_000)

        await assertCommands([], backend: fixture.backend)
        try await assertNoStatus(statuses)
    }

    func testSeekLoadingIsNoOp() async throws {
        let file = try makeApplicationPlayableFile("seek-loading")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        await fixture.controller.open(mediaFileID: file.mediaFileID)
        try await discardNextStatus(statuses: &statuses)

        await fixture.controller.seek(toMS: 30_000)

        await assertCommands([.load(playbackPlayableFile(from: file))], backend: fixture.backend)
        try await assertNoStatus(PlaybackStatusReader(existingIterator: statuses))
    }

    func testSeekFailedIsNoOp() async throws {
        let file = try makeApplicationPlayableFile("seek-failed")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        await fixture.controller.open(mediaFileID: file.mediaFileID)
        try await discardNextStatus(statuses: &statuses)
        fixture.backend.emit(.playbackFailed(.mpvError("boom")))
        try await discardNextStatus(statuses: &statuses)

        await fixture.controller.seek(toMS: 30_000)

        await assertCommands([.load(playbackPlayableFile(from: file))], backend: fixture.backend)
        try await assertNoStatus(PlaybackStatusReader(existingIterator: statuses))
    }

    func testSeekEndedIsNoOp() async throws {
        let file = try makeApplicationPlayableFile("seek-ended")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        await fixture.controller.open(mediaFileID: file.mediaFileID)
        try await discardNextStatus(statuses: &statuses)
        fixture.backend.emit(.stateChanged(.ready))
        try await discardNextStatus(statuses: &statuses)
        await fixture.backend.waitForCommandCount(2)
        fixture.backend.emit(.stateChanged(.playing))
        try await discardNextStatus(statuses: &statuses)
        fixture.backend.emit(.playbackEnded(finalPositionMS: 120_000, durationMS: 120_000))
        try await discardNextStatus(statuses: &statuses)

        await fixture.controller.seek(toMS: 50_000)

        await assertCommands(
            [.load(playbackPlayableFile(from: file)), .play],
            backend: fixture.backend
        )
        try await assertNoStatus(PlaybackStatusReader(existingIterator: statuses))
    }

    func testSeekRelativeForwardsAbsolutePosition() async throws {
        let file = try makeApplicationPlayableFile("seek-relative")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        try await openAndReachPlaying(file: file, fixture: fixture, statuses: &statuses)
        fixture.backend.emit(.positionUpdated(positionMS: 15_000))
        try await discardNextStatus(statuses: &statuses)

        await fixture.controller.seekRelative(byMS: 5_000)
        await fixture.backend.waitForCommandCount(3)
        await assertCommands(
            [.load(playbackPlayableFile(from: file)), .play, .seek(20_000)],
            backend: fixture.backend
        )
    }

    func testSeekRelativeClampsToZero() async throws {
        let file = try makeApplicationPlayableFile("seek-relative-clamp")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        try await openAndReachPlaying(file: file, fixture: fixture, statuses: &statuses)

        await fixture.controller.seekRelative(byMS: -100_000)
        await fixture.backend.waitForCommandCount(3)
        await assertCommands(
            [.load(playbackPlayableFile(from: file)), .play, .seek(0)],
            backend: fixture.backend
        )
    }

    func testSeekCallsNoteSeekRequested() async throws {
        let file = try makeApplicationPlayableFile("seek-note")
        let fixture = makeFixture(files: [file])
        var statuses = fixture.controller.statusStream.makeAsyncIterator()

        try await openAndReachPlaying(file: file, fixture: fixture, statuses: &statuses)
        fixture.backend.emit(.positionUpdated(positionMS: 15_000))
        try await discardNextStatus(statuses: &statuses)

        await fixture.controller.seek(toMS: 30_000)
        await fixture.backend.waitForCommandCount(3)

        fixture.backend.emit(.positionUpdated(positionMS: 30_000))
        try await discardNextStatus(statuses: &statuses)

        let savePositions = fixture.progressStore.saveCalls.map(\.positionMS)
        XCTAssertTrue(
            savePositions.contains(30_000),
            "Expected save at position 30_000 after seek, got saves at \(savePositions)"
        )
    }

    private func makeFixture(
        files: [Application.PlayableFile],
        openingError: (any Error)? = nil
    ) -> ControllerFixture {
        makeFixture(
            files: Dictionary(uniqueKeysWithValues: files.map { ($0.mediaFileID, $0) }),
            openingError: openingError
        )
    }

    private func makeFixture(
        files: [MediaFileID: Application.PlayableFile],
        openingError: (any Error)? = nil
    ) -> ControllerFixture {
        let backend = FakePlaybackBackend()
        let coordinator = PlaybackCoordinator(backend: backend)
        let progressStore = RecordingProgressStore()
        let progressCoordinator = PlaybackProgressCoordinator(
            progressUseCase: PlaybackProgressUseCase(store: progressStore),
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        let mediaOpening = FakeMediaOpening(files: files, error: openingError)
        let controller = PlaybackApplicationController(
            coordinator: coordinator,
            progressCoordinator: progressCoordinator,
            mediaOpening: mediaOpening
        )
        return ControllerFixture(
            controller: controller,
            backend: backend,
            mediaOpening: mediaOpening,
            progressStore: progressStore
        )
    }

    private func openAndReachPlaying(
        file: Application.PlayableFile,
        fixture: ControllerFixture,
        statuses: inout AsyncStream<PlaybackApplicationStatus>.Iterator,
        sourceFile: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        await fixture.controller.open(mediaFileID: file.mediaFileID)
        try await discardNextStatus(statuses: &statuses, file: sourceFile, line: line)

        fixture.backend.emit(.stateChanged(.ready))
        try await discardNextStatus(statuses: &statuses, file: sourceFile, line: line)
        await fixture.backend.waitForCommandCount(2)

        fixture.backend.emit(.stateChanged(.playing))
        try await assertNextStatus(
            PlaybackApplicationStatus(
                state: .playing,
                mediaFileID: file.mediaFileID,
                displayName: file.displayName,
                positionMS: 0,
                durationMS: nil
            ),
            statuses: &statuses,
            file: sourceFile,
            line: line
        )
    }

    private func assertNextStatus(
        _ expected: PlaybackApplicationStatus,
        statuses: inout AsyncStream<PlaybackApplicationStatus>.Iterator,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let status = try await nextStatus(statuses: &statuses, file: file, line: line)
        XCTAssertEqual(status, expected, file: file, line: line)
    }

    private func discardNextStatus(
        statuses: inout AsyncStream<PlaybackApplicationStatus>.Iterator,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        _ = try await nextStatus(statuses: &statuses, file: file, line: line)
    }

    private func nextStatus(
        statuses: inout AsyncStream<PlaybackApplicationStatus>.Iterator,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> PlaybackApplicationStatus {
        guard let status = await statuses.next() else {
            XCTFail("Expected playback application status", file: file, line: line)
            throw PlaybackApplicationControllerTestError.missingStatus
        }
        return status
    }

    private func assertNoStatus(
        _ statuses: PlaybackStatusReader,
        timeoutNanoseconds: UInt64 = 20_000_000,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let status = try await nextStatus(
            statuses,
            timeoutNanoseconds: timeoutNanoseconds
        )
        XCTAssertNil(status, file: file, line: line)
    }

    private func nextStatus(
        _ statuses: PlaybackStatusReader,
        timeoutNanoseconds: UInt64
    ) async throws -> PlaybackApplicationStatus? {
        try await withThrowingTaskGroup(of: PlaybackApplicationStatus?.self) { group in
            group.addTask {
                await statuses.next()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                return nil
            }

            let status = try await group.next() ?? nil
            group.cancelAll()
            return status
        }
    }

    private func assertCommands(
        _ expected: [FakeBackendCommand],
        backend: FakePlaybackBackend,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let commands = await backend.commands()
        XCTAssertEqual(commands, expected, file: file, line: line)
    }
}

private struct ControllerFixture {
    let controller: PlaybackApplicationController
    let backend: FakePlaybackBackend
    let mediaOpening: FakeMediaOpening
    let progressStore: RecordingProgressStore
}

private enum PlaybackApplicationControllerTestError: Error {
    case missingStatus
}

private final class PlaybackStatusReader: @unchecked Sendable {
    private var iterator: AsyncStream<PlaybackApplicationStatus>.Iterator

    init(_ stream: AsyncStream<PlaybackApplicationStatus>) {
        self.iterator = stream.makeAsyncIterator()
    }

    init(existingIterator: AsyncStream<PlaybackApplicationStatus>.Iterator) {
        self.iterator = existingIterator
    }

    func next() async -> PlaybackApplicationStatus? {
        await iterator.next()
    }
}

private struct SecretOpeningError: Error {
    let rawMessage = "secret opening details"
}

private final class FakeMediaOpening: MediaOpening, @unchecked Sendable {
    private let lock = NSLock()
    private let files: [MediaFileID: Application.PlayableFile]
    private let error: (any Error)?
    private var recordedCalls: [MediaFileID] = []

    init(files: [MediaFileID: Application.PlayableFile], error: (any Error)?) {
        self.files = files
        self.error = error
    }

    var calls: [MediaFileID] {
        withLock {
            recordedCalls
        }
    }

    func open(mediaFileID: MediaFileID) throws -> Application.PlayableFile {
        let result = withLock {
            recordedCalls.append(mediaFileID)
            return files[mediaFileID]
        }

        if let error {
            throw error
        }

        guard let result else {
            throw ApplicationPlaybackError.mediaFileNotFound
        }
        return result
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private enum FakeBackendCommand: Equatable {
    case load(Playback.PlayableFile)
    case play
    case pause
    case seek(Int)
    case stop
    case selectAudioTrack(String)
    case selectSubtitleTrack(String)
    case disableSubtitle
    case shutdown
}

private actor FakePlaybackBackendState {
    private var commandLog: [FakeBackendCommand] = []
    private var commandWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func append(_ command: FakeBackendCommand) {
        commandLog.append(command)
        resumeSatisfiedWaiters()
    }

    func commands() -> [FakeBackendCommand] {
        commandLog
    }

    func waitForCommandCount(_ count: Int) async {
        guard commandLog.count < count else {
            return
        }

        await withCheckedContinuation { continuation in
            commandWaiters.append((count, continuation))
        }
    }

    private func resumeSatisfiedWaiters() {
        var remainingWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
        for waiter in commandWaiters {
            if commandLog.count >= waiter.0 {
                waiter.1.resume()
            } else {
                remainingWaiters.append(waiter)
            }
        }
        commandWaiters = remainingWaiters
    }
}

private final class FakePlaybackBackend: PlaybackBackend, @unchecked Sendable {
    private let state = FakePlaybackBackendState()
    private let eventHub = FakePlaybackEventHub()

    var events: AsyncStream<PlaybackEvent> {
        eventHub.makeStream()
    }

    func load(playableFile: Playback.PlayableFile) async throws {
        await state.append(.load(playableFile))
    }

    func play() async throws {
        await state.append(.play)
    }

    func pause() async throws {
        await state.append(.pause)
    }

    func seek(toMS positionMS: Int) async throws {
        await state.append(.seek(positionMS))
    }

    func stop() async throws {
        await state.append(.stop)
    }

    func selectAudioTrack(trackID: String) async throws {
        await state.append(.selectAudioTrack(trackID))
    }

    func selectSubtitleTrack(trackID: String) async throws {
        await state.append(.selectSubtitleTrack(trackID))
    }

    func disableSubtitle() async throws {
        await state.append(.disableSubtitle)
    }

    func shutdown() async {
        await state.append(.shutdown)
        eventHub.finishAll()
    }

    func emit(_ event: PlaybackEvent) {
        eventHub.emit(event)
    }

    func commands() async -> [FakeBackendCommand] {
        await state.commands()
    }

    func waitForCommandCount(_ count: Int) async {
        await state.waitForCommandCount(count)
    }
}

private final class FakePlaybackEventHub: @unchecked Sendable {
    private let lock = NSLock()
    private var nextID = 0
    private var continuations: [Int: AsyncStream<PlaybackEvent>.Continuation] = [:]

    func makeStream() -> AsyncStream<PlaybackEvent> {
        let streamID = withLock {
            nextID += 1
            return nextID
        }

        return AsyncStream(bufferingPolicy: .unbounded) { continuation in
            self.withLock {
                self.continuations[streamID] = continuation
            }
            continuation.onTermination = { @Sendable [weak self] _ in
                self?.removeContinuation(streamID)
            }
        }
    }

    func emit(_ event: PlaybackEvent) {
        let continuation = withLock {
            continuations[nextID]
        }
        continuation?.yield(event)
    }

    func finishAll() {
        let activeContinuations = withLock {
            let values = Array(continuations.values)
            continuations.removeAll()
            return values
        }
        for continuation in activeContinuations {
            continuation.finish()
        }
    }

    private func removeContinuation(_ streamID: Int) {
        withLock {
            continuations[streamID] = nil
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class RecordingProgressStore: PlaybackProgressStore, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedSaveCalls: [SaveCall] = []
    private var recordedIncrementCalls: [IncrementCall] = []
    private var recordedOperations: [ProgressOperation] = []

    var saveCalls: [SaveCall] {
        withLock {
            recordedSaveCalls
        }
    }

    var incrementCalls: [IncrementCall] {
        withLock {
            recordedIncrementCalls
        }
    }

    var operations: [ProgressOperation] {
        withLock {
            recordedOperations
        }
    }

    func savePlaybackProgress(
        mediaItemID: MediaItemID,
        mediaFileID: MediaFileID,
        positionMS: Int,
        durationMS: Int?,
        completed: Bool,
        playedAt: Date
    ) throws {
        withLock {
            recordedSaveCalls.append(
                SaveCall(
                    mediaItemID: mediaItemID,
                    mediaFileID: mediaFileID,
                    positionMS: positionMS,
                    durationMS: durationMS,
                    completed: completed,
                    playedAt: playedAt
                )
            )
            recordedOperations.append(.save)
        }
    }

    func incrementPlaybackCount(
        mediaItemID: MediaItemID,
        mediaFileID: MediaFileID,
        playedAt: Date
    ) throws {
        withLock {
            recordedIncrementCalls.append(
                IncrementCall(
                    mediaItemID: mediaItemID,
                    mediaFileID: mediaFileID,
                    playedAt: playedAt
                )
            )
            recordedOperations.append(.increment)
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private struct SaveCall: Equatable {
    let mediaItemID: MediaItemID
    let mediaFileID: MediaFileID
    let positionMS: Int
    let durationMS: Int?
    let completed: Bool
    let playedAt: Date
}

private struct IncrementCall: Equatable {
    let mediaItemID: MediaItemID
    let mediaFileID: MediaFileID
    let playedAt: Date
}

private enum ProgressOperation: Equatable {
    case increment
    case save
}

private func makeApplicationPlayableFile(
    _ name: String,
    resumePositionMS: Int? = nil
) throws -> Application.PlayableFile {
    try Application.PlayableFile(
        mediaItemID: "media-item-\(name)",
        mediaFileID: "media-file-\(name)",
        url: URL(fileURLWithPath: "/tmp/\(name).mkv"),
        displayName: "\(name).mkv",
        resumePositionMS: resumePositionMS
    )
}

private func playbackPlayableFile(from file: Application.PlayableFile) -> Playback.PlayableFile {
    Playback.PlayableFile(
        mediaItemID: file.mediaItemID,
        mediaFileID: file.mediaFileID,
        url: file.url,
        displayName: file.displayName,
        resumePositionMS: file.resumePositionMS
    )
}
