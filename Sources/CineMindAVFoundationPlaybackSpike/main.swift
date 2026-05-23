import AppKit
import AVFoundation
import AVKit
import Foundation

private let defaultFixturePath = "Tests/Fixtures/Videos/Please_stop_buying_the_wrong_SSD.mp4"

@main
@MainActor
final class CineMindAVFoundationPlaybackSpike: NSObject, NSApplicationDelegate, NSWindowDelegate, @unchecked Sendable {
    private static let validationTailSeconds = 3.0

    private var window: NSWindow?
    private var playerView: AVPlayerView?
    private var player: AVPlayer?
    private var item: AVPlayerItem?
    private var itemStatusObservation: NSKeyValueObservation?
    private var timeControlStatusObservation: NSKeyValueObservation?
    private var durationObservation: NSKeyValueObservation?
    private var periodicTimeObserver: Any?
    private var endNotificationObserver: NSObjectProtocol?
    private var failureNotificationObserver: NSObjectProtocol?
    private var didStartPlayback = false
    private var didSeekNearEnd = false
    private var didFinish = false
    private var lastLoggedPositionSecond: Int?
    private var shouldSeekNearEnd = true

    static func main() {
        let application = NSApplication.shared
        let delegate = CineMindAVFoundationPlaybackSpike()
        application.delegate = delegate
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let launchOptions = try LaunchOptions(arguments: Array(CommandLine.arguments.dropFirst()))
            shouldSeekNearEnd = launchOptions.seekNearEndForValidation
            try startPlayback(fileURL: launchOptions.fileURL)
        } catch let error as LaunchError {
            log("failed", [
                ("phase", quoted("launch")),
                ("message", quoted(error.message))
            ])
            NSApp.terminate(nil)
        } catch {
            log("failed", [
                ("phase", quoted("launch")),
                ("message", quoted("Unable to start playback spike."))
            ])
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        cleanup()
        return .terminateNow
    }

    func windowWillClose(_ notification: Notification) {
        cleanup()
        NSApp.terminate(nil)
    }

