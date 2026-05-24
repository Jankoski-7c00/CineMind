@preconcurrency import AVFoundation
import Foundation
import Playback

public enum PlaybackAVFoundationModule {
    public static let name = "PlaybackAVFoundation"
    public static let playbackModule = PlaybackModule.self
}

public final class AVFoundationPlaybackBackend: PlaybackBackend, @unchecked Sendable {
    private let lock = NSLock()
    private let eventHub = PlaybackEventHub()
    private var state = BackendState()

    public init() {}

    public var events: AsyncStream<PlaybackEvent> {
        eventHub.makeStream()
    }

    public var player: AVPlayer? {
        withLock {
            state.player
        }
    }

    public func load(playableFile: PlayableFile) async throws {
        let generation: UInt64
        let cleanup: ObserverCleanup
        do {
            (generation, cleanup) = try beginReplacingPlayback()
        } catch {
            throw error
        }

        cleanupObservers(cleanup)
        emitStateIfChanged(.loading, generation: generation, requiresReady: false)

        guard playableFile.url.isFileURL else {
            let error = PlaybackError.invalidState("AVFoundation playback requires a local file URL")
            emitFailure(error, generation: generation)
            throw error
        }

        guard FileManager.default.fileExists(atPath: playableFile.url.path) else {
            emitFailure(.fileMissing, generation: generation)
            throw PlaybackError.fileMissing
        }

        let item = AVPlayerItem(url: playableFile.url)
        let player = AVPlayer(playerItem: item)

        guard storePlayer(player, item: item, generation: generation) else {
            cleanupObservers(ObserverCleanup(player: player))
            throw PlaybackError.invalidState("playback backend has shut down")
        }

        let observers = installObservers(item: item, player: player, generation: generation)
        guard storeObservers(observers, generation: generation) else {
            cleanupObservers(observers)
            throw PlaybackError.invalidState("playback backend has shut down")
        }

        if let resumePositionMS = playableFile.resumePositionMS, resumePositionMS > 0 {
            storePendingResumePosition(resumePositionMS, generation: generation)
        }
    }

    public func play() async throws {
        let player = try currentPlayer()
        player.play()
    }

    public func pause() async throws {
        let player = try currentPlayer()
        player.pause()
    }

