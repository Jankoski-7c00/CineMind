import Foundation

public enum CineMindBuildInfo {
    public static let productName = "CineMind"
    public static let phaseName = "Phase 1 Library Core"
}

public enum StablePathHash {
    public static func hash(_ value: String) -> String {
        let bytes = value.utf8
        var hash: UInt64 = 0xcbf29ce484222325

        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }

        return String(format: "%016llx", hash)
    }
}
