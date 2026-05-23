import Playback
import PlaybackAVFoundation
import XCTest

final class PlaybackAVFoundationTests: XCTestCase {
    func testModuleImportsAndBuilds() {
        XCTAssertEqual(PlaybackAVFoundationModule.name, "PlaybackAVFoundation")
    }

    func testLoadSupportedFixtureEmitsLoadingReadyAndDuration() async throws {
        let backend = AVFoundationPlaybackBackend()
        addTeardownBlock {
            await backend.shutdown()
        }
        let events = PlaybackEventReader(backend.events)

        try await backend.load(playableFile: makeFixturePlayableFile())

        try await events.waitFor(.stateChanged(.loading))
        let duration = try await events.waitForDuration()
        XCTAssertGreaterThan(duration, 0)
        try await events.waitFor(.stateChanged(.ready))
    }

    func testPlayEmitsPlaying() async throws {
        let backend = AVFoundationPlaybackBackend()
        addTeardownBlock {
            await backend.shutdown()
        }
        let events = PlaybackEventReader(backend.events)

        try await backend.load(playableFile: makeFixturePlayableFile())
        try await events.waitFor(.stateChanged(.ready))

        try await backend.play()

        try await events.waitFor(.stateChanged(.playing), timeoutNanoseconds: 8_000_000_000)
    }

    func testSeekEmitsPositionUpdate() async throws {
        let backend = AVFoundationPlaybackBackend()
        addTeardownBlock {
            await backend.shutdown()
        }
        let events = PlaybackEventReader(backend.events)

        try await backend.load(playableFile: makeFixturePlayableFile())
        try await events.waitFor(.stateChanged(.ready))

        try await backend.seek(toMS: 1_000)

        let position = try await events.waitForPosition(atLeast: 900)
        XCTAssertGreaterThanOrEqual(position, 900)
    }

    func testTrackCommandsAreNoopsAndStopEmitsIdle() async throws {
        let backend = AVFoundationPlaybackBackend()
        addTeardownBlock {
            await backend.shutdown()
        }
        let events = PlaybackEventReader(backend.events)

        try await backend.load(playableFile: makeFixturePlayableFile())
        try await events.waitFor(.stateChanged(.ready))

        try await backend.selectAudioTrack(trackID: "audio-1")
        try await backend.selectSubtitleTrack(trackID: "subtitle-1")
        try await backend.disableSubtitle()
        try await backend.stop()

        try await events.waitFor(.stateChanged(.idle))
    }

    func testShutdownFinishesEventStream() async throws {
        let backend = AVFoundationPlaybackBackend()
        let events = PlaybackEventReader(backend.events)

        try await backend.load(playableFile: makeFixturePlayableFile())
        try await events.waitFor(.stateChanged(.ready))

        await backend.shutdown()

        let nextEvent = try await events.next(timeoutNanoseconds: 1_000_000_000)
        XCTAssertNil(nextEvent)
    }

    private func makeFixturePlayableFile(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> PlayableFile {
        let fixtureURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tests/Fixtures/Videos/7683413-hd_1920_1080_24fps.mp4")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fixtureURL.path),
            "Expected playback fixture at \(fixtureURL.path)",
            file: file,
            line: line
        )

        return PlayableFile(
            mediaItemID: "avfoundation-media-item",
            mediaFileID: "avfoundation-media-file",
            url: fixtureURL,
            displayName: "AVFoundation Fixture",
            resumePositionMS: nil
        )
    }
}

private final class PlaybackEventReader: @unchecked Sendable {
    private var iterator: AsyncStream<PlaybackEvent>.Iterator

    init(_ stream: AsyncStream<PlaybackEvent>) {
        self.iterator = stream.makeAsyncIterator()
    }

    func waitFor(
        _ expected: PlaybackEvent,
        timeoutNanoseconds: UInt64 = 5_000_000_000,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        _ = try await waitForMatching(timeoutNanoseconds: timeoutNanoseconds, file: file, line: line) { event in
            event == expected
        }
    }

    func waitForDuration(
        timeoutNanoseconds: UInt64 = 5_000_000_000,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> Int {
        let event = try await waitForMatching(timeoutNanoseconds: timeoutNanoseconds, file: file, line: line) { event in
            if case .durationUpdated(let durationMS) = event {
                return durationMS > 0
            }
            return false
        }

        guard case .durationUpdated(let durationMS) = event else {
            throw PlaybackAVFoundationTestError.unexpectedEvent
        }
        return durationMS
    }

    func waitForPosition(
        atLeast minimumPositionMS: Int,
        timeoutNanoseconds: UInt64 = 5_000_000_000,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> Int {
        let event = try await waitForMatching(timeoutNanoseconds: timeoutNanoseconds, file: file, line: line) { event in
            if case .positionUpdated(let positionMS) = event {
                return positionMS >= minimumPositionMS
            }
            return false
        }

        guard case .positionUpdated(let positionMS) = event else {
            throw PlaybackAVFoundationTestError.unexpectedEvent
        }
        return positionMS
    }

    func waitForMatching(
        timeoutNanoseconds: UInt64 = 5_000_000_000,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ predicate: @escaping @Sendable (PlaybackEvent) -> Bool
    ) async throws -> PlaybackEvent {
        let deadline = Date().addingTimeInterval(Double(timeoutNanoseconds) / 1_000_000_000)

        while Date() < deadline {
            guard let event = try await next(timeoutNanoseconds: 500_000_000) else {
                XCTFail("Playback event stream finished before expected event arrived", file: file, line: line)
                throw PlaybackAVFoundationTestError.streamFinished
            }

            if predicate(event) {
                return event
            }
        }

        XCTFail("Timed out waiting for playback event", file: file, line: line)
        throw PlaybackAVFoundationTestError.timeout
    }

    func next(timeoutNanoseconds: UInt64) async throws -> PlaybackEvent? {
        try await withThrowingTaskGroup(of: PlaybackEvent?.self) { group in
            group.addTask {
                await self.iterator.next()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw PlaybackAVFoundationTestError.timeout
            }

            let result = try await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }
}

private enum PlaybackAVFoundationTestError: Error {
    case streamFinished
    case timeout
    case unexpectedEvent
}
