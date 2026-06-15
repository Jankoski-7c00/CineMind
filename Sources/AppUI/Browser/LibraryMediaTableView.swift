import Application
import Domain
import SwiftUI

struct LibraryMediaTableView: View {
    let items: [LibraryItemSummary]
    @Binding var selectedItemID: MediaItemID?
    let onShowInspector: () -> Void

    var body: some View {
        Table(of: LibraryItemSummary.self, selection: $selectedItemID) {
            TableColumn("Title") { item in
                mediaTitleCell(item)
            }
            TableColumn("Type") { item in
                LibraryBrowserStatusLabel(
                    descriptor: LibraryBrowserStatusDescriptor(
                        title: item.mediaTypeLabel,
                        systemImage: item.mediaTypeLabel == "TV Episode" ? "tv" : "film",
                        color: .secondary
                    )
                )
            }
            TableColumn("Metadata") { item in
                LibraryBrowserStatusLabel(
                    descriptor: LibraryBrowserStatusPresentation.metadata(item.metadataLabel)
                )
            }
            TableColumn("Availability") { item in
                LibraryBrowserStatusLabel(
                    descriptor: LibraryBrowserStatusPresentation.availability(item.availabilityLabel)
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
        .contextMenu {
            Button("Show Details", systemImage: "info.circle") {
                selectedItemID = item.id
            }
            Button("Show Inspector", systemImage: "sidebar.right") {
                selectedItemID = item.id
                onShowInspector()
            }
        }
    }

    private func mediaSubtitle(for item: LibraryItemSummary) -> String {
        let availability = LibraryBrowserStatusPresentation
            .availability(item.availabilityLabel)
            .title
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
}
