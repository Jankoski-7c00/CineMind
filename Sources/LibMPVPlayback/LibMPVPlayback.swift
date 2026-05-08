@preconcurrency import AppKit
import Foundation
import Playback

public enum LibMPVPlaybackModule {
    public static let name = "LibMPVPlayback"
    public static let playbackModule = PlaybackModule.self
}

public final class LibMPVPlaybackBackend: PlaybackBackend, @unchecked Sendable {
    private let eventHub = PlaybackEventHub()
    private let runtime: MPVRuntime
    private let renderAdapter: MPVOpenGLRenderAdapter?
    private let eventLoopTask: Task<Void, Never>

    public var events: AsyncStream<PlaybackEvent> {
        eventHub.makeStream()
    }

    public convenience init() throws {
        let runtime = try MPVRuntime()
        self.init(runtime: runtime, renderAdapter: nil)
    }

    @MainActor
    public convenience init(spikeOpenGLView: NSOpenGLView) throws {
        let runtime = try MPVRuntime(mode: .embedded)
        let renderAdapter = MPVOpenGLRenderAdapter(openGLView: spikeOpenGLView, runtime: runtime)
        self.init(runtime: runtime, renderAdapter: renderAdapter)
    }

    private init(runtime: MPVRuntime, renderAdapter: MPVOpenGLRenderAdapter?) {
        self.runtime = runtime
        self.renderAdapter = renderAdapter

        let eventHub = self.eventHub
        self.eventLoopTask = Task {
            while !Task.isCancelled {
                let events = await runtime.waitForEvents(timeout: 0.05)
                for event in events {
                    eventHub.emit(event)
                }

                if await !runtime.shouldContinueEventLoop {
                    return
                }
            }
        }
    }

    @MainActor
    public func prepareSpikeRenderSurface() async throws {
        guard let renderAdapter else {
            throw PlaybackError.invalidState("spike render surface is not configured")
        }

        try await renderAdapter.prepare()
    }

    @MainActor
    public func renderSpikeSurfaceNow() {
        renderAdapter?.renderNow()
    }

    public func load(playableFile: PlayableFile) async throws {
        try await runtime.load(playableFile: playableFile)
    }

    public func play() async throws {
        try await runtime.play()
    }

    public func pause() async throws {
        try await runtime.pause()
    }

    public func seek(toMS positionMS: Int) async throws {
        try await runtime.seek(toMS: positionMS)
    }

    public func stop() async throws {
        try await runtime.stop()
    }

    public func selectAudioTrack(trackID: String) async throws {
        try await runtime.selectAudioTrack(trackID: trackID)
    }

    public func selectSubtitleTrack(trackID: String) async throws {
        try await runtime.selectSubtitleTrack(trackID: trackID)
    }

    public func disableSubtitle() async throws {
        try await runtime.disableSubtitle()
    }

    public func shutdown() async {
        await renderAdapter?.shutdown()
        await runtime.stopEventLoop()
        eventLoopTask.cancel()
        await eventLoopTask.value
        await runtime.destroy()
        eventHub.finish()
    }
}

private final class PlaybackEventHub: @unchecked Sendable {
    private let lock = NSLock()
    private var nextStreamID = 0
    private var continuations: [Int: AsyncStream<PlaybackEvent>.Continuation] = [:]
    private var isFinished = false

    func makeStream() -> AsyncStream<PlaybackEvent> {
        let streamID: Int? = withLock {
            if isFinished {
                return nil
            }

            nextStreamID += 1
            return nextStreamID
        }

        return AsyncStream(bufferingPolicy: .unbounded) { continuation in
            guard let streamID else {
                continuation.finish()
                return
            }

            var shouldFinishImmediately = false
            self.withLock {
                if self.isFinished {
                    shouldFinishImmediately = true
                } else {
                    self.continuations[streamID] = continuation
                }
            }

            if shouldFinishImmediately {
                continuation.finish()
            }

            continuation.onTermination = { @Sendable [weak self] _ in
                self?.removeContinuation(streamID)
            }
        }
    }

    func emit(_ event: PlaybackEvent) {
        withLock {
            guard !isFinished else {
                return
            }

            for continuation in continuations.values {
                continuation.yield(event)
            }
        }
    }

    func finish() {
        let activeContinuations: [AsyncStream<PlaybackEvent>.Continuation] = withLock {
            guard !isFinished else {
                return []
            }

            isFinished = true
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
