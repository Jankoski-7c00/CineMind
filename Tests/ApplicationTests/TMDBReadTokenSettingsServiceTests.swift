import Application
import XCTest

@MainActor
final class TMDBReadTokenSettingsServiceTests: XCTestCase {
    func testSavedTokenTakesPrecedenceOverEnvironmentToken() {
        let store = FakeTMDBReadTokenStore(token: " saved-token ")
        let runtime = RecordingTMDBMetadataRuntime()

        let service = TMDBReadTokenSettingsService(
            tokenStore: store,
            environmentToken: "environment-token",
            metadataRuntime: runtime
        )

        XCTAssertEqual(service.status, .savedTokenActive)
        XCTAssertEqual(runtime.configuredTokens, ["saved-token"])
    }

    func testEnvironmentTokenIsUsedWhenNoSavedTokenExists() {
        let runtime = RecordingTMDBMetadataRuntime()

        let service = TMDBReadTokenSettingsService(
            tokenStore: FakeTMDBReadTokenStore(),
            environmentToken: " environment-token ",
            metadataRuntime: runtime
        )

        XCTAssertEqual(service.status, .environmentTokenActive)
        XCTAssertEqual(runtime.configuredTokens, ["environment-token"])
    }

    func testSaveAndRemoveReconfigureRuntimeImmediately() throws {
        let store = FakeTMDBReadTokenStore()
        let runtime = RecordingTMDBMetadataRuntime()
        let service = TMDBReadTokenSettingsService(
            tokenStore: store,
            environmentToken: "environment-token",
            metadataRuntime: runtime
        )

        try service.saveToken(" saved-token ")
        XCTAssertEqual(store.token, "saved-token")
        XCTAssertEqual(service.status, .savedTokenActive)

        try service.removeSavedToken()
        XCTAssertNil(store.token)
        XCTAssertEqual(service.status, .environmentTokenActive)
        XCTAssertEqual(runtime.configuredTokens, ["environment-token", "saved-token", "environment-token"])
    }

    func testEmptyTokenIsRejectedWithoutChangingRuntime() {
        let runtime = RecordingTMDBMetadataRuntime()
        let service = TMDBReadTokenSettingsService(
            tokenStore: FakeTMDBReadTokenStore(),
            environmentToken: nil,
            metadataRuntime: runtime
        )

        XCTAssertThrowsError(try service.saveToken("  \n ")) { error in
            XCTAssertEqual(error as? TMDBReadTokenSettingsError, .emptyToken)
        }
        XCTAssertEqual(runtime.configuredTokens, [nil])
        XCTAssertEqual(service.status, .notConfigured)
    }

    func testStorageFailureDoesNotSwitchRuntimeOrExposeToken() {
        let store = FakeTMDBReadTokenStore()
        store.saveError = FakeTokenStoreError.failed
        let runtime = RecordingTMDBMetadataRuntime()
        let service = TMDBReadTokenSettingsService(
            tokenStore: store,
            environmentToken: "environment-token",
            metadataRuntime: runtime
        )

        let secret = "very-secret-read-token"
        XCTAssertThrowsError(try service.saveToken(secret)) { error in
            XCTAssertEqual(error as? TMDBReadTokenSettingsError, .storageUnavailable)
            XCTAssertFalse(error.localizedDescription.contains(secret))
        }
        XCTAssertEqual(runtime.configuredTokens, ["environment-token"])
        XCTAssertEqual(service.status, .environmentTokenActive)
    }

    func testReadFailureFallsBackWithoutExposingEnvironmentToken() {
        let store = FakeTMDBReadTokenStore()
        store.readError = FakeTokenStoreError.failed
        let runtime = RecordingTMDBMetadataRuntime()
        let secret = "very-secret-environment-token"

        let service = TMDBReadTokenSettingsService(
            tokenStore: store,
            environmentToken: secret,
            metadataRuntime: runtime
        )

        XCTAssertEqual(runtime.configuredTokens, [secret])
        guard case .error(let message) = service.status else {
            return XCTFail("Expected a safe read error status.")
        }
        XCTAssertFalse(message.contains(secret))
    }
}

private final class FakeTMDBReadTokenStore: TMDBReadTokenStoring, @unchecked Sendable {
    var token: String?
    var readError: Error?
    var saveError: Error?
    var deleteError: Error?

    init(token: String? = nil) {
        self.token = token
    }

    func readToken() throws -> String? {
        if let readError {
            throw readError
        }
        return token
    }

    func saveToken(_ token: String) throws {
        if let saveError {
            throw saveError
        }
        self.token = token
    }

    func deleteToken() throws {
        if let deleteError {
            throw deleteError
        }
        token = nil
    }
}

@MainActor
private final class RecordingTMDBMetadataRuntime: TMDBMetadataRuntimeConfiguring {
    private(set) var configuredTokens: [String?] = []

    func configureMetadataActions(readToken: String?) {
        configuredTokens.append(readToken)
    }
}

private enum FakeTokenStoreError: Error {
    case failed
}
