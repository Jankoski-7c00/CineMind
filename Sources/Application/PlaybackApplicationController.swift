import Domain
import Foundation
import Playback

public enum PlaybackApplicationState: Sendable, Equatable {
    case idle
    case loading
    case ready
    case playing
    case paused
    case buffering
    case ended
    case failed(String)
}

public struct PlaybackApplicationStatus: Sendable, Equatable {
    public let state: PlaybackApplicationState
    public let mediaFileID: MediaFileID?
    public let displayName: String?
    public let positionMS: Int
    public let durationMS: Int?

    public init(
        state: PlaybackApplicationState,
        mediaFileID: MediaFileID?,
        displayName: String?,
        positionMS: Int,
        durationMS: Int?
    ) {
        self.state = state
        self.mediaFileID = mediaFileID
        self.displayName = displayName
        self.positionMS = positionMS
        self.durationMS = durationMS
    }

    public static let idle = PlaybackApplicationStatus(
        state: .idle,
        mediaFileID: nil,
        displayName: nil,
        positionMS: 0,
        durationMS: nil
    )
}

public protocol PlaybackApplicationControlling: Sendable {
    var statusStream: AsyncStream<PlaybackApplicationStatus> { get }
    func open(mediaFileID: MediaFileID) async
    func stop() async
}

