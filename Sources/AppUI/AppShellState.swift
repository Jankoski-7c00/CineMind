public enum AppShellState: Equatable, Sendable {
    case loading
    case ready
    case failed(String)
}