    public func seek(toMS positionMS: Int) async throws {
        guard positionMS >= 0 else {
            throw PlaybackError.invalidState("seek requires a non-negative position")
        }

        let player: AVPlayer
        let generation: UInt64
        (player, generation) = try currentPlayerAndGeneration()

        let target = CMTime(value: CMTimeValue(positionMS), timescale: 1000)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
            guard completed else {
                return
            }
            self?.emitPositionIfChanged(positionMS, generation: generation)
        }
    }

    public func stop() async throws {
        let cleanup = stopPlaybackForUser()
        cleanupObservers(cleanup)
        eventHub.emit(.stateChanged(.idle))
    }

    public func selectAudioTrack(trackID: String) async throws {
        try selectMediaOption(trackID: trackID, type: .audio)
    }

    public func selectSubtitleTrack(trackID: String) async throws {
        try selectMediaOption(trackID: trackID, type: .subtitle)
    }

    public func disableSubtitle() async throws {
        let selection = try currentMediaSelection(type: .subtitle)
        guard let item = selection.item,
              let group = selection.group else {
            return
        }

        item.select(nil, in: group)
        emitTracksDiscovered(item: item, generation: selection.generation)
    }

    public func shutdown() async {
        let cleanup = shutdownPlayback()
        cleanupObservers(cleanup)
        eventHub.finish()
    }

    private func beginReplacingPlayback() throws -> (UInt64, ObserverCleanup) {
        try withLock {
            guard !state.isShutdown else {
                throw PlaybackError.invalidState("playback backend has shut down")
            }

            state.generation &+= 1
            let generation = state.generation
            let cleanup = state.cleanup()
            state.clearPlayback()
            return (generation, cleanup)
        }
    }

    private func storePlayer(_ player: AVPlayer, item: AVPlayerItem, generation: UInt64) -> Bool {
        withLock {
            guard state.isActive(generation) else {
                return false
            }

            state.player = player
            state.item = item
            return true
        }
    }

    private func storeObservers(_ observers: ObserverCleanup, generation: UInt64) -> Bool {
        withLock {
            guard state.isActive(generation) else {
                return false
            }

            state.itemStatusObservation = observers.itemStatusObservation
            state.timeControlStatusObservation = observers.timeControlStatusObservation
            state.durationObservation = observers.durationObservation
            state.periodicTimeObserver = observers.periodicTimeObserver
            state.endNotificationObserver = observers.endNotificationObserver
            state.failureNotificationObserver = observers.failureNotificationObserver
            return true
        }
    }

    private func storePendingResumePosition(_ positionMS: Int, generation: UInt64) {
        withLock {
            guard state.isActive(generation) else {
                return
            }

            state.pendingResumePositionMS = positionMS
        }
    }

    private func currentPlayer() throws -> AVPlayer {
        try withLock {
            guard !state.isShutdown else {
                throw PlaybackError.invalidState("playback backend has shut down")
            }

            guard let player = state.player else {
                throw PlaybackError.invalidState("playback backend has no active player")
            }

            return player
        }
    }

    private func currentPlayerAndGeneration() throws -> (AVPlayer, UInt64) {
        try withLock {
            guard !state.isShutdown else {
                throw PlaybackError.invalidState("playback backend has shut down")
            }

            guard let player = state.player else {
                throw PlaybackError.invalidState("playback backend has no active player")
            }

            return (player, state.generation)
        }
    }

    private func stopPlaybackForUser() -> ObserverCleanup {
        withLock {
            guard !state.isShutdown else {
                return ObserverCleanup()
            }

            state.generation &+= 1
            let cleanup = state.cleanup()
            state.clearPlayback()
            state.lastState = .idle
            return cleanup
        }
    }

    private func shutdownPlayback() -> ObserverCleanup {
        withLock {
            guard !state.isShutdown else {
                return ObserverCleanup()
            }

            state.isShutdown = true
            state.generation &+= 1
            let cleanup = state.cleanup()
            state.clearPlayback()
            return cleanup
        }
    }

    private func installObservers(
        item: AVPlayerItem,
        player: AVPlayer,
        generation: UInt64
    ) -> ObserverCleanup {
        let itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            self?.handleItemStatus(item.status, item: item, generation: generation)
        }

        let timeControlStatusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            self?.handleTimeControlStatus(player.timeControlStatus, player: player, generation: generation)
        }

        let durationObservation = item.observe(\.duration, options: [.initial, .new]) { [weak self] item, _ in
            self?.emitDurationIfChanged(item.duration, generation: generation)
        }

        let periodicTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 600),
            queue: nil
        ) { [weak self] time in
            self?.emitPositionIfChanged(time, generation: generation)
        }

        let endNotificationObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: nil
        ) { [weak self] _ in
            self?.handlePlaybackEnded(item: item, generation: generation)
        }

        let failureNotificationObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: nil
        ) { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            self?.emitFailure(Self.playbackError(from: error), generation: generation)
        }

        return ObserverCleanup(
            player: player,
            itemStatusObservation: itemStatusObservation,
            timeControlStatusObservation: timeControlStatusObservation,
            durationObservation: durationObservation,
            periodicTimeObserver: periodicTimeObserver,
            endNotificationObserver: endNotificationObserver,
            failureNotificationObserver: failureNotificationObserver
        )
    }

    private func handleItemStatus(
        _ status: AVPlayerItem.Status,
        item: AVPlayerItem,
        generation: UInt64
    ) {
        switch status {
        case .unknown:
            return
        case .readyToPlay:
            emitDurationIfChanged(item.duration, generation: generation)
            seekToPendingResumePositionIfNeeded(item: item, generation: generation)
            emitTracksDiscovered(item: item, generation: generation)
            emitReady(generation: generation)
        case .failed:
            emitFailure(Self.playbackError(from: item.error), generation: generation)
        @unknown default:
            emitFailure(.unknown("AVFoundation reported an unknown playback item status."), generation: generation)
        }
    }

    private func handleTimeControlStatus(
        _ status: AVPlayer.TimeControlStatus,
        player: AVPlayer,
        generation: UInt64
    ) {
        switch status {
        case .paused:
            emitStateIfChanged(.paused, generation: generation, requiresReady: true)
        case .waitingToPlayAtSpecifiedRate:
            emitStateIfChanged(.buffering, generation: generation, requiresReady: true)
        case .playing:
            emitStateIfChanged(.playing, generation: generation, requiresReady: true)
        @unknown default:
            emitFailure(.unknown("AVFoundation reported an unknown playback time-control status."), generation: generation)
        }
    }

    private func seekToPendingResumePositionIfNeeded(item: AVPlayerItem, generation: UInt64) {
        let pendingPositionMS: Int? = withLock {
            guard state.isActive(generation), let positionMS = state.pendingResumePositionMS else {
                return nil
            }

            state.pendingResumePositionMS = nil
            return positionMS
        }

        guard let pendingPositionMS else {
            return
        }

        let target = CMTime(value: CMTimeValue(pendingPositionMS), timescale: 1000)
        item.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
            guard completed else {
                return
            }
            self?.emitPositionIfChanged(pendingPositionMS, generation: generation)
        }
    }

    private func emitReady(generation: UInt64) {
        let shouldEmit = withLock {
            guard state.isActive(generation), !state.didFinish else {
                return false
            }

            state.isReady = true
            guard state.lastState != .ready else {
                return false
            }

            state.lastState = .ready
            return true
        }

        if shouldEmit {
            eventHub.emit(.stateChanged(.ready))
        }
    }

    private func emitStateIfChanged(
        _ playbackState: PlaybackState,
        generation: UInt64,
        requiresReady: Bool
    ) {
        let shouldEmit = withLock {
            guard state.isActive(generation), !state.didFinish else {
                return false
            }

            if requiresReady, !state.isReady {
                return false
            }

            guard state.lastState != playbackState else {
                return false
            }

            state.lastState = playbackState
            return true
        }

        if shouldEmit {
            eventHub.emit(.stateChanged(playbackState))
        }
    }

    private func emitPositionIfChanged(_ time: CMTime, generation: UInt64) {
        guard let positionMS = Self.milliseconds(from: time) else {
            return
        }

        emitPositionIfChanged(positionMS, generation: generation)
    }

    private func emitPositionIfChanged(_ positionMS: Int, generation: UInt64) {
        let normalizedPositionMS = max(0, positionMS)
        let shouldEmit = withLock {
            guard state.isActive(generation), !state.didFinish else {
                return false
            }

            guard state.lastPositionMS != normalizedPositionMS else {
                return false
            }

            state.lastPositionMS = normalizedPositionMS
            return true
        }

        if shouldEmit {
            eventHub.emit(.positionUpdated(positionMS: normalizedPositionMS))
        }
    }

    private func emitDurationIfChanged(_ duration: CMTime, generation: UInt64) {
        guard let durationMS = Self.milliseconds(from: duration) else {
            return
        }

        let shouldEmit = withLock {
            guard state.isActive(generation), !state.didFinish else {
                return false
            }

            guard state.lastDurationMS != durationMS else {
                return false
            }

            state.lastDurationMS = durationMS
            return true
        }

        if shouldEmit {
            eventHub.emit(.durationUpdated(durationMS: durationMS))
        }
    }

    private func handlePlaybackEnded(item: AVPlayerItem, generation: UInt64) {
        let event: PlaybackEvent? = withLock {
            guard state.isActive(generation), !state.didFinish else {
                return nil
            }

            state.didFinish = true
            state.lastState = .ended
            let finalPositionMS = Self.milliseconds(from: item.currentTime()) ?? state.lastPositionMS ?? 0
            let durationMS = Self.milliseconds(from: item.duration)
            state.lastPositionMS = finalPositionMS
            state.lastDurationMS = durationMS ?? state.lastDurationMS
            return .playbackEnded(finalPositionMS: finalPositionMS, durationMS: durationMS)
        }

        if let event {
            eventHub.emit(event)
        }
    }

    private func selectMediaOption(trackID: String, type: PlaybackTrackType) throws {
        let selection = try currentMediaSelection(type: type)
        guard let item = selection.item,
              let group = selection.group,
              let option = selection.options[trackID] else {
            return
        }

        item.select(option, in: group)
        emitTracksDiscovered(item: item, generation: selection.generation)
    }

    private func currentMediaSelection(type: PlaybackTrackType) throws -> CurrentMediaSelection {
        try withLock {
            guard !state.isShutdown else {
                throw PlaybackError.invalidState("playback backend has shut down")
            }

            guard let item = state.item else {
                throw PlaybackError.invalidState("playback backend has no active item")
            }

            switch type {
            case .audio:
                return CurrentMediaSelection(
                    item: item,
                    group: state.audioSelectionGroup,
                    options: state.audioOptionsByID,
                    generation: state.generation
                )
            case .subtitle:
                return CurrentMediaSelection(
                    item: item,
                    group: state.subtitleSelectionGroup,
                    options: state.subtitleOptionsByID,
                    generation: state.generation
                )
            }
        }
    }

    private func emitTracksDiscovered(item: AVPlayerItem, generation: UInt64) {
        let audioGroup = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible)
        let subtitleGroup = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible)
        let audio = Self.tracksAndOptions(
            group: audioGroup,
            selectedOption: audioGroup.flatMap { item.currentMediaSelection.selectedMediaOption(in: $0) },
            type: .audio,
            idPrefix: "audio"
        )
        let subtitle = Self.tracksAndOptions(
            group: subtitleGroup,
            selectedOption: subtitleGroup.flatMap { item.currentMediaSelection.selectedMediaOption(in: $0) },
            type: .subtitle,
            idPrefix: "subtitle"
        )

        let shouldEmit = withLock {
            guard state.isActive(generation), !state.didFinish else {
                return false
            }

            state.audioSelectionGroup = audioGroup
            state.subtitleSelectionGroup = subtitleGroup
            state.audioOptionsByID = audio.optionsByID
            state.subtitleOptionsByID = subtitle.optionsByID
            return true
        }

        if shouldEmit {
            eventHub.emit(.tracksDiscovered(audioTracks: audio.tracks, subtitleTracks: subtitle.tracks))
        }
    }

    private static func tracksAndOptions(
        group: AVMediaSelectionGroup?,
        selectedOption: AVMediaSelectionOption?,
        type: PlaybackTrackType,
        idPrefix: String
    ) -> (tracks: [PlaybackTrack], optionsByID: [String: AVMediaSelectionOption]) {
        guard let group else {
            return ([], [:])
        }

        var optionsByID: [String: AVMediaSelectionOption] = [:]
        let playableOptions = group.options.filter(\.isPlayable)
        let tracks = playableOptions.enumerated().map { index, option in
            let id = "\(idPrefix)-\(index + 1)"
            optionsByID[id] = option
            return PlaybackTrack(
                id: id,
                type: type,
                language: option.extendedLanguageTag ?? option.locale?.identifier,
                title: option.displayName,
                isDefault: group.defaultOption == option,
                isSelected: selectedOption == option
            )
        }
        return (tracks, optionsByID)
    }

    private func emitFailure(_ error: PlaybackError, generation: UInt64) {
        let shouldEmit = withLock {
            guard state.isActive(generation), !state.didFinish else {
                return false
            }

            state.didFinish = true
            state.lastState = .failed
            return true
        }

        if shouldEmit {
            eventHub.emit(.playbackFailed(error))
        }
    }

    private func cleanupObservers(_ cleanup: ObserverCleanup) {
        if let periodicTimeObserver = cleanup.periodicTimeObserver, let player = cleanup.player {
            player.removeTimeObserver(periodicTimeObserver)
        }

        cleanup.player?.pause()
        cleanup.itemStatusObservation?.invalidate()
        cleanup.timeControlStatusObservation?.invalidate()
        cleanup.durationObservation?.invalidate()

        if let endNotificationObserver = cleanup.endNotificationObserver {
            NotificationCenter.default.removeObserver(endNotificationObserver)
        }

        if let failureNotificationObserver = cleanup.failureNotificationObserver {
            NotificationCenter.default.removeObserver(failureNotificationObserver)
        }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer {
            lock.unlock()
        }
        return try body()
    }

    private static func milliseconds(from time: CMTime) -> Int? {
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite, !seconds.isNaN else {
            return nil
        }

        let milliseconds = Int((seconds * 1000).rounded())
        guard milliseconds >= 0 else {
            return nil
        }

        return milliseconds
    }

    private static func playbackError(from error: (any Error)?) -> PlaybackError {
        guard let error else {
            return .unknown("AVFoundation playback failed.")
        }

        let nsError = error as NSError
        if nsError.domain == AVFoundationErrorDomain {
            switch AVError.Code(rawValue: nsError.code) {
            case .fileFormatNotRecognized, .fileFailedToParse, .decoderNotFound, .failedToParse, .formatUnsupported:
                return .unsupportedFormat
            default:
                return .unknown("AVFoundation playback failed.")
            }
        }

        switch nsError.code {
        case NSFileReadNoSuchFileError:
            return .fileMissing
        case NSFileReadNoPermissionError:
            return .permissionDenied
        default:
            return .unknown("AVFoundation playback failed.")
        }
    }
}

