import Application
import Domain
import SwiftUI

public struct LibraryBrowserView: View {
    @ObservedObject var viewModel: LibraryBrowserViewModel

    public init(viewModel: LibraryBrowserViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            workflowHeader
            Divider()
            browserContent
        }
        .task(id: viewModel.selectedSection) {
            await viewModel.load()
        }
    }

    private var workflowHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    Task { await viewModel.addFolder() }
                } label: {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }

                Button {
                    Task { await viewModel.scanLibrary() }
                } label: {
                    Label("Scan", systemImage: "arrow.clockwise")
                }

                if viewModel.isAddingFolder {
                    ProgressView("Adding folder...")
                        .controlSize(.small)
                } else if viewModel.isScanning {
                    ProgressView("Scanning...")
                        .controlSize(.small)
                }

                Spacer()
            }
            .disabled(viewModel.isAddingFolder || viewModel.isScanning)

            if let workflowErrorMessage = viewModel.workflowErrorMessage {
                Text(workflowErrorMessage)
                    .font(.callout)
                    .foregroundColor(.red)
            } else if let workflowMessage = viewModel.workflowMessage {
                Text(workflowMessage)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            if let lastScanResult = viewModel.lastScanResult {
                scanResultSummary(lastScanResult)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var browserContent: some View {
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

    private func scanResultSummary(_ result: LibraryScanResultSummary) -> some View {
        Text(
            "Status: \(result.statusLabel) • Files discovered: \(result.counts.filesDiscovered) • Media items: \(result.counts.mediaItemsCreated) created, \(result.counts.mediaItemsUpdated) updated • Issues: \(result.counts.issuesRecorded)"
        )
        .font(.caption)
        .foregroundColor(.secondary)
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
