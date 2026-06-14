import Application
import SwiftUI

@MainActor
public final class LibraryMetadataActionsState: ObservableObject {
    @Published public private(set) var revision = 0

    public private(set) var actions: (any LibraryMetadataActionHandling)?
    public private(set) var unavailableMessage: String?

    public init(
        actions: (any LibraryMetadataActionHandling)? = nil,
        unavailableMessage: String? = "Open CineMind Settings to configure TMDB metadata actions."
    ) {
        self.actions = actions
        self.unavailableMessage = unavailableMessage
    }

    public func update(
        actions: (any LibraryMetadataActionHandling)?,
        unavailableMessage: String?
    ) {
        self.actions = actions
        self.unavailableMessage = unavailableMessage
        revision += 1
    }
}

public enum TMDBSettingsFeedback: Equatable {
    case success(String)
    case error(String)
}

@MainActor
public final class TMDBSettingsViewModel: ObservableObject {
    @Published public var tokenDraft = ""
    @Published public private(set) var status: TMDBReadTokenConfigurationStatus = .notConfigured
    @Published public private(set) var feedback: TMDBSettingsFeedback?

    private var manager: (any TMDBReadTokenSettingsManaging)?

    public init() {}

    public func setManager(_ manager: (any TMDBReadTokenSettingsManaging)?) {
        self.manager = manager
        status = manager?.status ?? .notConfigured
        feedback = nil
    }

    public func saveToken() {
        guard let manager else {
            feedback = .error("TMDB settings are unavailable until CineMind finishes starting.")
            return
        }

        do {
            try manager.saveToken(tokenDraft)
            tokenDraft = ""
            status = manager.status
            feedback = .success("TMDB API Read Access Token saved.")
        } catch {
            feedback = .error(safeMessage(for: error))
        }
    }

    public func removeSavedToken() {
        guard let manager else {
            feedback = .error("TMDB settings are unavailable until CineMind finishes starting.")
            return
        }

        do {
            try manager.removeSavedToken()
            tokenDraft = ""
            status = manager.status
            feedback = .success("Saved TMDB token removed.")
        } catch {
            feedback = .error(safeMessage(for: error))
        }
    }

    public var statusDescription: String {
        switch status {
        case .savedTokenActive:
            "Using the token saved in macOS Keychain."
        case .environmentTokenActive:
            "Using CINEMIND_TMDB_READ_TOKEN because no token is saved."
        case .notConfigured:
            "TMDB metadata actions are not configured."
        case .error(let message):
            message
        }
    }

    public var canRemoveSavedToken: Bool {
        status == .savedTokenActive
    }

    private func safeMessage(for error: Error) -> String {
        if let settingsError = error as? TMDBReadTokenSettingsError {
            return settingsError.errorDescription ?? "CineMind could not update the TMDB token."
        }
        return "CineMind could not update the TMDB token."
    }
}

public struct TMDBSettingsView: View {
    @ObservedObject private var viewModel: TMDBSettingsViewModel

    public init(viewModel: TMDBSettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            Section("TMDB Metadata") {
                Text("Enter a TMDB API Read Access Token. CineMind stores it in macOS Keychain and never displays the saved value.")
                    .foregroundStyle(.secondary)

                SecureField("API Read Access Token", text: $viewModel.tokenDraft)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save Token") {
                        viewModel.saveToken()
                    }
                    .disabled(
                        viewModel.tokenDraft
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                    )

                    Button("Remove Saved Token", role: .destructive) {
                        viewModel.removeSavedToken()
                    }
                    .disabled(!viewModel.canRemoveSavedToken)
                }

                Label(viewModel.statusDescription, systemImage: statusSystemImage)
                    .foregroundStyle(.secondary)

                if let feedback = viewModel.feedback {
                    feedbackView(feedback)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 300)
        .scenePadding()
    }

    private var statusSystemImage: String {
        switch viewModel.status {
        case .savedTokenActive:
            "key.fill"
        case .environmentTokenActive:
            "terminal.fill"
        case .notConfigured:
            "key.slash"
        case .error:
            "exclamationmark.triangle.fill"
        }
    }

    @ViewBuilder
    private func feedbackView(_ feedback: TMDBSettingsFeedback) -> some View {
        switch feedback {
        case .success(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}
