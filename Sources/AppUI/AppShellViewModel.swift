import SwiftUI

@MainActor
public final class AppShellViewModel: ObservableObject {
    @Published public private(set) var state: AppShellState
    @Published public private(set) var environment: AppShellEnvironment?

    public init(state: AppShellState = .loading) {
        self.state = state
    }

    public func markLoading() {
        environment = nil
        state = .loading
    }

    public func markReady() {
        state = .ready
    }

    public func markReady(environment: AppShellEnvironment) {
        self.environment = environment
        state = .ready
    }

    public func markFailed(_ message: String) {
        environment = nil
        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        state = .failed(
            normalizedMessage.isEmpty
                ? "CineMind could not start. Please try again."
                : normalizedMessage
        )
    }
}
