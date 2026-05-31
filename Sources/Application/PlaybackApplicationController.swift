import Domain
import Foundation
import Playback
import Subtitle

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

public struct PlaybackApplicationTrack: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayLabel: String
    public let isDefault: Bool
    public let isSelected: Bool
    public let source: PlaybackApplicationTrackSource
    public let isSelectable: Bool

    public init(
        id: String,
        displayLabel: String,
        isDefault: Bool,
        isSelected: Bool,
        source: PlaybackApplicationTrackSource = .embedded,
        isSelectable: Bool = true
    ) {
        self.id = id
        self.displayLabel = displayLabel
        self.isDefault = isDefault
        self.isSelected = isSelected
        self.source = source
        self.isSelectable = isSelectable
    }
}

public struct PlaybackApplicationStatus: Sendable, Equatable {
    public let state: PlaybackApplicationState
    public let mediaFileID: MediaFileID?
    public let displayName: String?
    public let positionMS: Int
    public let durationMS: Int?
    public let audioTracks: [PlaybackApplicationTrack]
    public let subtitleTracks: [PlaybackApplicationTrack]
    public let activeSubtitleText: String?
    public let notice: String?

    public init(
        state: PlaybackApplicationState,
        mediaFileID: MediaFileID?,
        displayName: String?,
        positionMS: Int,
        durationMS: Int?,
        audioTracks: [PlaybackApplicationTrack] = [],
        subtitleTracks: [PlaybackApplicationTrack] = [],
        activeSubtitleText: String? = nil,
        notice: String? = nil
    ) {
        self.state = state
        self.mediaFileID = mediaFileID
        self.displayName = displayName
        self.positionMS = positionMS
        self.durationMS = durationMS
        self.audioTracks = audioTracks
        self.subtitleTracks = subtitleTracks
        self.activeSubtitleText = activeSubtitleText
        self.notice = notice
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
    func pause() async
    func resume() async
    func togglePlayPause() async
    func stop() async
    func seek(toMS positionMS: Int) async
    func seekRelative(byMS deltaMS: Int) async
    func selectAudioTrack(trackID: String) async
    func selectSubtitleTrack(trackID: String) async
    func disableSubtitles() async
    func shutdown() async
}

public actor PlaybackApplicationController: PlaybackApplicationControlling, PlaybackExternalSubtitleRefreshing {
    public nonisolated let statusStream: AsyncStream<PlaybackApplicationStatus>

    private let coordinator: PlaybackCoordinator
    private let progressCoordinator: PlaybackProgressCoordinator
    private let mediaOpening: any MediaOpening
    private let subtitleAssetReader: (any PlaybackSubtitleAssetReading)?
    private let subtitleFileLoader: any PlaybackSubtitleFileLoading
    private let statusContinuation: AsyncStream<PlaybackApplicationStatus>.Continuation

    private var eventTask: Task<Void, Never>?
    private var activeMediaFileID: MediaFileID?
    private var activeDisplayName: String?
    private var currentState: PlaybackApplicationState = .idle
    private var currentPositionMS = 0
    private var currentDurationMS: Int?
    private var currentAudioTracks: [PlaybackApplicationTrack] = []
    private var currentSubtitleTracks: [PlaybackApplicationTrack] = []
    private var currentExternalSubtitleTracks: [PlaybackApplicationTrack] = []
    private var externalSubtitleAssetsByTrackID: [String: PlaybackSubtitleAsset] = [:]
    private var activeExternalSubtitleTimeline: SubtitleCueTimeline?
    private var activeSubtitleText: String?
    private var progressSessionOpen = false
    private var didAutoPlayActiveSession = false
    private var lastEmittedStatus: PlaybackApplicationStatus?
    private var shouldSuppressNextCoordinatorIdle = false

    public init(
        coordinator: PlaybackCoordinator,
        progressCoordinator: PlaybackProgressCoordinator,
        mediaOpening: any MediaOpening,
        subtitleAssetReader: (any PlaybackSubtitleAssetReading)? = nil,
        subtitleFileLoader: any PlaybackSubtitleFileLoading = FileSystemPlaybackSubtitleFileLoader()
    ) {
        self.coordinator = coordinator
        self.progressCoordinator = progressCoordinator
        self.mediaOpening = mediaOpening
        self.subtitleAssetReader = subtitleAssetReader
        self.subtitleFileLoader = subtitleFileLoader

        var continuation: AsyncStream<PlaybackApplicationStatus>.Continuation?
        self.statusStream = AsyncStream(bufferingPolicy: .unbounded) { streamContinuation in
            continuation = streamContinuation
        }
        self.statusContinuation = continuation!
        self.eventTask = nil
    }

    public func open(mediaFileID: MediaFileID) async {
        startEventLoopIfNeeded()

        if activeMediaFileID == mediaFileID, activeSessionShouldIgnoreRepeatedOpen {
            return
        }

        let playableFile: PlayableFile
        do {
            playableFile = try mediaOpening.open(mediaFileID: mediaFileID)
        } catch {
            guard !activeSessionShouldIgnoreRepeatedOpen else {
                emitCurrentStatus(notice: "Could not open media file.")
                return
            }

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

        if activeMediaFileID != nil || progressSessionOpen {
            await stop()
        }

        activeMediaFileID = playableFile.mediaFileID
        activeDisplayName = playableFile.displayName
        currentState = .loading
        currentPositionMS = max(0, playableFile.resumePositionMS ?? 0)
        currentDurationMS = nil
        currentAudioTracks = []
        currentSubtitleTracks = []
        loadExternalSubtitleOptions(mediaFileID: playableFile.mediaFileID)
        activeExternalSubtitleTimeline = nil
        activeSubtitleText = nil
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

        let shouldSuppressCoordinatorIdle = activeMediaFileID != nil || progressSessionOpen
        if shouldSuppressCoordinatorIdle {
            shouldSuppressNextCoordinatorIdle = true
        }
        let didStopCoordinatorSession = await coordinator.stop()
        if shouldSuppressCoordinatorIdle, !didStopCoordinatorSession {
            shouldSuppressNextCoordinatorIdle = false
        }
        let closeNotice = await closeProgressSessionIfOpen()
        resetActiveSession()
        emitStatus(idleStatus(notice: closeNotice), force: true)
    }

    public func pause() async {
        startEventLoopIfNeeded()

        guard currentState == .playing else {
            return
        }

        await coordinator.pause()
    }

    public func resume() async {
        startEventLoopIfNeeded()

        guard currentState == .paused else {
            return
        }

        await coordinator.play()
    }

    public func togglePlayPause() async {
        switch currentState {
        case .playing:
            await pause()
        case .paused:
            await resume()
        case .idle, .loading, .ready, .buffering, .ended, .failed:
            return
        }
    }

    public func seek(toMS positionMS: Int) async {
        startEventLoopIfNeeded()

        guard validSeekState else {
            return
        }

        let clampedPositionMS = clampSeekPosition(positionMS)
        await progressCoordinator.noteSeekRequested()
        await coordinator.seek(toMS: clampedPositionMS)
    }

    public func seekRelative(byMS deltaMS: Int) async {
        let targetMS = currentPositionMS + deltaMS
        await seek(toMS: targetMS)
    }

    public func selectAudioTrack(trackID: String) async {
        startEventLoopIfNeeded()

        guard validTrackSelectionState,
              currentAudioTracks.contains(where: { $0.id == trackID }) else {
            return
        }

        await coordinator.selectAudioTrack(trackID: trackID)
        currentAudioTracks = tracksBySelecting(trackID, in: currentAudioTracks)
        emitCurrentStatus()
    }

    public func selectSubtitleTrack(trackID: String) async {
        startEventLoopIfNeeded()

        guard validTrackSelectionState else {
            return
        }

        if let asset = externalSubtitleAssetsByTrackID[trackID] {
            await selectExternalSubtitle(trackID: trackID, asset: asset)
            return
        }

        guard currentSubtitleTracks.contains(where: { $0.id == trackID && $0.isSelectable }) else {
            return
        }

        await coordinator.selectSubtitleTrack(trackID: trackID)
        currentSubtitleTracks = tracksBySelecting(trackID, in: currentSubtitleTracks)
        currentExternalSubtitleTracks = tracksByDeselecting(currentExternalSubtitleTracks)
        activeExternalSubtitleTimeline = nil
        activeSubtitleText = nil
        emitCurrentStatus()
    }

    public func disableSubtitles() async {
        startEventLoopIfNeeded()

        guard validTrackSelectionState,
              currentSubtitleTracks.contains(where: \.isSelected)
                || currentExternalSubtitleTracks.contains(where: \.isSelected) else {
            return
        }

        if currentSubtitleTracks.contains(where: \.isSelected) {
            await coordinator.disableSubtitle()
        }
        currentSubtitleTracks = tracksByDeselecting(currentSubtitleTracks)
        currentExternalSubtitleTracks = tracksByDeselecting(currentExternalSubtitleTracks)
        activeExternalSubtitleTimeline = nil
        activeSubtitleText = nil
        emitCurrentStatus()
    }

    public func reloadExternalSubtitleOptions(mediaFileID: MediaFileID) async {
        startEventLoopIfNeeded()

        guard activeMediaFileID == mediaFileID else {
            return
        }

        let selectedExternalTrackID = currentExternalSubtitleTracks
            .first(where: \.isSelected)?
            .id
        loadExternalSubtitleOptions(mediaFileID: mediaFileID)

        if let selectedExternalTrackID,
           let selectedAsset = externalSubtitleAssetsByTrackID[selectedExternalTrackID],
           selectedAsset.isSelectable,
           let timeline = externalSubtitleTimeline(for: selectedAsset) {
            currentExternalSubtitleTracks = tracksBySelecting(
                selectedExternalTrackID,
                in: currentExternalSubtitleTracks
            )
            activeExternalSubtitleTimeline = timeline
            updateActiveSubtitleText()
        } else if selectedExternalTrackID != nil {
            currentExternalSubtitleTracks = tracksByDeselecting(currentExternalSubtitleTracks)
            activeExternalSubtitleTimeline = nil
            activeSubtitleText = nil
        }

        emitCurrentStatus()
    }

    public func shutdown() async {
        startEventLoopIfNeeded()

        if activeMediaFileID != nil || progressSessionOpen {
            await stop()
        }

        eventTask?.cancel()
        eventTask = nil
        await coordinator.shutdown()
        statusContinuation.finish()
    }

    private var validSeekState: Bool {
        switch currentState {
        case .ready, .playing, .paused, .buffering:
            return true
        case .idle, .loading, .ended, .failed:
            return false
        }
    }

    private var validTrackSelectionState: Bool {
        validSeekState
    }

    private var activeSessionShouldIgnoreRepeatedOpen: Bool {
        switch currentState {
        case .loading, .ready, .playing, .paused, .buffering:
            return true
        case .idle, .ended, .failed:
            return false
        }
    }

    private func clampSeekPosition(_ positionMS: Int) -> Int {
        let lowerBound = max(0, positionMS)
        if let durationMS = currentDurationMS, durationMS > 0 {
            return min(lowerBound, durationMS)
        }
        return lowerBound
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
        if shouldSuppressCoordinatorEvent(event) {
            return
        }

        if shouldIgnoreStaleCoordinatorEvent(event) {
            return
        }

        let progressNotice = await progressNotice(for: event)

        switch event {
        case .stateChanged(let playbackState):
            await handlePlaybackState(playbackState, notice: progressNotice)
        case .positionUpdated(let positionMS):
            currentPositionMS = max(0, positionMS)
            updateActiveSubtitleText()
            emitCurrentStatus(notice: progressNotice)
        case .durationUpdated(let durationMS):
            currentDurationMS = max(0, durationMS)
            emitCurrentStatus(notice: progressNotice)
        case .playbackEnded(let finalPositionMS, let durationMS):
            currentPositionMS = max(0, finalPositionMS)
            currentDurationMS = durationMS.map { max(0, $0) }
            currentState = .ended
            emitCurrentStatus(notice: progressNotice)
            if let closeNotice = await closeProgressSessionIfOpen() {
                emitCurrentStatus(notice: closeNotice)
            }
        case .playbackFailed(let error):
            currentState = .failed(userSafeMessage(forPlaybackError: error))
            emitCurrentStatus(notice: progressNotice)
        case .tracksDiscovered(let audioTracks, let subtitleTracks):
            currentAudioTracks = Self.mapTracks(audioTracks, fallbackPrefix: "Audio")
            currentSubtitleTracks = Self.mapTracks(subtitleTracks, fallbackPrefix: "Subtitle")
            emitCurrentStatus(notice: progressNotice)
        }
    }

    private func handlePlaybackState(_ playbackState: PlaybackState, notice: String?) async {
        switch playbackState {
        case .idle:
            let closeNotice = await closeProgressSessionIfOpen()
            resetActiveSession()
            emitStatus(idleStatus(notice: closeNotice ?? notice))
        case .loading:
            currentState = .loading
            emitCurrentStatus(notice: notice)
        case .ready:
            currentState = .ready
            emitCurrentStatus(notice: notice)
            if activeMediaFileID != nil, !didAutoPlayActiveSession {
                didAutoPlayActiveSession = true
                await coordinator.play()
            }
        case .playing:
            currentState = .playing
            emitCurrentStatus(notice: notice)
        case .paused:
            currentState = .paused
            emitCurrentStatus(notice: notice)
        case .buffering:
            currentState = .buffering
            emitCurrentStatus(notice: notice)
        case .ended:
            currentState = .ended
            emitCurrentStatus(notice: notice)
            if let closeNotice = await closeProgressSessionIfOpen() {
                emitCurrentStatus(notice: closeNotice)
            }
        case .failed:
            if case .failed = currentState {
                return
            }
            currentState = .failed("Playback failed.")
            emitCurrentStatus(notice: notice)
        }
    }

    private func shouldSuppressCoordinatorEvent(_ event: PlaybackEvent) -> Bool {
        guard case .stateChanged(.idle) = event,
              shouldSuppressNextCoordinatorIdle else {
            return false
        }

        shouldSuppressNextCoordinatorIdle = false
        return true
    }

    private func shouldIgnoreStaleCoordinatorEvent(_ event: PlaybackEvent) -> Bool {
        guard activeMediaFileID == nil else {
            return false
        }

        switch event {
        case .stateChanged(.idle):
            return false
        case .stateChanged, .positionUpdated, .durationUpdated, .playbackEnded, .playbackFailed, .tracksDiscovered:
            return true
        }
    }

    private func progressNotice(for event: PlaybackEvent) async -> String? {
        do {
            try await progressCoordinator.handle(event)
            return nil
        } catch {
            return "Could not save playback progress."
        }
    }

    private func closeProgressSessionIfOpen() async -> String? {
        guard progressSessionOpen else {
            return nil
        }

        progressSessionOpen = false
        do {
            try await progressCoordinator.closeSession()
            return nil
        } catch {
            return "Could not save playback progress."
        }
    }

    private func resetActiveSession() {
        activeMediaFileID = nil
        activeDisplayName = nil
        currentState = .idle
        currentPositionMS = 0
        currentDurationMS = nil
        currentAudioTracks = []
        currentSubtitleTracks = []
        currentExternalSubtitleTracks = []
        externalSubtitleAssetsByTrackID = [:]
        activeExternalSubtitleTimeline = nil
        activeSubtitleText = nil
        progressSessionOpen = false
        didAutoPlayActiveSession = false
    }

    private func emitCurrentStatus(notice: String? = nil) {
        emitStatus(
            PlaybackApplicationStatus(
                state: currentState,
                mediaFileID: activeMediaFileID,
                displayName: activeDisplayName,
                positionMS: currentPositionMS,
                durationMS: currentDurationMS,
                audioTracks: currentAudioTracks,
                subtitleTracks: currentSubtitleTracks + currentExternalSubtitleTracks,
                activeSubtitleText: activeSubtitleText,
                notice: notice
            )
        )
    }

    private func idleStatus(notice: String?) -> PlaybackApplicationStatus {
        PlaybackApplicationStatus(
            state: .idle,
            mediaFileID: nil,
            displayName: nil,
            positionMS: 0,
            durationMS: nil,
            notice: notice
        )
    }

    private func emitStatus(_ status: PlaybackApplicationStatus, force: Bool = false) {
        guard force || status != lastEmittedStatus else {
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

    private func loadExternalSubtitleOptions(mediaFileID: MediaFileID) {
        guard let subtitleAssetReader else {
            currentExternalSubtitleTracks = []
            externalSubtitleAssetsByTrackID = [:]
            return
        }

        do {
            let assets = try subtitleAssetReader.fetchPlaybackSubtitleAssets(mediaFileID: mediaFileID)
            externalSubtitleAssetsByTrackID = Dictionary(
                uniqueKeysWithValues: assets.map { ($0.trackID, $0) }
            )
            currentExternalSubtitleTracks = assets.map(mapExternalSubtitleAsset)
        } catch {
            currentExternalSubtitleTracks = []
            externalSubtitleAssetsByTrackID = [:]
        }
    }

    private func mapExternalSubtitleAsset(_ asset: PlaybackSubtitleAsset) -> PlaybackApplicationTrack {
        PlaybackApplicationTrack(
            id: asset.trackID,
            displayLabel: externalSubtitleDisplayLabel(for: asset),
            isDefault: false,
            isSelected: false,
            source: asset.format.supportsExternalCueParsing ? .external : .unsupportedExternal,
            isSelectable: asset.isSelectable
        )
    }

    private func externalSubtitleDisplayLabel(for asset: PlaybackSubtitleAsset) -> String {
        var label = asset.displayName
        if !asset.format.supportsExternalCueParsing {
            label += " (Unsupported)"
        }
        return label
    }

    private func selectExternalSubtitle(trackID: String, asset: PlaybackSubtitleAsset) async {
        guard validTrackSelectionState, asset.isSelectable,
              let timeline = externalSubtitleTimeline(for: asset) else {
            return
        }

        if currentSubtitleTracks.contains(where: \.isSelected) {
            await coordinator.disableSubtitle()
        }
        currentSubtitleTracks = tracksByDeselecting(currentSubtitleTracks)
        currentExternalSubtitleTracks = tracksBySelecting(trackID, in: currentExternalSubtitleTracks)
        activeExternalSubtitleTimeline = timeline
        updateActiveSubtitleText()
        emitCurrentStatus()
    }

    private func externalSubtitleTimeline(for asset: PlaybackSubtitleAsset) -> SubtitleCueTimeline? {
        guard let subtitleURL = resolvedSubtitleURL(for: asset) else {
            return nil
        }

        do {
            let text = try subtitleFileLoader.loadSubtitleText(from: subtitleURL)
            return try SubtitleParser.parse(text, format: asset.format)
        } catch {
            return nil
        }
    }

    private func resolvedSubtitleURL(for asset: PlaybackSubtitleAsset) -> URL? {
        guard !asset.folderRootPath.isEmpty,
              (asset.folderRootPath as NSString).isAbsolutePath,
              !(asset.relativePath as NSString).isAbsolutePath else {
            return nil
        }

        let rootURL = URL(fileURLWithPath: asset.folderRootPath, isDirectory: true).standardizedFileURL
        let resolvedURL = rootURL
            .appendingPathComponent(asset.relativePath, isDirectory: false)
            .standardizedFileURL

        let rootPath = rootURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        let resolvedPath = resolvedURL.path
        guard resolvedPath == rootPath || resolvedPath.hasPrefix(rootPrefix) else {
            return nil
        }
        return resolvedURL
    }

    private func updateActiveSubtitleText() {
        activeSubtitleText = activeExternalSubtitleTimeline?.activeText(atMS: currentPositionMS)
    }

    private func tracksBySelecting(
        _ selectedTrackID: String,
        in tracks: [PlaybackApplicationTrack]
    ) -> [PlaybackApplicationTrack] {
        tracks.map { track in
            PlaybackApplicationTrack(
                id: track.id,
                displayLabel: track.displayLabel,
                isDefault: track.isDefault,
                isSelected: track.id == selectedTrackID,
                source: track.source,
                isSelectable: track.isSelectable
            )
        }
    }

    private func tracksByDeselecting(_ tracks: [PlaybackApplicationTrack]) -> [PlaybackApplicationTrack] {
        tracks.map { track in
            PlaybackApplicationTrack(
                id: track.id,
                displayLabel: track.displayLabel,
                isDefault: track.isDefault,
                isSelected: false,
                source: track.source,
                isSelectable: track.isSelectable
            )
        }
    }

    private static func mapTracks(
        _ tracks: [PlaybackTrack],
        fallbackPrefix: String
    ) -> [PlaybackApplicationTrack] {
        tracks.enumerated().map { index, track in
            PlaybackApplicationTrack(
                id: track.id,
                displayLabel: trackDisplayLabel(
                    for: track,
                    fallbackPrefix: fallbackPrefix,
                    index: index
                ),
                isDefault: track.isDefault,
                isSelected: track.isSelected
            )
        }
    }

    private static func trackDisplayLabel(
        for track: PlaybackTrack,
        fallbackPrefix: String,
        index: Int
    ) -> String {
        let title = track.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = track.language?.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseLabel: String
        if let title, !title.isEmpty {
            baseLabel = title
        } else if let language, !language.isEmpty {
            baseLabel = language.uppercased()
        } else {
            baseLabel = "\(fallbackPrefix) \(index + 1)"
        }

        if track.isDefault {
            return "\(baseLabel) (Default)"
        }
        return baseLabel
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
