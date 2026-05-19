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

@MainActor
public final class LibraryItemDetailViewModel: ObservableObject {
    @Published public private(set) var detail: LibraryItemDetailShell?
    @Published public private(set) var detailState: DetailState = .empty
    @Published public private(set) var posterImageState: PosterImageState = .idle
    @Published public private(set) var playbackStatus: PlaybackApplicationStatus = .idle

    private let detailBrowser: any LibraryItemDetailBrowsing
    private let posterImageLoader: any PosterImageLoading
    private var playbackController: (any PlaybackApplicationControlling)?
    private var playbackStatusTask: Task<Void, Never>?
    private var currentItemID: MediaItemID?
    private var loadingGeneration: Int = 0

    public init(
        detailBrowser: any LibraryItemDetailBrowsing,
        playbackController: (any PlaybackApplicationControlling)? = nil
    ) {
        self.detailBrowser = detailBrowser
        self.posterImageLoader = LocalPosterImageLoader()
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
}

public struct LibraryItemDetailView: View {
    @ObservedObject var viewModel: LibraryItemDetailViewModel

    public init(viewModel: LibraryItemDetailViewModel) {
        self.viewModel = viewModel
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

            ForEach(files, id: \.fileName) { file in
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
                }
            }
        }
    }

    private func displayValue(_ value: String?) -> String {
        value ?? "Not provided"
    }
}
