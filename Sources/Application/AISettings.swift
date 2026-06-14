import AI
import Foundation

public enum AIProviderAvailability: Sendable, Equatable {
    case notConfigured
    case unavailable(AIProviderDescriptor)
    case available(AIProviderDescriptor)
    case error
}

public enum AIProviderConfigurationStatus: Sendable, Equatable {
    case noProviderConfigured
    case providerUnavailable(providerLabel: String, capabilityLabels: [String])
    case ready(providerLabel: String, capabilityLabels: [String])
    case error(String)
}

public enum AIFeaturePolicyStatus: Sendable, Equatable {
    case disabledByUser
    case notConfigured
    case providerUnavailable
    case ready
    case error(String)
}

public struct AISettingsSnapshot: Sendable, Equatable {
    public let isEnabled: Bool
    public let providerStatus: AIProviderConfigurationStatus
    public let policyStatus: AIFeaturePolicyStatus

    public init(
        isEnabled: Bool,
        providerStatus: AIProviderConfigurationStatus,
        policyStatus: AIFeaturePolicyStatus
    ) {
        self.isEnabled = isEnabled
        self.providerStatus = providerStatus
        self.policyStatus = policyStatus
    }
}

public enum AISettingsError: Error, LocalizedError, Sendable, Equatable {
    case storageUnavailable

    public var errorDescription: String? {
        "CineMind could not update AI settings. AI remains disabled."
    }
}

public enum AIFeaturePolicyError: Error, LocalizedError, Sendable, Equatable {
    case disabled
    case notConfigured
    case providerUnavailable
    case unsupportedCapability
    case configurationUnavailable

    public var errorDescription: String? {
        switch self {
        case .disabled:
            "AI features are disabled."
        case .notConfigured:
            "No AI provider is configured."
        case .providerUnavailable:
            "The AI provider is unavailable."
        case .unsupportedCapability:
            "The AI provider does not support this feature."
        case .configurationUnavailable:
            "AI configuration is temporarily unavailable."
        }
    }
}

public protocol AISettingsStoring: Sendable {
    func readIsEnabled() throws -> Bool
    func writeIsEnabled(_ isEnabled: Bool) throws
}

public protocol AIProviderAvailabilityReading: Sendable {
    func currentAvailability() throws -> AIProviderAvailability
}

public struct StaticAIProviderAvailabilityReader: AIProviderAvailabilityReading {
    private let availability: AIProviderAvailability

    public init(_ availability: AIProviderAvailability) {
        self.availability = availability
    }

    public func currentAvailability() throws -> AIProviderAvailability {
        availability
    }
}

@MainActor
public protocol AISettingsManaging: AnyObject {
    var snapshot: AISettingsSnapshot { get }

    func setEnabled(_ isEnabled: Bool) throws
    func refreshStatus()
}

@MainActor
public protocol AIFeaturePolicyChecking: AnyObject {
    func requireCapability(_ capability: AIProviderCapability) throws
}

@MainActor
public final class AISettingsService: AISettingsManaging, AIFeaturePolicyChecking {
    public private(set) var snapshot: AISettingsSnapshot

    private let settingsStore: any AISettingsStoring
    private let providerAvailabilityReader: any AIProviderAvailabilityReading
    private let requiredCapabilities: Set<AIProviderCapability>
    private var currentAvailability: AIProviderAvailability = .notConfigured

    public init(
        settingsStore: any AISettingsStoring,
        providerAvailabilityReader: any AIProviderAvailabilityReading,
        requiredCapabilities: Set<AIProviderCapability> = Set(AIProviderCapability.allCases)
    ) {
        self.settingsStore = settingsStore
        self.providerAvailabilityReader = providerAvailabilityReader
        self.requiredCapabilities = requiredCapabilities
        self.snapshot = AISettingsSnapshot(
            isEnabled: false,
            providerStatus: .noProviderConfigured,
            policyStatus: .disabledByUser
        )

        do {
            let storedIsEnabled = try settingsStore.readIsEnabled()
            updateSnapshot(isEnabled: storedIsEnabled)
        } catch {
            updateSnapshot(
                isEnabled: false,
                policyError: "CineMind could not read AI settings. AI remains disabled."
            )
        }
    }

