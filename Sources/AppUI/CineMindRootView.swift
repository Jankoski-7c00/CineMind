import SwiftUI

public struct CineMindRootView: View {
    @StateObject private var viewModel: AppShellViewModel

    public init(viewModel: AppShellViewModel = AppShellViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        switch viewModel.state {
        case .loading:
            loadingView
        case .ready:
            shellView
        case .failed(let message):
            errorView(message)
        }
    }

    private var loadingView: some View {
        ProgressView("Loading Library...")
    }

    private var shellView: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            Text("Select an item")
                .foregroundColor(.secondary)
        } detail: {
            Text("Detail")
                .foregroundColor(.secondary)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.yellow)
            Text("Failed to Start")
                .font(.headline)
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
