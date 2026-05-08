import Foundation
import Playback

actor MPVRuntime {
    private let api: MPVClientAPI
    private var handle: UnsafeMutableRawPointer?
    private var shouldRunEventLoop = true
    private var isDestroyed = false

    private var loadedFile: PlayableFile?
    private var isLoaded = false
    private var explicitPlayRequested = false
    private var hasStartedPlayback = false
    private var isPaused = true
    private var isBuffering = false
    private var suppressNextIdleForUserStop = false
    private var pendingResumePositionMS: Int?
    private var latestPositionMS = 0
    private var latestDurationMS: Int?
    private var audioTracks: [PlaybackTrack] = []
    private var subtitleTracks: [PlaybackTrack] = []

    var shouldContinueEventLoop: Bool {
        shouldRunEventLoop
    }

    init() throws {
        let api = try MPVClientAPI()
        self.api = api

        do {
            let handle = try Self.createInitializedHandle(api: api)
            self.handle = handle
            _ = api.requestLogMessages(handle, "no")
            try Self.observeProperties(api: api, handle: handle)
        } catch {
            if let handle {
                api.terminateDestroy(handle)
            }
            self.handle = nil
            isDestroyed = true
            shouldRunEventLoop = false
            throw error
        }
    }

    func load(playableFile: PlayableFile) throws {
        try ensureUsableHandle()
        try validatePlayableFile(playableFile)

        try setFlagProperty("pause", value: true)
        try command(["loadfile", playableFile.url.path, "replace"])

        loadedFile = playableFile
        isLoaded = false
        explicitPlayRequested = false
        hasStartedPlayback = false
        isPaused = true
        isBuffering = false
        suppressNextIdleForUserStop = false
        pendingResumePositionMS = playableFile.resumePositionMS
        latestPositionMS = playableFile.resumePositionMS ?? 0
        latestDurationMS = nil
        audioTracks = []
        subtitleTracks = []
    }

    func play() throws {
        try ensureUsableHandle()
        explicitPlayRequested = true
        try setFlagProperty("pause", value: false)
    }

    func pause() throws {
        try ensureUsableHandle()
        explicitPlayRequested = false
        try setFlagProperty("pause", value: true)
    }

    func seek(toMS positionMS: Int) throws {
        try ensureUsableHandle()
        guard positionMS >= 0 else {
            throw PlaybackError.invalidState("seek requires a non-negative position")
        }

        try seekWithoutStateChange(toMS: positionMS)
    }

    func stop() throws {
        try ensureUsableHandle()
        suppressNextIdleForUserStop = true
        try command(["stop"])
        isLoaded = false
        explicitPlayRequested = false
        hasStartedPlayback = false
        isPaused = true
        isBuffering = false
    }

    func selectAudioTrack(trackID: String) throws {
        try ensureUsableHandle()
        try setStringProperty("aid", value: trackID)
    }

    func selectSubtitleTrack(trackID: String) throws {
        try ensureUsableHandle()
        try setStringProperty("sid", value: trackID)
    }

    func disableSubtitle() throws {
        try ensureUsableHandle()
        try setStringProperty("sid", value: "no")
    }

    func waitForEvents(timeout: Double) -> [PlaybackEvent] {
        guard shouldRunEventLoop, let handle else {
            return []
        }

        guard let eventPointer = api.waitEvent(handle, timeout) else {
            return []
        }

        return handleMPVEvent(eventPointer.pointee)
    }

    func stopEventLoop() {
        shouldRunEventLoop = false
    }

    func destroy() {
        guard !isDestroyed, let handle else {
            return
        }

        self.handle = nil
        isDestroyed = true
        shouldRunEventLoop = false
        api.terminateDestroy(handle)
    }

    private func observeProperties() throws {
        try observe(.pause, name: "pause", format: MPV_FORMAT_FLAG)
        try observe(.timePosition, name: "time-pos", format: MPV_FORMAT_DOUBLE)
        try observe(.duration, name: "duration", format: MPV_FORMAT_DOUBLE)
        try observe(.trackList, name: "track-list", format: MPV_FORMAT_NODE)
        _ = try? observe(.pausedForCache, name: "paused-for-cache", format: MPV_FORMAT_FLAG)
    }

    private static func observeProperties(api: MPVClientAPI, handle: UnsafeMutableRawPointer) throws {
        try observe(api: api, handle: handle, .pause, name: "pause", format: MPV_FORMAT_FLAG)
        try observe(api: api, handle: handle, .timePosition, name: "time-pos", format: MPV_FORMAT_DOUBLE)
        try observe(api: api, handle: handle, .duration, name: "duration", format: MPV_FORMAT_DOUBLE)
        try observe(api: api, handle: handle, .trackList, name: "track-list", format: MPV_FORMAT_NODE)
        _ = try? observe(api: api, handle: handle, .pausedForCache, name: "paused-for-cache", format: MPV_FORMAT_FLAG)
    }

    private static func observe(
        api: MPVClientAPI,
        handle: UnsafeMutableRawPointer,
        _ property: MPVObservedProperty,
        name: String,
        format: Int32
    ) throws {
        let result = api.observeProperty(handle, property.rawValue, name, format)
        guard result >= 0 else {
            throw MPVMapper.playbackError(
                fromMPVCode: result,
                api: api,
                fallback: "failed to observe mpv property \(name)"
            )
        }
    }

    private func observe(_ property: MPVObservedProperty, name: String, format: Int32) throws {
        guard let handle else {
            throw PlaybackError.mpvUnavailable
        }

        let result = api.observeProperty(handle, property.rawValue, name, format)
        guard result >= 0 else {
            throw MPVMapper.playbackError(
                fromMPVCode: result,
                api: api,
                fallback: "failed to observe mpv property \(name)"
            )
        }
    }

    private func handleMPVEvent(_ event: MPVEvent) -> [PlaybackEvent] {
        switch event.event_id {
        case MPV_EVENT_NONE:
            return []
        case MPV_EVENT_FILE_LOADED:
            return handleFileLoaded()
        case MPV_EVENT_END_FILE:
            return handleEndFile(event)
        case MPV_EVENT_PROPERTY_CHANGE:
            return handlePropertyChange(event)
        case MPV_EVENT_QUEUE_OVERFLOW:
            return [.playbackFailed(.mpvError("mpv event queue overflow"))]
        case MPV_EVENT_SHUTDOWN:
            shouldRunEventLoop = false
            return []
        default:
            return []
        }
    }

    private func handleFileLoaded() -> [PlaybackEvent] {
        isLoaded = true
        isPaused = true
        isBuffering = false

        var events: [PlaybackEvent] = []
        if let durationMS = readDurationMS() {
            latestDurationMS = durationMS
            events.append(.durationUpdated(durationMS: durationMS))
        }

        if let tracksEvent = readTracksEventIfChanged(force: true) {
            events.append(tracksEvent)
        }

        if let resumePositionMS = pendingResumePositionMS,
           resumePositionMS >= 10_000 {
            do {
                try seekWithoutStateChange(toMS: resumePositionMS)
                latestPositionMS = resumePositionMS
                events.append(.positionUpdated(positionMS: resumePositionMS))
            } catch {
                events.append(.playbackFailed(MPVMapper.playbackError(from: error)))
            }
        }

        pendingResumePositionMS = nil
        events.append(.stateChanged(.ready))
        return events
    }

    private func handleEndFile(_ event: MPVEvent) -> [PlaybackEvent] {
        guard let endFile = event.data?.assumingMemoryBound(to: MPVEventEndFile.self).pointee else {
            return []
        }

        isLoaded = false
        explicitPlayRequested = false
        hasStartedPlayback = false
        isPaused = true
        isBuffering = false

        switch endFile.reason {
        case MPV_END_FILE_REASON_EOF:
            return [
                .playbackEnded(
                    finalPositionMS: latestPositionMS,
                    durationMS: latestDurationMS
                )
            ]
        case MPV_END_FILE_REASON_ERROR:
            return [
                .playbackFailed(
                    MPVMapper.playbackError(
                        fromMPVCode: endFile.error,
                        api: api,
                        playableFile: loadedFile,
                        fallback: "mpv playback failed"
                    )
                )
            ]
        case MPV_END_FILE_REASON_STOP, MPV_END_FILE_REASON_QUIT:
            if suppressNextIdleForUserStop {
                suppressNextIdleForUserStop = false
                return []
            }
            return [.stateChanged(.idle)]
        default:
            return []
        }
    }

    private func handlePropertyChange(_ event: MPVEvent) -> [PlaybackEvent] {
        guard let property = MPVMapper.propertyChange(from: event),
              property.hasValue else {
            return []
        }

        switch property.observedProperty {
        case .pause:
            guard let isPaused = property.flagValue else {
                return []
            }
            return handlePauseChange(isPaused: isPaused)
        case .timePosition:
            guard let seconds = property.doubleValue else {
                return []
            }
            let positionMS = MPVMapper.milliseconds(fromSeconds: seconds)
            latestPositionMS = positionMS
            return [.positionUpdated(positionMS: positionMS)]
        case .duration:
            guard let seconds = property.doubleValue else {
                return []
            }
            let durationMS = MPVMapper.milliseconds(fromSeconds: seconds)
            latestDurationMS = durationMS
            return [.durationUpdated(durationMS: durationMS)]
        case .trackList:
            return readTracksEventIfChanged(force: false).map { [$0] } ?? []
        case .pausedForCache:
            guard let isPausedForCache = property.flagValue else {
                return []
            }
            return handlePausedForCacheChange(isPausedForCache: isPausedForCache)
        }
    }

    private func handlePauseChange(isPaused newValue: Bool) -> [PlaybackEvent] {
        isPaused = newValue

        guard isLoaded else {
            return []
        }

        if newValue {
            guard hasStartedPlayback else {
                return []
            }
            return [.stateChanged(.paused)]
        }

        guard explicitPlayRequested else {
            return []
        }

        hasStartedPlayback = true
        if isBuffering {
            return []
        }
        return [.stateChanged(.playing)]
    }

    private func handlePausedForCacheChange(isPausedForCache: Bool) -> [PlaybackEvent] {
        guard isLoaded else {
            isBuffering = false
            return []
        }

        isBuffering = isPausedForCache
        if isPausedForCache {
            return hasStartedPlayback ? [.stateChanged(.buffering)] : []
        }

        if isPaused {
            return hasStartedPlayback ? [.stateChanged(.paused)] : []
        }

        return explicitPlayRequested ? [.stateChanged(.playing)] : []
    }

    private func readDurationMS() -> Int? {
        guard let handle else {
            return nil
        }

        var duration = 0.0
        let result = api.getProperty(handle, "duration", MPV_FORMAT_DOUBLE, &duration)
        guard result >= 0 else {
            return nil
        }

        return MPVMapper.milliseconds(fromSeconds: duration)
    }

    private func readTracksEventIfChanged(force: Bool) -> PlaybackEvent? {
        guard let handle else {
            return nil
        }

        var node = MPVNode()
        let result = api.getProperty(handle, "track-list", MPV_FORMAT_NODE, &node)
        guard result >= 0 else {
            return nil
        }
        defer {
            api.freeNodeContents(&node)
        }

        let tracks = MPVMapper.tracks(from: node)
        guard force || tracks.audioTracks != audioTracks || tracks.subtitleTracks != subtitleTracks else {
            return nil
        }

        audioTracks = tracks.audioTracks
        subtitleTracks = tracks.subtitleTracks
        return .tracksDiscovered(audioTracks: tracks.audioTracks, subtitleTracks: tracks.subtitleTracks)
    }

    private func validatePlayableFile(_ playableFile: PlayableFile) throws {
        guard playableFile.url.isFileURL else {
            throw PlaybackError.unsupportedFormat
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: playableFile.url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw PlaybackError.fileMissing
        }

        guard FileManager.default.isReadableFile(atPath: playableFile.url.path) else {
            throw PlaybackError.permissionDenied
        }
    }

    private func seekWithoutStateChange(toMS positionMS: Int) throws {
        let seconds = String(
            format: "%.3f",
            locale: Locale(identifier: "en_US_POSIX"),
            Double(positionMS) / 1_000.0
        )
        try command(["seek", seconds, "absolute+exact"])
    }

    private static func createInitializedHandle(api: MPVClientAPI) throws -> UnsafeMutableRawPointer {
        do {
            return try createInitializedHandle(api: api, videoOutput: "gpu-next")
        } catch {
            return try createInitializedHandle(api: api, videoOutput: "gpu")
        }
    }

    private static func createInitializedHandle(
        api: MPVClientAPI,
        videoOutput: String
    ) throws -> UnsafeMutableRawPointer {
        guard let handle = api.create() else {
            throw PlaybackError.mpvUnavailable
        }

        do {
            try setOption(api: api, handle: handle, "terminal", value: "no")
            try setOption(api: api, handle: handle, "config", value: "no")
            try setOption(api: api, handle: handle, "load-scripts", value: "no")
            try setOption(api: api, handle: handle, "idle", value: "yes")
            try setOption(api: api, handle: handle, "keep-open", value: "no")
            try setOption(api: api, handle: handle, "pause", value: "yes")
            // Phase 2 standalone shell smoke validation only; revisit for embedded rendering.
            try setOption(api: api, handle: handle, "force-window", value: "yes")
            try setOption(api: api, handle: handle, "video", value: "auto")
            try setOption(api: api, handle: handle, "vo", value: videoOutput)
            _ = api.setOptionString(handle, "hwdec", "auto-safe")

            let initializeResult = api.initialize(handle)
            guard initializeResult >= 0 else {
                throw MPVMapper.playbackError(
                    fromMPVCode: initializeResult,
                    api: api,
                    fallback: "mpv initialization failed"
                )
            }

            return handle
        } catch {
            api.terminateDestroy(handle)
            throw error
        }
    }

    private static func setOption(
        api: MPVClientAPI,
        handle: UnsafeMutableRawPointer,
        _ name: String,
        value: String
    ) throws {
        let result = api.setOptionString(handle, name, value)
        guard result >= 0 else {
            throw MPVMapper.playbackError(
                fromMPVCode: result,
                api: api,
                fallback: "failed to set mpv option \(name)"
            )
        }
    }

    private func setOption(_ name: String, value: String) throws {
        guard let handle else {
            throw PlaybackError.mpvUnavailable
        }

        let result = api.setOptionString(handle, name, value)
        guard result >= 0 else {
            throw MPVMapper.playbackError(
                fromMPVCode: result,
                api: api,
                fallback: "failed to set mpv option \(name)"
            )
        }
    }

    private func setFlagProperty(_ name: String, value: Bool) throws {
        guard let handle else {
            throw PlaybackError.mpvUnavailable
        }

        var flag: Int32 = value ? 1 : 0
        let result = api.setProperty(handle, name, MPV_FORMAT_FLAG, &flag)
        guard result >= 0 else {
            throw MPVMapper.playbackError(
                fromMPVCode: result,
                api: api,
                fallback: "failed to set mpv property \(name)"
            )
        }
    }

    private func setStringProperty(_ name: String, value: String) throws {
        guard let handle else {
            throw PlaybackError.mpvUnavailable
        }

        let result = api.setPropertyString(handle, name, value)
        guard result >= 0 else {
            throw MPVMapper.playbackError(
                fromMPVCode: result,
                api: api,
                fallback: "failed to set mpv property \(name)"
            )
        }
    }

    private func command(_ arguments: [String]) throws {
        guard let handle else {
            throw PlaybackError.mpvUnavailable
        }

        let result = withMPVCStringArray(arguments) { cArguments in
            api.command(handle, cArguments)
        }

        guard result >= 0 else {
            throw MPVMapper.playbackError(
                fromMPVCode: result,
                api: api,
                playableFile: loadedFile,
                fallback: "mpv command failed"
            )
        }
    }

    private func ensureUsableHandle() throws {
        guard handle != nil, !isDestroyed else {
            throw PlaybackError.mpvUnavailable
        }
    }
}

enum MPVObservedProperty: UInt64 {
    case pause = 1
    case timePosition = 2
    case duration = 3
    case trackList = 4
    case pausedForCache = 5
}

private func withMPVCStringArray<T>(
    _ strings: [String],
    _ body: (UnsafePointer<UnsafePointer<CChar>?>) -> T
) -> T {
    var cStrings: [UnsafePointer<CChar>?] = []

    func appendCString(at index: Int) -> T {
        guard index < strings.count else {
            cStrings.append(nil)
            return cStrings.withUnsafeBufferPointer { buffer in
                body(buffer.baseAddress!)
            }
        }

        return strings[index].withCString { pointer in
            cStrings.append(pointer)
            return appendCString(at: index + 1)
        }
    }

    return appendCString(at: 0)
}
