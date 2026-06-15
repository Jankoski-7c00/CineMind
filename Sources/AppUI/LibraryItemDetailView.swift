import Application
import SwiftUI

public struct LibraryItemDetailView: View {
    @ObservedObject var viewModel: LibraryItemDetailViewModel
    private let playbackSurface: AnyView?

    @State private var isScrubbing = false
    @State private var scrubPositionMS: Double = 0

    public init(
        viewModel: LibraryItemDetailViewModel,
        playbackSurface: AnyView? = nil
    ) {
        self.viewModel = viewModel
        self.playbackSurface = playbackSurface
    }

    public var body: some View {
        Group {
            switch viewModel.detailState {
            case .empty:
                emptyContent
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notFound:
                notFoundContent
            case .error(let message):
                errorContent(message: message)
            case .loaded:
                if let detail = viewModel.detail {
                    detailContent(detail)
                }
            }
        }
    }

    private var emptyContent: some View {
        ContentUnavailableView(
            "No Selection",
            systemImage: "film.stack",
            description: Text("Select a media item to view its details.")
        )
    }

    private var notFoundContent: some View {
        ContentUnavailableView(
            "Item Not Found",
            systemImage: "questionmark.folder",
            description: Text("The selected media item is no longer available.")
        )
    }

    private func errorContent(message: String) -> some View {
        ContentUnavailableView {
            Label("Failed to Load Detail", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry", systemImage: "arrow.clockwise") {
                viewModel.retry()
            }
        }
    }

    private func detailContent(_ detail: LibraryItemDetailShell) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MediaDetailHeaderView(
                    detail: detail,
                    posterImageState: viewModel.posterImageState
                )

                LibraryDetailPrimaryActionSection(
                    files: detail.files,
                    playbackStatus: viewModel.playbackStatus,
                    onPlay: { viewModel.playFile(mediaFileID: $0) },
                    onResume: { viewModel.resumePlayback() }
                )

