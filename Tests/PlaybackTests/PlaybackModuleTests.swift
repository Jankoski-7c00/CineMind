import Playback
import XCTest

final class PlaybackModuleTests: XCTestCase {
    func testPlaybackTargetImportsAndBuilds() {
        XCTAssertEqual(PlaybackModule.name, "Playback")
    }

    func testInitialStateIsIdle() async {
        let backend = FakePlaybackBackend()
        let coordinator = PlaybackCoordinator(backend: backend)

        await assertState(.idle, coordinator: coordinator)
        await assertNoActiveSession(coordinator)
    }

    func testOpenTransitionsToLoadingThenReadyAndPlayingFromBackendEvents() async throws {
        let backend = FakePlaybackBackend()
        let coordinator = PlaybackCoordinator(backend: backend)
        var events = coordinator.events.makeAsyncIterator()
        let file = makePlayableFile("first")

        await coordinator.open(file)
        try await assertNextEvent(.stateChanged(.loading), events: &events)
        await assertState(.loading, coordinator: coordinator)

        backend.emit(.stateChanged(.ready))
        try await assertNextEvent(.stateChanged(.ready), events: &events)
        await assertState(.ready, coordinator: coordinator)

        backend.emit(.stateChanged(.playing))
        try await assertNextEvent(.stateChanged(.playing), events: &events)
        await assertState(.playing, coordinator: coordinator)
    }

    func testPlayCommandForwardsToBackend() async throws {
        let backend = FakePlaybackBackend()
        let coordinator = PlaybackCoordinator(backend: backend)
        var events = coordinator.events.makeAsyncIterator()
        let file = makePlayableFile("play")
        try await openAndReachReady(file, coordinator: coordinator, backend: backend, events: &events)

        await coordinator.play()

        await assertCommands([.load(file), .play], backend: backend)
    }

    func testPauseCommandForwardsAndUpdatesStateThroughBackendEvent() async throws {
        let backend = FakePlaybackBackend()
        let coordinator = PlaybackCoordinator(backend: backend)
        var events = coordinator.events.makeAsyncIterator()
        let file = makePlayableFile("pause")
        try await openAndReachReady(file, coordinator: coordinator, backend: backend, events: &events)
        backend.emit(.stateChanged(.playing))
        try await assertNextEvent(.stateChanged(.playing), events: &events)

        await coordinator.pause()
        backend.emit(.stateChanged(.paused))

        await assertCommands([.load(file), .pause], backend: backend)
        try await assertNextEvent(.stateChanged(.paused), events: &events)
        await assertState(.paused, coordinator: coordinator)
    }

    func testSeekCommandForwardsAndPropagatesPositionUpdate() async throws {
        let backend = FakePlaybackBackend()
        let coordinator = PlaybackCoordinator(backend: backend)
        var events = coordinator.events.makeAsyncIterator()
        let file = makePlayableFile("seek")
        try await openAndReachReady(file, coordinator: coordinator, backend: backend, events: &events)

        await coordinator.seek(toMS: 42_000)
        backend.emit(.positionUpdated(positionMS: 42_000))

        await assertCommands([.load(file), .seek(42_000)], backend: backend)
        try await assertNextEvent(.positionUpdated(positionMS: 42_000), events: &events)
        let session = await coordinator.activeSession
        XCTAssertEqual(session?.positionMS, 42_000)
    }

    func testStopReturnsToIdle() async throws {
        let backend = FakePlaybackBackend()
        let coordinator = PlaybackCoordinator(backend: backend)
        var events = coordinator.events.makeAsyncIterator()
        let file = makePlayableFile("stop")
        try await openAndReachReady(file, coordinator: coordinator, backend: backend, events: &events)

        let didStop = await coordinator.stop()

        XCTAssertTrue(didStop)
        await assertCommands([.load(file), .stop], backend: backend)
        try await assertNextEvent(.stateChanged(.idle), events: &events)
        await assertState(.idle, coordinator: coordinator)
        await assertNoActiveSession(coordinator)
    }

    func testStopWithoutActiveSessionReturnsFalseAndDoesNotEmitIdle() async throws {
        let backend = FakePlaybackBackend()
        let coordinator = PlaybackCoordinator(backend: backend)
        let events = PlaybackEventReader(coordinator.events)

        let didStop = await coordinator.stop()

        XCTAssertFalse(didStop)
        await assertCommands([], backend: backend)
        await assertNoEvent(events)
    }

