import SwiftUI

enum CineMindDisplayText {
    static let emptyValue = "—"
    static let missingSummary = "No summary available."

    static func value(_ value: String?) -> String {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return emptyValue
        }

        return trimmed
    }

    static func summary(_ value: String?) -> String {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return missingSummary
        }

        return trimmed
    }

    static func friendlyStatus(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { word in
                word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }
}

private struct CineMindDetailTitleTextModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.largeTitle.weight(.semibold))
            .foregroundStyle(.white)
    }
}

private struct CineMindSectionTitleTextModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.92))
    }
}

private struct CineMindSecondaryTextModifier: ViewModifier {
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white.opacity(opacity))
    }
}

private struct CineMindCaptionTextModifier: ViewModifier {
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .font(.caption)
            .foregroundStyle(.white.opacity(opacity))
    }
}

extension View {
    func cinemindDetailTitleStyle() -> some View {
        modifier(CineMindDetailTitleTextModifier())
    }

    func cinemindSectionTitleStyle() -> some View {
        modifier(CineMindSectionTitleTextModifier())
    }

    func cinemindSecondaryTextStyle(opacity: Double = 0.66) -> some View {
        modifier(CineMindSecondaryTextModifier(opacity: opacity))
    }

    func cinemindCaptionTextStyle(opacity: Double = 0.56) -> some View {
        modifier(CineMindCaptionTextModifier(opacity: opacity))
    }
}