public actor PlaybackApplicationController: PlaybackApplicationControlling {
    public nonisolated let statusStream: AsyncStream<PlaybackApplicationStatus>

    private let coordinator: PlaybackCoordinator
    private let progressCoordinator: PlaybackProgressCoordinator
    private let mediaOpening: any MediaOpening
    private let statusContinuation: AsyncStream<PlaybackApplicationStatus>.Continuation

    private var eventTask: Task<Void, Never>?
    private var activeMediaFileID: MediaFileID?
    private var activeDisplayName: String?
    private var currentState: PlaybackApplicationState = .idle
    private var currentPositionMS = 0
    private var currentDurationMS: Int?
    private var progressSessionOpen = false
    private var didAutoPlayActiveSession = false
    private var lastEmittedStatus: PlaybackApplicationStatus?

    public init(
        coordinator: PlaybackCoordinator,
        progressCoordinator: PlaybackProgressCoordinator,
        mediaOpening: any MediaOpening
    ) {
        self.coordinator = coordinator
        self.progressCoordinator = progressCoordinator
        self.mediaOpening = mediaOpening

        var continuation: AsyncStream<PlaybackApplicationStatus>.Continuation?
        self.statusStream = AsyncStream(bufferingPolicy: .unbounded) { streamContinuation in
            continuation = streamContinuation
        }
        self.statusContinuation = continuation!
        self.eventTask = nil
    }

    public func open(mediaFileID: MediaFileID) async {
        startEventLoopIfNeeded()

        if activeMediaFileID != nil || progressSessionOpen {
            await stop()
        }

        let playableFile: PlayableFile
        do {
            playableFile = try mediaOpening.open(mediaFileID: mediaFileID)
        } catch {
            resetActiveSession()
            emitStatus(
                PlaybackApplicationStatus(
                    state: .failed(userSafeMessage(forOpeningError: error)),
                    mediaFileID: mediaFileID,
                    displayName: nil,
                    positionMS: 0,
                    durationMS: nil
                )
            )
            return
        }

        activeMediaFileID = playableFile.mediaFileID
        activeDisplayName = playableFile.displayName
        currentState = .loading
        currentPositionMS = max(0, playableFile.resumePositionMS ?? 0)
        currentDurationMS = nil
        didAutoPlayActiveSession = false
        progressSessionOpen = true

        await progressCoordinator.startSession(
            mediaItemID: playableFile.mediaItemID,
            mediaFileID: playableFile.mediaFileID,
            initialPositionMS: currentPositionMS
        )
        emitCurrentStatus()

        await coordinator.open(playbackPlayableFile(from: playableFile))
    }

    public func stop() async {
        startEventLoopIfNeeded()

        await coordinator.stop()
        await closeProgressSessionIfOpen()
        resetActiveSession()
        emitStatus(.idle)
    }

    private func startEventLoopIfNeeded() {
        guard eventTask == nil else {
            return
        }

        eventTask = Task {
            await self.consumeCoordinatorEvents()
        }
    }

    private func consumeCoordinatorEvents() async {
        for await event in coordinator.events {
            await handleCoordinatorEvent(event)
        }
    }

    private func handleCoordinatorEvent(_ event: PlaybackEvent) async {
        if case .tracksDiscovered = event {
            return
        }

        await handleProgressEvent(event)

        switch event {
        case .stateChanged(let playbackState):
            await handlePlaybackState(playbackState)
        case .positionUpdated(let positionMS):
            currentPositionMS = max(0, positionMS)
            emitCurrentStatus()
        case .durationUpdated(let durationMS):
            currentDurationMS = max(0, durationMS)
            emitCurrentStatus()
        case .playbackEnded(let finalPositionMS, let durationMS):
            currentPositionMS = max(0, finalPositionMS)
            currentDurationMS = durationMS.map { max(0, $0) }
            currentState = .ended
            emitCurrentStatus()
            await closeProgressSessionIfOpen()
        case .playbackFailed(let error):
            currentState = .failed(userSafeMessage(forPlaybackError: error))
            emitCurrentStatus()
        case .tracksDiscovered:
            break
        }
    }

    private func handlePlaybackState(_ playbackState: PlaybackState) async {
        switch playbackState {
        case .idle:
            await closeProgressSessionIfOpen()
            resetActiveSession()
            emitStatus(.idle)
        case .loading:
            currentState = .loading
            emitCurrentStatus()
        case .ready:
            currentState = .ready
            emitCurrentStatus()
            if activeMediaFileID != nil, !didAutoPlayActiveSession {
                didAutoPlayActiveSession = true
                await coordinator.play()
            }
        case .playing:
            currentState = .playing
            emitCurrentStatus()
        case .paused:
            currentState = .paused
            emitCurrentStatus()
        case .buffering:
            currentState = .buffering
            emitCurrentStatus()
        case .ended:
            currentState = .ended
            emitCurrentStatus()
            await closeProgressSessionIfOpen()
        case .failed:
            if case .failed = currentState {
                return
            }
            currentState = .failed("Playback failed.")
            emitCurrentStatus()
        }
    }

    private func handleProgressEvent(_ event: PlaybackEvent) async {
        do {
            try await progressCoordinator.handle(event)
        } catch {
            currentState = .failed("Could not save playback progress.")
            emitCurrentStatus()
        }
    }

    private func closeProgressSessionIfOpen() async {
        guard progressSessionOpen else {
            return
        }

        progressSessionOpen = false
        do {
            try await progressCoordinator.closeSession()
        } catch {
            currentState = .failed("Could not save playback progress.")
            emitCurrentStatus()
        }
    }

    private func resetActiveSession() {
        activeMediaFileID = nil
        activeDisplayName = nil
        currentState = .idle
        currentPositionMS = 0
        currentDurationMS = nil
        progressSessionOpen = false
        didAutoPlayActiveSession = false
    }

    private func emitCurrentStatus() {
        emitStatus(
            PlaybackApplicationStatus(
                state: currentState,
                mediaFileID: activeMediaFileID,
                displayName: activeDisplayName,
                positionMS: currentPositionMS,
                durationMS: currentDurationMS
            )
        )
    }

    private func emitStatus(_ status: PlaybackApplicationStatus) {
        guard status != lastEmittedStatus else {
            return
        }

        lastEmittedStatus = status
        statusContinuation.yield(status)
    }

    private func playbackPlayableFile(from file: PlayableFile) -> Playback.PlayableFile {
        Playback.PlayableFile(
            mediaItemID: file.mediaItemID,
            mediaFileID: file.mediaFileID,
            url: file.url,
            displayName: file.displayName,
            resumePositionMS: file.resumePositionMS
        )
    }

    private func userSafeMessage(forOpeningError error: any Error) -> String {
        guard let playbackError = error as? ApplicationPlaybackError else {
            return "Could not open media file."
        }

        switch playbackError {
        case .mediaFileNotFound:
            return "Media file was not found."
        case .mediaFileUnavailable:
            return "Media file is unavailable."
        case .libraryFolderNotFound:
            return "Library folder was not found."
        case .libraryFolderUnavailable:
            return "Library folder is unavailable."
        case .resolvedFileMissing:
            return "Media file is missing on disk."
        case .invalidResolvedURL:
            return "Media file path is invalid."
        case .persistenceFailure:
            return "Could not open media file."
        }
    }

    private func userSafeMessage(forPlaybackError error: PlaybackError) -> String {
        switch error {
        case .fileMissing:
            return "Playback file is missing."
        case .permissionDenied:
            return "Playback permission was denied."
        case .unsupportedFormat:
            return "Unsupported media format."
        case .mpvUnavailable:
            return "Playback engine is unavailable."
        case .mpvError, .invalidState, .unknown:
            return "Playback failed."
        }
    }
}
