import Application
@testable import AppUI
import Domain
import XCTest

@MainActor
final class TMDBSettingsViewModelTests: XCTestCase {
    func testSavedTokenIsNeverLoadedIntoDraftAndSuccessfulSaveClearsDraft() {
        let manager = FakeTMDBReadTokenSettingsManager(status: .savedTokenActive)
        let viewModel = TMDBSettingsViewModel()

        viewModel.setManager(manager)
        XCTAssertEqual(viewModel.tokenDraft, "")
        XCTAssertEqual(viewModel.status, .savedTokenActive)

        viewModel.tokenDraft = "very-secret-token"
        viewModel.saveToken()

        XCTAssertEqual(manager.savedTokens, ["very-secret-token"])
        XCTAssertEqual(viewModel.tokenDraft, "")
        XCTAssertEqual(viewModel.feedback, .success("TMDB API Read Access Token saved."))
    }

    func testSettingsErrorsDoNotExposeDraftToken() {
        let manager = FakeTMDBReadTokenSettingsManager(status: .notConfigured)
        manager.saveError = TMDBReadTokenSettingsError.storageUnavailable
        let viewModel = TMDBSettingsViewModel()
        viewModel.setManager(manager)
        viewModel.tokenDraft = "very-secret-token"

        viewModel.saveToken()

        guard case .error(let message) = viewModel.feedback else {
            return XCTFail("Expected safe settings error feedback.")
        }
        XCTAssertFalse(message.contains("very-secret-token"))
    }

    func testDetailViewModelCanReplaceMetadataActionsImmediately() {
        let viewModel = LibraryItemDetailViewModel(detailBrowser: EmptyDetailBrowser())
        XCTAssertFalse(viewModel.metadataActionsAvailable)

        viewModel.setMetadataActions(FakeMetadataActions(), unavailableMessage: nil)
        XCTAssertTrue(viewModel.metadataActionsAvailable)
        XCTAssertNil(viewModel.metadataActionsUnavailableMessage)

        viewModel.setMetadataActions(nil, unavailableMessage: "Open CineMind Settings.")
        XCTAssertFalse(viewModel.metadataActionsAvailable)
        XCTAssertEqual(viewModel.metadataActionsUnavailableMessage, "Open CineMind Settings.")
    }

    func testMetadataActionsStatePublishesEachRuntimeReplacement() {
        let state = LibraryMetadataActionsState()
        XCTAssertEqual(state.revision, 0)

        state.update(actions: FakeMetadataActions(), unavailableMessage: nil)
        XCTAssertEqual(state.revision, 1)
        XCTAssertNotNil(state.actions)

        state.update(actions: nil, unavailableMessage: "Open CineMind Settings.")
        XCTAssertEqual(state.revision, 2)
        XCTAssertNil(state.actions)
    }
}

@MainActor
private final class FakeTMDBReadTokenSettingsManager: TMDBReadTokenSettingsManaging {
    private(set) var status: TMDBReadTokenConfigurationStatus
    var saveError: Error?
    var removeError: Error?
    private(set) var savedTokens: [String] = []

    init(status: TMDBReadTokenConfigurationStatus) {
        self.status = status
    }

    func saveToken(_ token: String) throws {
        if let saveError {
            throw saveError
        }
        savedTokens.append(token)
        status = .savedTokenActive
    }

    func removeSavedToken() throws {
        if let removeError {
            throw removeError
        }
        status = .notConfigured
    }
}

private struct EmptyDetailBrowser: LibraryItemDetailBrowsing {
    func fetchDetail(id: MediaItemID) async throws -> LibraryItemDetailShell? {
        nil
    }
}

private struct FakeMetadataActions: LibraryMetadataActionHandling {
    func refreshMetadata(mediaItemID: MediaItemID) async throws -> LibraryMetadataActionResult {
        LibraryMetadataActionResult(message: "Refreshed.")
    }

    func searchMetadataCandidates(mediaItemID: MediaItemID) async throws -> [LibraryMetadataCandidate] {
        []
    }

    func rematchMetadata(
        mediaItemID: MediaItemID,
        providerID: String
    ) async throws -> LibraryMetadataActionResult {
        LibraryMetadataActionResult(message: "Rematched.")
    }

    func setMetadataOverride(
        mediaItemID: MediaItemID,
        field: MetadataOverrideField,
        value: String?
    ) async throws -> LibraryMetadataActionResult {
        LibraryMetadataActionResult(message: "Saved.")
    }

    func clearMetadataOverride(
        mediaItemID: MediaItemID,
        field: MetadataOverrideField
    ) async throws -> LibraryMetadataActionResult {
        LibraryMetadataActionResult(message: "Cleared.")
    }

    func selectPoster(
        mediaItemID: MediaItemID,
        posterAssetID: PosterAssetID
    ) async throws -> LibraryMetadataActionResult {
        LibraryMetadataActionResult(message: "Selected.")
    }
}
