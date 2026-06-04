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
        .background {
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.04, blue: 0.052),
                    Color.black.opacity(0.96)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .task(id: viewModel.loadTrigger) {
            await viewModel.load()
        }
    }

    private var workflowHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Library")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.94))

                    Text(browserSubtitle)
                        .font(.callout)
                        .cinemindSecondaryTextStyle(opacity: 0.62)
                }

                Spacer()

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
            }

            searchControls

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
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.045),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
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

    private var searchControls: some View {
        LiquidGlassPanel(
            cornerRadius: 14,
            material: .thinMaterial,
            padding: EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        ) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    searchField
                        .frame(minWidth: 220)
                    mediaTypePicker
                        .frame(width: 190)
                    availabilityPicker
                        .frame(width: 130)
                    favoritePicker
                        .frame(width: 126)
                    tagFilterPicker
                        .frame(width: 150)
                    sortPicker
                        .frame(width: 170)
                    clearSearchButton
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        searchField
                        clearSearchButton
                    }
                    HStack(spacing: 8) {
                        mediaTypePicker
                        availabilityPicker
                        favoritePicker
                        tagFilterPicker
                        sortPicker
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search Library", text: $viewModel.searchText)
                .textFieldStyle(.plain)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var mediaTypePicker: some View {
        Picker("Type", selection: $viewModel.searchMediaTypeFilter) {
            Text("All").tag(LibrarySearchMediaTypeFilter.all)
            Text("Movies").tag(LibrarySearchMediaTypeFilter.movies)
            Text("TV").tag(LibrarySearchMediaTypeFilter.tvEpisodes)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var availabilityPicker: some View {
        Picker("Availability", selection: $viewModel.searchAvailabilityFilter) {
            Text("Any").tag(LibrarySearchAvailabilityFilter.any)
            Text("Available").tag(LibrarySearchAvailabilityFilter.available)
            Text("Missing").tag(LibrarySearchAvailabilityFilter.unavailable)
        }
        .pickerStyle(.menu)
    }

    private var favoritePicker: some View {
        Picker("Favorite", selection: $viewModel.searchFavoriteFilter) {
            Text("Any").tag(LibrarySearchFavoriteFilter.any)
            Text("Favorites").tag(LibrarySearchFavoriteFilter.favoritesOnly)
        }
        .pickerStyle(.menu)
    }

    private var tagFilterPicker: some View {
        Picker("Tag", selection: $viewModel.searchTagID) {
            Text("Any Tag").tag(Optional<TagID>.none)
            ForEach(viewModel.curationSnapshot.tags) { tag in
                Text(tag.name).tag(Optional(tag.id))
            }
        }
        .pickerStyle(.menu)
        .disabled(viewModel.curationSnapshot.tags.isEmpty)
    }

    private var sortPicker: some View {
        Picker("Sort", selection: $viewModel.searchSort) {
            Text("Relevance").tag(LibrarySearchSort.relevance)
            Text("Title").tag(LibrarySearchSort.title)
            Text("Recently Added").tag(LibrarySearchSort.recentlyAdded)
            Text("Recently Played").tag(LibrarySearchSort.recentlyPlayed)
            Text("Year").tag(LibrarySearchSort.year)
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private var clearSearchButton: some View {
        if viewModel.isSearchActive {
            Button {
                viewModel.clearSearch()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Clear search")
            .frame(width: 24, height: 24)
        }
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
        } else if !viewModel.isSearchActive,
                  viewModel.selectedSection == .folders,
                  let folderSnapshot = viewModel.folderSnapshot,
                  !folderSnapshot.folders.isEmpty {
            folderTableContent(folders: folderSnapshot.folders)
        } else if let items = displayedMediaItems, !items.isEmpty {
            mediaTableContent(items: items)
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
        LiquidGlassCard {
            VStack(spacing: 12) {
                Image(systemName: emptyStateIconName)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))

                Text(emptyStateTitle)
                    .cinemindSectionTitleStyle()

                Text(emptyStateMessage)
                    .font(.callout)
                    .cinemindSecondaryTextStyle()
                    .multilineTextAlignment(.center)

                if viewModel.isSearchActive {
                    Button {
                        viewModel.clearSearch()
                    } label: {
                        Label("Clear Search", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.liquidGlass)
                } else if emptyStateShowsAddFolderButton {
                    Button {
                        Task { await viewModel.addFolder() }
                    } label: {
                        Label("Add Folder", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.liquidGlassPrimary)
                    .disabled(workflowIsBusy)
                }
            }
            .frame(maxWidth: 340)
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
            TableColumn("Metadata") { item in
                let descriptor = metadataDescriptor(item.metadataLabel)
                tableStatusLabel(
                    descriptor.title,
                    systemImage: descriptor.systemImage,
                    color: descriptor.color
                )
            }
            TableColumn("Availability") { item in
                let descriptor = availabilityDescriptor(item.availabilityLabel)
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
        HStack(spacing: 9) {
            Image(systemName: item.isFavorite ? "star.fill" : mediaIconName(for: item))
                .foregroundStyle(item.isFavorite ? Color.yellow : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                Text(mediaSubtitle(for: item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 7)
    }

    private func mediaSubtitle(for item: LibraryItemSummary) -> String {
        let availability = availabilityDescriptor(item.availabilityLabel).title
        var parts: [String] = [item.mediaTypeLabel]
        guard let yearOrEpisode = item.yearOrEpisodeLabel,
              !yearOrEpisode.isEmpty else {
            parts.append(availability)
            if let tagSummary = tagSummary(for: item) {
                parts.append(tagSummary)
            }
            return parts.joined(separator: " · ")
        }

        parts.append(yearOrEpisode)
        parts.append(availability)
        if let tagSummary = tagSummary(for: item) {
            parts.append(tagSummary)
        }
        return parts.joined(separator: " · ")
    }

    private func mediaIconName(for item: LibraryItemSummary) -> String {
        item.mediaTypeLabel == "TV Episode" ? "tv" : "film"
    }

    private func tagSummary(for item: LibraryItemSummary) -> String? {
        guard !item.tagLabels.isEmpty else {
            return nil
        }
        let visible = item.tagLabels.prefix(2).joined(separator: ", ")
        let remaining = item.tagLabels.count - 2
        return remaining > 0 ? "\(visible) +\(remaining)" : visible
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
