import Domain
import Foundation
import Playback

public actor PlaybackProgressCoordinator {
    public static let defaultSaveInterval: TimeInterval = 5
    public static let defaultMaterialPositionChangeMS = 1_000

    private let progressUseCase: PlaybackProgressUseCase
    private let now: @Sendable () -> Date
    private let saveInterval: TimeInterval
    private let materialPositionChangeMS: Int

    private var session: ProgressSession?

    public init(
        progressUseCase: PlaybackProgressUseCase,
        now: @escaping @Sendable () -> Date = { Date() },
        saveInterval: TimeInterval = PlaybackProgressCoordinator.defaultSaveInterval,
        materialPositionChangeMS: Int = PlaybackProgressCoordinator.defaultMaterialPositionChangeMS
    ) {
        precondition(saveInterval >= 0, "saveInterval must be non-negative")
        precondition(materialPositionChangeMS >= 0, "materialPositionChangeMS must be non-negative")

        self.progressUseCase = progressUseCase
        self.now = now
        self.saveInterval = saveInterval
        self.materialPositionChangeMS = materialPositionChangeMS
    }

    public func startSession(
        mediaItemID: MediaItemID,
        mediaFileID: MediaFileID,
        initialPositionMS: Int
    ) {
        let clampedPositionMS = max(0, initialPositionMS)
        session = ProgressSession(
            mediaItemID: mediaItemID,
            mediaFileID: mediaFileID,
            latestPositionMS: clampedPositionMS,
            lastSavedPositionMS: clampedPositionMS
        )
    }

    public func handle(_ event: PlaybackEvent) throws {
        guard session != nil else {
            return
        }

        switch event {
        case .stateChanged(let state):
            try handleStateChanged(state)
        case .positionUpdated(let positionMS):
            try handlePositionUpdated(positionMS)
        case .durationUpdated(let durationMS):
            session?.latestDurationMS = max(0, durationMS)
        case .playbackEnded(let finalPositionMS, let durationMS):
            try handlePlaybackEnded(finalPositionMS: finalPositionMS, durationMS: durationMS)
        case .playbackFailed:
            session?.latestState = .failed
        case .tracksDiscovered:
            break
        }
    }

    public func noteSeekRequested() {
        session?.pendingSeekSave = true
    }

    public func closeSession() throws {
        guard var currentSession = session, !currentSession.didCloseSession else {
            return
        }

        if currentSession.didReceiveCompletedEvent {
            session = currentSession
            try saveIfNeeded(
                reliableEndEventReceived: true,
                allowCompletedWithoutMaterialChange: true,
                requiresPlaybackStarted: false
            )
        } else if currentSession.hasReachedPlaying {
            session = currentSession
            try saveIfNeeded(
                reliableEndEventReceived: false,
                allowCompletedWithoutMaterialChange: currentSession.latestState != .failed,
                requiresPlaybackStarted: true
            )
        } else {
            currentSession.didCloseSession = true
            session = currentSession
            return
        }

        session?.didCloseSession = true
    }

    private func handleStateChanged(_ state: PlaybackState) throws {
        guard var currentSession = session, !currentSession.didCloseSession else {
            return
        }

        let previousState = currentSession.latestState
        currentSession.latestState = state
        session = currentSession

        switch state {
        case .playing:
            let playedAt = now()
            session?.hasReachedPlaying = true
            if previousState != .playing {
                session?.lastPeriodicSaveAt = playedAt
            }
            try ensurePlayCountIncremented(playedAt: playedAt)
        case .paused:
            try saveIfNeeded(
                reliableEndEventReceived: false,
                allowCompletedWithoutMaterialChange: true,
                requiresPlaybackStarted: true
            )
        case .idle:
            try saveIfNeeded(
                reliableEndEventReceived: false,
                allowCompletedWithoutMaterialChange: true,
                requiresPlaybackStarted: true
            )
            session?.didCloseSession = true
        case .failed:
            session?.latestState = .failed
        case .loading, .ready, .buffering, .ended:
            break
        }
    }

    private func handlePositionUpdated(_ positionMS: Int) throws {
        guard var currentSession = session, !currentSession.didCloseSession else {
            return
        }

        currentSession.latestPositionMS = max(0, positionMS)
        let shouldSaveAfterSeek = currentSession.pendingSeekSave
        currentSession.pendingSeekSave = false
        session = currentSession

        if shouldSaveAfterSeek {
            try saveIfNeeded(
                reliableEndEventReceived: false,
                allowCompletedWithoutMaterialChange: true,
                requiresPlaybackStarted: true
            )
            return
        }

        guard currentSession.latestState == .playing else {
            return
        }

        let playedAt = now()
        guard let lastPeriodicSaveAt = currentSession.lastPeriodicSaveAt else {
            session?.lastPeriodicSaveAt = playedAt
            return
        }

        guard playedAt.timeIntervalSince(lastPeriodicSaveAt) >= saveInterval else {
            return
        }

        try saveIfNeeded(
            playedAt: playedAt,
            reliableEndEventReceived: false,
            allowCompletedWithoutMaterialChange: true,
            requiresPlaybackStarted: true
        )
    }

    private func handlePlaybackEnded(finalPositionMS: Int, durationMS: Int?) throws {
        guard var currentSession = session, !currentSession.didCloseSession else {
            return
        }

        currentSession.latestPositionMS = max(0, finalPositionMS)
        currentSession.latestDurationMS = durationMS.map { max(0, $0) }
        currentSession.latestState = .ended
        currentSession.didReceiveCompletedEvent = true
        session = currentSession

        try saveIfNeeded(
            reliableEndEventReceived: true,
            allowCompletedWithoutMaterialChange: true,
            requiresPlaybackStarted: false
        )
    }

    private func saveIfNeeded(
        playedAt providedPlayedAt: Date? = nil,
        reliableEndEventReceived: Bool,
        allowCompletedWithoutMaterialChange: Bool,
        requiresPlaybackStarted: Bool
    ) throws {
        guard var currentSession = session else {
            return
        }

        if requiresPlaybackStarted, !currentSession.hasReachedPlaying {
            return
        }

        let completed = PlaybackCompletionPolicy.isCompleted(
            reliableEndEventReceived: reliableEndEventReceived,
            positionMS: currentSession.latestPositionMS,
            durationMS: currentSession.latestDurationMS
        )
        let materiallyChanged = abs(
            currentSession.latestPositionMS - currentSession.lastSavedPositionMS
        ) >= materialPositionChangeMS
        let completedChanged = completed && !currentSession.lastSavedCompleted

        guard materiallyChanged || (allowCompletedWithoutMaterialChange && completedChanged) else {
            return
        }

        let playedAt = providedPlayedAt ?? now()
        session = currentSession
        if currentSession.hasReachedPlaying {
            try ensurePlayCountIncremented(playedAt: playedAt)
            guard let refreshedSession = session else {
                return
            }
            currentSession = refreshedSession
        }

        try progressUseCase.saveProgress(
            mediaItemID: currentSession.mediaItemID,
            mediaFileID: currentSession.mediaFileID,
            positionMS: currentSession.latestPositionMS,
            durationMS: currentSession.latestDurationMS,
            completed: completed,
            playedAt: playedAt
        )

        currentSession.lastSavedPositionMS = currentSession.latestPositionMS
        currentSession.lastSavedCompleted = completed
        currentSession.lastPeriodicSaveAt = playedAt
        session = currentSession
    }

    private func ensurePlayCountIncremented(playedAt: Date) throws {
        guard var currentSession = session,
              !currentSession.didIncrementPlayCount else {
            return
        }

        try progressUseCase.incrementPlayCount(
            mediaItemID: currentSession.mediaItemID,
            mediaFileID: currentSession.mediaFileID,
            playedAt: playedAt
        )

        currentSession.didIncrementPlayCount = true
        session = currentSession
    }
}

private struct ProgressSession {
    let mediaItemID: MediaItemID
    let mediaFileID: MediaFileID
    var latestPositionMS: Int
    var latestDurationMS: Int?
    var latestState: PlaybackState?
    var hasReachedPlaying = false
    var didIncrementPlayCount = false
    var didReceiveCompletedEvent = false
    var pendingSeekSave = false
    var didCloseSession = false
    var lastSavedPositionMS: Int
    var lastSavedCompleted = false
    var lastPeriodicSaveAt: Date?
}
