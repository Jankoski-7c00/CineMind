import SwiftUI

public struct CineMindRootView: View {
    @StateObject private var viewModel: AppShellViewModel
    private let playbackSurface: AnyView?

    public init(
        viewModel: AppShellViewModel = AppShellViewModel(),
        playbackSurface: AnyView? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.playbackSurface = playbackSurface
    }

    public var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                loadingView
            case .ready:
                shellView
            case .failed(let message):
                errorView(message)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var loadingView: some View {
        ProgressView("Loading Library...")
    }

    @ViewBuilder
    private var shellView: some View {
        if let environment = viewModel.environment {
            ReadyShellView(
                environment: environment,
                playbackSurface: playbackSurface
            )
        } else {
            NavigationSplitView {
                SidebarView(selectedSection: .constant(.library), collections: [])
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
    let playbackSurface: AnyView?
    @StateObject private var browserViewModel: LibraryBrowserViewModel
    @StateObject private var detailViewModel: LibraryItemDetailViewModel
    @ObservedObject private var metadataActionsState: LibraryMetadataActionsState

    init(
        environment: AppShellEnvironment,
        playbackSurface: AnyView?
    ) {
        self.environment = environment
        self.playbackSurface = playbackSurface
        _metadataActionsState = ObservedObject(wrappedValue: environment.metadataActionsState)
        let detailViewModel = LibraryItemDetailViewModel(
            detailBrowser: environment.itemDetailBrowser,
            playbackController: environment.playbackController,
            metadataActions: environment.metadataActionsState.actions,
            metadataActionsUnavailableMessage: environment.metadataActionsState.unavailableMessage,
            curationActions: environment.curationHandler,
            subtitleActions: environment.subtitleActions,
            subtitleActionsUnavailableMessage: environment.subtitleActionsUnavailableMessage
        )
        _browserViewModel = StateObject(wrappedValue:
            LibraryBrowserViewModel(
                mediaSummaryBrowser: environment.mediaSummaryBrowser,
                mediaSearcher: environment.mediaSearcher,
                curationBrowser: environment.curationBrowser,
                folderSummaryBrowser: environment.folderSummaryBrowser,
                folderPicker: environment.folderPicker,
                folderAdder: environment.folderAdder,
                libraryScanner: environment.libraryScanner,
                reloadSelectedItemDetail: { selectedItemID in
                    await detailViewModel.loadDetail(for: selectedItemID)
                }
            ))
        _detailViewModel = StateObject(wrappedValue: detailViewModel)
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedSection: Binding(
                    get: { browserViewModel.selectedSection },
                    set: { browserViewModel.selectSection($0) }
                ),
                collections: browserViewModel.curationSnapshot.collections
            )
        } content: {
            LibraryBrowserView(viewModel: browserViewModel)
        } detail: {
            LibraryItemDetailView(
                viewModel: detailViewModel,
                curationSnapshot: browserViewModel.curationSnapshot,
                playbackSurface: playbackSurface
            )
                .onChange(of: browserViewModel.selectedItemID) { _, newID in
                    Task { await detailViewModel.loadDetail(for: newID) }
                }
                .onChange(of: detailViewModel.metadataMutationRevision) { _, _ in
                    Task { await browserViewModel.reloadCurrentSection() }
                }
                .onChange(of: detailViewModel.curationMutationRevision) { _, _ in
                    Task {
                        await browserViewModel.reloadCurationSnapshot()
                        await browserViewModel.reloadCurrentSection()
                    }
                }
                .onChange(of: metadataActionsState.revision) { _, _ in
                    detailViewModel.setMetadataActions(
                        metadataActionsState.actions,
                        unavailableMessage: metadataActionsState.unavailableMessage
                    )
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
