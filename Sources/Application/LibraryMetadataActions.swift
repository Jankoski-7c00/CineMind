import Domain
import Foundation
import Metadata

public struct LibraryMetadataCandidate: Identifiable, Sendable, Equatable {
    public let id: String
    public let providerID: String
    public let title: String
    public let subtitle: String?
    public let overviewPreview: String?
    public let confidenceLabel: String

    public init(
        providerID: String,
        title: String,
        subtitle: String?,
        overviewPreview: String?,
        confidenceLabel: String
    ) {
        self.id = providerID
        self.providerID = providerID
        self.title = title
        self.subtitle = subtitle
        self.overviewPreview = overviewPreview
        self.confidenceLabel = confidenceLabel
    }
}

public struct LibraryMetadataActionResult: Sendable, Equatable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

public struct LibraryMetadataActionError: Error, LocalizedError, Sendable, Equatable {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}

public protocol LibraryMetadataActionHandling: Sendable {
    func refreshMetadata(mediaItemID: MediaItemID) async throws -> LibraryMetadataActionResult
    func searchMetadataCandidates(mediaItemID: MediaItemID) async throws -> [LibraryMetadataCandidate]
    func rematchMetadata(
        mediaItemID: MediaItemID,
        providerID: String
    ) async throws -> LibraryMetadataActionResult
    func setMetadataOverride(
        mediaItemID: MediaItemID,
        field: MetadataOverrideField,
        value: String?
    ) async throws -> LibraryMetadataActionResult
    func clearMetadataOverride(
        mediaItemID: MediaItemID,
        field: MetadataOverrideField
    ) async throws -> LibraryMetadataActionResult
    func selectPoster(
        mediaItemID: MediaItemID,
        posterAssetID: PosterAssetID
    ) async throws -> LibraryMetadataActionResult
}

public final class LibraryMetadataActionService: LibraryMetadataActionHandling, @unchecked Sendable {
    private let store: any ApplicationMetadataStore
    private let provider: any MetadataProvider
    private let posterCache: (any ApplicationPosterCaching)?
    private let language: String?
    private let now: () -> Date

    public init(
        store: any ApplicationMetadataStore,
        provider: any MetadataProvider,
        posterCache: (any ApplicationPosterCaching)? = nil,
        language: String? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.provider = provider
        self.posterCache = posterCache
        self.language = language
        self.now = now
    }

    public func refreshMetadata(mediaItemID: MediaItemID) async throws -> LibraryMetadataActionResult {
        do {
            let result = try await RefreshMetadataUseCase(
                store: store,
                provider: provider,
                posterCache: posterCache,
                now: now
            ).refresh(mediaItemID: mediaItemID, language: language)
            return LibraryMetadataActionResult(message: message(for: result))
        } catch {
            throw mapActionError(error)
        }
    }

    public func searchMetadataCandidates(
        mediaItemID: MediaItemID
    ) async throws -> [LibraryMetadataCandidate] {
        do {
            let candidates = try await SearchMetadataCandidatesUseCase(
                store: store,
                provider: provider
            ).search(mediaItemID: mediaItemID, language: language)
            return candidates.map(mapCandidate)
        } catch {
            throw mapActionError(error)
        }
    }

    public func rematchMetadata(
        mediaItemID: MediaItemID,
        providerID: String
    ) async throws -> LibraryMetadataActionResult {
        do {
            _ = try await ManualMatchMetadataUseCase(
                store: store,
                provider: provider,
                posterCache: posterCache,
                now: now
            ).match(
                mediaItemID: mediaItemID,
                providerID: providerID,
                language: language
            )
            return LibraryMetadataActionResult(message: "Metadata match saved.")
        } catch {
            throw mapActionError(error)
        }
    }

    public func setMetadataOverride(
        mediaItemID: MediaItemID,
        field: MetadataOverrideField,
        value: String?
    ) async throws -> LibraryMetadataActionResult {
        do {
            _ = try SetMetadataOverrideUseCase(store: store, now: now).set(
                mediaItemID: mediaItemID,
                field: field,
                value: value
            )
            return LibraryMetadataActionResult(message: "\(label(for: field)) override saved.")
        } catch {
            throw mapActionError(error)
        }
    }

