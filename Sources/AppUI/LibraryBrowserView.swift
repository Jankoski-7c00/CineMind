import Application
import SwiftUI

public struct LibraryBrowserView: View {
    @ObservedObject var viewModel: LibraryBrowserViewModel
    @Binding private var presentationMode: LibraryBrowserPresentationMode

    public init(viewModel: LibraryBrowserViewModel) {
        self.viewModel = viewModel
        _presentationMode = .constant(.grid)
    }

    init(
        viewModel: LibraryBrowserViewModel,
        presentationMode: Binding<LibraryBrowserPresentationMode>
    ) {
        self.viewModel = viewModel
        _presentationMode = presentationMode
    }

    public var body: some View {
        VStack(spacing: 0) {
            browserStatusBar
            browserContent
        }
        .navigationTitle(browserTitle)
        .task(id: viewModel.loadTrigger) {
            await viewModel.load()
        }
    }

    private var browserTitle: String {
        switch viewModel.selectedSection {
        case .library:
            "Library"
        case .movies:
            "Movies"
        case .tvEpisodes:
            "TV Episodes"
        case .recentlyPlayed:
            "Recently Played"
        case .needsMetadata:
            "Needs Metadata"
        case .favorites:
            "Favorites"
        case .folders:
            "Folders"
        case .collection(let collectionID):
            viewModel.curationSnapshot.collections
                .first(where: { $0.id == collectionID })?
                .name ?? "Collection"
        }
    }

    private var browserStatusBar: some View {
        HStack(spacing: 8) {
            if viewModel.isAddingFolder {
                ProgressView()
                    .controlSize(.small)
                Text("Adding folder...")
            } else if viewModel.isScanning {
                ProgressView()
                    .controlSize(.small)
                Text("Scanning library...")
            } else if let workflowErrorMessage = viewModel.workflowErrorMessage {
                Label(workflowErrorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            } else if let workflowMessage = viewModel.workflowMessage {
                Label(workflowMessage, systemImage: "checkmark.circle")
            } else {
                Text(browserSubtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let lastScanResult = viewModel.lastScanResult {
                scanResultSummary(lastScanResult)
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private var workflowIsBusy: Bool {
        viewModel.isAddingFolder || viewModel.isScanning
    }

    private var browserSubtitle: String {
        if viewModel.isSearchActive {
            if let resultDescription = viewModel.searchSnapshot?.resultDescription {
                return resultDescription
            }
            return "Search results"
        }

        if viewModel.selectedSection == .folders {
            if let count = viewModel.folderSnapshot?.folders.count {
                return count == 1 ? "1 folder" : "\(count) folders"
            }
            return "Local folders"
        }

        if viewModel.selectedSection == .favorites {
            return "Favorite media"
        }

        if case .collection(let collectionID) = viewModel.selectedSection,
           let collection = viewModel.curationSnapshot.collections.first(where: { $0.id == collectionID }) {
            return collection.mediaItemCountLabel ?? collection.name
        }

        if let count = viewModel.snapshot?.items.count {
            return count == 1 ? "1 item" : "\(count) items"
        }

        return "Local library"
    }

    @ViewBuilder
    private var browserContent: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage {
            errorContent(message: errorMessage)
        } else if !viewModel.isSearchActive,
                  viewModel.selectedSection == .folders,
                  let folderSnapshot = viewModel.folderSnapshot,
                  !folderSnapshot.folders.isEmpty {
            LibraryFolderTableView(folders: folderSnapshot.folders)
        } else if let items = displayedMediaItems, !items.isEmpty {
            switch presentationMode {
            case .grid:
                LibraryMediaPosterGridView(
                    items: items,
                    selectedItemID: $viewModel.selectedItemID
                )
            case .list:
                LibraryMediaTableView(
                    items: items,
                    selectedItemID: $viewModel.selectedItemID
                )
            }
        } else {
            emptyContent
        }
    }

    private var displayedMediaItems: [LibraryItemSummary]? {
        if viewModel.isSearchActive {
            return viewModel.searchSnapshot?.items
        }
        return viewModel.snapshot?.items
    }

    private func scanResultSummary(_ result: LibraryScanResultSummary) -> some View {
        Text(
            "\(CineMindDisplayText.friendlyStatus(result.statusLabel)): \(result.counts.filesDiscovered) files, \(result.counts.mediaItemsCreated) created, \(result.counts.mediaItemsUpdated) updated, \(result.counts.issuesRecorded) issues"
        )
        .font(.caption)
        .cinemindSecondaryTextStyle()
    }

    private var emptyContent: some View {
        ContentUnavailableView {
            Label(emptyStateTitle, systemImage: emptyStateIconName)
        } description: {
            Text(emptyStateMessage)
        } actions: {
            if viewModel.isSearchActive {
                Button("Clear Search", systemImage: "xmark.circle") {
                    viewModel.clearSearch()
                }
            } else if emptyStateShowsAddFolderButton {
                Button("Add Folder", systemImage: "folder.badge.plus") {
                    Task { await viewModel.addFolder() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(workflowIsBusy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateShowsAddFolderButton: Bool {
        switch viewModel.selectedSection {
        case .favorites, .collection:
            false
        case .folders, .library, .movies, .tvEpisodes, .recentlyPlayed, .needsMetadata:
            true
        }
    }

    private var emptyStateIconName: String {
        if viewModel.isSearchActive {
            return "magnifyingglass"
        }
        switch viewModel.selectedSection {
        case .folders:
            return "folder"
        case .favorites:
            return "star"
        case .collection:
            return "rectangle.stack"
        case .library, .movies, .tvEpisodes, .recentlyPlayed, .needsMetadata:
            return "film.stack"
        }
    }

    private var emptyStateTitle: String {
        if viewModel.isSearchActive {
            return "No matches"
        }
        switch viewModel.selectedSection {
        case .folders:
            return "No folders yet"
        case .favorites:
            return "No favorites yet"
        case .collection:
            return "No collection items"
        case .library, .movies, .tvEpisodes, .recentlyPlayed, .needsMetadata:
            return "No media yet"
        }
    }

    private var emptyStateMessage: String {
        if viewModel.isSearchActive {
            return "Try a different search or filter."
        }
        switch viewModel.selectedSection {
        case .favorites:
            return "Mark media as favorite from the detail view."
        case .collection:
            return "Add media to this collection from the detail view."
        case .folders, .library, .movies, .tvEpisodes, .recentlyPlayed, .needsMetadata:
            return "Add a folder to start building your library."
        }
    }

    private func errorContent(message: String) -> some View {
        ContentUnavailableView {
            Label("Failed to Load", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry", systemImage: "arrow.clockwise") {
                Task { await viewModel.load() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}
