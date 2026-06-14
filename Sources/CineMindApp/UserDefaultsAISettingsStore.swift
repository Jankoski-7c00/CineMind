import Application
import Foundation

struct UserDefaultsAISettingsStore: AISettingsStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let enabledKey = "com.cinemind.settings.ai.enabled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func readIsEnabled() throws -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? false
    }

    func writeIsEnabled(_ isEnabled: Bool) throws {
        defaults.set(isEnabled, forKey: enabledKey)
    }
}
