import Application
import SwiftUI

public enum AISettingsFeedback: Equatable {
    case error(String)
}

@MainActor
public final class AISettingsViewModel: ObservableObject {
    @Published public private(set) var snapshot = AISettingsSnapshot(
        isEnabled: false,
        providerStatus: .noProviderConfigured,
        policyStatus: .disabledByUser
    )
    @Published public private(set) var feedback: AISettingsFeedback?

    private var manager: (any AISettingsManaging)?

    public init() {}

    public func setManager(_ manager: (any AISettingsManaging)?) {
        self.manager = manager
        snapshot = manager?.snapshot ?? Self.defaultSnapshot
        feedback = nil
    }

    public func setEnabled(_ isEnabled: Bool) {
        guard let manager else {
            snapshot = Self.defaultSnapshot
            feedback = .error("AI settings are unavailable until CineMind finishes starting.")
            return
        }

        do {
            try manager.setEnabled(isEnabled)
            snapshot = manager.snapshot
            feedback = nil
        } catch {
            snapshot = manager.snapshot
            feedback = .error(safeMessage(for: error))
        }
    }

    public func refreshStatus() {
        guard let manager else {
            return
        }
        manager.refreshStatus()
        snapshot = manager.snapshot
    }

    public var isEnabled: Bool {
        snapshot.isEnabled
    }

    public var canChangeEnabled: Bool {
        manager != nil
    }

    public var policyDescription: String {
        switch snapshot.policyStatus {
        case .disabledByUser:
            "AI features are disabled. Keyword search and manual tags remain available."
        case .notConfigured:
            "AI features are enabled, but no provider is configured."
        case .providerUnavailable:
            "AI features are enabled, but the required provider capabilities are unavailable."
        case .ready:
            "AI features are enabled and ready for supported workflows."
        case .error(let message):
            message
        }
    }

    public var providerStatusDescription: String {
        switch snapshot.providerStatus {
        case .noProviderConfigured:
            "No AI provider is configured. Keyword search and manual tags remain available."
        case .providerUnavailable(let providerLabel, _):
            "\(providerLabel) is configured but unavailable."
        case .ready(let providerLabel, _):
            "\(providerLabel) is configured and available."
        case .error(let message):
            message
        }
    }

    public var capabilityLabels: [String] {
        switch snapshot.providerStatus {
        case .noProviderConfigured, .error:
            []
        case .providerUnavailable(_, let labels), .ready(_, let labels):
            labels
        }
    }

    private func safeMessage(for error: Error) -> String {
        if let settingsError = error as? AISettingsError {
            return settingsError.errorDescription
                ?? "CineMind could not update AI settings. AI remains disabled."
        }
        return "CineMind could not update AI settings. AI remains disabled."
    }

    private static let defaultSnapshot = AISettingsSnapshot(
        isEnabled: false,
        providerStatus: .noProviderConfigured,
        policyStatus: .disabledByUser
    )
}

public struct AISettingsView: View {
    @ObservedObject private var viewModel: AISettingsViewModel

    public init(viewModel: AISettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            Section("AI Features") {
                Toggle(
                    "Enable AI features",
                    isOn: Binding(
                        get: { viewModel.isEnabled },
                        set: { viewModel.setEnabled($0) }
                    )
                )
                .disabled(!viewModel.canChangeEnabled)

                Label(viewModel.policyDescription, systemImage: policySystemImage)
                    .foregroundStyle(.secondary)

                Label(
                    viewModel.providerStatusDescription,
                    systemImage: providerSystemImage
                )
                .foregroundStyle(.secondary)

                if !viewModel.capabilityLabels.isEmpty {
                    LabeledContent(
                        "Capabilities",
                        value: viewModel.capabilityLabels.joined(separator: ", ")
                    )
                }

                Text(
                    "AI requests can include title, year, media type, and public metadata only. Paths, video, file hashes, and subtitle text are excluded."
                )
                .foregroundStyle(.secondary)

                if case .error(let message) = viewModel.feedback {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var policySystemImage: String {
        switch viewModel.snapshot.policyStatus {
        case .disabledByUser:
            "power"
        case .notConfigured:
            "gearshape"
        case .providerUnavailable:
            "exclamationmark.triangle"
        case .ready:
            "checkmark.circle.fill"
        case .error:
            "exclamationmark.triangle.fill"
        }
    }

    private var providerSystemImage: String {
        switch viewModel.snapshot.providerStatus {
        case .noProviderConfigured:
            "bolt.slash"
        case .providerUnavailable:
            "bolt.trianglebadge.exclamationmark"
        case .ready:
            "bolt.fill"
        case .error:
            "exclamationmark.triangle.fill"
        }
    }
}

public struct CineMindSettingsView: View {
    private let tmdbViewModel: TMDBSettingsViewModel
    private let aiViewModel: AISettingsViewModel

    public init(
        tmdbViewModel: TMDBSettingsViewModel,
        aiViewModel: AISettingsViewModel
    ) {
        self.tmdbViewModel = tmdbViewModel
        self.aiViewModel = aiViewModel
    }

    public var body: some View {
        TabView {
            TMDBSettingsView(viewModel: tmdbViewModel)
                .tabItem {
                    Label("Metadata", systemImage: "film")
                }

            AISettingsView(viewModel: aiViewModel)
                .tabItem {
                    Label("AI", systemImage: "sparkles")
                }
        }
        .frame(width: 560, height: 390)
        .scenePadding()
    }
}