    public func clearMetadataOverride(
        mediaItemID: MediaItemID,
        field: MetadataOverrideField
    ) async throws -> LibraryMetadataActionResult {
        do {
            _ = try ClearMetadataOverrideUseCase(store: store, now: now).clear(
                mediaItemID: mediaItemID,
                field: field
            )
            return LibraryMetadataActionResult(message: "\(label(for: field)) override cleared.")
        } catch {
            throw mapActionError(error)
        }
    }

    public func selectPoster(
        mediaItemID: MediaItemID,
        posterAssetID: PosterAssetID
    ) async throws -> LibraryMetadataActionResult {
        do {
            try SelectPosterAssetUseCase(store: store).select(
                mediaItemID: mediaItemID,
                posterAssetID: posterAssetID
            )
            return LibraryMetadataActionResult(message: "Poster selected.")
        } catch {
            throw mapActionError(error)
        }
    }

    private func mapCandidate(_ candidate: MetadataCandidate) -> LibraryMetadataCandidate {
        LibraryMetadataCandidate(
            providerID: candidate.identifier.rawValue,
            title: candidate.displayTitle,
            subtitle: subtitle(for: candidate),
            overviewPreview: candidate.overviewPreview,
            confidenceLabel: confidenceLabel(candidate.confidence)
        )
    }

    private func subtitle(for candidate: MetadataCandidate) -> String? {
        [
            candidate.year.map(String.init),
            candidate.airDate
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        .joined(separator: " · ")
        .nilIfEmpty
    }

    private func confidenceLabel(_ confidence: Double) -> String {
        "\(Int((confidence * 100).rounded()))%"
    }

    private func message(for result: RefreshMetadataResult) -> String {
        switch result {
        case .refreshed:
            "Metadata refreshed."
        case .autoMatched(let autoMatchResult):
            message(for: autoMatchResult)
        }
    }

    private func message(for result: AutoMatchMetadataResult) -> String {
        switch result {
        case .matched:
            "Metadata matched and refreshed."
        case .skippedManualLock:
            "Manual metadata match was preserved."
        case .noCandidates:
            "No metadata candidates found."
        case .lowConfidence:
            "No high-confidence metadata match found."
        case .ambiguous:
            "Multiple metadata matches need review."
        }
    }

    private func label(for field: MetadataOverrideField) -> String {
        switch field {
        case .title:
            "Title"
        case .summary:
            "Summary"
        case .language:
            "Language"
        }
    }

    private func mapActionError(_ error: Error) -> LibraryMetadataActionError {
        if let actionError = error as? LibraryMetadataActionError {
            return actionError
        }

        if let metadataError = error as? MetadataError {
            return LibraryMetadataActionError(message: message(for: metadataError))
        }

        if let applicationError = error as? ApplicationMetadataError {
            return LibraryMetadataActionError(message: message(for: applicationError))
        }

        return LibraryMetadataActionError(message: "Metadata action failed.")
    }

    private func message(for error: MetadataError) -> String {
        switch error {
        case .missingToken:
            "TMDB read token is missing. Open CineMind Settings to configure it."
        case .unauthorized:
            "TMDB rejected the configured token."
        case .notFound:
            "TMDB could not find that metadata record."
        case .rateLimited:
            "TMDB rate limit reached. Try again later."
        case .serverUnavailable:
            "TMDB is temporarily unavailable. Try again later."
        case .invalidResponse:
            "TMDB returned an invalid metadata response."
        case .transportFailure:
            "Metadata provider request failed."
        }
    }

    private func message(for error: ApplicationMetadataError) -> String {
        switch error {
        case .mediaItemNotFound:
            "Media item was not found."
        case .posterAssetMediaItemMismatch:
            "That poster is not available for this item."
        case .missingEpisodeInfo:
            "This episode is missing season or episode information."
        case .invalidProviderID:
            "The selected metadata candidate is invalid."
        case .providerMismatch:
            "Existing metadata source does not match the configured provider."
        case .providerMediaTypeMismatch:
            "Selected metadata candidate does not match this item type."
        case .episodeProviderIDMismatch:
            "Selected episode candidate does not match this episode."
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
