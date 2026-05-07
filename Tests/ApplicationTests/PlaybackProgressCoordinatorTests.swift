import Application
import Domain
import Foundation
import Playback
import XCTest

final class PlaybackProgressCoordinatorTests: XCTestCase {
    private let mediaItemID: MediaItemID = "item"
    private let mediaFileID: MediaFileID = "file"

    func testFirstPlayingIncrementsPlayCountButDoesNotSaveProgress() async throws {
        let store = RecordingProgressStore()
        let coordinator = makeCoordinator(store: store)

        await startSession(coordinator)
        try await coordinator.handle(.stateChanged(.ready))
        try await coordinator.handle(.stateChanged(.playing))

        XCTAssertEqual(store.incrementCalls.count, 1)
        XCTAssertEqual(store.saveCalls.count, 0)
        XCTAssertEqual(store.operations, [.increment])
    }

    func testPeriodicSaveOccursEveryFiveSecondsWhilePlaying() async throws {
        let store = RecordingProgressStore()
        let clock = ManualClock()
        let coordinator = makeCoordinator(store: store, clock: clock)

        await startSession(coordinator)
        try await coordinator.handle(.stateChanged(.ready))
        try await coordinator.handle(.stateChanged(.playing))

        clock.advance(seconds: 4.9)
        try await coordinator.handle(.positionUpdated(positionMS: 4_000))
        XCTAssertEqual(store.saveCalls.count, 0)

        clock.advance(seconds: 0.1)
        try await coordinator.handle(.positionUpdated(positionMS: 5_000))
        XCTAssertEqual(store.saveCalls.map(\.positionMS), [5_000])

        clock.advance(seconds: 5)
        try await coordinator.handle(.positionUpdated(positionMS: 10_000))
        XCTAssertEqual(store.saveCalls.map(\.positionMS), [5_000, 10_000])
    }

    func testNoPeriodicSaveBeforeThreshold() async throws {
        let store = RecordingProgressStore()
        let clock = ManualClock()
        let coordinator = makeCoordinator(store: store, clock: clock)

        await startSession(coordinator)
        try await coordinator.handle(.stateChanged(.playing))

        clock.advance(seconds: 4.999)
        try await coordinator.handle(.positionUpdated(positionMS: 4_999))

        XCTAssertEqual(store.saveCalls.count, 0)
    }

    func testPeriodicSaveOnlyRunsWhileLatestStateIsPlaying() async throws {
        let store = RecordingProgressStore()
        let clock = ManualClock()
        let coordinator = makeCoordinator(store: store, clock: clock)

        await startSession(coordinator)
        try await coordinator.handle(.stateChanged(.playing))
        try await coordinator.handle(.positionUpdated(positionMS: 500))
        try await coordinator.handle(.stateChanged(.paused))

        clock.advance(seconds: 10)
        try await coordinator.handle(.positionUpdated(positionMS: 5_000))
        XCTAssertEqual(store.saveCalls.count, 0)

        try await coordinator.handle(.stateChanged(.playing))
        clock.advance(seconds: 4.9)
        try await coordinator.handle(.positionUpdated(positionMS: 9_000))
        XCTAssertEqual(store.saveCalls.count, 0)

        clock.advance(seconds: 0.1)
        try await coordinator.handle(.positionUpdated(positionMS: 10_000))
        XCTAssertEqual(store.saveCalls.map(\.positionMS), [10_000])
    }

    func testImmediateSaveOnPauseRequiresStartedPlaybackAndMaterialPosition() async throws {
        let store = RecordingProgressStore()
        let coordinator = makeCoordinator(store: store)

        await startSession(coordinator)
        try await coordinator.handle(.positionUpdated(positionMS: 20_000))
        try await coordinator.handle(.stateChanged(.paused))
        XCTAssertEqual(store.saveCalls.count, 0)

        try await coordinator.handle(.stateChanged(.playing))
        try await coordinator.handle(.positionUpdated(positionMS: 20_000))
        try await coordinator.handle(.stateChanged(.paused))

        XCTAssertEqual(store.saveCalls.map(\.positionMS), [20_000])
    }

    func testImmediateSaveOnStopRequiresStartedPlaybackAndMaterialPosition() async throws {
        let store = RecordingProgressStore()
        let coordinator = makeCoordinator(store: store)

        await startSession(coordinator)
        try await coordinator.handle(.stateChanged(.playing))
        try await coordinator.handle(.positionUpdated(positionMS: 20_000))
        try await coordinator.handle(.stateChanged(.idle))
        try await coordinator.closeSession()

        XCTAssertEqual(store.saveCalls.map(\.positionMS), [20_000])
    }

    func testEndedSaveIsCompletedAndLaterIdleOrCloseDoesNotDuplicate() async throws {
        let store = RecordingProgressStore()
        let coordinator = makeCoordinator(store: store)

        await startSession(coordinator)
        try await coordinator.handle(.stateChanged(.playing))
        try await coordinator.handle(.playbackEnded(finalPositionMS: 600_000, durationMS: 600_000))
        try await coordinator.handle(.stateChanged(.idle))
        try await coordinator.closeSession()

        XCTAssertEqual(store.saveCalls.count, 1)
        XCTAssertEqual(store.saveCalls[0].positionMS, 600_000)
        XCTAssertTrue(store.saveCalls[0].completed)
    }

