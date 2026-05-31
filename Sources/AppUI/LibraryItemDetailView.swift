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

public enum SubtitleActionStatus: Equatable, Sendable {
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
    @Published public private(set) var subtitleActionStatus: SubtitleActionStatus = .idle
    @Published public private(set) var subtitleCandidates: [LibrarySubtitleCandidate] = []
    @Published public private(set) var isSearchingSubtitleCandidates = false
    @Published public private(set) var downloadingSubtitleResultID: String?
    @Published public private(set) var installedSubtitleResultIDs: Set<String> = []

    private let detailBrowser: any LibraryItemDetailBrowsing
    private let posterImageLoader: any PosterImageLoading
    private let metadataActions: (any LibraryMetadataActionHandling)?
    public let metadataActionsUnavailableMessage: String?
    private let subtitleActions: (any LibrarySubtitleActionHandling)?
    public let subtitleActionsUnavailableMessage: String?
    private var playbackController: (any PlaybackApplicationControlling)?
    private var playbackStatusTask: Task<Void, Never>?
    private var currentItemID: MediaItemID?
    private var loadingGeneration: Int = 0

    public init(
        detailBrowser: any LibraryItemDetailBrowsing,
        playbackController: (any PlaybackApplicationControlling)? = nil,
        metadataActions: (any LibraryMetadataActionHandling)? = nil,
        metadataActionsUnavailableMessage: String? = nil,
        subtitleActions: (any LibrarySubtitleActionHandling)? = nil,
        subtitleActionsUnavailableMessage: String? = nil
    ) {
        self.detailBrowser = detailBrowser
        self.posterImageLoader = LocalPosterImageLoader()
        self.metadataActions = metadataActions
        self.metadataActionsUnavailableMessage = metadataActionsUnavailableMessage
        self.subtitleActions = subtitleActions
        self.subtitleActionsUnavailableMessage = subtitleActionsUnavailableMessage
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
            resetSubtitleActionState()
            return
        }

        loadingGeneration += 1
        let generation = loadingGeneration
        currentItemID = id
        detailState = .loading
        posterImageState = .idle
        resetSubtitleActionState()

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

    public var subtitleActionsAvailable: Bool {
        subtitleActions != nil
    }

