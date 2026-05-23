import AppKit
import LibMPVPlayback
import Playback

@main
final class CineMindPlaybackSurfaceSpike: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let filePath: String
    private let playableFile: PlayableFile
    private var window: NSWindow?
    private var backend: LibMPVPlaybackBackend?
    private var coordinator: PlaybackCoordinator?
    private var playbackTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var hasAutoPlayed = false
    private var lastLoggedPositionMS = -1_000
    private var isShuttingDown = false
    private var didCompleteShutdown = false

    private init(filePath: String) {
        self.filePath = filePath
        self.playableFile = makePlayableFile(filePath: filePath)
        super.init()
    }

    static func main() {
        do {
            let filePath = try parseFilePath(CommandLine.arguments)
            print("CineMindPlaybackSurfaceSpike starting")
            print("Selected file: \(filePath)")

            let app = NSApplication.shared
            let delegate = CineMindPlaybackSurfaceSpike(filePath: filePath)
            app.delegate = delegate
            app.setActivationPolicy(.regular)
            app.run()
        } catch let error as SpikeError {
            writeError(error.description)
            printUsage()
            exit(2)
        } catch {
            writeError("Unexpected error: \(error)")
            exit(1)
        }
    }

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        let openGLView = makeOpenGLView()
        openGLView.renderAfterSurfaceChange = { [weak self] in
            self?.backend?.renderSurfaceNow()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "CineMind Playback Surface Spike"
        window.contentView = openGLView
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window

        print("Window shown")
        NSApp.activate(ignoringOtherApps: true)
        startPlayback(using: openGLView)
    }

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !didCompleteShutdown else {
            return .terminateNow
        }

        Task { @MainActor [weak self] in
            await self?.shutdownPlayback()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        print("App exiting")
    }

    @MainActor
    func windowWillClose(_ notification: Notification) {
        print("Window will close")
        Task { @MainActor [weak self] in
            await self?.shutdownPlayback()
            NSApp.terminate(nil)
        }
    }

    @MainActor
    private func startPlayback(using openGLView: NSOpenGLView) {
        do {
            let backend = try LibMPVPlaybackBackend(mode: .embedded)
            try backend.attachRenderSurface(openGLView)
            let coordinator = PlaybackCoordinator(backend: backend)
            self.backend = backend
            self.coordinator = coordinator
            startEventLogging(coordinator: coordinator)

            playbackTask = Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                do {
                    print("Preparing embedded render surface")
                    try await backend.prepareRenderSurface()
                    print("Opening file through PlaybackCoordinator: \(self.filePath)")
                    await coordinator.open(self.playableFile)
                } catch {
                    writeError("Playback surface startup failed: \(error)")
                    await self.shutdownPlayback()
                    NSApp.terminate(nil)
                }
            }
        } catch {
            writeError("Failed to create embedded playback backend: \(error)")
            Task { @MainActor [weak self] in
                await self?.shutdownPlayback()
                NSApp.terminate(nil)
            }
        }
    }

    @MainActor
    private func startEventLogging(coordinator: PlaybackCoordinator) {
        eventTask = Task { @MainActor [weak self] in
            for await event in coordinator.events {
                self?.handlePlaybackEvent(event, coordinator: coordinator)
            }
        }
    }

    @MainActor
    private func handlePlaybackEvent(_ event: PlaybackEvent, coordinator: PlaybackCoordinator) {
        switch event {
        case .stateChanged(let state):
            print("Playback state: \(state)")
            if state == .ready, !hasAutoPlayed {
                hasAutoPlayed = true
                Task {
                    await coordinator.play()
                }
            }
        case .durationUpdated(let durationMS):
            print("Duration: \(durationMS) ms")
        case .positionUpdated(let positionMS):
            guard positionMS - lastLoggedPositionMS >= 1_000 else {
                return
            }
            lastLoggedPositionMS = positionMS
            print("Position: \(positionMS) ms")
        case .playbackFailed(let error):
            print("Playback error: \(error)")
        case .playbackEnded(let finalPositionMS, let durationMS):
            print("Playback ended at \(finalPositionMS) ms, duration: \(durationMS.map(String.init) ?? "unknown")")
        case .tracksDiscovered:
            break
        }
    }

    @MainActor
    private func shutdownPlayback() async {
        guard !isShuttingDown else {
            return
        }

        isShuttingDown = true
        print("Stopping playback")
        playbackTask?.cancel()
        playbackTask = nil
        eventTask?.cancel()
        eventTask = nil

        if let coordinator {
            await coordinator.shutdown()
        }

        coordinator = nil
        backend = nil
        didCompleteShutdown = true
        print("Playback shutdown complete")
    }

    @MainActor
    private func makeOpenGLView() -> SpikeOpenGLView {
        let attributes: [NSOpenGLPixelFormatAttribute] = [
            UInt32(NSOpenGLPFADoubleBuffer),
            UInt32(NSOpenGLPFAAccelerated),
            0
        ]

        guard let pixelFormat = NSOpenGLPixelFormat(attributes: attributes) else {
            fatalError("Failed to create NSOpenGLPixelFormat")
        }

        guard let view = SpikeOpenGLView(frame: .zero, pixelFormat: pixelFormat) else {
            fatalError("Failed to create NSOpenGLView")
        }
        return view
    }
}

private enum SpikeError: Error, CustomStringConvertible {
    case invalidArguments(String)

    var description: String {
        switch self {
        case .invalidArguments(let message):
            return message
        }
    }
}

private func parseFilePath(_ arguments: [String]) throws -> String {
    let values = Array(arguments.dropFirst())
    guard values.count == 2 else {
        throw SpikeError.invalidArguments("Expected exactly --file <path>.")
    }

    guard values[0] == "--file" else {
        throw SpikeError.invalidArguments("Unknown argument: \(values[0])")
    }

    let filePath = values[1].trimmingCharacters(in: .whitespacesAndNewlines)
    guard !filePath.isEmpty else {
        throw SpikeError.invalidArguments("Missing value for --file.")
    }

    return filePath
}

private func makePlayableFile(filePath: String) -> PlayableFile {
    let url = URL(fileURLWithPath: filePath).standardizedFileURL
    return PlayableFile(
        mediaItemID: "surface-spike",
        mediaFileID: url.path,
        url: url,
        displayName: url.lastPathComponent,
        resumePositionMS: nil
    )
}

private final class SpikeOpenGLView: NSOpenGLView {
    var renderAfterSurfaceChange: (() -> Void)?

    override func reshape() {
        super.reshape()
        openGLContext?.update()
        renderAfterSurfaceChange?()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        openGLContext?.update()
        renderAfterSurfaceChange?()
    }
}

private func printUsage() {
    print("""
    Usage:
      CineMindPlaybackSurfaceSpike --file <video-file>
    """)
}

private func writeError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
