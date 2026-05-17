import Application
import Domain
import SwiftUI

public struct LibraryBrowserView: View {
    @ObservedObject var viewModel: LibraryBrowserViewModel

    public init(viewModel: LibraryBrowserViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage {
                errorContent(message: errorMessage)
            } else if viewModel.selectedSection == .folders,
                      let folderSnapshot = viewModel.folderSnapshot,
                      !folderSnapshot.folders.isEmpty {
                folderTableContent(folders: folderSnapshot.folders)
            } else if let snapshot = viewModel.snapshot, !snapshot.items.isEmpty {
                mediaTableContent(items: snapshot.items)
            } else {
                emptyContent
            }
        }
        .task(id: viewModel.selectedSection) {
            await viewModel.load()
        }
    }

    private var emptyContent: some View {
        Text(viewModel.selectedSection == .folders ? "No folders found" : "No media found")
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorContent(message: String) -> some View {
        VStack(spacing: 12) {
            Text("Failed to load")
                .font(.headline)
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await viewModel.load() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func mediaTableContent(items: [LibraryItemSummary]) -> some View {
        Table(of: LibraryItemSummary.self, selection: $viewModel.selectedItemID) {
            TableColumn("Title") { item in
                Text(item.displayTitle)
            }
            TableColumn("Type") { item in
                Text(item.mediaTypeLabel)
            }
            TableColumn("Year / Episode") { item in
                Text(item.yearOrEpisodeLabel ?? "—")
            }
            TableColumn("Availability") { item in
                Text(item.availabilityLabel)
            }
            TableColumn("Metadata") { item in
                Text(item.metadataLabel)
            }
            TableColumn("Last Played") { item in
                Text(item.lastPlayedLabel ?? "—")
            }
        } rows: {
            ForEach(items) { item in
                TableRow(item)
            }
        }
    }

    private func folderTableContent(folders: [LibraryFolderSummary]) -> some View {
        Table(of: LibraryFolderSummary.self) {
            TableColumn("Name") { folder in
                Text(folder.displayName)
            }
            TableColumn("Path") { folder in
                Text(folder.rootPath)
            }
            TableColumn("Availability") { folder in
                Text(folder.availabilityLabel)
            }
            TableColumn("Files") { folder in
                Text(folder.fileCountLabel)
            }
            TableColumn("Last Seen") { folder in
                Text(folder.lastSeenLabel ?? "—")
            }
            TableColumn("Last Scan") { folder in
                Text(folder.lastScanLabel ?? "—")
            }
        } rows: {
            ForEach(folders) { folder in
                TableRow(folder)
            }
        }
    }
}
