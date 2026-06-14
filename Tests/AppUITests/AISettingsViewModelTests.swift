import Application
@testable import AppUI
import XCTest

@MainActor
final class AISettingsViewModelTests: XCTestCase {
    func testDefaultDisplayIsDisabledAndNotConfigured() {
        let viewModel = AISettingsViewModel()
        viewModel.setManager(FakeAISettingsManager(snapshot: defaultSnapshot))

        XCTAssertFalse(viewModel.isEnabled)
        XCTAssertEqual(
            viewModel.policyDescription,
            "AI features are disabled. Keyword search and manual tags remain available."
        )
        XCTAssertEqual(
            viewModel.providerStatusDescription,
            "No AI provider is configured. Keyword search and manual tags remain available."
        )
    }

    func testChangingToggleDelegatesToApplicationManager() {
        let manager = FakeAISettingsManager(snapshot: defaultSnapshot)
        let viewModel = AISettingsViewModel()
        viewModel.setManager(manager)

        viewModel.setEnabled(true)

        XCTAssertEqual(manager.setEnabledCalls, [true])
        XCTAssertTrue(viewModel.isEnabled)
        XCTAssertEqual(viewModel.snapshot.policyStatus, .notConfigured)
    }

    func testStorageFailureLeavesToggleDisabled() {
        let manager = FakeAISettingsManager(snapshot: defaultSnapshot)
        manager.setEnabledError = AISettingsError.storageUnavailable
        let viewModel = AISettingsViewModel()
        viewModel.setManager(manager)

        viewModel.setEnabled(true)

        XCTAssertFalse(viewModel.isEnabled)
        XCTAssertEqual(
            viewModel.feedback,
            .error("CineMind could not update AI settings. AI remains disabled.")
        )
    }

    func testProviderStatusDisplaysOnlyApplicationSafeValues() {
        let secret = "private-provider-id?token=secret"
        let snapshot = AISettingsSnapshot(
            isEnabled: true,
            providerStatus: .ready(
                providerLabel: "Local Provider",
                capabilityLabels: ["Chat", "Embeddings"]
            ),
            policyStatus: .ready
        )
        let viewModel = AISettingsViewModel()
        viewModel.setManager(FakeAISettingsManager(snapshot: snapshot))

        XCTAssertEqual(
            viewModel.providerStatusDescription,
            "Local Provider is configured and available."
        )
        XCTAssertEqual(viewModel.capabilityLabels, ["Chat", "Embeddings"])
        XCTAssertFalse(viewModel.providerStatusDescription.contains(secret))
        XCTAssertFalse(viewModel.capabilityLabels.joined().contains(secret))
    }

    func testUnavailableManagerKeepsSafeDefaultAndClearFeedback() {
        let viewModel = AISettingsViewModel()

        viewModel.setEnabled(true)

        XCTAssertFalse(viewModel.isEnabled)
        XCTAssertEqual(
            viewModel.feedback,
            .error("AI settings are unavailable until CineMind finishes starting.")
        )
    }
}

@MainActor
private final class FakeAISettingsManager: AISettingsManaging {
    private(set) var snapshot: AISettingsSnapshot
    var setEnabledError: Error?
    private(set) var setEnabledCalls: [Bool] = []

    init(snapshot: AISettingsSnapshot) {
        self.snapshot = snapshot
    }

    func setEnabled(_ isEnabled: Bool) throws {
        setEnabledCalls.append(isEnabled)
        if let setEnabledError {
            snapshot = defaultSnapshot
            throw setEnabledError
        }
        snapshot = AISettingsSnapshot(
            isEnabled: isEnabled,
            providerStatus: .noProviderConfigured,
            policyStatus: isEnabled ? .notConfigured : .disabledByUser
        )
    }

    func refreshStatus() {}
}

private let defaultSnapshot = AISettingsSnapshot(
    isEnabled: false,
    providerStatus: .noProviderConfigured,
    policyStatus: .disabledByUser
)