private struct BackendState {
    var generation: UInt64 = 0
    var player: AVPlayer?
    var item: AVPlayerItem?
    var audioSelectionGroup: AVMediaSelectionGroup?
    var subtitleSelectionGroup: AVMediaSelectionGroup?
    var audioOptionsByID: [String: AVMediaSelectionOption] = [:]
    var subtitleOptionsByID: [String: AVMediaSelectionOption] = [:]
    var itemStatusObservation: NSKeyValueObservation?
    var timeControlStatusObservation: NSKeyValueObservation?
    var durationObservation: NSKeyValueObservation?
    var periodicTimeObserver: Any?
    var endNotificationObserver: NSObjectProtocol?
    var failureNotificationObserver: NSObjectProtocol?
    var pendingResumePositionMS: Int?
    var isReady = false
    var didFinish = false
    var isShutdown = false
    var lastState: PlaybackState?
    var lastPositionMS: Int?
    var lastDurationMS: Int?

    func isActive(_ generation: UInt64) -> Bool {
        !isShutdown && self.generation == generation
    }

    func cleanup() -> ObserverCleanup {
        ObserverCleanup(
            player: player,
            itemStatusObservation: itemStatusObservation,
            timeControlStatusObservation: timeControlStatusObservation,
            durationObservation: durationObservation,
            periodicTimeObserver: periodicTimeObserver,
            endNotificationObserver: endNotificationObserver,
            failureNotificationObserver: failureNotificationObserver
        )
    }

