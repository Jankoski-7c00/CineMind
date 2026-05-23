import AppUI
import Application
import AppKit
import SwiftUI

struct CineMindApp: App {
    @StateObject private var viewModel = AppShellViewModel()
    @StateObject private var playbackKeyboardShortcuts = PlaybackKeyboardShortcutMonitor()
    @State private var playbackRuntime: CineMindPlaybackRuntime?

    var body: some Scene {
        WindowGroup {
            CineMindRootView(
                viewModel: viewModel,
                playbackSurface: playbackSurface
            )
                .task {
                    activateApplication()
                    playbackKeyboardShortcuts.install(
                        togglePlayPause: { togglePlayPause() },
                        seekRelative: { seekRelative(byMS: $0) }
                    )
                    startAppIfNeeded()
                }
        }
        .commands {
            CommandMenu("Playback") {
                Button("Toggle Play/Pause") {
                    togglePlayPause()
                }

                Button("Seek Backward 10 Seconds") {
                    seekRelative(byMS: -10_000)
                }

                Button("Seek Forward 10 Seconds") {
                    seekRelative(byMS: 10_000)
                }
            }
        }
    }

    private var playbackSurface: AnyView? {
        guard let playbackRuntime else {
            return nil
        }

        return AnyView(
            PlaybackAVFoundationSurfaceView(backend: playbackRuntime.backend)
        )
    }

    @MainActor
    private func activateApplication() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    private var playbackController: (any PlaybackApplicationControlling)? {
        playbackRuntime?.controller ?? viewModel.environment?.playbackController
    }

    @MainActor
    private func togglePlayPause() {
        guard let controller = playbackController else {
            return
        }

        Task {
            await controller.togglePlayPause()
        }
    }

    @MainActor
    private func seekRelative(byMS deltaMS: Int) {
        guard let controller = playbackController else {
            return
        }

        Task {
            await controller.seekRelative(byMS: deltaMS)
        }
    }

    @MainActor
    private func startAppIfNeeded() {
        guard StartupRunGuard.claim() else {
            return
        }

        viewModel.markLoading()

        do {
            let startup = try CineMindAppEnvironmentFactory.start()
            playbackRuntime = startup.playbackRuntime
            viewModel.markReady(environment: startup.appShellEnvironment)
        } catch {
            viewModel.markFailed(
                CineMindAppEnvironmentFactory.startupFailureMessage(for: error)
            )
        }
    }
}

@MainActor
private enum StartupRunGuard {
    private static var didRun = false

    static func claim() -> Bool {
        guard !didRun else {
            return false
        }

        didRun = true
        return true
    }
}

CineMindApp.main()