    func testOpeningSecondFileStopsPreviousSession() async throws {
        let backend = FakePlaybackBackend()
        let coordinator = PlaybackCoordinator(backend: backend)
        var events = coordinator.events.makeAsyncIterator()
        let first = makePlayableFile("first")
        let second = makePlayableFile("second")

        await coordinator.open(first)
        try await assertNextEvent(.stateChanged(.loading), events: &events)

        await coordinator.open(second)

        await assertCommands([.load(first), .stop, .load(second)], backend: backend)
        try await assertNextEvent(.stateChanged(.idle), events: &events)
        try await assertNextEvent(.stateChanged(.loading), events: &events)
        let session = await coordinator.activeSession
        XCTAssertEqual(session?.playableFile, second)
    }

    func testLoadThrowEmitsFailureBeforeFailedState() async throws {
        let backend = FakePlaybackBackend()
        await backend.setLoadError(.unsupportedFormat)
        let coordinator = PlaybackCoordinator(backend: backend)
        var events = coordinator.events.makeAsyncIterator()
        let file = makePlayableFile("load-fail")

        await coordinator.open(file)

        try await assertNextEvent(.stateChanged(.loading), events: &events)
        try await assertNextEvent(.playbackFailed(.unsupportedFormat), events: &events)
        try await assertNextEvent(.stateChanged(.failed), events: &events)
        await assertState(.failed, coordinator: coordinator)
        let session = await coordinator.activeSession
        XCTAssertEqual(session?.state, .failed)
    }

    func testBackendStopThrowStillClearsSessionAndReturnsToIdle() async throws {
        let backend = FakePlaybackBackend()
        let coordinator = PlaybackCoordinator(backend: backend)
        var events = coordinator.events.makeAsyncIterator()
        let file = makePlayableFile("stop-fail")
        try await openAndReachReady(file, coordinator: coordinator, backend: backend, events: &events)
        await backend.setStopError(.mpvError("stop failed"))

        let didStop = await coordinator.stop()

        XCTAssertTrue(didStop)
        try await assertNextEvent(.playbackFailed(.mpvError("stop failed")), events: &events)
        try await assertNextEvent(.stateChanged(.idle), events: &events)
        await assertState(.idle, coordinator: coordinator)
        await assertNoActiveSession(coordinator)
    }

    func testLateEventsFromStoppedOrReplacedSessionDoNotMutateCurrentSession() async throws {
        let backend = FakePlaybackBackend()
        let coordinator = PlaybackCoordinator(backend: backend)
        var events = coordinator.events.makeAsyncIterator()
        let first = makePlayableFile("old")
        let second = makePlayableFile("new")

        await coordinator.open(first)
        try await assertNextEvent(.stateChanged(.loading), events: &events)
        let firstStreamID = backend.latestStreamID()

        await coordinator.open(second)
        try await assertNextEvent(.stateChanged(.idle), events: &events)
        try await assertNextEvent(.stateChanged(.loading), events: &events)

        backend.emit(.stateChanged(.playing), toStreamID: firstStreamID)
        try await Task.sleep(nanoseconds: 20_000_000)
        await assertState(.loading, coordinator: coordinator)
        let loadingSession = await coordinator.activeSession
        XCTAssertEqual(loadingSession?.playableFile, second)

        backend.emit(.stateChanged(.ready))
        try await assertNextEvent(.stateChanged(.ready), events: &events)
        await assertState(.ready, coordinator: coordinator)
    }

    func testFailedBackendEventMovesStateToFailed() async throws {
        let backend = FakePlaybackBackend()
        let coordinator = PlaybackCoordinator(backend: backend)
        var events = coordinator.events.makeAsyncIterator()
        let file = makePlayableFile("backend-fail")
        try await openAndReachReady(file, coordinator: coordinator, backend: backend, events: &events)

        backend.emit(.playbackFailed(.mpvError("boom")))

        try await assertNextEvent(.playbackFailed(.mpvError("boom")), events: &events)
        try await assertNextEvent(.stateChanged(.failed), events: &events)
        await assertState(.failed, coordinator: coordinator)
        let session = await coordinator.activeSession
        XCTAssertEqual(session?.state, .failed)
    }

