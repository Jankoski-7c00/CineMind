import AI
import Application
import XCTest

@MainActor
final class AISettingsServiceTests: XCTestCase {
    func testGlobalOptInDefaultsToDisabledWithNormalNotConfiguredState() {
        let service = makeService()

        XCTAssertEqual(
            service.snapshot,
            AISettingsSnapshot(
                isEnabled: false,
                providerStatus: .noProviderConfigured,
                policyStatus: .disabledByUser
            )
        )
    }

    func testStoredEnabledStateIsReadAndNoProviderRemainsRecoverable() {
        let service = makeService(store: FakeAISettingsStore(isEnabled: true))

        XCTAssertTrue(service.snapshot.isEnabled)
        XCTAssertEqual(service.snapshot.providerStatus, .noProviderConfigured)
        XCTAssertEqual(service.snapshot.policyStatus, .notConfigured)
    }

    func testEnableAndDisableWritesUpdatePolicyStatus() throws {
        let store = FakeAISettingsStore()
        let service = makeService(store: store)

        try service.setEnabled(true)
        XCTAssertEqual(store.writes, [true])
        XCTAssertEqual(service.snapshot.policyStatus, .notConfigured)

        try service.setEnabled(false)
        XCTAssertEqual(store.writes, [true, false])
        XCTAssertEqual(service.snapshot.policyStatus, .disabledByUser)
    }

    func testStorageFailuresFallBackToDisabledAndUseSafeMessages() {
        let secret = "/private/provider/endpoint?token=secret"
        let readFailureStore = FakeAISettingsStore()
        readFailureStore.readError = FakeAISettingsFailure(message: secret)

        let service = makeService(store: readFailureStore)

        XCTAssertFalse(service.snapshot.isEnabled)
        guard case .error(let readMessage) = service.snapshot.policyStatus else {
            return XCTFail("Expected a safe read error.")
        }
        XCTAssertFalse(readMessage.contains(secret))

        let writeFailureStore = FakeAISettingsStore(isEnabled: true)
        let writeFailureService = makeService(store: writeFailureStore)
        writeFailureStore.writeError = FakeAISettingsFailure(message: secret)

        XCTAssertThrowsError(try writeFailureService.setEnabled(false)) { error in
            XCTAssertEqual(error as? AISettingsError, .storageUnavailable)
            XCTAssertFalse(error.localizedDescription.contains(secret))
        }
        XCTAssertFalse(writeFailureService.snapshot.isEnabled)
    }

    func testUnavailableProviderProducesRecoverableState() {
        let descriptor = providerDescriptor()
        let service = makeService(
            store: FakeAISettingsStore(isEnabled: true),
            availability: .unavailable(descriptor)
        )

        XCTAssertEqual(
            service.snapshot.providerStatus,
            .providerUnavailable(
                providerLabel: "Fake Provider",
                capabilityLabels: ["Chat", "Embeddings"]
            )
        )
        XCTAssertEqual(service.snapshot.policyStatus, .providerUnavailable)
    }

    func testProviderMissingRequiredCapabilityIsNotReady() {
        let descriptor = providerDescriptor(capabilities: [.embeddings])
        let service = makeService(
            store: FakeAISettingsStore(isEnabled: true),
            availability: .available(descriptor)
        )

        XCTAssertEqual(
            service.snapshot.providerStatus,
            .providerUnavailable(
                providerLabel: "Fake Provider",
                capabilityLabels: ["Embeddings"]
            )
        )
        XCTAssertEqual(service.snapshot.policyStatus, .providerUnavailable)
    }

    func testReadyStatusMapsOnlyProviderLabelAndCapabilityLabels() {
        let descriptor = providerDescriptor(
            id: "private-provider-id",
            capabilities: [.chat, .embeddings]
        )
        let service = makeService(
            store: FakeAISettingsStore(isEnabled: true),
            availability: .available(descriptor)
        )

        XCTAssertEqual(
            service.snapshot.providerStatus,
            .ready(
                providerLabel: "Fake Provider",
                capabilityLabels: ["Chat", "Embeddings"]
            )
        )
        XCTAssertEqual(service.snapshot.policyStatus, .ready)
        XCTAssertFalse(String(describing: service.snapshot).contains("private-provider-id"))
    }

    func testProviderStatusFailureUsesFixedUserSafeMessage() {
        let secret = "https://provider.example?token=secret"
        let reader = FakeAIProviderAvailabilityReader(.notConfigured)
        reader.error = FakeAISettingsFailure(message: secret)

        let service = AISettingsService(
            settingsStore: FakeAISettingsStore(isEnabled: true),
            providerAvailabilityReader: reader
        )

        guard case .error(let message) = service.snapshot.providerStatus else {
            return XCTFail("Expected a safe provider status error.")
        }
        XCTAssertFalse(message.contains(secret))
    }

    func testPolicyGateRefusesDisabledNotConfiguredAndUnsupportedWork() throws {
        let disabled = makeService(
            availability: .available(providerDescriptor())
        )
        XCTAssertThrowsError(try disabled.requireCapability(.embeddings)) { error in
            XCTAssertEqual(error as? AIFeaturePolicyError, .disabled)
        }

        let notConfigured = makeService(store: FakeAISettingsStore(isEnabled: true))
        XCTAssertThrowsError(try notConfigured.requireCapability(.embeddings)) { error in
            XCTAssertEqual(error as? AIFeaturePolicyError, .notConfigured)
        }

        let partial = makeService(
            store: FakeAISettingsStore(isEnabled: true),
            availability: .available(providerDescriptor(capabilities: [.embeddings]))
        )
        XCTAssertNoThrow(try partial.requireCapability(.embeddings))
        XCTAssertThrowsError(try partial.requireCapability(.chat)) { error in
            XCTAssertEqual(error as? AIFeaturePolicyError, .unsupportedCapability)
        }
    }

    private func makeService(
        store: FakeAISettingsStore = FakeAISettingsStore(),
        availability: AIProviderAvailability = .notConfigured
    ) -> AISettingsService {
        AISettingsService(
            settingsStore: store,
            providerAvailabilityReader: FakeAIProviderAvailabilityReader(availability)
        )
    }

    private func providerDescriptor(
        id: String = "fake",
        capabilities: Set<AIProviderCapability> = [.embeddings, .chat]
    ) -> AIProviderDescriptor {
        AIProviderDescriptor(
            id: id,
            displayName: "Fake Provider",
            capabilities: capabilities
        )
    }
}

private final class FakeAISettingsStore: AISettingsStoring, @unchecked Sendable {
    var isEnabled: Bool
    var readError: Error?
    var writeError: Error?
    private(set) var writes: [Bool] = []

    init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    func readIsEnabled() throws -> Bool {
        if let readError {
            throw readError
        }
        return isEnabled
    }

    func writeIsEnabled(_ isEnabled: Bool) throws {
        if let writeError {
            throw writeError
        }
        self.isEnabled = isEnabled
        writes.append(isEnabled)
    }
}

private final class FakeAIProviderAvailabilityReader: AIProviderAvailabilityReading, @unchecked Sendable {
    var availability: AIProviderAvailability
    var error: Error?

    init(_ availability: AIProviderAvailability) {
        self.availability = availability
    }

    func currentAvailability() throws -> AIProviderAvailability {
        if let error {
            throw error
        }
        return availability
    }
}

private struct FakeAISettingsFailure: Error {
    let message: String
}
