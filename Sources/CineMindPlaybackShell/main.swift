import Application
import Foundation
import LibMPVPlayback
import Persistence
import Playback
import Shared

@main
enum CineMindPlaybackShell {
    static func main() async {
        do {
            let mode = try ShellArguments.parse(CommandLine.arguments)
            switch mode {
            case .help:
                printUsage()
            case .directFile(let path):
                let playableFile = try makeDirectPlayableFile(path: path)
                try await runPlayback(
                    playableFile: playableFile,
                    progressCoordinator: nil
                )
            case .library(let databasePath, let mediaFileID):
                let context = try makeLibraryPlaybackContext(
                    databasePath: databasePath,
                    mediaFileID: mediaFileID
                )
                try await runPlayback(
                    playableFile: context.playableFile,
                    progressCoordinator: context.progressCoordinator
                )
            }
        } catch let error as ShellError {
            writeError(error.description)
            if error.shouldPrintUsage {
                printUsage()
            }
            exit(Int32(error.exitCode))
        } catch {
            writeError("Playback shell failed: \(error)")
            exit(1)
        }
    }

    private static func runPlayback(
        playableFile: Playback.PlayableFile,
        progressCoordinator: PlaybackProgressCoordinator?
    ) async throws {
        let backend = try LibMPVPlaybackBackend()
        let coordinator = PlaybackCoordinator(backend: backend)
        let stateStore = PlaybackShellState()

        print("\(CineMindBuildInfo.productName) Playback Shell")
        print("Opening: \(playableFile.displayName)")
        if let resumePositionMS = playableFile.resumePositionMS {
            print("Resume: \(formatTime(milliseconds: resumePositionMS))")
        }
        print("Commands: p, s, q, seek +10, seek -10")

        await progressCoordinator?.startSession(
            mediaItemID: playableFile.mediaItemID,
            mediaFileID: playableFile.mediaFileID,
            initialPositionMS: playableFile.resumePositionMS ?? 0
        )

        let eventTask = Task {
            await consumeEvents(
                coordinator: coordinator,
                stateStore: stateStore,
                progressCoordinator: progressCoordinator
            )
        }

        await coordinator.open(playableFile)
        await runCommandLoop(
            coordinator: coordinator,
            stateStore: stateStore,
            progressCoordinator: progressCoordinator
        )
        eventTask.cancel()
        _ = await eventTask.result
    }

    private static func consumeEvents(
        coordinator: PlaybackCoordinator,
        stateStore: PlaybackShellState,
        progressCoordinator: PlaybackProgressCoordinator?
    ) async {
        var didRequestInitialPlay = false
        var lastPositionPrintTime = Date.distantPast
        var lastPrintedPositionSecond: Int?

        for await event in coordinator.events {
            guard !Task.isCancelled else {
                return
            }

            await stateStore.apply(event)
            await persistProgress(event, progressCoordinator: progressCoordinator)

            switch event {
            case .stateChanged(let state):
                print("State: \(state.label)")
                if state == .ready, !didRequestInitialPlay {
                    didRequestInitialPlay = true
                    await coordinator.play()
                }
            case .positionUpdated(let positionMS):
                let positionSecond = positionMS / 1_000
                let now = Date()
                if positionSecond != lastPrintedPositionSecond,
                   now.timeIntervalSince(lastPositionPrintTime) >= 1.0 {
                    lastPrintedPositionSecond = positionSecond
                    lastPositionPrintTime = now
                    let snapshot = await stateStore.snapshot()
                    if let durationMS = snapshot.durationMS {
                        print(
                            "Position: \(formatTime(milliseconds: positionMS)) / \(formatTime(milliseconds: durationMS))"
                        )
                    } else {
                        print("Position: \(formatTime(milliseconds: positionMS))")
                    }
                }
            case .durationUpdated(let durationMS):
                print("Duration: \(formatTime(milliseconds: durationMS))")
            case .tracksDiscovered(let audioTracks, let subtitleTracks):
                printTracks(audioTracks: audioTracks, subtitleTracks: subtitleTracks)
            case .playbackEnded(let finalPositionMS, let durationMS):
                if let durationMS {
                    print(
                        "Playback ended: \(formatTime(milliseconds: finalPositionMS)) / \(formatTime(milliseconds: durationMS))"
                    )
                } else {
                    print("Playback ended: \(formatTime(milliseconds: finalPositionMS))")
                }
            case .playbackFailed(let error):
                print("Playback failed: \(error.label)")
            }
        }
    }

