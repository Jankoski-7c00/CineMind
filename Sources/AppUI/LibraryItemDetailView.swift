import Application
import Domain
import SwiftUI

public enum DetailState: Equatable, Sendable {
    case empty
    case loading
    case loaded
    case notFound
    case error(String)
}

public enum PosterImageState: Sendable {
    case idle
    case loading
    case loaded(LoadedPosterImage)
    case placeholder(PosterImagePlaceholderReason)
}

public enum MetadataActionStatus: Equatable, Sendable {
    case idle
    case loading(String)
    case success(String)
    case error(String)
}

private enum FilePlaybackButtonState {
    case play
    case resume
    case disabled(String)

    var title: String {
        switch self {
        case .play:
            "Play"
        case .resume:
            "Resume"
        case .disabled(let title):
            title
        }
    }

    var systemImage: String {
        switch self {
        case .play, .resume:
            "play.fill"
        case .disabled:
            "play.slash"
        }
    }

    var isDisabled: Bool {
        if case .disabled = self {
            return true
        }
        return false
    }
}

@MainActor
public final class LibraryItemDetailViewModel: ObservableObject {
    @Published public private(set) var detail: LibraryItemDetailShell?
    @Published public private(set) var detailState: DetailState = .empty
    @Published public private(set) var posterImageState: PosterImageState = .idle
    @Published public private(set) var playbackStatus: PlaybackApplicationStatus = .idle
    @Published public private(set) var metadataActionStatus: MetadataActionStatus = .idle
    @Published public private(set) var metadataCandidates: [LibraryMetadataCandidate] = []
    @Published public private(set) var isSearchingMetadataCandidates = false
    @Published public private(set) var metadataMutationRevision = 0

    private let detailBrowser: any LibraryItemDetailBrowsing
    private let posterImageLoader: any PosterImageLoading
    private let metadataActions: (any LibraryMetadataActionHandling)?
    public let metadataActionsUnavailableMessage: String?
    private var playbackController: (any PlaybackApplicationControlling)?
    private var playbackStatusTask: Task<Void, Never>?
    private var currentItemID: MediaItemID?
    private var loadingGeneration: Int = 0

    public init(
        detailBrowser: any LibraryItemDetailBrowsing,
        playbackController: (any PlaybackApplicationControlling)? = nil,
        metadataActions: (any LibraryMetadataActionHandling)? = nil,
        metadataActionsUnavailableMessage: String? = nil
    ) {
        self.detailBrowser = detailBrowser
        self.posterImageLoader = LocalPosterImageLoader()
        self.metadataActions = metadataActions
        self.metadataActionsUnavailableMessage = metadataActionsUnavailableMessage
        setPlaybackController(playbackController)
    }

    deinit {
        playbackStatusTask?.cancel()
    }

    public func setPlaybackController(_ controller: (any PlaybackApplicationControlling)?) {
        playbackStatusTask?.cancel()
        playbackStatusTask = nil
        playbackController = controller
        playbackStatus = .idle

        guard let controller else {
            return
        }

        playbackStatusTask = Task { [weak self, controller] in
            for await status in controller.statusStream {
                guard !Task.isCancelled else {
                    break
                }

                await MainActor.run { [weak self] in
                    self?.playbackStatus = status
                }
            }
        }
    }

    public func loadDetail(for id: MediaItemID?) async {
        guard let id else {
            loadingGeneration += 1
            currentItemID = nil
            detail = nil
            detailState = .empty
            posterImageState = .idle
            metadataActionStatus = .idle
            metadataCandidates = []
            isSearchingMetadataCandidates = false
            return
        }

        loadingGeneration += 1
        let generation = loadingGeneration
        currentItemID = id
        detailState = .loading
        posterImageState = .idle

        do {
            let result = try await detailBrowser.fetchDetail(id: id)
            guard generation == loadingGeneration else { return }
            if let result {
                detail = result
                detailState = .loaded
                await loadPosterImage(
                    localCachePath: result.selectedPoster.localCachePath,
                    generation: generation
                )
            } else {
                detail = nil
                detailState = .notFound
                posterImageState = .idle
            }
        } catch {
            guard generation == loadingGeneration else { return }
            detail = nil
            detailState = .error(error.localizedDescription)
            posterImageState = .idle
        }
    }

    public func retry() {
        guard let id = currentItemID else { return }
        Task { await loadDetail(for: id) }
    }

    public var metadataActionsAvailable: Bool {
        metadataActions != nil
    }

    public func refreshMetadata() {
        runMetadataMutation(loadingMessage: "Refreshing metadata...") { actions, mediaItemID in
            try await actions.refreshMetadata(mediaItemID: mediaItemID)
        }
    }

