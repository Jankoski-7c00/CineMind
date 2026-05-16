import AppUI
import SwiftUI

struct CineMindApp: App {
    @StateObject private var viewModel = AppShellViewModel()

    var body: some Scene {
        WindowGroup {
            CineMindRootView(viewModel: viewModel)
                .task {
                    startAppIfNeeded()
                }
        }
    }

    @MainActor
    private func startAppIfNeeded() {
        guard StartupRunGuard.claim() else {
            return
        }

        viewModel.state = CineMindAppEnvironmentFactory.startupState()
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
