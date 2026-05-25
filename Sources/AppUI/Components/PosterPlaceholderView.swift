import SwiftUI

struct PosterPlaceholderView: View {
    private let title: String
    private let subtitle: String?
    private let isLoading: Bool

    init(
        title: String = "No Poster",
        subtitle: String? = nil,
        isLoading: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isLoading = isLoading
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "film")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))

            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(.center)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlassSurface(
            cornerRadius: 14,
            material: .ultraThinMaterial,
            tint: .black
        )
        .accessibilityLabel(isLoading ? "Loading poster" : title)
    }
}