    func testIdleAfterEndedCanSaveAgainWhenPositionMateriallyChanged() async throws {
        let store = RecordingProgressStore()
        let coordinator = makeCoordinator(store: store)

        await startSession(coordinator)
        try await coordinator.handle(.stateChanged(.playing))
        try await coordinator.handle(.playbackEnded(finalPositionMS: 600_000, durationMS: 600_000))
        try await coordinator.handle(.positionUpdated(positionMS: 602_000))
        try await coordinator.handle(.stateChanged(.idle))

        XCTAssertEqual(store.saveCalls.map(\.positionMS), [600_000, 602_000])
        XCTAssertEqual(store.saveCalls.map(\.completed), [true, true])
    }

    func testNoProgressSaveOrPlayCountForFailedLoad() async throws {
        let store = RecordingProgressStore()
        let coordinator = makeCoordinator(store: store)

        await startSession(coordinator)
        try await coordinator.handle(.playbackFailed(.fileMissing))
        try await coordinator.handle(.stateChanged(.failed))
        try await coordinator.closeSession()

        XCTAssertEqual(store.saveCalls.count, 0)
        XCTAssertEqual(store.incrementCalls.count, 0)
    }

    func testPlaybackFailedDoesNotSaveImmediatelyButCloseCanSaveChangedProgress() async throws {
        let store = RecordingProgressStore()
        let coordinator = makeCoordinator(store: store)

        await startSession(coordinator)
        try await coordinator.handle(.stateChanged(.playing))
        try await coordinator.handle(.positionUpdated(positionMS: 15_000))
        try await coordinator.handle(.playbackFailed(.mpvError("decode failed")))
        XCTAssertEqual(store.saveCalls.count, 0)

        try await coordinator.closeSession()

        XCTAssertEqual(store.saveCalls.map(\.positionMS), [15_000])
        XCTAssertFalse(store.saveCalls[0].completed)
    }

    func testUnchangedPositionDoesNotDuplicateSave() async throws {
        let store = RecordingProgressStore()
        let coordinator = makeCoordinator(store: store)

        await startSession(coordinator)
        try await coordinator.handle(.stateChanged(.playing))
        try await coordinator.handle(.positionUpdated(positionMS: 20_000))
        try await coordinator.handle(.stateChanged(.paused))
        try await coordinator.handle(.stateChanged(.idle))
        try await coordinator.closeSession()

        XCTAssertEqual(store.saveCalls.map(\.positionMS), [20_000])
    }

    func testSeekRequestSavesOnNextPositionUpdate() async throws {
        let store = RecordingProgressStore()
        let coordinator = makeCoordinator(store: store)

        await startSession(coordinator)
        try await coordinator.handle(.stateChanged(.playing))
        await coordinator.noteSeekRequested()
        try await coordinator.handle(.positionUpdated(positionMS: 30_000))

        XCTAssertEqual(store.saveCalls.map(\.positionMS), [30_000])
    }

    func testPlayCountIncrementsOnceAcrossRepeatedPlayingStates() async throws {
        let store = RecordingProgressStore()
        let coordinator = makeCoordinator(store: store)

        await startSession(coordinator)
        try await coordinator.handle(.stateChanged(.playing))
        try await coordinator.handle(.stateChanged(.paused))
        try await coordinator.handle(.stateChanged(.playing))
        try await coordinator.handle(.stateChanged(.buffering))
        try await coordinator.handle(.stateChanged(.playing))

        XCTAssertEqual(store.incrementCalls.count, 1)
    }

    func testCloseSessionIsIdempotent() async throws {
        let store = RecordingProgressStore()
        let coordinator = makeCoordinator(store: store)

        await startSession(coordinator)
        try await coordinator.handle(.stateChanged(.playing))
        try await coordinator.handle(.positionUpdated(positionMS: 15_000))
        try await coordinator.closeSession()
        try await coordinator.closeSession()

        XCTAssertEqual(store.saveCalls.map(\.positionMS), [15_000])
    }

    private func makeCoordinator(
        store: RecordingProgressStore,
        clock: ManualClock = ManualClock()
    ) -> PlaybackProgressCoordinator {
        PlaybackProgressCoordinator(
            progressUseCase: PlaybackProgressUseCase(store: store),
            now: { clock.now() }
        )
    }

    private func startSession(_ coordinator: PlaybackProgressCoordinator) async {
        await coordinator.startSession(
            mediaItemID: mediaItemID,
            mediaFileID: mediaFileID,
            initialPositionMS: 0
        )
    }
}

private final class RecordingProgressStore: PlaybackProgressStore {
    var saveCalls: [SaveCall] = []
    var incrementCalls: [IncrementCall] = []
    var operations: [ProgressOperation] = []

    func savePlaybackProgress(
        mediaItemID: MediaItemID,
        mediaFileID: MediaFileID,
        positionMS: Int,
        durationMS: Int?,
        completed: Bool,
        playedAt: Date
    ) throws {
        saveCalls.append(
            SaveCall(
                mediaItemID: mediaItemID,
                mediaFileID: mediaFileID,
                positionMS: positionMS,
                durationMS: durationMS,
                completed: completed,
                playedAt: playedAt
            )
        )
        operations.append(.save)
    }

    func incrementPlaybackCount(
        mediaItemID: MediaItemID,
        mediaFileID: MediaFileID,
        playedAt: Date
    ) throws {
        incrementCalls.append(
            IncrementCall(
                mediaItemID: mediaItemID,
                mediaFileID: mediaFileID,
                playedAt: playedAt
            )
        )
        operations.append(.increment)
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

private final class ManualClock: @unchecked Sendable {
    private var current: Date

    init(timeIntervalSince1970: TimeInterval = 1_000) {
        current = Date(timeIntervalSince1970: timeIntervalSince1970)
    }

    func now() -> Date {
        current
    }

    func advance(seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
    }
}