    public func searchMetadataCandidates() {
        guard let metadataActions, let currentItemID else {
            metadataActionStatus = .error(metadataUnavailableMessage)
            return
        }

        metadataActionStatus = .loading("Searching metadata...")
        metadataCandidates = []
        isSearchingMetadataCandidates = true

        Task {
            do {
                let candidates = try await metadataActions.searchMetadataCandidates(
                    mediaItemID: currentItemID
                )
                metadataCandidates = candidates
                metadataActionStatus = .success(
                    candidates.isEmpty
                        ? "No metadata candidates found."
                        : "\(candidates.count) metadata candidates found."
                )
            } catch {
                metadataCandidates = []
                metadataActionStatus = .error(actionErrorMessage(error))
            }
            isSearchingMetadataCandidates = false
        }
    }

    public func rematchMetadata(providerID: String) {
        runMetadataMutation(loadingMessage: "Saving metadata match...") { actions, mediaItemID in
            try await actions.rematchMetadata(
                mediaItemID: mediaItemID,
                providerID: providerID
            )
        }
    }

    public func setMetadataOverride(
        field: MetadataOverrideField,
        value: String?
    ) {
        runMetadataMutation(loadingMessage: "Saving metadata override...") { actions, mediaItemID in
            try await actions.setMetadataOverride(
                mediaItemID: mediaItemID,
                field: field,
                value: value
            )
        }
    }

    public func clearMetadataOverride(field: MetadataOverrideField) {
        runMetadataMutation(loadingMessage: "Clearing metadata override...") { actions, mediaItemID in
            try await actions.clearMetadataOverride(
                mediaItemID: mediaItemID,
                field: field
            )
        }
    }

    public func selectPoster(posterAssetID: PosterAssetID) {
        runMetadataMutation(loadingMessage: "Selecting poster...") { actions, mediaItemID in
            try await actions.selectPoster(
                mediaItemID: mediaItemID,
                posterAssetID: posterAssetID
            )
        }
    }

    public func playFile(mediaFileID: MediaFileID) {
        guard let playbackController else {
            playbackStatus = PlaybackApplicationStatus(
                state: .failed("Playback is unavailable."),
                mediaFileID: mediaFileID,
                displayName: nil,
                positionMS: 0,
                durationMS: nil
            )
            return
        }

        Task {
            await playbackController.open(mediaFileID: mediaFileID)
        }
    }

    public func stopPlayback() {
        guard let playbackController else {
            playbackStatus = .idle
            return
        }

        Task {
            await playbackController.stop()
        }
    }

    public func pausePlayback() {
        guard let playbackController else {
            return
        }

        Task {
            await playbackController.pause()
        }
    }

    public func resumePlayback() {
        guard let playbackController else {
            return
        }

        Task {
            await playbackController.resume()
        }
    }

    public func seek(toMS positionMS: Int) {
        guard let playbackController else {
            return
        }

        Task {
            await playbackController.seek(toMS: positionMS)
        }
    }

    public func seekRelative(byMS deltaMS: Int) {
        guard let playbackController else {
            return
        }

        Task {
            await playbackController.seekRelative(byMS: deltaMS)
        }
    }

    public func selectAudioTrack(trackID: String) {
        guard let playbackController else {
            return
        }

        Task {
            await playbackController.selectAudioTrack(trackID: trackID)
        }
    }

    public func selectSubtitleTrack(trackID: String) {
        guard let playbackController else {
            return
        }

        Task {
            await playbackController.selectSubtitleTrack(trackID: trackID)
        }
    }

    public func disableSubtitles() {
        guard let playbackController else {
            return
        }

        Task {
            await playbackController.disableSubtitles()
        }
    }

    public func togglePlayPause() {
        guard let playbackController else {
            return
        }

        Task {
            await playbackController.togglePlayPause()
        }
    }

    private func loadPosterImage(localCachePath: String?, generation: Int) async {
        guard generation == loadingGeneration else { return }
        posterImageState = .loading
        let result = await posterImageLoader.load(localCachePath: localCachePath)
        guard generation == loadingGeneration else { return }

        switch result {
        case .loaded(let image):
            posterImageState = .loaded(image)
        case .placeholder(let reason):
            posterImageState = .placeholder(reason)
        }
    }

    private var metadataUnavailableMessage: String {
        metadataActionsUnavailableMessage ?? "Metadata actions are unavailable."
    }