                playbackBlock(for: detail)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(detail.id)
        }
    }

    @ViewBuilder
    private func playbackBlock(for detail: LibraryItemDetailShell) -> some View {
        if let status = playbackStatus(for: detail) {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    if let playbackSurface {
                        ZStack(alignment: .bottom) {
                            playbackSurface
                                .id("playback-surface")
                                .frame(maxWidth: .infinity)
                                .frame(height: 320)
                                .background(Color.black)

                            if let subtitleText = status.activeSubtitleText {
                                subtitleOverlay(text: subtitleText)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(playbackStatusLabel(status))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if case .loading = status.state,
                               status.positionMS > 0 {
                                Text("Resuming from \(timeLabel(milliseconds: status.positionMS))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if let notice = status.notice, !notice.isEmpty {
                                Text(notice)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        playbackControls(for: status.state)
                    }

                    playbackTrackMenus(for: status)

                    VStack(spacing: 4) {
                        if let durationMS = status.durationMS, durationMS > 0 {
                            Slider(
                                value: Binding(
                                    get: {
                                        isScrubbing
                                            ? scrubPositionMS
                                            : Double(status.positionMS)
                                    },
                                    set: { newValue in
                                        scrubPositionMS = newValue
                                        if !isScrubbing {
                                            isScrubbing = true
                                        }
                                    }
                                ),
                                in: 0...Double(durationMS),
                                onEditingChanged: { editing in
                                    if editing {
                                        if !isScrubbing {
                                            scrubPositionMS = Double(status.positionMS)
                                        }
                                        isScrubbing = true
                                    } else {
                                        isScrubbing = false
                                        viewModel.seek(toMS: Int(scrubPositionMS.rounded()))
                                    }
                                }
                            )
                        } else {
                            ProgressView(value: playbackProgressRatio(status), total: 1.0)
                        }
                        HStack {
                            Text(timeLabel(
                                milliseconds: isScrubbing
                                    ? Int(scrubPositionMS)
                                    : status.positionMS
                            ))
                            Spacer()
                            Text(playbackDurationLabel(status.durationMS))
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                    }
                }
            } label: {
                Label("Playback", systemImage: "play.rectangle")
            }
            .onChange(of: status.positionMS) { _, newPositionMS in
                guard !isScrubbing else { return }
                scrubPositionMS = Double(newPositionMS)
            }
            .onAppear {
                scrubPositionMS = Double(status.positionMS)
                isScrubbing = false
            }
        }
    }

    @ViewBuilder
    private func playbackTrackMenus(for status: PlaybackApplicationStatus) -> some View {
        let isEnabled = trackSelectionEnabled(status.state)
        if !status.audioTracks.isEmpty || !status.subtitleTracks.isEmpty {
            HStack(spacing: 8) {
                if !status.audioTracks.isEmpty {
                    trackMenu(
                        title: "Audio",
                        systemImage: "speaker.wave.2.fill",
                        tracks: status.audioTracks,
                        isEnabled: isEnabled
                    ) { trackID in
                        viewModel.selectAudioTrack(trackID: trackID)
                    }
                }

                if !status.subtitleTracks.isEmpty {
                    subtitleTrackMenu(
                        tracks: status.subtitleTracks,
                        isEnabled: isEnabled
                    )
                }
            }
        }
    }

    private func trackMenu(
        title: String,
        systemImage: String,
        tracks: [PlaybackApplicationTrack],
        isEnabled: Bool,
        select: @escaping (String) -> Void
    ) -> some View {
        Menu {
            ForEach(tracks) { track in
                Button {
                    select(track.id)
                } label: {
                    trackMenuItemLabel(track.displayLabel, isSelected: track.isSelected)
                }
                .disabled(!isEnabled || track.isSelected)
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
        .controlSize(.small)
        .disabled(!isEnabled)
    }

    private func subtitleTrackMenu(
        tracks: [PlaybackApplicationTrack],
        isEnabled: Bool
    ) -> some View {
        let subtitlesDisabled = !tracks.contains(where: \.isSelected)
        return Menu {
            Button {
                viewModel.disableSubtitles()
            } label: {
                trackMenuItemLabel("Off", isSelected: subtitlesDisabled)
            }
            .disabled(!isEnabled || subtitlesDisabled)

            Divider()

            ForEach(tracks) { track in
                Button {
                    viewModel.selectSubtitleTrack(trackID: track.id)
                } label: {
                    trackMenuItemLabel(track.displayLabel, isSelected: track.isSelected)
                }
                .disabled(!isEnabled || track.isSelected || !track.isSelectable)
            }
        } label: {
            Label("Subtitles", systemImage: "captions.bubble")
        }
        .controlSize(.small)
        .disabled(!isEnabled)
    }

    private func trackMenuItemLabel(
        _ label: String,
        isSelected: Bool
    ) -> some View {
        HStack {
            Text(label)
            if isSelected {
                Image(systemName: "checkmark")
            }
        }
    }

    private func subtitleOverlay(text: String) -> some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
            .shadow(radius: 2)
    }

    private func trackSelectionEnabled(_ state: PlaybackApplicationState) -> Bool {
        switch state {
        case .ready, .playing, .paused, .buffering:
            true
        case .idle, .loading, .ended, .failed:
            false
        }
    }

    private func playbackStatus(for detail: LibraryItemDetailShell) -> PlaybackApplicationStatus? {
        let status = viewModel.playbackStatus
        guard status.state != .idle else {
            return nil
        }

        guard let activeMediaFileID = status.mediaFileID else {
            return nil
        }

        guard detail.files.contains(where: { $0.mediaFileID == activeMediaFileID }) else {
            return nil
        }

        return status
    }

    @ViewBuilder
    private func playbackControls(for state: PlaybackApplicationState) -> some View {
        HStack(spacing: 8) {
            switch state {
            case .playing:
                seekBackwardButton
                Button {
                    viewModel.pausePlayback()
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .controlSize(.small)

                seekForwardButton
                stopPlaybackButton
            case .paused:
                seekBackwardButton
                Button {
                    viewModel.resumePlayback()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .controlSize(.small)

                seekForwardButton
                stopPlaybackButton
            case .loading, .ready, .buffering, .ended, .failed(_):
                stopPlaybackButton
            case .idle:
                EmptyView()
            }
        }
    }

    private var seekBackwardButton: some View {
        Button {
            viewModel.seekRelative(byMS: -10_000)
        } label: {
            Label("Back 10s", systemImage: "gobackward.10")
        }
        .controlSize(.small)
    }

    private var seekForwardButton: some View {
        Button {
            viewModel.seekRelative(byMS: 10_000)
        } label: {
            Label("Forward 10s", systemImage: "goforward.10")
        }
        .controlSize(.small)
    }

    private var stopPlaybackButton: some View {
        Button {
            viewModel.stopPlayback()
        } label: {
            Label("Stop", systemImage: "stop.fill")
        }
        .controlSize(.small)
    }


    private func playbackStatusLabel(_ status: PlaybackApplicationStatus) -> String {
        let stateLabel = playbackStateLabel(status.state)

        var parts = [stateLabel]
        if let displayName = status.displayName, !displayName.isEmpty {
            parts.append(displayName)
        }
        return parts.joined(separator: " - ")
    }

    private func playbackStateLabel(_ state: PlaybackApplicationState) -> String {
        switch state {
        case .idle:
            "Idle"
        case .loading:
            "Loading"
        case .ready:
            "Ready"
        case .playing:
            "Playing"
        case .paused:
            "Paused"
        case .buffering:
            "Buffering"
        case .ended:
            "Ended"
        case .failed(let message):
            "Failed: \(message)"
        }
    }

    private func playbackDurationLabel(_ durationMS: Int?) -> String {
        guard let durationMS, durationMS > 0 else {
            return "--:--"
        }

        return timeLabel(milliseconds: durationMS)
    }

    private func playbackProgressRatio(_ status: PlaybackApplicationStatus) -> Double {
        guard let durationMS = status.durationMS, durationMS > 0 else {
            return 0
        }

        let progress = Double(status.positionMS) / Double(durationMS)
        return min(max(progress, 0), 1)
    }

    private func timeLabel(milliseconds: Int) -> String {
        let totalSeconds = max(0, milliseconds) / 1_000
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours):\(twoDigit(minutes)):\(twoDigit(seconds))"
        }
        return "\(minutes):\(twoDigit(seconds))"
    }

    private func twoDigit(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }

}
