import Application
import Domain
import SwiftUI

struct LibraryDetailFilesSection: View {
    let files: [LibraryFileSummary]
    let playbackStatus: PlaybackApplicationStatus
    let onPlay: (MediaFileID) -> Void
    let onResume: () -> Void

    var body: some View {
        LiquidGlassCard("Files", systemImage: "doc") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(files, id: \.mediaFileID) { file in
                    fileRow(file)

                    if file.mediaFileID != files.last?.mediaFileID {
                        Divider()
                            .opacity(0.30)
                    }
                }
            }
        }
    }

    private func fileRow(_ file: LibraryFileSummary) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(file.fileName)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.90))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(file.fileSizeLabel)
                    if let resumeLabel = file.resumePositionLabel, file.isPlayable {
                        Text("·")
                        Text("Resume from \(resumeLabel)")
                    }
                    if let reason = file.playabilityReason {
                        Text("·")
                        Text(reason)
                            .help(reason)
                    }
                }
                .font(.caption)
                .cinemindSecondaryTextStyle(opacity: 0.62)
                .lineLimit(1)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                fileAvailabilityBadge(file.availabilityLabel)

                if file.isPlayable {
                    let buttonState = LibraryFilePlaybackPresentation.buttonState(
                        for: file,
                        playbackStatus: playbackStatus
                    )
                    Button {
                        perform(buttonState, mediaFileID: file.mediaFileID)
                    } label: {
                        Label(buttonState.title, systemImage: buttonState.systemImage)
                    }
                    .buttonStyle(.liquidGlassPrimary)
                    .disabled(buttonState.isDisabled)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func perform(
        _ buttonState: LibraryFilePlaybackButtonState,
        mediaFileID: MediaFileID
    ) {
        switch buttonState {
        case .play:
            onPlay(mediaFileID)
        case .resume:
            onResume()
        case .disabled:
            break
        }
    }

    private func fileAvailabilityBadge(_ value: String) -> some View {
        let descriptor = fileAvailabilityDescriptor(value)
        return LiquidGlassBadge(
            descriptor.title,
            systemImage: descriptor.systemImage,
            variant: descriptor.variant
        )
    }

    private func fileAvailabilityDescriptor(_ value: String) -> BadgeDescriptor {
        switch value.lowercased() {
        case "available":
            BadgeDescriptor(
                title: "Available",
                systemImage: "checkmark.circle.fill",
                variant: .success
            )
        case "unavailable", "no files":
            BadgeDescriptor(
                title: "Missing File",
                systemImage: "xmark.circle.fill",
                variant: .danger
            )
        case "folder unavailable":
            BadgeDescriptor(
                title: "Folder Missing",
                systemImage: "folder.badge.questionmark",
                variant: .warning
            )
        case "partially available":
            BadgeDescriptor(
                title: "Partial",
                systemImage: "exclamationmark.circle.fill",
                variant: .warning
            )
        default:
            BadgeDescriptor(
                title: CineMindDisplayText.friendlyStatus(value),
                systemImage: "info.circle",
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
