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
            browserContent
        }
        .background(Color.black.opacity(0.94))
        .task(id: viewModel.selectedSection) {
            await viewModel.load()
        }
    }

    private var workflowHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                LiquidGlassPanel(
                    cornerRadius: 18,
                    material: .thinMaterial,
                    padding: EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 12)
                ) {
                    HStack(spacing: 8) {
                        Button {
                            Task { await viewModel.addFolder() }
                        } label: {
                            Label("Add Folder", systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.liquidGlassPrimary)
                        .disabled(workflowIsBusy)

                        Button {
                            Task { await viewModel.scanLibrary() }
                        } label: {
                            Label("Scan", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.liquidGlass)
                        .disabled(workflowIsBusy)

                        workflowProgressLabel
                    }
                }

                Spacer()
            }

            if let workflowErrorMessage = viewModel.workflowErrorMessage {
                Text(workflowErrorMessage)
                    .font(.callout)
                    .foregroundColor(.red)
            } else if let workflowMessage = viewModel.workflowMessage {
                Text(workflowMessage)
                    .font(.caption)
                    .cinemindSecondaryTextStyle()
            }

            if let lastScanResult = viewModel.lastScanResult {
                scanResultSummary(lastScanResult)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var workflowIsBusy: Bool {
        viewModel.isAddingFolder || viewModel.isScanning
    }

    @ViewBuilder
    private var workflowProgressLabel: some View {
        if viewModel.isAddingFolder {
            ProgressView("Adding...")
                .controlSize(.small)
                .font(.caption)
        } else if viewModel.isScanning {
            ProgressView("Scanning...")
                .controlSize(.small)
                .font(.caption)
        }
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
            "\(CineMindDisplayText.friendlyStatus(result.statusLabel)): \(result.counts.filesDiscovered) files, \(result.counts.mediaItemsCreated) created, \(result.counts.mediaItemsUpdated) updated, \(result.counts.issuesRecorded) issues"
        )
        .font(.caption)
        .cinemindSecondaryTextStyle()
    }

    private var emptyContent: some View {
        LiquidGlassCard {
            VStack(spacing: 12) {
                Image(systemName: viewModel.selectedSection == .folders ? "folder" : "film.stack")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))

                Text(viewModel.selectedSection == .folders ? "No folders yet" : "No media yet")
                    .cinemindSectionTitleStyle()

                Text("Add a folder to start building your library.")
                    .font(.callout)
                    .cinemindSecondaryTextStyle()
                    .multilineTextAlignment(.center)

                Button {
                    Task { await viewModel.addFolder() }
                } label: {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.liquidGlassPrimary)
                .disabled(workflowIsBusy)
            }
            .frame(maxWidth: 340)
        }
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
                mediaTitleCell(item)
            }
            TableColumn("Type") { item in
                tableStatusLabel(
                    item.mediaTypeLabel,
                    systemImage: item.mediaTypeLabel == "TV Episode" ? "tv" : "film",
                    color: .secondary
                )
            }
            TableColumn("Year / Episode") { item in
                Text(item.yearOrEpisodeLabel ?? CineMindDisplayText.emptyValue)
            }
            TableColumn("Availability") { item in
                let descriptor = availabilityDescriptor(item.availabilityLabel)
                tableStatusLabel(
                    descriptor.title,
                    systemImage: descriptor.systemImage,
                    color: descriptor.color
                )
            }
            TableColumn("Metadata") { item in
                let descriptor = metadataDescriptor(item.metadataLabel)
                tableStatusLabel(
                    descriptor.title,
                    systemImage: descriptor.systemImage,
                    color: descriptor.color
                )
            }
            TableColumn("Last Played") { item in
                Text(item.lastPlayedLabel ?? CineMindDisplayText.emptyValue)
            }
        } rows: {
            ForEach(items) { item in
                TableRow(item)
            }
        }
    }

    private func mediaTitleCell(_ item: LibraryItemSummary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.mediaTypeLabel == "TV Episode" ? "tv" : "film")
                .foregroundStyle(.secondary)

            Text(item.displayTitle)
                .lineLimit(1)
        }
        .padding(.vertical, 5)
    }

    private func tableStatusLabel(
        _ title: String,
        systemImage: String,
        color: Color
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .imageScale(.small)
            Text(title)
                .lineLimit(1)
        }
        .font(.callout)
        .foregroundStyle(color)
    }

    private func availabilityDescriptor(_ label: String) -> TableStatusDescriptor {
        switch label.lowercased() {
        case "available":
            TableStatusDescriptor(title: "Available", systemImage: "checkmark.circle.fill", color: .green)
        case "unavailable", "no files":
            TableStatusDescriptor(title: "Missing File", systemImage: "xmark.circle.fill", color: .red)
        case "partially available":
            TableStatusDescriptor(title: "Partial", systemImage: "exclamationmark.circle.fill", color: .yellow)
        default:
            TableStatusDescriptor(
                title: CineMindDisplayText.friendlyStatus(label),
                systemImage: "info.circle",
                color: .secondary
            )
        }
    }

    private func metadataDescriptor(_ label: String) -> TableStatusDescriptor {
        switch label.lowercased() {
        case "complete":
            TableStatusDescriptor(title: "Matched", systemImage: "checkmark.seal.fill", color: .green)
        case "partial":
            TableStatusDescriptor(title: "Partial", systemImage: "exclamationmark.circle.fill", color: .yellow)
        case "missing":
            TableStatusDescriptor(title: "Needs Metadata", systemImage: "tag.fill", color: .accentColor)
        default:
            TableStatusDescriptor(
                title: CineMindDisplayText.friendlyStatus(label),
                systemImage: "tag",
                color: .secondary
            )
        }
    }

    private struct TableStatusDescriptor {
        let title: String
        let systemImage: String
        let color: Color
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
                let descriptor = availabilityDescriptor(folder.availabilityLabel)
                tableStatusLabel(
                    descriptor.title,
                    systemImage: descriptor.systemImage,
                    color: descriptor.color
                )
            }
            TableColumn("Files") { folder in
                Text(folder.fileCountLabel)
            }
            TableColumn("Last Seen") { folder in
                Text(folder.lastSeenLabel ?? CineMindDisplayText.emptyValue)
            }
            TableColumn("Last Scan") { folder in
                Text(folder.lastScanLabel ?? CineMindDisplayText.emptyValue)
            }
        } rows: {
            ForEach(folders) { folder in
                TableRow(folder)
            }
        }
    }
}