    private static func runCommandLoop(
        coordinator: PlaybackCoordinator,
        stateStore: PlaybackShellState,
        progressCoordinator: PlaybackProgressCoordinator?
    ) async {
        while let rawLine = readLine() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            if await handleCommand(
                line,
                coordinator: coordinator,
                stateStore: stateStore,
                progressCoordinator: progressCoordinator
            ) {
                await shutdown(
                    coordinator: coordinator,
                    progressCoordinator: progressCoordinator
                )
                return
            }
        }

        await shutdown(
            coordinator: coordinator,
            progressCoordinator: progressCoordinator
        )
    }

    private static func handleCommand(
        _ line: String,
        coordinator: PlaybackCoordinator,
        stateStore: PlaybackShellState,
        progressCoordinator: PlaybackProgressCoordinator?
    ) async -> Bool {
        switch line {
        case "q", "quit":
            return true
        case "s", "stop":
            await coordinator.stop()
        case "p":
            await togglePlayPause(coordinator: coordinator, stateStore: stateStore)
        default:
            if line.hasPrefix("seek ") {
                await handleSeek(
                    line,
                    coordinator: coordinator,
                    stateStore: stateStore,
                    progressCoordinator: progressCoordinator
                )
            } else {
                print("Unknown command: \(line)")
                print("Commands: p, s, q, seek +10, seek -10")
            }
        }

        return false
    }

    private static func togglePlayPause(
        coordinator: PlaybackCoordinator,
        stateStore: PlaybackShellState
    ) async {
        let snapshot = await stateStore.snapshot()
        guard let state = snapshot.state else {
            print("Play/pause ignored because playback state is unknown.")
            return
        }

        switch state {
        case .ready, .paused, .buffering:
            await coordinator.play()
        case .playing:
            await coordinator.pause()
        case .idle, .loading, .ended, .failed:
            print("Play/pause ignored while playback is \(state.label).")
        }
    }

    private static func handleSeek(
        _ line: String,
        coordinator: PlaybackCoordinator,
        stateStore: PlaybackShellState,
        progressCoordinator: PlaybackProgressCoordinator?
    ) async {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 2, let seconds = Int(parts[1]) else {
            print("Usage: seek +10 or seek -10")
            return
        }

        let snapshot = await stateStore.snapshot()
        guard let state = snapshot.state else {
            print("Seek ignored because playback state is unknown.")
            return
        }

        switch state {
        case .ready, .playing, .paused, .buffering:
            let deltaMS = seconds * 1_000
            var targetMS = max(0, snapshot.positionMS + deltaMS)
            if let durationMS = snapshot.durationMS {
                targetMS = min(targetMS, durationMS)
            }
            print("Seek: \(formatTime(milliseconds: targetMS))")
            await progressCoordinator?.noteSeekRequested()
            await coordinator.seek(toMS: targetMS)
        case .idle, .loading, .ended, .failed:
            print("Seek ignored while playback is \(state.label).")
        }
    }

    private static func shutdown(
        coordinator: PlaybackCoordinator,
        progressCoordinator: PlaybackProgressCoordinator?
    ) async {
        if let progressCoordinator {
            do {
                try await progressCoordinator.closeSession()
            } catch {
                writeWarning("Playback progress persistence warning: \(error)")
            }
        }

        let activeSession = await coordinator.activeSession
        if activeSession != nil {
            await coordinator.stop()
        }
        await coordinator.shutdown()
    }

    private static func makeDirectPlayableFile(path: String) throws -> Playback.PlayableFile {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ShellError.fileNotFound(path)
        }
        guard !isDirectory.boolValue else {
            throw ShellError.pathIsDirectory(path)
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw ShellError.fileNotReadable(path)
        }

        return Playback.PlayableFile(
            mediaItemID: "direct-file",
            mediaFileID: "direct-file",
            url: url,
            displayName: url.lastPathComponent,
            resumePositionMS: nil
        )
    }

    private static func makeLibraryPlaybackContext(
        databasePath: String,
        mediaFileID: String
    ) throws -> LibraryPlaybackContext {
        let databaseURL = URL(fileURLWithPath: databasePath).standardizedFileURL
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw ShellError.databaseNotFound(databasePath)
        }

        let store = try CineMindStore(path: databaseURL.path)
        let applicationPlayableFile = try OpenMediaUseCase(store: store).open(mediaFileID: mediaFileID)
        return LibraryPlaybackContext(
            playableFile: mapToPlaybackPlayableFile(applicationPlayableFile),
            progressCoordinator: PlaybackProgressCoordinator(
                progressUseCase: PlaybackProgressUseCase(store: store)
            )
        )
    }

    private static func mapToPlaybackPlayableFile(
        _ playableFile: Application.PlayableFile
    ) -> Playback.PlayableFile {
        Playback.PlayableFile(
            mediaItemID: playableFile.mediaItemID,
            mediaFileID: playableFile.mediaFileID,
            url: playableFile.url,
            displayName: playableFile.displayName,
            resumePositionMS: playableFile.resumePositionMS
        )
    }

    private static func printUsage() {
        print("""
        Usage:
          CineMindPlaybackShell --file <video-file>
          CineMindPlaybackShell --db <cinemind.sqlite> --media-file-id <id>

        Commands while running:
          p             play/pause toggle
          s             stop
          q             quit
          seek +10      seek forward 10 seconds
          seek -10      seek backward 10 seconds
        """)
    }

    private static func persistProgress(
        _ event: PlaybackEvent,
        progressCoordinator: PlaybackProgressCoordinator?
    ) async {
        guard let progressCoordinator else {
            return
        }

        do {
            try await progressCoordinator.handle(event)
        } catch {
            writeWarning("Playback progress persistence warning: \(error)")
        }
    }
}

