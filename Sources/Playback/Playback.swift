import Domain
import Foundation
import Shared

public enum PlaybackModule {
    public static let name = "Playback"
}

// Intentionally mirrors Application.PlayableFile to preserve the module boundary.
// TODO: Map Application.PlayableFile into Playback.PlayableFile when wiring playback use cases.
public struct PlayableFile: Sendable, Equatable {
    public let mediaItemID: MediaItemID
    public let mediaFileID: MediaFileID
    public let url: URL
    public let displayName: String
    public let resumePositionMS: Int?

    public init(
        mediaItemID: MediaItemID,
        mediaFileID: MediaFileID,
        url: URL,
        displayName: String,
        resumePositionMS: Int?
    ) {
        self.mediaItemID = mediaItemID
        self.mediaFileID = mediaFileID
        self.url = url
        self.displayName = displayName
        self.resumePositionMS = resumePositionMS
    }
}

public enum PlaybackState: Sendable, Equatable, Hashable {
    case idle
    case loading
    case ready
    case playing
    case paused
    case buffering
    case ended
    case failed
}

public enum PlaybackCommand: Sendable, Equatable {
    case open(PlayableFile)
    case play
    case pause
    case seek(toMS: Int)
    case stop
    case selectAudioTrack(trackID: String)
    case selectSubtitleTrack(trackID: String)
    case disableSubtitle
}

public enum PlaybackEvent: Sendable, Equatable {
    case stateChanged(PlaybackState)
    case positionUpdated(positionMS: Int)
    case durationUpdated(durationMS: Int)
    case playbackEnded(finalPositionMS: Int, durationMS: Int?)
    case playbackFailed(PlaybackError)
    case tracksDiscovered(audioTracks: [PlaybackTrack], subtitleTracks: [PlaybackTrack])
}

public enum PlaybackError: Error, Sendable, Equatable {
    case fileMissing
    case permissionDenied
    case unsupportedFormat
    case mpvUnavailable
    case mpvError(String)
    case invalidState(String)
    case unknown(String)
}

public enum PlaybackTrackType: Sendable, Equatable, Hashable {
    case audio
    case subtitle
}

public struct PlaybackTrack: Sendable, Equatable {
    public let id: String
    public let type: PlaybackTrackType
    public let language: String?
    public let title: String?
    public let isDefault: Bool
    public let isSelected: Bool

    public init(
        id: String,
        type: PlaybackTrackType,
        language: String?,
        title: String?,
        isDefault: Bool,
        isSelected: Bool
    ) {
        self.id = id
        self.type = type
        self.language = language
        self.title = title
        self.isDefault = isDefault
        self.isSelected = isSelected
    }
}

public struct PlaybackSession: Sendable, Equatable {
    public var playableFile: PlayableFile
    public var state: PlaybackState
    public var positionMS: Int
    public var durationMS: Int?
    public var audioTracks: [PlaybackTrack]
    public var subtitleTracks: [PlaybackTrack]

    public init(
        playableFile: PlayableFile,
        state: PlaybackState,
        positionMS: Int = 0,
        durationMS: Int? = nil,
        audioTracks: [PlaybackTrack] = [],
        subtitleTracks: [PlaybackTrack] = []
    ) {
        self.playableFile = playableFile
        self.state = state
        self.positionMS = positionMS
        self.durationMS = durationMS
        self.audioTracks = audioTracks
        self.subtitleTracks = subtitleTracks
    }
}

public protocol PlaybackBackend: Sendable {
    var events: AsyncStream<PlaybackEvent> { get }

    func load(playableFile: PlayableFile) async throws
    func play() async throws
    func pause() async throws
    func seek(toMS: Int) async throws
    func stop() async throws
    func selectAudioTrack(trackID: String) async throws
    func selectSubtitleTrack(trackID: String) async throws
    func disableSubtitle() async throws
    func shutdown() async
}