    private func runMetadataMutation(
        loadingMessage: String,
        operation: @escaping (
            any LibraryMetadataActionHandling,
            MediaItemID
        ) async throws -> LibraryMetadataActionResult
    ) {
        guard let metadataActions, let currentItemID else {
            metadataActionStatus = .error(metadataUnavailableMessage)
            return
        }

        metadataActionStatus = .loading(loadingMessage)

        Task {
            do {
                let result = try await operation(metadataActions, currentItemID)
                metadataActionStatus = .success(result.message)
                metadataMutationRevision += 1
                await loadDetail(for: currentItemID)
            } catch {
                metadataActionStatus = .error(actionErrorMessage(error))
            }
        }
    }

    private func actionErrorMessage(_ error: Error) -> String {
        if let actionError = error as? LibraryMetadataActionError {
            return actionError.message
        }
        return error.localizedDescription
    }
}

public struct LibraryItemDetailView: View {
    @ObservedObject var viewModel: LibraryItemDetailViewModel
    private let playbackSurface: AnyView?

    @State private var isScrubbing = false
    @State private var scrubPositionMS: Double = 0
    @State private var isRematchSheetPresented = false
    @State private var titleOverrideText = ""
    @State private var summaryOverrideText = ""
    @State private var languageOverrideText = ""

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
        .sheet(isPresented: $isRematchSheetPresented) {
            metadataCandidateSheet
        }
    }

    private var emptyContent: some View {
        Text("Select an item")
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var notFoundContent: some View {
        Text("Item not found")
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorContent(message: String) -> some View {
        VStack(spacing: 12) {
            Text("Failed to load detail")
                .font(.headline)
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                viewModel.retry()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func detailContent(_ detail: LibraryItemDetailShell) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    posterPanel(
                        selectedPoster: detail.selectedPoster,
                        imageState: viewModel.posterImageState
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        titleBlock(detail)
                        overviewBlock(detail)
                        statusBlock(detail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                playbackBlock(for: detail)

                Divider()
                metadataActionsBlock(detail)

                Divider()
                metadataBlock(detail.metadataDetail)

                Divider()
                sourceBlock(detail.metadataDetail.source)

                Divider()
                posterAssetsBlock(detail.posterAssets)

                if !detail.files.isEmpty {
                    Divider()
                    filesBlock(detail.files)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metadataActionsBlock(_ detail: LibraryItemDetailShell) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Metadata Actions")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.refreshMetadata()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(!viewModel.metadataActionsAvailable)

                Button {
                    isRematchSheetPresented = true
                    viewModel.searchMetadataCandidates()
                } label: {
                    Label("Search Matches", systemImage: "magnifyingglass")
                }
                .controlSize(.small)
                .disabled(!viewModel.metadataActionsAvailable)
            }

            if let unavailableMessage = viewModel.metadataActionsUnavailableMessage {
                Label(unavailableMessage, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            metadataActionStatusView
            overrideEditor(detail.metadataDetail)
        }
        .onAppear {
            syncOverrideDrafts(from: detail.metadataDetail)
        }
        .onChange(of: detail.metadataDetail) { _, metadata in
            syncOverrideDrafts(from: metadata)
        }
    }

    @ViewBuilder
    private var metadataActionStatusView: some View {
        switch viewModel.metadataActionStatus {
        case .idle:
            EmptyView()
        case .loading(let message):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(message)
                    .foregroundColor(.secondary)
            }
            .font(.callout)
        case .success(let message):
            Label(message, systemImage: "checkmark.circle")
                .font(.callout)
                .foregroundColor(.green)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundColor(.red)
        }
    }

    private func overrideEditor(_ metadata: LibraryMetadataDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overrides")
                .font(.subheadline)

            overrideRow(
                label: "Title",
                text: $titleOverrideText,
                field: .title,
                isLocked: metadata.titleOverrideLocked
            )
            overrideRow(
                label: "Summary",
                text: $summaryOverrideText,
                field: .summary,
                isLocked: metadata.summaryOverrideLocked
            )
            overrideRow(
                label: "Language",
                text: $languageOverrideText,
                field: .language,
                isLocked: metadata.languageOverrideLocked
            )
        }
    }

    private func overrideRow(
        label: String,
        text: Binding<String>,
        field: MetadataOverrideField,
        isLocked: Bool
    ) -> some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                TextField(label, text: text)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!viewModel.metadataActionsAvailable)

                Button {
                    viewModel.setMetadataOverride(field: field, value: text.wrappedValue)
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .controlSize(.small)
                .disabled(!viewModel.metadataActionsAvailable)

                Button {
                    viewModel.clearMetadataOverride(field: field)
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .controlSize(.small)
                .disabled(!viewModel.metadataActionsAvailable || !isLocked)
            }
        }
    }

    private var metadataCandidateSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Metadata Matches")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    isRematchSheetPresented = false
                }
            }

            if viewModel.isSearchingMetadataCandidates {
                ProgressView("Searching...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.metadataCandidates.isEmpty {
                Text("No matches found")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.metadataCandidates) { candidate in
                    Button {
                        isRematchSheetPresented = false
                        viewModel.rematchMetadata(providerID: candidate.providerID)
                    } label: {
                        metadataCandidateRow(candidate)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .frame(minWidth: 460, minHeight: 320)
    }

    private func metadataCandidateRow(_ candidate: LibraryMetadataCandidate) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.title)
                    .font(.headline)
                if let subtitle = candidate.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let overviewPreview = candidate.overviewPreview {
                    Text(overviewPreview)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Text(candidate.confidenceLabel)
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func syncOverrideDrafts(from metadata: LibraryMetadataDetail) {
        titleOverrideText = metadata.metadataTitle ?? ""
        summaryOverrideText = metadata.summary ?? ""
        languageOverrideText = metadata.languageLabel ?? ""
    }

    @ViewBuilder
    private func playbackBlock(for detail: LibraryItemDetailShell) -> some View {
        if let status = playbackStatus(for: detail) {
            VStack(alignment: .leading, spacing: 10) {
                if let playbackSurface {
                    playbackSurface
                        .id("playback-surface")
                        .frame(maxWidth: .infinity)
                        .frame(height: 320)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Playback")
                            .font(.headline)
                        Text(playbackStatusLabel(status))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if case .loading = status.state,
                           status.positionMS > 0 {
                            Text("Resuming from \(timeLabel(milliseconds: status.positionMS))")
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
                .disabled(!isEnabled || track.isSelected)
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

    private func posterPanel(
        selectedPoster: LibrarySelectedPosterDetail,
        imageState: PosterImageState
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.35), lineWidth: 1)

            switch imageState {
            case .loaded(let loadedImage):
                Image(decorative: loadedImage.image, scale: 1.0)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 140, height: 210)
                    .clipped()
                    .overlay(alignment: .bottom) {
                        Text(selectedPoster.statusLabel)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity)
                            .background(Color.black.opacity(0.55))
                    }
            case .idle:
                posterPlaceholderContent(selectedPoster: selectedPoster)
            case .loading:
                posterPlaceholderContent(
                    selectedPoster: selectedPoster
                ) {
                    ProgressView()
                        .controlSize(.small)
                }
            case .placeholder(let reason):
                posterPlaceholderContent(
                    selectedPoster: selectedPoster,
                    reasonLabel: posterPlaceholderReasonLabel(reason)
                )
            }
        }
        .frame(width: 140, height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private func posterPlaceholderContent<Accessory: View>(
        selectedPoster: LibrarySelectedPosterDetail,
        reasonLabel: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        VStack(spacing: 8) {
            Text(selectedPoster.statusLabel)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(selectedPoster.placeholderSeed)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if let reasonLabel {
                Text(reasonLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            accessory()
        }
        .padding(10)
    }

    private func posterPlaceholderContent(
        selectedPoster: LibrarySelectedPosterDetail,
        reasonLabel: String? = nil
    ) -> some View {
        posterPlaceholderContent(
            selectedPoster: selectedPoster,
            reasonLabel: reasonLabel
        ) {
            EmptyView()
        }
    }

    private func posterPlaceholderReasonLabel(_ reason: PosterImagePlaceholderReason) -> String {
        switch reason {
        case .noCachePath:
            "no cache path"
        case .fileMissing:
            "file missing"
        case .decodeFailed:
            "decode failed"
        }
    }

    private func titleBlock(_ detail: LibraryItemDetailShell) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(detail.displayTitle)
                .font(.title)

            HStack {
                Text(detail.mediaTypeLabel)
                if let yearOrEpisodeLabel = detail.yearOrEpisodeLabel {
                    Text("·")
                    Text(yearOrEpisodeLabel)
                }
            }
            .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func overviewBlock(_ detail: LibraryItemDetailShell) -> some View {
        if let summary = detail.summary {
            Text(summary)
                .font(.body)
        }
    }

    private func statusBlock(_ detail: LibraryItemDetailShell) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Availability", value: detail.availabilityLabel)
            LabeledContent("Metadata", value: detail.metadataLabel)
            if let lastPlayedLabel = detail.lastPlayedLabel {
                LabeledContent("Last Played", value: lastPlayedLabel)
            }
        }
    }

    private func metadataBlock(_ metadata: LibraryMetadataDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metadata")
                .font(.headline)

            LabeledContent("Status", value: metadata.statusLabel)
            LabeledContent("Local Title", value: metadata.localTitle)
            LabeledContent("Metadata Title", value: displayValue(metadata.metadataTitle))
            LabeledContent("Original Title", value: displayValue(metadata.originalTitle))
            LabeledContent("Summary", value: displayValue(metadata.summary))
            LabeledContent("Language", value: displayValue(metadata.languageLabel))
            LabeledContent("Date", value: displayValue(metadata.releaseOrAirDateLabel))
        }
    }

    @ViewBuilder
    private func sourceBlock(_ source: LibraryMetadataSourceDetail?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Source")
                .font(.headline)

            if let source {
                LabeledContent("Provider", value: source.providerLabel)
                LabeledContent("Provider ID", value: source.providerID)
                LabeledContent("Media Type", value: source.providerMediaTypeLabel)
                LabeledContent("Confidence", value: source.confidenceLabel)
                LabeledContent("Match Source", value: source.matchSourceLabel)
                LabeledContent("Manual Lock", value: source.manualMatchLockLabel)
                LabeledContent("Matched", value: source.matchedAtLabel)
                LabeledContent("Refreshed", value: displayValue(source.refreshedAtLabel))
            } else {
                Text("Not provided")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func posterAssetsBlock(_ posterAssets: [LibraryPosterAssetDetail]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Poster Assets")
                .font(.headline)

            if posterAssets.isEmpty {
                Text("Not provided")
                    .foregroundColor(.secondary)
            } else {
                ForEach(posterAssets) { asset in
                    posterAssetRow(asset)
                    if asset.id != posterAssets.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private func posterAssetRow(_ asset: LibraryPosterAssetDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(asset.isSelected ? "Selected" : "Available")
                    .font(.subheadline)
                Spacer()
                Text(asset.statusLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !asset.isSelected {
                    Button {
                        viewModel.selectPoster(posterAssetID: asset.id)
                    } label: {
                        Label("Select", systemImage: "photo")
                    }
                    .controlSize(.small)
                    .disabled(!viewModel.metadataActionsAvailable)
                }
            }

            Text(asset.remotePath)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            LabeledContent("Source", value: asset.sourceLabel)
            LabeledContent("Dimensions", value: displayValue(asset.dimensionsLabel))
            LabeledContent("Cached", value: displayValue(asset.cachedAtLabel))
            LabeledContent("Preferred Size", value: asset.preferredCacheSizeLabel)
            LabeledContent("Selection Source", value: asset.selectionSourceLabel)
        }
    }

    private func filesBlock(_ files: [LibraryFileSummary]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Files")
                .font(.headline)

            ForEach(files, id: \.mediaFileID) { file in
                HStack {
                    VStack(alignment: .leading) {
                        Text(file.fileName)
                            .lineLimit(1)
                        Text(file.fileSizeLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(file.availabilityLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let reason = file.playabilityReason {
                        Text(reason)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .help(reason)
                    }
                    if file.isPlayable,
                       let resumeLabel = file.resumePositionLabel {
                        Text("Resume from \(resumeLabel)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if file.isPlayable {
                        let buttonState = filePlaybackButtonState(for: file)
                        Button {
                            performFilePlaybackAction(
                                buttonState,
                                mediaFileID: file.mediaFileID
                            )
                        } label: {
                            Label(buttonState.title, systemImage: buttonState.systemImage)
                        }
                        .controlSize(.small)
                        .disabled(buttonState.isDisabled)
                    }
                }
            }
        }
    }

    private func filePlaybackButtonState(
        for file: LibraryFileSummary
    ) -> FilePlaybackButtonState {
        let status = viewModel.playbackStatus
        guard status.mediaFileID == file.mediaFileID else {
            return .play
        }

        switch status.state {
        case .idle, .ended, .failed:
            return .play
        case .paused:
            return .resume
        case .loading, .ready:
            return .disabled("Starting")
        case .playing:
            return .disabled("Playing")
        case .buffering:
            return .disabled("Buffering")
        }
    }

    private func performFilePlaybackAction(
        _ buttonState: FilePlaybackButtonState,
        mediaFileID: MediaFileID
    ) {
        switch buttonState {
        case .play:
            viewModel.playFile(mediaFileID: mediaFileID)
        case .resume:
            viewModel.resumePlayback()
        case .disabled:
            break
        }
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

    private func displayValue(_ value: String?) -> String {
        value ?? "Not provided"
    }
}
