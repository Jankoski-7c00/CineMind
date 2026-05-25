import Application
import Foundation
import SwiftUI

struct MediaDetailHeaderView: View {
    let detail: LibraryItemDetailShell
    let posterImageState: PosterImageState

    var body: some View {
        LiquidGlassPanel(cornerRadius: 22, material: .thinMaterial) {
            HStack(alignment: .top, spacing: 22) {
                posterView

                VStack(alignment: .leading, spacing: 14) {
                    badgeRow

                    VStack(alignment: .leading, spacing: 6) {
                        Text(detail.displayTitle)
                            .cinemindDetailTitleStyle()
                            .lineLimit(3)

                        subtitleLine
                    }

                    Label(lastPlayedText, systemImage: "clock")
                        .font(.callout)
                        .cinemindSecondaryTextStyle(opacity: 0.72)

                    Text(CineMindDisplayText.summary(detail.summary))
                        .font(.body)
                        .lineSpacing(3)
                        .cinemindSecondaryTextStyle(opacity: detail.summary == nil ? 0.58 : 0.82)
                        .lineLimit(6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
        case .loading:
            PosterPlaceholderView(title: "Loading Poster", isLoading: true)
                .frame(width: 168, height: 252)
        case .idle, .placeholder:
            PosterPlaceholderView()
                .frame(width: 168, height: 252)
        }
    }

    private var badgeRow: some View {
        HStack(spacing: 8) {
            LiquidGlassBadge(
                detail.mediaTypeLabel,
                systemImage: detail.mediaTypeLabel == "TV Episode" ? "tv" : "film",
                variant: .neutral
            )

            let availability = availabilityBadge
            LiquidGlassBadge(
                availability.title,
                systemImage: availability.systemImage,
                variant: availability.variant
            )

            let metadata = metadataBadge
            LiquidGlassBadge(
                metadata.title,
                systemImage: metadata.systemImage,
                variant: metadata.variant
            )
        }
    }

    @ViewBuilder
    private var subtitleLine: some View {
        if let yearOrEpisodeLabel = detail.yearOrEpisodeLabel,
           !yearOrEpisodeLabel.isEmpty {
            Text(yearOrEpisodeLabel)
                .font(.title3.weight(.medium))
                .cinemindSecondaryTextStyle(opacity: 0.70)
                .lineLimit(2)
        } else {
            Text(detail.mediaTypeLabel)
                .font(.title3.weight(.medium))
                .cinemindSecondaryTextStyle(opacity: 0.70)
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

    private var availabilityBadge: BadgeDescriptor {
        switch detail.availabilityLabel.lowercased() {
        case "available":
            BadgeDescriptor(title: "Available", systemImage: "checkmark.circle.fill", variant: .success)
        case "unavailable", "no files":
            BadgeDescriptor(title: "Missing File", systemImage: "xmark.circle.fill", variant: .danger)
        case "partially available":
            BadgeDescriptor(title: "Partial Availability", systemImage: "exclamationmark.circle.fill", variant: .warning)
        default:
            BadgeDescriptor(
                title: CineMindDisplayText.friendlyStatus(detail.availabilityLabel),
                systemImage: "info.circle",
                variant: .neutral
            )
        }
    }

    private var metadataBadge: BadgeDescriptor {
        switch detail.metadataLabel.lowercased() {
        case "complete":
            BadgeDescriptor(title: "Matched", systemImage: "checkmark.seal.fill", variant: .success)
        case "partial":
            BadgeDescriptor(title: "Partial Metadata", systemImage: "exclamationmark.circle.fill", variant: .warning)
        case "missing":
            BadgeDescriptor(title: "Needs Metadata", systemImage: "tag.fill", variant: .accent)
        default:
            BadgeDescriptor(
                title: CineMindDisplayText.friendlyStatus(detail.metadataLabel),
                systemImage: "tag",
                variant: .neutral
            )
        }
    }

    private struct BadgeDescriptor {
        let title: String
        let systemImage: String
        let variant: LiquidGlassBadge.Variant
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
