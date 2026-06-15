import Application
import SwiftUI

struct LibraryDetailMetadataSection: View {
    let metadata: LibraryMetadataDetail

    var body: some View {
        LiquidGlassCard("Metadata", systemImage: "tag") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    Text("Match Status")
                        .font(.callout.weight(.medium))
                        .cinemindSecondaryTextStyle(opacity: 0.70)
                    Spacer()
                    metadataStatusBadge(metadata.statusLabel)
                }

                Divider()
                    .opacity(0.35)

                VStack(alignment: .leading, spacing: 10) {
                    metadataFieldRow(
                        "Local Title",
                        value: CineMindDisplayText.value(metadata.localTitle)
                    )
                    metadataFieldRow(
                        "Matched Title",
                        value: CineMindDisplayText.value(metadata.metadataTitle)
                    )
                    metadataFieldRow(
                        "Original Title",
                        value: CineMindDisplayText.value(metadata.originalTitle)
                    )
                    metadataFieldRow(
                        "Language",
                        value: CineMindDisplayText.value(metadata.languageLabel)
                    )
                    metadataFieldRow(
                        "Release Date",
                        value: CineMindDisplayText.value(metadata.releaseOrAirDateLabel)
                    )
                }
            }
        }
    }

    private func metadataFieldRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label)
                .font(.callout.weight(.medium))
                .cinemindSecondaryTextStyle(opacity: 0.62)
                .frame(width: 116, alignment: .leading)

            Text(value)
                .font(.callout)
                .foregroundStyle(.white.opacity(value == CineMindDisplayText.emptyValue ? 0.50 : 0.84))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metadataStatusBadge(_ value: String) -> some View {
        let descriptor = metadataStatusDescriptor(value)
        return LiquidGlassBadge(
            descriptor.title,
            systemImage: descriptor.systemImage,
            variant: descriptor.variant
        )
    }

    private func metadataStatusDescriptor(_ value: String) -> BadgeDescriptor {
        switch value.lowercased() {
        case "complete":
            BadgeDescriptor(
                title: "Matched",
                systemImage: "checkmark.seal.fill",
                variant: .success
            )
        case "partial":
            BadgeDescriptor(
                title: "Partial",
                systemImage: "exclamationmark.circle.fill",
                variant: .warning
            )
        case "missing":
            BadgeDescriptor(
                title: "Needs Metadata",
                systemImage: "tag.fill",
                variant: .accent
            )
        default:
            BadgeDescriptor(
                title: CineMindDisplayText.friendlyStatus(value),
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
}