    mutating func clearPlayback() {
        player = nil
        item = nil
        audioSelectionGroup = nil
        subtitleSelectionGroup = nil
        audioOptionsByID = [:]
        subtitleOptionsByID = [:]
        itemStatusObservation = nil
        timeControlStatusObservation = nil
        durationObservation = nil
        periodicTimeObserver = nil
        endNotificationObserver = nil
        failureNotificationObserver = nil
        pendingResumePositionMS = nil
        isReady = false
        didFinish = false
        lastPositionMS = nil
        lastDurationMS = nil
        lastState = nil
    }
}

private struct CurrentMediaSelection {
    let item: AVPlayerItem?
    let group: AVMediaSelectionGroup?
    let options: [String: AVMediaSelectionOption]
    let generation: UInt64
}

private struct ObserverCleanup {
    var player: AVPlayer?
    var itemStatusObservation: NSKeyValueObservation?
    var timeControlStatusObservation: NSKeyValueObservation?
    var durationObservation: NSKeyValueObservation?
    var periodicTimeObserver: Any?
    var endNotificationObserver: NSObjectProtocol?
    var failureNotificationObserver: NSObjectProtocol?

    init(
        player: AVPlayer? = nil,
        itemStatusObservation: NSKeyValueObservation? = nil,
        timeControlStatusObservation: NSKeyValueObservation? = nil,
        durationObservation: NSKeyValueObservation? = nil,
        periodicTimeObserver: Any? = nil,
        endNotificationObserver: NSObjectProtocol? = nil,
        failureNotificationObserver: NSObjectProtocol? = nil
    ) {
        self.player = player
        self.itemStatusObservation = itemStatusObservation
        self.timeControlStatusObservation = timeControlStatusObservation
        self.durationObservation = durationObservation
        self.periodicTimeObserver = periodicTimeObserver
        self.endNotificationObserver = endNotificationObserver
        self.failureNotificationObserver = failureNotificationObserver
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
        let activeContinuations: [AsyncStream<PlaybackEvent>.Continuation] = withLock {
            guard !isFinished else {
                return []
            }

            return Array(continuations.values)
        }

        for continuation in activeContinuations {
            continuation.yield(event)
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