public actor PlaybackCoordinator {
    // Phase 2 exposes a single-consumer event stream. Multi-subscriber fanout is deferred.
    public nonisolated let events: AsyncStream<PlaybackEvent>

    public private(set) var state: PlaybackState = .idle
    public private(set) var activeSession: PlaybackSession?

    private let backend: any PlaybackBackend
    private let eventContinuation: AsyncStream<PlaybackEvent>.Continuation
    private var backendEventTask: Task<Void, Never>?
    private var currentSessionGeneration: UInt64 = 0
    private var isShutdown = false

    public init(backend: any PlaybackBackend) {
        self.backend = backend

        var continuation: AsyncStream<PlaybackEvent>.Continuation?
        self.events = AsyncStream(bufferingPolicy: .unbounded) { streamContinuation in
            continuation = streamContinuation
        }
        self.eventContinuation = continuation!
    }

    public func send(_ command: PlaybackCommand) async {
        switch command {
        case .open(let playableFile):
            await open(playableFile)
        case .play:
            await play()
        case .pause:
            await pause()
        case .seek(let positionMS):
            await seek(toMS: positionMS)
        case .stop:
            await stop()
        case .selectAudioTrack(let trackID):
            await selectAudioTrack(trackID: trackID)
        case .selectSubtitleTrack(let trackID):
            await selectSubtitleTrack(trackID: trackID)
        case .disableSubtitle:
            await disableSubtitle()
        }
    }

    public func open(_ playableFile: PlayableFile) async {
        guard !isShutdown else {
            return
        }

        if activeSession != nil {
            await stopActiveSession(emitIdle: true)
        }

        guard !isShutdown else {
            return
        }

        currentSessionGeneration &+= 1
        let generation = currentSessionGeneration

        activeSession = PlaybackSession(
            playableFile: playableFile,
            state: .loading,
            positionMS: playableFile.resumePositionMS ?? 0
        )
        state = .loading
        startBackendEventTask(for: generation)
        emit(.stateChanged(.loading))

        do {
            try await backend.load(playableFile: playableFile)
        } catch {
            transitionToFailed(
                Self.playbackError(from: error),
                generation: generation,
                cancelBackendEvents: true
            )
        }
    }

    public func play() async {
        guard let generation = activeGeneration(
            commandName: "play",
            allowedStates: [.ready, .paused, .buffering]
        ) else {
            return
        }

        do {
            try await backend.play()
        } catch {
            transitionToFailed(Self.playbackError(from: error), generation: generation)
        }
    }

    public func pause() async {
        guard let generation = activeGeneration(
            commandName: "pause",
            allowedStates: [.playing, .buffering]
        ) else {
            return
        }

        do {
            try await backend.pause()
        } catch {
            transitionToFailed(Self.playbackError(from: error), generation: generation)
        }
    }

    public func seek(toMS positionMS: Int) async {
        guard positionMS >= 0 else {
            emitInvalidState("seek requires a non-negative position")
            return
        }

        guard let generation = activeGeneration(
            commandName: "seek",
            allowedStates: [.ready, .playing, .paused, .buffering]
        ) else {
            return
        }

        do {
            try await backend.seek(toMS: positionMS)
        } catch {
            transitionToFailed(Self.playbackError(from: error), generation: generation)
        }
    }

    public func stop() async {
        guard !isShutdown else {
            return
        }

        await stopActiveSession(emitIdle: true)
    }

    public func selectAudioTrack(trackID: String) async {
        guard let generation = activeGeneration(
            commandName: "selectAudioTrack",
            allowedStates: [.ready, .playing, .paused, .buffering]
        ) else {
            return
        }

        do {
            try await backend.selectAudioTrack(trackID: trackID)
        } catch {
            transitionToFailed(Self.playbackError(from: error), generation: generation)
        }
    }

    public func selectSubtitleTrack(trackID: String) async {
        guard let generation = activeGeneration(
            commandName: "selectSubtitleTrack",
            allowedStates: [.ready, .playing, .paused, .buffering]
        ) else {
            return
        }

        do {
            try await backend.selectSubtitleTrack(trackID: trackID)
        } catch {
            transitionToFailed(Self.playbackError(from: error), generation: generation)
        }
    }

    public func disableSubtitle() async {
        guard let generation = activeGeneration(
            commandName: "disableSubtitle",
            allowedStates: [.ready, .playing, .paused, .buffering]
        ) else {
            return
        }

        do {
            try await backend.disableSubtitle()
        } catch {
            transitionToFailed(Self.playbackError(from: error), generation: generation)
        }
    }

    public func shutdown() async {
        guard !isShutdown else {
            return
        }

        isShutdown = true
        currentSessionGeneration &+= 1
        backendEventTask?.cancel()
        backendEventTask = nil
        activeSession = nil
        state = .idle
        await backend.shutdown()
        eventContinuation.finish()
    }

    private func activeGeneration(
        commandName: String,
        allowedStates: Set<PlaybackState>
    ) -> UInt64? {
        guard !isShutdown else {
            return nil
        }

        guard activeSession != nil else {
            emitInvalidState("\(commandName) requires an active session")
            return nil
        }

        guard allowedStates.contains(state) else {
            emitInvalidState("\(commandName) is invalid while playback is \(state)")
            return nil
        }

        return currentSessionGeneration
    }

    private func stopActiveSession(emitIdle: Bool) async {
        guard activeSession != nil else {
            return
        }

        currentSessionGeneration &+= 1
        let stopGeneration = currentSessionGeneration
        backendEventTask?.cancel()
        backendEventTask = nil

        do {
            try await backend.stop()
        } catch {
            emit(.playbackFailed(Self.playbackError(from: error)))
        }

        guard !isShutdown, currentSessionGeneration == stopGeneration else {
            return
        }

        activeSession = nil
        state = .idle
        if emitIdle {
            emit(.stateChanged(.idle))
        }
    }

    private func startBackendEventTask(for generation: UInt64) {
        backendEventTask?.cancel()

        let stream = backend.events
        backendEventTask = Task {
            for await event in stream {
                guard !Task.isCancelled else {
                    return
                }
                self.handleBackendEvent(event, generation: generation)
            }
        }
    }

    private func handleBackendEvent(_ event: PlaybackEvent, generation: UInt64) {
        guard !isShutdown, generation == currentSessionGeneration else {
            return
        }

        switch event {
        case .stateChanged(let newState):
            state = newState
            activeSession?.state = newState
            emit(event)
        case .positionUpdated(let positionMS):
            activeSession?.positionMS = positionMS
            emit(event)
        case .durationUpdated(let durationMS):
            activeSession?.durationMS = durationMS
            emit(event)
        case .playbackEnded(let finalPositionMS, let durationMS):
            activeSession?.positionMS = finalPositionMS
            activeSession?.durationMS = durationMS
            activeSession?.state = .ended
            state = .ended
            emit(event)
            emit(.stateChanged(.ended))
        case .playbackFailed(let error):
            transitionToFailed(error, generation: generation)
        case .tracksDiscovered(let audioTracks, let subtitleTracks):
            activeSession?.audioTracks = audioTracks
            activeSession?.subtitleTracks = subtitleTracks
            emit(event)
        }
    }

    private func transitionToFailed(
        _ error: PlaybackError,
        generation: UInt64,
        cancelBackendEvents: Bool = false
    ) {
        guard !isShutdown, generation == currentSessionGeneration else {
            return
        }

        if cancelBackendEvents {
            backendEventTask?.cancel()
            backendEventTask = nil
        }

        activeSession?.state = .failed
        state = .failed
        emit(.playbackFailed(error))
        emit(.stateChanged(.failed))
    }

    private func emitInvalidState(_ message: String) {
        guard !isShutdown else {
            return
        }

        emit(.playbackFailed(.invalidState(message)))
    }

    private func emit(_ event: PlaybackEvent) {
        guard !isShutdown else {
            return
        }

        eventContinuation.yield(event)
    }

    private static func playbackError(from error: any Error) -> PlaybackError {
        if let playbackError = error as? PlaybackError {
            return playbackError
        }

        return .unknown(String(describing: error))
    }
}
