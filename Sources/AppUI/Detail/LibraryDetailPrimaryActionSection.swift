import Application
import Domain
import SwiftUI

struct LibraryDetailPrimaryActionSection: View {
    let files: [LibraryFileSummary]
    let playbackStatus: PlaybackApplicationStatus
    let onPlay: (MediaFileID) -> Void
    let onResume: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let file = LibraryFilePlaybackPresentation.primaryFile(
                in: files,
                playbackStatus: playbackStatus
            ) {
                let buttonState = LibraryFilePlaybackPresentation.buttonState(
                    for: file,
                    playbackStatus: playbackStatus
                )
                Button {
                    perform(buttonState, mediaFileID: file.mediaFileID)
                } label: {
                    Label(buttonState.title, systemImage: buttonState.systemImage)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(buttonState.isDisabled)

                VStack(alignment: .leading, spacing: 3) {
                    Text(file.fileName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    if let resumeLabel = file.resumePositionLabel {
                        Text("Resume from \(resumeLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(file.fileSizeLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Label("No playable local file", systemImage: "play.slash")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
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
}