    public var subtitleTargetAvailable: Bool {
        subtitleTargetMediaFileID() != nil
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

    public func searchSubtitleCandidates() {
        guard let subtitleActions, let currentItemID else {
            subtitleActionStatus = .error(subtitleUnavailableMessage)
            return
        }

        guard let mediaFileID = subtitleTargetMediaFileID() else {
            subtitleActionStatus = .error(subtitlePlayableFileRequiredMessage)
            return
        }

        subtitleActionStatus = .loading("Searching subtitles...")
        subtitleCandidates = []
        isSearchingSubtitleCandidates = true

        Task {
            do {
                let candidates = try await subtitleActions.searchSubtitles(
                    mediaItemID: currentItemID,
                    mediaFileID: mediaFileID,
                    languageCode: nil
                )
                subtitleCandidates = candidates
                subtitleActionStatus = .success(
                    candidates.isEmpty
                        ? "No subtitles found."
                        : "\(candidates.count) subtitle candidates found."
                )
            } catch {
                subtitleCandidates = []
                subtitleActionStatus = .error(actionErrorMessage(error))
            }
            isSearchingSubtitleCandidates = false
        }
    }

    public func downloadSubtitle(resultID: String) {
        guard let subtitleActions, let currentItemID else {
            subtitleActionStatus = .error(subtitleUnavailableMessage)
            return
        }

        guard let mediaFileID = subtitleTargetMediaFileID() else {
            subtitleActionStatus = .error(subtitlePlayableFileRequiredMessage)
            return
        }

        downloadingSubtitleResultID = resultID
        subtitleActionStatus = .loading("Downloading subtitle...")

        Task {
            do {
                let result = try await subtitleActions.downloadSubtitle(
                    mediaItemID: currentItemID,
                    mediaFileID: mediaFileID,
                    resultID: resultID
                )
                installedSubtitleResultIDs.insert(result.resultID)
                subtitleActionStatus = .success(result.message)
            } catch {
                subtitleActionStatus = .error(actionErrorMessage(error))
            }
            downloadingSubtitleResultID = nil
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

    private var subtitleUnavailableMessage: String {
        subtitleActionsUnavailableMessage ?? "Subtitle search is unavailable."
    }

    private var subtitlePlayableFileRequiredMessage: String {
        "A playable local file is required before subtitles can be downloaded."
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

    private func resetSubtitleActionState() {
        subtitleActionStatus = .idle
        subtitleCandidates = []
        isSearchingSubtitleCandidates = false
        downloadingSubtitleResultID = nil
        installedSubtitleResultIDs = []
    }

    private func subtitleTargetMediaFileID() -> MediaFileID? {
        guard let detail else {
            return nil
        }

        if let activeMediaFileID = playbackStatus.mediaFileID,
           detail.files.contains(where: { $0.mediaFileID == activeMediaFileID && $0.isPlayable }) {
            return activeMediaFileID
        }

        return detail.files.first(where: \.isPlayable)?.mediaFileID
    }

    private func actionErrorMessage(_ error: Error) -> String {
        if let actionError = error as? LibraryMetadataActionError {
            return actionError.message
        }
        if let actionError = error as? LibrarySubtitleActionError {
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
    @State private var isSubtitleSearchSheetPresented = false
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
        .sheet(isPresented: $isSubtitleSearchSheetPresented) {
            subtitleCandidateSheet
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
        ZStack {
            detailBackdrop

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MediaDetailHeaderView(
                        detail: detail,
                        posterImageState: viewModel.posterImageState
                    )

                    primaryActionRow(files: detail.files)

                    playbackBlock(for: detail)

                    metadataBlock(detail.metadataDetail)

                    if !detail.files.isEmpty {
                        filesBlock(detail.files)
                    }

                    subtitleActionsBlock

                    metadataActionsBlock(detail)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(detail.id)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.easeOut(duration: 0.18), value: detail.id)
            }
        }
    }

    private var detailBackdrop: some View {
        LinearGradient(
            colors: [
                Color.black,
                Color(red: 0.08, green: 0.09, blue: 0.11),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var subtitleActionsBlock: some View {
        LiquidGlassCard {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 14) {
                    if viewModel.subtitleActionsAvailable {
                        subtitleActionButtons
                        subtitleActionStatusView
                    } else {
                        subtitleUnavailableCallout
                    }
                }
                .padding(.top, 10)
            } label: {
                Label("Advanced Subtitles", systemImage: "captions.bubble")
                    .cinemindSectionTitleStyle()
            }
        }
    }

    private var subtitleActionButtons: some View {
        HStack(spacing: 8) {
            Button {
                isSubtitleSearchSheetPresented = true
                viewModel.searchSubtitleCandidates()
            } label: {
                Label("Search Online", systemImage: "magnifyingglass")
            }
            .buttonStyle(.liquidGlass)
            .disabled(!viewModel.subtitleTargetAvailable)

            if !viewModel.subtitleTargetAvailable {
                Text("A playable local file is required.")
                    .font(.caption)
                    .cinemindSecondaryTextStyle(opacity: 0.72)
            }

            Spacer()
        }
        .controlSize(.small)
    }

    private var subtitleUnavailableCallout: some View {
        Label(
            viewModel.subtitleActionsUnavailableMessage
                ?? "Subtitle search is not configured. Local and embedded subtitles are still available.",
            systemImage: "exclamationmark.circle"
        )
        .font(.callout)
        .cinemindSecondaryTextStyle(opacity: 0.76)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassSurface(cornerRadius: 12, material: .ultraThinMaterial)
    }

    @ViewBuilder
    private var subtitleActionStatusView: some View {
        switch viewModel.subtitleActionStatus {
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

    private func metadataActionsBlock(_ detail: LibraryItemDetailShell) -> some View {
        LiquidGlassCard {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 14) {
                    if viewModel.metadataActionsAvailable {
                        metadataActionButtons
                        metadataActionStatusView
                        overrideEditor(detail.metadataDetail)
                    } else {
                        metadataUnavailableCallout
                    }

                    Divider()
                    sourceBlock(detail.metadataDetail.source)

                    Divider()
                    posterAssetsBlock(detail.posterAssets)
                }
                .padding(.top, 10)
            } label: {
                Label("Advanced Metadata", systemImage: "slider.horizontal.3")
                    .cinemindSectionTitleStyle()
            }
        }
        .onAppear {
            syncOverrideDrafts(from: detail.metadataDetail)
        }
        .onChange(of: detail.metadataDetail) { _, metadata in
            syncOverrideDrafts(from: metadata)
        }
    }

    private var metadataActionButtons: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.refreshMetadata()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.liquidGlass)

            Button {
                isRematchSheetPresented = true
                viewModel.searchMetadataCandidates()
            } label: {
                Label("Search Matches", systemImage: "magnifyingglass")
            }
            .buttonStyle(.liquidGlass)

            Spacer()
        }
        .controlSize(.small)
    }

    private var metadataUnavailableCallout: some View {
        Label(
            viewModel.metadataActionsUnavailableMessage
                ?? "Set CINEMIND_TMDB_READ_TOKEN to enable online metadata matching.",
            systemImage: "exclamationmark.circle"
        )
        .font(.callout)
        .cinemindSecondaryTextStyle(opacity: 0.76)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassSurface(cornerRadius: 12, material: .ultraThinMaterial)
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

    private var subtitleCandidateSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Subtitle Results")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    isSubtitleSearchSheetPresented = false
                }
            }

            subtitleActionStatusView

            if viewModel.isSearchingSubtitleCandidates {
                ProgressView("Searching...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.subtitleCandidates.isEmpty {
                Text("No subtitles found")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.subtitleCandidates) { candidate in
                    subtitleCandidateRow(candidate)
                }
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 340)
    }