private struct LibraryPlaybackContext {
    let playableFile: Playback.PlayableFile
    let progressCoordinator: PlaybackProgressCoordinator
}

private actor PlaybackShellState {
    private var latestState: PlaybackState?
    private var latestPositionMS = 0
    private var latestDurationMS: Int?

    func apply(_ event: PlaybackEvent) {
        switch event {
        case .stateChanged(let state):
            latestState = state
        case .positionUpdated(let positionMS):
            latestPositionMS = positionMS
        case .durationUpdated(let durationMS):
            latestDurationMS = durationMS
        case .playbackEnded(let finalPositionMS, let durationMS):
            latestState = .ended
            latestPositionMS = finalPositionMS
            latestDurationMS = durationMS
        case .playbackFailed:
            latestState = .failed
        case .tracksDiscovered:
            break
        }
    }

    func snapshot() -> PlaybackShellSnapshot {
        PlaybackShellSnapshot(
            state: latestState,
            positionMS: latestPositionMS,
            durationMS: latestDurationMS
        )
    }
}

private struct PlaybackShellSnapshot: Sendable {
    let state: PlaybackState?
    let positionMS: Int
    let durationMS: Int?
}

private enum ShellArguments {
    case help
    case directFile(path: String)
    case library(databasePath: String, mediaFileID: String)

