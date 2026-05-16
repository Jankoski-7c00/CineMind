import SwiftUI

@MainActor
public final class AppShellViewModel: ObservableObject {
    @Published public private(set) var state: AppShellState

    public init(state: AppShellState = .loading) {
        self.state = state
    }

    public func markLoading() {
        state = .loading
    }

    public func markReady() {
        state = .ready
    }

    public func markFailed(_ message: String) {
        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        state = .failed(
            normalizedMessage.isEmpty
                ? "CineMind could not start. Please try again."
                : normalizedMessage
        )
    }
}
