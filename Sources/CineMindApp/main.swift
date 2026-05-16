import AppUI
import SwiftUI

@main
struct CineMindApp: App {
    @StateObject private var viewModel = AppShellViewModel(state: .ready)

    var body: some Scene {
        WindowGroup {
            CineMindRootView(viewModel: viewModel)
        }
    }
}
