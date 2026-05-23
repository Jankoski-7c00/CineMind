import AppUI
import SwiftUI

struct CineMindApp: App {
    @StateObject private var viewModel = AppShellViewModel()
    @State private var playbackRuntime: CineMindPlaybackRuntime?

    var body: some Scene {
        WindowGroup {
            CineMindRootView(
                viewModel: viewModel,
                playbackSurface: playbackSurface
            )
                .task {
                    startAppIfNeeded()
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