    func testInvalidCommandEmitsInvalidStateAndPreservesCurrentState() async throws {
        let backend = FakePlaybackBackend()
        let coordinator = PlaybackCoordinator(backend: backend)
        var events = coordinator.events.makeAsyncIterator()
        let file = makePlayableFile("invalid")
        try await openAndReachReady(file, coordinator: coordinator, backend: backend, events: &events)

        await coordinator.pause()

        let event = try await nextEvent(&events)
        guard case .playbackFailed(.invalidState(let message)) = event else {
            return XCTFail("Expected invalidState, got \(event)")
        }
        XCTAssertTrue(message.contains("pause"))
        await assertState(.ready, coordinator: coordinator)
        await assertCommands([.load(file)], backend: backend)
    }

    func testTracksDiscoveredEventIsPropagatedAndStored() async throws {
        let backend = FakePlaybackBackend()
        let coordinator = PlaybackCoordinator(backend: backend)
        var events = coordinator.events.makeAsyncIterator()
        let file = makePlayableFile("tracks")
        try await openAndReachReady(file, coordinator: coordinator, backend: backend, events: &events)
        let audioTracks = [
            PlaybackTrack(
                id: "a1",
                type: .audio,
                language: "en",
                title: "English",
                isDefault: true,
                isSelected: true
            )
        ]
        let subtitleTracks = [
            PlaybackTrack(
                id: "s1",
                type: .subtitle,
                language: "es",
                title: "Spanish",
                isDefault: false,
                isSelected: false
            )
        ]

        backend.emit(.tracksDiscovered(audioTracks: audioTracks, subtitleTracks: subtitleTracks))

        try await assertNextEvent(
            .tracksDiscovered(audioTracks: audioTracks, subtitleTracks: subtitleTracks),
            events: &events
        )
        let session = await coordinator.activeSession
        XCTAssertEqual(session?.audioTracks, audioTracks)
        XCTAssertEqual(session?.subtitleTracks, subtitleTracks)
    }

    func testTrackSelectionCommandsAreForwardedWithActiveSession() async throws {
        let backend = FakePlaybackBackend()
        let coordinator = PlaybackCoordinator(backend: backend)
        var events = coordinator.events.makeAsyncIterator()
        let file = makePlayableFile("select")
        try await openAndReachReady(file, coordinator: coordinator, backend: backend, events: &events)

        await coordinator.selectAudioTrack(trackID: "audio-2")
        await coordinator.selectSubtitleTrack(trackID: "subtitle-3")
        await coordinator.disableSubtitle()

        await assertCommands(
            [
                .load(file),
                .selectAudioTrack("audio-2"),
                .selectSubtitleTrack("subtitle-3"),
                .disableSubtitle
            ],
            backend: backend
        )
    }

    func testTrackSelectionWithoutActiveSessionEmitsInvalidStateAndDoesNotCallBackend() async throws {
        let backend = FakePlaybackBackend()
        let coordinator = PlaybackCoordinator(backend: backend)
        var events = coordinator.events.makeAsyncIterator()

        await coordinator.selectAudioTrack(trackID: "audio-1")

        let event = try await nextEvent(&events)
        guard case .playbackFailed(.invalidState(let message)) = event else {
            return XCTFail("Expected invalidState, got \(event)")
        }
        XCTAssertTrue(message.contains("active session"))
        await assertState(.idle, coordinator: coordinator)
        await assertCommands([], backend: backend)
    }

    func testShutdownCallsBackendShutdownAndPostShutdownCommandsDoNotCrash() async throws {
        let backend = FakePlaybackBackend()
        let coordinator = PlaybackCoordinator(backend: backend)
        var events = coordinator.events.makeAsyncIterator()
        let file = makePlayableFile("shutdown")

        await coordinator.open(file)
        try await assertNextEvent(.stateChanged(.loading), events: &events)

        await coordinator.shutdown()
        await coordinator.play()
        await coordinator.pause()
        await coordinator.seek(toMS: 1_000)
        await coordinator.selectSubtitleTrack(trackID: "s1")
        let didStopAfterShutdown = await coordinator.stop()
        await coordinator.open(makePlayableFile("after-shutdown"))

        XCTAssertFalse(didStopAfterShutdown)
        await assertCommands([.load(file), .shutdown], backend: backend)
        await assertState(.idle, coordinator: coordinator)
        await assertNoActiveSession(coordinator)
    }

    private func openAndReachReady(
        _ file: PlayableFile,
        coordinator: PlaybackCoordinator,
        backend: FakePlaybackBackend,
        events: inout AsyncStream<PlaybackEvent>.Iterator
    ) async throws {
        await coordinator.open(file)
        try await assertNextEvent(.stateChanged(.loading), events: &events)
        backend.emit(.stateChanged(.ready))
        try await assertNextEvent(.stateChanged(.ready), events: &events)
        await assertState(.ready, coordinator: coordinator)
    }

