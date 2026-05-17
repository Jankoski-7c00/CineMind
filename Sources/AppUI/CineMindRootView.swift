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

    @ViewBuilder
    private var shellView: some View {
        if let environment = viewModel.environment {
            ReadyShellView(environment: environment)
        } else {
            NavigationSplitView {
                SidebarView(selectedSection: .constant(.library))
            } content: {
                Text("Select an item")
                    .foregroundColor(.secondary)
            } detail: {
                Text("Detail")
                    .foregroundColor(.secondary)
            }
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

fileprivate struct ReadyShellView: View {
    let environment: AppShellEnvironment
    @StateObject private var browserViewModel: LibraryBrowserViewModel
    @StateObject private var detailViewModel: LibraryItemDetailViewModel

    init(environment: AppShellEnvironment) {
        self.environment = environment
        _browserViewModel = StateObject(wrappedValue:
            LibraryBrowserViewModel(
                mediaSummaryBrowser: environment.mediaSummaryBrowser,
                folderSummaryBrowser: environment.folderSummaryBrowser
            ))
        _detailViewModel = StateObject(wrappedValue:
            LibraryItemDetailViewModel(detailBrowser: environment.itemDetailBrowser))
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedSection: Binding(
                    get: { browserViewModel.selectedSection },
                    set: { browserViewModel.selectSection($0) }
                )
            )
        } content: {
            LibraryBrowserView(viewModel: browserViewModel)
        } detail: {
            LibraryItemDetailView(viewModel: detailViewModel)
                .onChange(of: browserViewModel.selectedItemID) { _, newID in
                    Task { await detailViewModel.loadDetail(for: newID) }
                }
        }
    }
}

#Preview("Loading") {
    CineMindRootView(viewModel: AppShellViewModel(state: .loading))
}

#Preview("Ready") {
    CineMindRootView(viewModel: AppShellViewModel(state: .ready))
}

#Preview("Failed") {
    CineMindRootView(
        viewModel: AppShellViewModel(
            state: .failed("CineMind could not open its local library database.")
        )
    )
}