    public func setEnabled(_ isEnabled: Bool) throws {
        do {
            try settingsStore.writeIsEnabled(isEnabled)
        } catch {
            updateSnapshot(
                isEnabled: false,
                policyError: AISettingsError.storageUnavailable.errorDescription
            )
            throw AISettingsError.storageUnavailable
        }

        updateSnapshot(isEnabled: isEnabled)
    }

    public func refreshStatus() {
        updateSnapshot(isEnabled: snapshot.isEnabled)
    }

    public func requireCapability(_ capability: AIProviderCapability) throws {
        guard snapshot.isEnabled else {
            throw AIFeaturePolicyError.disabled
        }

        switch currentAvailability {
        case .notConfigured:
            throw AIFeaturePolicyError.notConfigured
        case .unavailable:
            throw AIFeaturePolicyError.providerUnavailable
        case .available(let descriptor):
            guard descriptor.capabilities.contains(capability) else {
                throw AIFeaturePolicyError.unsupportedCapability
            }
        case .error:
            throw AIFeaturePolicyError.configurationUnavailable
        }
    }

    private func updateSnapshot(isEnabled: Bool, policyError: String? = nil) {
        currentAvailability = safeCurrentAvailability()
        let providerStatus = providerStatus(for: currentAvailability)
        let policyStatus: AIFeaturePolicyStatus

        if let policyError {
            policyStatus = .error(policyError)
        } else if !isEnabled {
            policyStatus = .disabledByUser
        } else {
            policyStatus = enabledPolicyStatus(for: currentAvailability)
        }

        snapshot = AISettingsSnapshot(
            isEnabled: isEnabled,
            providerStatus: providerStatus,
            policyStatus: policyStatus
        )
    }

    private func safeCurrentAvailability() -> AIProviderAvailability {
        do {
            return try providerAvailabilityReader.currentAvailability()
        } catch {
            return .error
        }
    }

    private func providerStatus(
        for availability: AIProviderAvailability
    ) -> AIProviderConfigurationStatus {
        switch availability {
        case .notConfigured:
            .noProviderConfigured
        case .unavailable(let descriptor):
            .providerUnavailable(
                providerLabel: providerLabel(for: descriptor),
                capabilityLabels: capabilityLabels(for: descriptor)
            )
        case .available(let descriptor):
            if requiredCapabilities.isSubset(of: descriptor.capabilities) {
                .ready(
                    providerLabel: providerLabel(for: descriptor),
                    capabilityLabels: capabilityLabels(for: descriptor)
                )
            } else {
                .providerUnavailable(
                    providerLabel: providerLabel(for: descriptor),
                    capabilityLabels: capabilityLabels(for: descriptor)
                )
            }
        case .error:
            .error("CineMind could not read AI provider status.")
        }
    }

    private func enabledPolicyStatus(
        for availability: AIProviderAvailability
    ) -> AIFeaturePolicyStatus {
        switch availability {
        case .notConfigured:
            .notConfigured
        case .unavailable:
            .providerUnavailable
        case .available(let descriptor):
            requiredCapabilities.isSubset(of: descriptor.capabilities)
                ? .ready
                : .providerUnavailable
        case .error:
            .error("AI configuration is temporarily unavailable.")
        }
    }

    private func providerLabel(for descriptor: AIProviderDescriptor) -> String {
        let label = descriptor.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? "Configured provider" : label
    }

    private func capabilityLabels(for descriptor: AIProviderDescriptor) -> [String] {
        descriptor.capabilities
            .map(\.displayName)
            .sorted()
    }
}
