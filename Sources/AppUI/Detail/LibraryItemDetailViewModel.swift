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

public enum CurationActionStatus: Equatable, Sendable {
    case idle
    case loading(String)
    case success(String)
    case error(String)
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
    @Published public private(set) var curationActionStatus: CurationActionStatus = .idle
    @Published public private(set) var curationMutationRevision = 0
    @Published public private(set) var subtitleActionStatus: SubtitleActionStatus = .idle
    @Published public private(set) var subtitleCandidates: [LibrarySubtitleCandidate] = []
    @Published public private(set) var isSearchingSubtitleCandidates = false
    @Published public private(set) var downloadingSubtitleResultID: String?
    @Published public private(set) var installedSubtitleResultIDs: Set<String> = []

    private let detailBrowser: any LibraryItemDetailBrowsing
    private let posterImageLoader: any PosterImageLoading
    private var metadataActions: (any LibraryMetadataActionHandling)?
    @Published public private(set) var metadataActionsUnavailableMessage: String?
    private let curationActions: (any LibraryCurationHandling)?
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
        curationActions: (any LibraryCurationHandling)? = nil,
        subtitleActions: (any LibrarySubtitleActionHandling)? = nil,
        subtitleActionsUnavailableMessage: String? = nil
    ) {
        self.detailBrowser = detailBrowser
        self.posterImageLoader = LocalPosterImageLoader()
        self.metadataActions = metadataActions
        self.metadataActionsUnavailableMessage = metadataActionsUnavailableMessage
        self.curationActions = curationActions
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
            curationActionStatus = .idle
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

    public func setMetadataActions(
        _ actions: (any LibraryMetadataActionHandling)?,
        unavailableMessage: String?
    ) {
        metadataActions = actions
        metadataActionsUnavailableMessage = unavailableMessage
        metadataActionStatus = .idle
        metadataCandidates = []
        isSearchingMetadataCandidates = false
    }

    public var curationActionsAvailable: Bool {
        curationActions != nil
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

    public func setFavorite(_ isFavorite: Bool) {
        runCurationMutation(
            loadingMessage: "Updating favorite...",
            successMessage: isFavorite ? "Added to favorites." : "Removed from favorites."
        ) { actions, mediaItemID in
            _ = try await actions.setFavorite(mediaItemID: mediaItemID, isFavorite: isFavorite)
        }
    }

    public func createAndAssignTag(name: String) {
        runCurationMutation(
            loadingMessage: "Adding tag...",
            successMessage: "Tag added."
        ) { actions, mediaItemID in
            let tag = try await actions.createTag(name: name)
            _ = try await actions.assignTag(tagID: tag.id, mediaItemID: mediaItemID)
        }
    }

    public func assignTag(tagID: TagID) {
        runCurationMutation(
            loadingMessage: "Assigning tag...",
            successMessage: "Tag assigned."
        ) { actions, mediaItemID in
            _ = try await actions.assignTag(tagID: tagID, mediaItemID: mediaItemID)
        }
    }

    public func removeTag(tagID: TagID) {
        runCurationMutation(
            loadingMessage: "Removing tag...",
            successMessage: "Tag removed."
        ) { actions, mediaItemID in
            _ = try await actions.removeTag(tagID: tagID, mediaItemID: mediaItemID)
        }
    }

    public func renameTag(tagID: TagID, name: String) {
        runCurationMutation(
            loadingMessage: "Renaming tag...",
            successMessage: "Tag renamed."
        ) { actions, _ in
            _ = try await actions.renameTag(tagID: tagID, name: name)
        }
    }

    public func deleteTag(tagID: TagID) {
        runCurationMutation(
            loadingMessage: "Deleting tag...",
            successMessage: "Tag deleted."
        ) { actions, _ in
            try await actions.deleteTag(tagID: tagID)
        }
    }

    public func createAndAddCollection(name: String) {
        runCurationMutation(
            loadingMessage: "Adding collection...",
            successMessage: "Collection updated."
        ) { actions, mediaItemID in
            let collection = try await actions.createCollection(name: name, description: nil)
            _ = try await actions.addToCollection(collectionID: collection.id, mediaItemID: mediaItemID)
        }
    }

    public func addToCollection(collectionID: CollectionID) {
        runCurationMutation(
            loadingMessage: "Adding to collection...",
            successMessage: "Collection updated."
        ) { actions, mediaItemID in
            _ = try await actions.addToCollection(collectionID: collectionID, mediaItemID: mediaItemID)
        }
    }

    public func removeFromCollection(collectionID: CollectionID) {
        runCurationMutation(
            loadingMessage: "Removing from collection...",
            successMessage: "Collection updated."
        ) { actions, mediaItemID in
            _ = try await actions.removeFromCollection(collectionID: collectionID, mediaItemID: mediaItemID)
        }
    }

    public func renameCollection(collectionID: CollectionID, name: String) {
        runCurationMutation(
            loadingMessage: "Renaming collection...",
            successMessage: "Collection renamed."
        ) { actions, _ in
            _ = try await actions.renameCollection(
                collectionID: collectionID,
                name: name,
                description: nil
            )
        }
    }

    public func deleteCollection(collectionID: CollectionID) {
        runCurationMutation(
            loadingMessage: "Deleting collection...",
            successMessage: "Collection deleted."
        ) { actions, _ in
            try await actions.deleteCollection(collectionID: collectionID)
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

    private func runCurationMutation(
        loadingMessage: String,
        successMessage: String,
        operation: @escaping (
            any LibraryCurationHandling,
            MediaItemID
        ) async throws -> Void
    ) {
        guard let curationActions, let currentItemID else {
            curationActionStatus = .error("Curation actions are unavailable.")
            return
        }

        curationActionStatus = .loading(loadingMessage)

        Task {
            do {
                try await operation(curationActions, currentItemID)
                curationActionStatus = .success(successMessage)
                curationMutationRevision += 1
                await loadDetail(for: currentItemID)
            } catch {
                curationActionStatus = .error(actionErrorMessage(error))
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
        if let actionError = error as? LibraryCurationError {
            return actionError.message
        }
        return error.localizedDescription
    }
}
