import SwiftUI

@MainActor
public final class AppShellViewModel: ObservableObject {
    @Published public var state: AppShellState

    public init(state: AppShellState = .loading) {
        self.state = state
    }
}
