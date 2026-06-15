import Application
import Domain
import SwiftUI

struct LibraryBrowserToolbarContent: ToolbarContent {
    @ObservedObject var viewModel: LibraryBrowserViewModel
    @Binding var presentationMode: LibraryBrowserPresentationMode
    @Binding var isInspectorPresented: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup {
            presentationPicker
            filterMenu
            sortMenu
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                isInspectorPresented.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .help(isInspectorPresented ? "Hide Inspector" : "Show Inspector")

            Button {
                Task { await viewModel.addFolder() }
            } label: {
                Label("Add Folder", systemImage: "folder.badge.plus")
            }
            .disabled(workflowIsBusy)
            .help("Add Folder")

            Button {
                Task { await viewModel.scanLibrary() }
            } label: {
                if viewModel.isScanning {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Scanning Library")
                } else {
                    Label("Scan Library", systemImage: "arrow.clockwise")
                }
            }
            .disabled(workflowIsBusy)
            .help(viewModel.isScanning ? "Scanning Library" : "Scan Library")
        }
    }

    private var workflowIsBusy: Bool {
        viewModel.isAddingFolder || viewModel.isScanning
    }

    private var presentationPicker: some View {
        Picker("View", selection: $presentationMode) {
            Label("Grid", systemImage: "square.grid.2x2")
                .tag(LibraryBrowserPresentationMode.grid)
            Label("List", systemImage: "list.bullet")
                .tag(LibraryBrowserPresentationMode.list)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(viewModel.selectedSection == .folders && !viewModel.isSearchActive)
        .help("Browser View")
    }

    private var filterMenu: some View {
        Menu {
            Picker("Media Type", selection: $viewModel.searchMediaTypeFilter) {
                Text("All Media").tag(LibrarySearchMediaTypeFilter.all)
                Text("Movies").tag(LibrarySearchMediaTypeFilter.movies)
                Text("TV Episodes").tag(LibrarySearchMediaTypeFilter.tvEpisodes)
            }

            Picker("Availability", selection: $viewModel.searchAvailabilityFilter) {
                Text("Any Availability").tag(LibrarySearchAvailabilityFilter.any)
                Text("Available").tag(LibrarySearchAvailabilityFilter.available)
                Text("Missing").tag(LibrarySearchAvailabilityFilter.unavailable)
            }

            Picker("Favorite", selection: $viewModel.searchFavoriteFilter) {
                Text("All Items").tag(LibrarySearchFavoriteFilter.any)
                Text("Favorites").tag(LibrarySearchFavoriteFilter.favoritesOnly)
            }

            Picker("Tag", selection: $viewModel.searchTagID) {
                Text("Any Tag").tag(Optional<TagID>.none)
                ForEach(viewModel.curationSnapshot.tags) { tag in
                    Text(tag.name).tag(Optional(tag.id))
                }
            }
            .disabled(viewModel.curationSnapshot.tags.isEmpty)

            Divider()

            Button("Clear Search and Filters") {
                viewModel.clearSearch()
            }
            .disabled(!viewModel.isSearchActive)
        } label: {
            Label(
                "Filter",
                systemImage: viewModel.isSearchActive
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
        .help("Filter Library")
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $viewModel.searchSort) {
                Text("Relevance").tag(LibrarySearchSort.relevance)
                Text("Title").tag(LibrarySearchSort.title)
                Text("Recently Added").tag(LibrarySearchSort.recentlyAdded)
                Text("Recently Played").tag(LibrarySearchSort.recentlyPlayed)
                Text("Year").tag(LibrarySearchSort.year)
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .help("Sort Library")
    }
}