    private func subtitleCandidateRow(_ candidate: LibrarySubtitleCandidate) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.title)
                    .font(.headline)
                HStack(spacing: 8) {
                    Text(candidate.languageLabel)
                    Text(candidate.formatLabel)
                }
                .font(.caption)
                .foregroundColor(.secondary)
                if let reason = candidate.unavailableReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            let isInstalled = viewModel.installedSubtitleResultIDs.contains(candidate.resultID)
            Button {
                viewModel.downloadSubtitle(resultID: candidate.resultID)
            } label: {
                if viewModel.downloadingSubtitleResultID == candidate.resultID {
                    Label("Downloading", systemImage: "arrow.down.circle")
                } else if isInstalled {
                    Label("Installed", systemImage: "checkmark.circle")
                } else {
                    Label("Download", systemImage: "arrow.down.circle")
                }
            }
            .controlSize(.small)
            .disabled(
                !candidate.isDownloadable
                    || isInstalled
                    || viewModel.downloadingSubtitleResultID != nil
            )
        }
        .padding(.vertical, 4)
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

    private func primaryActionRow(files: [LibraryFileSummary]) -> some View {
        LiquidGlassPanel(
            cornerRadius: 18,
            material: .thinMaterial,
            padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        ) {
            HStack(spacing: 12) {
                if let file = primaryPlaybackFile(in: files) {
                    let buttonState = filePlaybackButtonState(for: file)
                    Button {
                        performFilePlaybackAction(
                            buttonState,
                            mediaFileID: file.mediaFileID
                        )
                    } label: {
                        Label(buttonState.title, systemImage: buttonState.systemImage)
                    }
                    .buttonStyle(.liquidGlassPrimary)
                    .disabled(buttonState.isDisabled)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(file.fileName)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        if let resumeLabel = file.resumePositionLabel {
                            Text("Resume from \(resumeLabel)")
                                .font(.caption)
                                .cinemindSecondaryTextStyle()
                        } else {
                            Text(file.fileSizeLabel)
                                .font(.caption)
                                .cinemindSecondaryTextStyle()
                        }
                    }
                } else {
                    Label("No playable local file", systemImage: "play.slash")
                        .font(.callout.weight(.medium))
                        .cinemindSecondaryTextStyle(opacity: 0.72)
                }

                Spacer()
            }
        }
    }

    private func primaryPlaybackFile(in files: [LibraryFileSummary]) -> LibraryFileSummary? {
        if let activeMediaFileID = viewModel.playbackStatus.mediaFileID,
           let activeFile = files.first(where: { $0.mediaFileID == activeMediaFileID && $0.isPlayable }) {
            return activeFile
        }

        return files.first(where: \.isPlayable)
    }

    @ViewBuilder
    private func playbackBlock(for detail: LibraryItemDetailShell) -> some View {
        if let status = playbackStatus(for: detail) {
            LiquidGlassCard("Playback", systemImage: "play.rectangle") {
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

    private func metadataBlock(_ metadata: LibraryMetadataDetail) -> some View {
        LiquidGlassCard("Metadata", systemImage: "tag") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Status", value: metadataStatusLabel(metadata.statusLabel))
                LabeledContent("Local Title", value: CineMindDisplayText.value(metadata.localTitle))
                LabeledContent("Matched Title", value: CineMindDisplayText.value(metadata.metadataTitle))
                LabeledContent("Original Title", value: CineMindDisplayText.value(metadata.originalTitle))
                LabeledContent("Summary", value: CineMindDisplayText.summary(metadata.summary))
                LabeledContent("Language", value: CineMindDisplayText.value(metadata.languageLabel))
                LabeledContent("Release Date", value: CineMindDisplayText.value(metadata.releaseOrAirDateLabel))
            }
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
                Text(CineMindDisplayText.emptyValue)
                    .cinemindSecondaryTextStyle()
            }
        }
    }

    private func posterAssetsBlock(_ posterAssets: [LibraryPosterAssetDetail]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Poster Assets")
                .font(.headline)

            if posterAssets.isEmpty {
                Text(CineMindDisplayText.emptyValue)
                    .cinemindSecondaryTextStyle()
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
                Text(posterAssetStatusLabel(asset.statusLabel))
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
        LiquidGlassCard("Files", systemImage: "doc") {
            VStack(alignment: .leading, spacing: 8) {
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
                        Text(fileAvailabilityLabel(file.availabilityLabel))
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
        CineMindDisplayText.value(value)
    }

    private func fileAvailabilityLabel(_ value: String) -> String {
        switch value.lowercased() {
        case "available":
            "Available"
        case "unavailable":
            "Missing File"
        case "folder unavailable":
            "Folder Missing"
        default:
            CineMindDisplayText.friendlyStatus(value)
        }
    }

    private func metadataStatusLabel(_ value: String) -> String {
        switch value.lowercased() {
        case "complete":
            "Matched"
        case "partial":
            "Partial"
        case "missing":
            "Needs Metadata"
        default:
            CineMindDisplayText.friendlyStatus(value)
        }
    }

    private func posterAssetStatusLabel(_ value: String) -> String {
        switch value.lowercased() {
        case "cached":
            "Cached"
        case "uncached":
            "Remote Only"
        default:
            CineMindDisplayText.friendlyStatus(value)
        }
    }
}
