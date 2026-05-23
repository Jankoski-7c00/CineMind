@preconcurrency import AppKit
import Foundation
import Playback

public enum LibMPVPlaybackModule {
    public static let name = "LibMPVPlayback"
    public static let playbackModule = PlaybackModule.self
}

public enum LibMPVPlaybackBackendMode: Sendable {
    case standalone
    case embedded
}

public final class LibMPVPlaybackBackend: PlaybackBackend, @unchecked Sendable {
    private let eventHub = PlaybackEventHub()
    private let runtime: MPVRuntime
    private let lock = NSLock()
    private var renderAdapter: MPVOpenGLRenderAdapter?
    private let eventLoopTask: Task<Void, Never>
    private var isShuttingDown = false

    public var events: AsyncStream<PlaybackEvent> {
        eventHub.makeStream()
    }

    public convenience init() throws {
        try self.init(mode: .standalone)
    }

    public convenience init(mode: LibMPVPlaybackBackendMode) throws {
        let runtimeMode: MPVRuntimeMode
        switch mode {
        case .standalone:
            runtimeMode = .standalone
        case .embedded:
            runtimeMode = .embedded
        }

        let runtime = try MPVRuntime(mode: runtimeMode)
        self.init(runtime: runtime, renderAdapter: nil)
    }

    @available(*, deprecated, message: "Use init(mode: .embedded), attachRenderSurface(_:), and prepareRenderSurface().")
    @MainActor
    public convenience init(spikeOpenGLView: NSOpenGLView) throws {
        try self.init(mode: .embedded)
        try attachRenderSurface(spikeOpenGLView)
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
    public func attachRenderSurface(_ openGLView: NSOpenGLView) throws {
        guard !readShuttingDown() else {
            throw PlaybackError.invalidState("playback backend has shut down")
        }

        guard renderAdapter == nil else {
            throw PlaybackError.invalidState("render surface is already attached")
        }

        renderAdapter = MPVOpenGLRenderAdapter(openGLView: openGLView, runtime: runtime)
    }

    @MainActor
    public func prepareRenderSurface() async throws {
        guard !readShuttingDown() else {
            throw PlaybackError.invalidState("playback backend has shut down")
        }

        guard let renderAdapter else {
            throw PlaybackError.invalidState("render surface is not attached")
        }

        try await renderAdapter.prepare()
    }

    @MainActor
    public func detachRenderSurface() {
        guard !readShuttingDown() else {
            return
        }

        let renderAdapter = self.renderAdapter
        self.renderAdapter = nil
        renderAdapter?.detach()
    }

    @MainActor
    public func renderSurfaceNow() {
        guard !readShuttingDown() else {
            return
        }

        renderAdapter?.renderNow()
    }

    @available(*, deprecated, message: "Use prepareRenderSurface().")
    @MainActor
    public func prepareSpikeRenderSurface() async throws {
        try await prepareRenderSurface()
    }

    @available(*, deprecated, message: "Use renderSurfaceNow().")
    @MainActor
    public func renderSpikeSurfaceNow() {
        renderSurfaceNow()
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
        guard markShuttingDownIfNeeded() else {
            return
        }

        let renderAdapter = await MainActor.run {
            let adapter = self.renderAdapter
            self.renderAdapter = nil
            return adapter
        }

        await renderAdapter?.shutdown()
        await runtime.stopEventLoop()
        eventLoopTask.cancel()
        await eventLoopTask.value
        await runtime.destroy()
        eventHub.finish()
    }

    private func markShuttingDownIfNeeded() -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }

        guard !isShuttingDown else {
            return false
        }

        isShuttingDown = true
        return true
    }

    private func readShuttingDown() -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        return isShuttingDown
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
