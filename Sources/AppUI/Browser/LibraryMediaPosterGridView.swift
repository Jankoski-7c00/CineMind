import Application
import Domain
import SwiftUI

struct LibraryMediaPosterGridView: View {
    let items: [LibraryItemSummary]
    @Binding var selectedItemID: MediaItemID?

    private let columns = [
        GridItem(.adaptive(minimum: 132, maximum: 190), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                ForEach(items) { item in
                    posterButton(for: item)
                }
            }
            .padding(16)
        }
    }

    private func posterButton(for item: LibraryItemSummary) -> some View {
        let isSelected = selectedItemID == item.id
        return Button {
            selectedItemID = item.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                posterPlaceholder(for: item, isSelected: isSelected)

                Text(item.displayTitle)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(item.yearOrEpisodeLabel ?? item.mediaTypeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Show Details", systemImage: "info.circle") {
                selectedItemID = item.id
            }
        }
        .accessibilityLabel(item.displayTitle)
        .accessibilityValue(accessibilityValue(for: item))
    }

    private func posterPlaceholder(
        for item: LibraryItemSummary,
        isSelected: Bool
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            LibraryPosterThumbnailView(
                title: item.displayTitle,
                mediaTypeLabel: item.mediaTypeLabel,
                localCachePath: item.selectedPosterLocalCachePath
            )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.secondary.opacity(0.18),
                            lineWidth: isSelected ? 3 : 1
                        )
                }

            if item.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .padding(8)
                    .accessibilityHidden(true)
            } else if item.availabilityLabel.lowercased() != "available" {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .padding(8)
                    .accessibilityHidden(true)
            }
        }
    }

    private func accessibilityValue(for item: LibraryItemSummary) -> String {
        [
            item.mediaTypeLabel,
            item.yearOrEpisodeLabel,
            item.availabilityLabel,
            item.metadataLabel,
            item.isFavorite ? "Favorite" : nil
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}