    private func assertNextEvent(
        _ expected: PlaybackEvent,
        events: inout AsyncStream<PlaybackEvent>.Iterator,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let event = try await nextEvent(&events, file: file, line: line)
        XCTAssertEqual(event, expected, file: file, line: line)
    }

    private func assertState(
        _ expected: PlaybackState,
        coordinator: PlaybackCoordinator,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let state = await coordinator.state
        XCTAssertEqual(state, expected, file: file, line: line)
    }

    private func assertNoActiveSession(
        _ coordinator: PlaybackCoordinator,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let session = await coordinator.activeSession
        XCTAssertNil(session, file: file, line: line)
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

    private func nextEvent(
        _ events: inout AsyncStream<PlaybackEvent>.Iterator,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> PlaybackEvent {
        guard let event = await events.next() else {
            XCTFail("Expected a playback event", file: file, line: line)
            throw PlaybackTestError.missingEvent
        }

        return event
    }

    private func assertNoEvent(
        _ events: PlaybackEventReader,
        timeoutNanoseconds: UInt64 = 20_000_000,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let event = await withTaskGroup(of: PlaybackEvent?.self) { group in
            group.addTask {
                await events.next()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return nil
            }

            let event = await group.next() ?? nil
            group.cancelAll()
            return event
        }
        XCTAssertNil(event, file: file, line: line)
    }

    private func makePlayableFile(_ name: String) -> PlayableFile {
        PlayableFile(
            mediaItemID: "media-item-\(name)",
            mediaFileID: "media-file-\(name)",
            url: URL(fileURLWithPath: "/tmp/\(name).mkv"),
            displayName: "\(name).mkv",
            resumePositionMS: nil
        )
    }
}

private enum PlaybackTestError: Error {
    case missingEvent
}

private final class PlaybackEventReader: @unchecked Sendable {
    private var iterator: AsyncStream<PlaybackEvent>.Iterator

    init(_ stream: AsyncStream<PlaybackEvent>) {
        self.iterator = stream.makeAsyncIterator()
    }

    func next() async -> PlaybackEvent? {
        await iterator.next()
    }
}

private enum FakeBackendCommand: Equatable {
    case load(PlayableFile)
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
    private var loadFailure: PlaybackError?
    private var stopFailure: PlaybackError?

    func append(_ command: FakeBackendCommand) {
        commandLog.append(command)
    }

    func commands() -> [FakeBackendCommand] {
        commandLog
    }

    func setLoadError(_ error: PlaybackError?) {
        loadFailure = error
    }

    func setStopError(_ error: PlaybackError?) {
        stopFailure = error
    }

    func currentLoadError() -> PlaybackError? {
        loadFailure
    }

    func currentStopError() -> PlaybackError? {
        stopFailure
    }
}

// @unchecked Sendable is limited to this test fake. Command state is actor-isolated,
// and event continuation state is protected by FakePlaybackEventHub's lock.
private final class FakePlaybackBackend: PlaybackBackend, @unchecked Sendable {
    private let state = FakePlaybackBackendState()
    private let eventHub = FakePlaybackEventHub()

    var events: AsyncStream<PlaybackEvent> {
        eventHub.makeStream()
    }

    func load(playableFile: PlayableFile) async throws {
        await state.append(.load(playableFile))
        if let error = await state.currentLoadError() {
            throw error
        }
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
        if let error = await state.currentStopError() {
            throw error
        }
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

    func emit(_ event: PlaybackEvent, toStreamID streamID: Int) {
        eventHub.emit(event, toStreamID: streamID)
    }

    func latestStreamID() -> Int {
        eventHub.latestStreamID()
    }

    func commands() async -> [FakeBackendCommand] {
        await state.commands()
    }

    func setLoadError(_ error: PlaybackError?) async {
        await state.setLoadError(error)
    }

    func setStopError(_ error: PlaybackError?) async {
        await state.setStopError(error)
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
        emit(event, toStreamID: latestStreamID())
    }

    func emit(_ event: PlaybackEvent, toStreamID streamID: Int) {
        let continuation = withLock {
            continuations[streamID]
        }
        continuation?.yield(event)
    }

    func latestStreamID() -> Int {
        withLock {
            nextID
        }
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
        defer {
            lock.unlock()
        }
        return body()
    }
}
