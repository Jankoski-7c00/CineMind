import Application
import Foundation
import SwiftUI

struct MediaDetailHeaderView: View {
    let detail: LibraryItemDetailShell
    let posterImageState: PosterImageState

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            posterView

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(detail.displayTitle)
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(3)

                    subtitleLine
                }

                statusRow

                Label(lastPlayedText, systemImage: "clock")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text(CineMindDisplayText.summary(detail.summary))
                    .font(.body)
                    .lineSpacing(3)
                    .foregroundStyle(detail.summary == nil ? .secondary : .primary)
                    .lineLimit(6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var posterView: some View {
        switch posterImageState {
        case .loaded(let loadedImage):
            Image(decorative: loadedImage.image, scale: 1.0)
                .resizable()
                .scaledToFill()
                .frame(width: 168, height: 252)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .loading:
            posterPlaceholder(title: "Loading Poster", isLoading: true)
        case .idle, .placeholder:
            posterPlaceholder(title: "No Poster", isLoading: false)
        }
    }

    private func posterPlaceholder(title: String, isLoading: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary)

            VStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                }
                Text(title)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .frame(width: 168, height: 252)
        .accessibilityLabel(title)
    }

    private var statusRow: some View {
        HStack(spacing: 12) {
            statusLabel(
                title: detail.mediaTypeLabel,
                systemImage: detail.mediaTypeLabel == "TV Episode" ? "tv" : "film",
                color: .secondary
            )

            let availability = availabilityStatus
            statusLabel(
                title: availability.title,
                systemImage: availability.systemImage,
                color: availability.color
            )

            let metadata = metadataStatus
            statusLabel(
                title: metadata.title,
                systemImage: metadata.systemImage,
                color: metadata.color
            )
        }
        .font(.caption)
    }

    private func statusLabel(
        title: String,
        systemImage: String,
        color: Color
    ) -> some View {
        Label(title, systemImage: systemImage)
            .foregroundStyle(color)
    }

    @ViewBuilder
    private var subtitleLine: some View {
        if let yearOrEpisodeLabel = detail.yearOrEpisodeLabel,
           !yearOrEpisodeLabel.isEmpty {
            Text(yearOrEpisodeLabel)
                .font(.title3)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        } else {
            Text(detail.mediaTypeLabel)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var lastPlayedText: String {
        guard let label = detail.lastPlayedLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty else {
            return "Never played"
        }

        guard let date = Self.isoDateFormatter.date(from: label) else {
            return "Last played \(label)"
        }

        let calendar = Calendar.current
        let time = Self.timeFormatter.string(from: date)

        if calendar.isDateInToday(date) {
            return "Last played today at \(time)"
        }

        if calendar.isDateInYesterday(date) {
            return "Last played yesterday at \(time)"
        }

        return "Last played on \(Self.dateFormatter.string(from: date)) at \(time)"
    }

    private var availabilityStatus: StatusDescriptor {
        switch detail.availabilityLabel.lowercased() {
        case "available":
            StatusDescriptor(title: "Available", systemImage: "checkmark.circle.fill", color: .green)
        case "unavailable", "no files":
            StatusDescriptor(title: "Missing File", systemImage: "xmark.circle.fill", color: .red)
        case "partially available":
            StatusDescriptor(
                title: "Partial Availability",
                systemImage: "exclamationmark.circle.fill",
                color: .orange
            )
        default:
            StatusDescriptor(
                title: CineMindDisplayText.friendlyStatus(detail.availabilityLabel),
                systemImage: "info.circle",
                color: .secondary
            )
        }
    }

    private var metadataStatus: StatusDescriptor {
        switch detail.metadataLabel.lowercased() {
        case "complete":
            StatusDescriptor(title: "Matched", systemImage: "checkmark.seal.fill", color: .green)
        case "partial":
            StatusDescriptor(
                title: "Partial Metadata",
                systemImage: "exclamationmark.circle.fill",
                color: .orange
            )
        case "missing":
            StatusDescriptor(title: "Needs Metadata", systemImage: "tag.fill", color: .accentColor)
        default:
            StatusDescriptor(
                title: CineMindDisplayText.friendlyStatus(detail.metadataLabel),
                systemImage: "tag",
                color: .secondary
            )
        }
    }

    private struct StatusDescriptor {
        let title: String
        let systemImage: String
        let color: Color
    }

    private static let isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withFullDate,
            .withTime,
            .withTimeZone,
            .withColonSeparatorInTime
        ]
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