    static func parse(_ arguments: [String]) throws -> ShellArguments {
        let values = Array(arguments.dropFirst())
        if values.isEmpty || values == ["--help"] || values == ["-h"] {
            return .help
        }

        var filePath: String?
        var databasePath: String?
        var mediaFileID: String?
        var index = 0

        while index < values.count {
            let flag = values[index]
            switch flag {
            case "--file":
                guard filePath == nil else {
                    throw ShellError.invalidArguments("Duplicate --file flag.")
                }
                index += 1
                guard index < values.count else {
                    throw ShellError.invalidArguments("Missing value for --file.")
                }
                filePath = values[index]
            case "--db":
                guard databasePath == nil else {
                    throw ShellError.invalidArguments("Duplicate --db flag.")
                }
                index += 1
                guard index < values.count else {
                    throw ShellError.invalidArguments("Missing value for --db.")
                }
                databasePath = values[index]
            case "--media-file-id":
                guard mediaFileID == nil else {
                    throw ShellError.invalidArguments("Duplicate --media-file-id flag.")
                }
                index += 1
                guard index < values.count else {
                    throw ShellError.invalidArguments("Missing value for --media-file-id.")
                }
                mediaFileID = values[index]
            default:
                throw ShellError.invalidArguments("Unknown argument: \(flag)")
            }

            index += 1
        }

        if let filePath {
            guard databasePath == nil, mediaFileID == nil else {
                throw ShellError.invalidArguments("--file cannot be combined with --db or --media-file-id.")
            }
            return .directFile(path: filePath)
        }

        if let databasePath, let mediaFileID {
            return .library(databasePath: databasePath, mediaFileID: mediaFileID)
        }

        if databasePath != nil {
            throw ShellError.invalidArguments("--db requires --media-file-id.")
        }
        if mediaFileID != nil {
            throw ShellError.invalidArguments("--media-file-id requires --db.")
        }

        throw ShellError.invalidArguments("Expected a playback mode.")
    }
}

private enum ShellError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case fileNotFound(String)
    case pathIsDirectory(String)
    case fileNotReadable(String)
    case databaseNotFound(String)

    var description: String {
        switch self {
        case .invalidArguments(let message):
            message
        case .fileNotFound(let path):
            "Video file not found: \(path)"
        case .pathIsDirectory(let path):
            "Expected a video file but found a directory: \(path)"
        case .fileNotReadable(let path):
            "Video file is not readable: \(path)"
        case .databaseNotFound(let path):
            "SQLite database not found: \(path)"
        }
    }

    var exitCode: Int {
        switch self {
        case .invalidArguments:
            2
        case .fileNotFound, .pathIsDirectory, .fileNotReadable, .databaseNotFound:
            1
        }
    }

    var shouldPrintUsage: Bool {
        if case .invalidArguments = self {
            return true
        }
        return false
    }
}

private extension PlaybackState {
    var label: String {
        switch self {
        case .idle:
            "idle"
        case .loading:
            "loading"
        case .ready:
            "ready"
        case .playing:
            "playing"
        case .paused:
            "paused"
        case .buffering:
            "buffering"
        case .ended:
            "ended"
        case .failed:
            "failed"
        }
    }
}

private extension PlaybackError {
    var label: String {
        switch self {
        case .fileMissing:
            "file missing"
        case .permissionDenied:
            "permission denied"
        case .unsupportedFormat:
            "unsupported format"
        case .mpvUnavailable:
            "mpv unavailable"
        case .mpvError(let message):
            "mpv error: \(message)"
        case .invalidState(let message):
            "invalid state: \(message)"
        case .unknown(let message):
            "unknown error: \(message)"
        }
    }
}

private func printTracks(
    audioTracks: [PlaybackTrack],
    subtitleTracks: [PlaybackTrack]
) {
    print("Tracks discovered: audio=\(audioTracks.count), subtitles=\(subtitleTracks.count)")
    for track in audioTracks {
        print("  audio \(trackDescription(track))")
    }
    for track in subtitleTracks {
        print("  subtitle \(trackDescription(track))")
    }
}

private func trackDescription(_ track: PlaybackTrack) -> String {
    var details = ["id=\(track.id)"]
    if let language = track.language, !language.isEmpty {
        details.append("lang=\(language)")
    }
    if let title = track.title, !title.isEmpty {
        details.append("title=\(title)")
    }
    if track.isDefault {
        details.append("default")
    }
    if track.isSelected {
        details.append("selected")
    }
    return details.joined(separator: " ")
}

private func formatTime(milliseconds: Int) -> String {
    let totalSeconds = max(0, milliseconds / 1_000)
    let hours = totalSeconds / 3_600
    let minutes = (totalSeconds % 3_600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%02d:%02d", minutes, seconds)
}

private func writeError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

private func writeWarning(_ message: String) {
    FileHandle.standardError.write(Data(("Warning: " + message + "\n").utf8))
}