    private func startPlayback(fileURL: URL) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw LaunchError("File does not exist: \(fileURL.path)")
        }

        log("loading", [
            ("path", quoted(fileURL.path)),
            ("url", quoted(fileURL.absoluteString))
        ])

        let item = AVPlayerItem(url: fileURL)
        let player = AVPlayer(playerItem: item)
        let playerView = AVPlayerView(frame: NSRect(x: 0, y: 0, width: 960, height: 540))
        playerView.player = player
        playerView.controlsStyle = .floating
        playerView.videoGravity = .resizeAspect

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "CineMind AVFoundation Playback Spike"
        window.contentView = playerView
        window.delegate = self
        window.makeKeyAndOrderFront(nil)

        self.item = item
        self.player = player
        self.playerView = playerView
        self.window = window

        installObservers(item: item, player: player)

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installObservers(item: AVPlayerItem, player: AVPlayer) {
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                self?.handleItemStatus(item.status, item: item)
            }
        }

        timeControlStatusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                self?.handleTimeControlStatus(player.timeControlStatus, player: player)
            }
        }

        durationObservation = item.observe(\.duration, options: [.initial, .new]) { item, _ in
            DispatchQueue.main.async {
                guard let duration = milliseconds(from: item.duration) else {
                    return
                }
                log("duration", [("duration_ms", "\(duration)")])
            }
        }

        periodicTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.logPosition(time: time)
            }
        }

        endNotificationObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlePlaybackEnded()
            }
        }

        failureNotificationObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let errorDescription = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
            Task { @MainActor [weak self] in
                self?.handleFailure(
                    message: "Playback failed before reaching the end.",
                    errorDescription: errorDescription
                )
            }
        }
    }

    private func handleItemStatus(_ status: AVPlayerItem.Status, item: AVPlayerItem) {
        guard !didFinish else {
            return
        }

        switch status {
        case .unknown:
            log("status", [("item_status", quoted("unknown"))])
        case .readyToPlay:
            let duration = milliseconds(from: item.duration)
            var fields = [("item_status", quoted("readyToPlay"))]
            if let duration {
                fields.append(("duration_ms", "\(duration)"))
            }
            log("ready", fields)
            beginPlayback(item: item)
        case .failed:
            handleFailure(
                message: "Unsupported, unreadable, or failed media item.",
                errorDescription: item.error?.localizedDescription
            )
        @unknown default:
            log("status", [("item_status", quoted("unknown_future_case"))])
        }
    }

    private func beginPlayback(item: AVPlayerItem) {
        guard !didStartPlayback, let player else {
            return
        }

        didStartPlayback = true

        if shouldSeekNearEnd,
           let durationSeconds = finiteSeconds(from: item.duration),
           durationSeconds > Self.validationTailSeconds + 1 {
            didSeekNearEnd = true
            let target = CMTime(seconds: durationSeconds - Self.validationTailSeconds, preferredTimescale: 600)
            log("seek_near_end", [
                ("target_ms", "\(milliseconds(from: target) ?? 0)"),
                ("reason", quoted("validation_shortcut"))
            ])
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
                DispatchQueue.main.async {
                    guard completed else {
                        self?.handleFailure(message: "Unable to seek before playback.", errorDescription: nil)
                        return
                    }
                    self?.player?.play()
                }
            }
        } else {
            player.play()
        }
    }

    private func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus, player: AVPlayer) {
        guard !didFinish else {
            return
        }

        switch status {
        case .paused:
            log("paused", [("rate", "\(player.rate)")])
        case .waitingToPlayAtSpecifiedRate:
            log("waiting", [
                ("reason", quoted(waitingReasonDescription(player.reasonForWaitingToPlay)))
            ])
        case .playing:
            log("playing", [("rate", "\(player.rate)")])
        @unknown default:
            log("status", [("time_control_status", quoted("unknown_future_case"))])
        }
    }

    private func logPosition(time: CMTime) {
        guard !didFinish,
              let positionSeconds = finiteSeconds(from: time) else {
            return
        }

        let wholeSecond = Int(positionSeconds)
        guard wholeSecond != lastLoggedPositionSecond else {
            return
        }
        lastLoggedPositionSecond = wholeSecond

        var fields: [(String, String)] = [
            ("position_ms", "\(milliseconds(from: time) ?? 0)")
        ]
        if let duration = item.flatMap({ milliseconds(from: $0.duration) }) {
            fields.append(("duration_ms", "\(duration)"))
        }
        log("position", fields)
    }

    private func handlePlaybackEnded() {
        guard !didFinish else {
            return
        }

        didFinish = true
        var fields: [(String, String)] = []
        if let player {
            fields.append(("position_ms", "\(milliseconds(from: player.currentTime()) ?? 0)"))
        }
        if let duration = item.flatMap({ milliseconds(from: $0.duration) }) {
            fields.append(("duration_ms", "\(duration)"))
        }
        if didSeekNearEnd {
            fields.append(("validation_seek", quoted("true")))
        }
        log("ended", fields)
        cleanup()
        NSApp.terminate(nil)
    }

    private func handleFailure(message: String, errorDescription: String?) {
        guard !didFinish else {
            return
        }

        didFinish = true
        var fields: [(String, String)] = [
            ("message", quoted(message))
        ]
        if let errorDescription {
            fields.append(("detail", quoted(errorDescription)))
        }
        log("failed", fields)
        cleanup()
        NSApp.terminate(nil)
    }

    private func cleanup() {
        if let periodicTimeObserver, let player {
            player.removeTimeObserver(periodicTimeObserver)
        }
        periodicTimeObserver = nil

        if let endNotificationObserver {
            NotificationCenter.default.removeObserver(endNotificationObserver)
        }
        endNotificationObserver = nil

        if let failureNotificationObserver {
            NotificationCenter.default.removeObserver(failureNotificationObserver)
        }
        failureNotificationObserver = nil

        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        timeControlStatusObservation?.invalidate()
        timeControlStatusObservation = nil
        durationObservation?.invalidate()
        durationObservation = nil

        player?.pause()
        playerView?.player = nil
        player = nil
        item = nil
    }
}

private struct LaunchOptions {
    let fileURL: URL
    let seekNearEndForValidation: Bool

    init(arguments: [String]) throws {
        var seekNearEndForValidation = true
        var filePath: String?

        for argument in arguments {
            switch argument {
            case "--help", "-h":
                throw LaunchError("Usage: CineMindAVFoundationPlaybackSpike [--play-full] [path]")
            case "--play-full":
                seekNearEndForValidation = false
            default:
                if filePath == nil {
                    filePath = argument
                } else {
                    throw LaunchError("Expected at most one local file path.")
                }
            }
        }

        let selectedPath = filePath ?? defaultFixturePath
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        self.fileURL = URL(fileURLWithPath: selectedPath, relativeTo: currentDirectory).standardizedFileURL
        self.seekNearEndForValidation = seekNearEndForValidation
    }
}

private struct LaunchError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

private func finiteSeconds(from time: CMTime) -> Double? {
    let seconds = CMTimeGetSeconds(time)
    guard seconds.isFinite, !seconds.isNaN else {
        return nil
    }
    return seconds
}

private func milliseconds(from time: CMTime) -> Int? {
    guard let seconds = finiteSeconds(from: time) else {
        return nil
    }
    return Int((seconds * 1000).rounded())
}

private func waitingReasonDescription(_ reason: AVPlayer.WaitingReason?) -> String {
    guard let reason else {
        return "unspecified"
    }
    switch reason {
    case .evaluatingBufferingRate:
        return "evaluatingBufferingRate"
    case .toMinimizeStalls:
        return "toMinimizeStalls"
    case .noItemToPlay:
        return "noItemToPlay"
    default:
        return reason.rawValue
    }
}

private func quoted(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
}

private func log(_ event: String, _ fields: [(String, String)] = []) {
    let fieldText = fields.map { "\($0)=\($1)" }.joined(separator: " ")
    if fieldText.isEmpty {
        print("event=\(event)")
    } else {
        print("event=\(event) \(fieldText)")
    }
    fflush(stdout)
}
