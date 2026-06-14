import Foundation

public enum TMDBReadTokenConfigurationStatus: Equatable, Sendable {
    case savedTokenActive
    case environmentTokenActive
    case notConfigured
    case error(String)
}

public enum TMDBReadTokenSettingsError: Error, LocalizedError, Equatable, Sendable {
    case emptyToken
    case storageUnavailable

    public var errorDescription: String? {
        switch self {
        case .emptyToken:
            "Enter a TMDB API Read Access Token before saving."
        case .storageUnavailable:
            "CineMind could not update the saved TMDB token."
        }
    }
}

public protocol TMDBReadTokenStoring: Sendable {
    func readToken() throws -> String?
    func saveToken(_ token: String) throws
    func deleteToken() throws
}

@MainActor
public protocol TMDBMetadataRuntimeConfiguring: AnyObject {
    func configureMetadataActions(readToken: String?)
}

@MainActor
public protocol TMDBReadTokenSettingsManaging: AnyObject {
    var status: TMDBReadTokenConfigurationStatus { get }

    func saveToken(_ token: String) throws
    func removeSavedToken() throws
}

@MainActor
public final class TMDBReadTokenSettingsService: TMDBReadTokenSettingsManaging {
    public private(set) var status: TMDBReadTokenConfigurationStatus

    private let tokenStore: any TMDBReadTokenStoring
    private let environmentToken: String?
    private let metadataRuntime: any TMDBMetadataRuntimeConfiguring

    public init(
        tokenStore: any TMDBReadTokenStoring,
        environmentToken: String?,
        metadataRuntime: any TMDBMetadataRuntimeConfiguring
    ) {
        self.tokenStore = tokenStore
        self.environmentToken = Self.normalized(environmentToken)
        self.metadataRuntime = metadataRuntime

        do {
            if let savedToken = Self.normalized(try tokenStore.readToken()) {
                status = .savedTokenActive
                metadataRuntime.configureMetadataActions(readToken: savedToken)
            } else {
                status = Self.statusForFallbackToken(self.environmentToken)
                metadataRuntime.configureMetadataActions(readToken: self.environmentToken)
            }
        } catch {
            status = .error(
                "CineMind could not read the saved TMDB token. An environment token was used when available."
            )
            metadataRuntime.configureMetadataActions(readToken: self.environmentToken)
        }
    }

    public func saveToken(_ token: String) throws {
        guard let normalizedToken = Self.normalized(token) else {
            throw TMDBReadTokenSettingsError.emptyToken
        }

        do {
            try tokenStore.saveToken(normalizedToken)
        } catch {
            throw TMDBReadTokenSettingsError.storageUnavailable
        }

        metadataRuntime.configureMetadataActions(readToken: normalizedToken)
        status = .savedTokenActive
    }

    public func removeSavedToken() throws {
        do {
            try tokenStore.deleteToken()
        } catch {
            throw TMDBReadTokenSettingsError.storageUnavailable
        }

        metadataRuntime.configureMetadataActions(readToken: environmentToken)
        status = Self.statusForFallbackToken(environmentToken)
    }

    private static func normalized(_ token: String?) -> String? {
        let normalized = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? nil : normalized
    }

    private static func statusForFallbackToken(
        _ environmentToken: String?
    ) -> TMDBReadTokenConfigurationStatus {
        environmentToken == nil ? .notConfigured : .environmentTokenActive
    }
}
