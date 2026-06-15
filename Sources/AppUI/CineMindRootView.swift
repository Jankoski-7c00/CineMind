import Application
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
    private let inspectorActions: LibraryItemInspectorActions
    @State private var inspectorSnapshot: LibraryItemInspectorSnapshot
    @State private var inspectorCurationSnapshot: LibraryCurationSnapshot
    @SceneStorage("CineMind.libraryBrowserPresentationMode")
    private var browserPresentationModeRawValue = LibraryBrowserPresentationMode.grid.rawValue
    @State private var isInspectorPresented = false
    @SceneStorage("CineMind.inspectorSection")
    private var inspectorSectionRawValue = LibraryInspectorSection.info.rawValue

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
        inspectorActions = LibraryItemInspectorActions(viewModel: detailViewModel)
        _inspectorSnapshot = State(
            initialValue: LibraryItemInspectorSnapshot(viewModel: detailViewModel)
        )
        _inspectorCurationSnapshot = State(initialValue: .empty)
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
            LibraryBrowserView(
                viewModel: browserViewModel,
                presentationMode: browserPresentationMode,
                onShowInspector: {
                    isInspectorPresented = true
                }
            )
        } detail: {
            LibraryItemDetailView(
                viewModel: detailViewModel,
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
                .inspector(isPresented: $isInspectorPresented) {
                    LibraryItemInspectorView(
                        snapshot: inspectorSnapshot,
                        actions: inspectorActions,
                        curationSnapshot: inspectorCurationSnapshot,
                        selectedSection: inspectorSection
                    )
                    .inspectorColumnWidth(min: 280, ideal: 340, max: 440)
                }
        }
        .searchable(
            text: $browserViewModel.searchText,
            placement: .toolbar,
            prompt: "Search Library"
        )
        .toolbar {
            LibraryBrowserToolbarContent(
                viewModel: browserViewModel,
                presentationMode: browserPresentationMode,
                isInspectorPresented: $isInspectorPresented
            )
        }
        .focusedSceneValue(\.libraryCommandActions, libraryCommandActions)
        .onReceive(detailViewModel.objectWillChange) { _ in
            Task { @MainActor in
                await Task.yield()
                inspectorSnapshot = LibraryItemInspectorSnapshot(viewModel: detailViewModel)
            }
        }
        .onReceive(browserViewModel.objectWillChange) { _ in
            Task { @MainActor in
                await Task.yield()
                inspectorCurationSnapshot = browserViewModel.curationSnapshot
            }
        }
    }

    private var browserPresentationMode: Binding<LibraryBrowserPresentationMode> {
        Binding(
            get: {
                LibraryBrowserPresentationMode(rawValue: browserPresentationModeRawValue) ?? .grid
            },
            set: { browserPresentationModeRawValue = $0.rawValue }
        )
    }

    private var inspectorSection: Binding<LibraryInspectorSection> {
        Binding(
            get: {
                LibraryInspectorSection(rawValue: inspectorSectionRawValue) ?? .info
            },
            set: { inspectorSectionRawValue = $0.rawValue }
        )
    }

    private var libraryCommandActions: LibraryCommandActions {
        let presentationMode = browserPresentationMode
        let workflowIsBusy = browserViewModel.isAddingFolder || browserViewModel.isScanning
        let canTogglePresentation = browserViewModel.selectedSection != .folders
            || browserViewModel.isSearchActive

        return LibraryCommandActions(
            canAddFolder: !workflowIsBusy,
            canScanLibrary: !workflowIsBusy,
            canTogglePresentation: canTogglePresentation,
            addFolder: {
                Task { await browserViewModel.addFolder() }
            },
            scanLibrary: {
                Task { await browserViewModel.scanLibrary() }
            },
            togglePresentation: {
                guard canTogglePresentation else { return }
                presentationMode.wrappedValue = presentationMode.wrappedValue == .grid
                    ? .list
                    : .grid
            },
            toggleInspector: {
                isInspectorPresented.toggle()
            }
        )
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
