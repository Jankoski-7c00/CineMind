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

@MainActor
public final class LibraryItemDetailViewModel: ObservableObject {
    @Published public private(set) var detail: LibraryItemDetailShell?
    @Published public private(set) var detailState: DetailState = .empty

    private let detailBrowser: any LibraryItemDetailBrowsing
    private var currentItemID: MediaItemID?
    private var loadingGeneration: Int = 0

    public init(detailBrowser: any LibraryItemDetailBrowsing) {
        self.detailBrowser = detailBrowser
    }

    public func loadDetail(for id: MediaItemID?) async {
        guard let id else {
            loadingGeneration += 1
            currentItemID = nil
            detail = nil
            detailState = .empty
            return
        }

        loadingGeneration += 1
        let generation = loadingGeneration
        currentItemID = id
        detailState = .loading

        do {
            let result = try await detailBrowser.fetchDetail(id: id)
            guard generation == loadingGeneration else { return }
            if let result {
                detail = result
                detailState = .loaded
            } else {
                detail = nil
                detailState = .notFound
            }
        } catch {
            guard generation == loadingGeneration else { return }
            detail = nil
            detailState = .error(error.localizedDescription)
        }
    }

    public func retry() {
        guard let id = currentItemID else { return }
        Task { await loadDetail(for: id) }
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
            VStack(alignment: .leading, spacing: 12) {
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

                if let summary = detail.summary {
                    Text(summary)
                        .font(.body)
                }

                Divider()

                LabeledContent("Availability", value: detail.availabilityLabel)
                LabeledContent("Metadata", value: detail.metadataLabel)
                if let lastPlayedLabel = detail.lastPlayedLabel {
                    LabeledContent("Last Played", value: lastPlayedLabel)
                }

                if !detail.files.isEmpty {
                    Divider()
                    Text("Files")
                        .font(.headline)
                    ForEach(detail.files, id: \.fileName) { file in
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
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
