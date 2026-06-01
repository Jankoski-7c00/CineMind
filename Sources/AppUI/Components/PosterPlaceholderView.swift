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
        ZStack {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.08),
                    Color(red: 0.08, green: 0.10, blue: 0.14).opacity(0.68),
                    Color.black.opacity(0.42)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.accentColor.opacity(0.20),
                    .clear
                ],
                center: .topLeading,
                startRadius: 8,
                endRadius: 150
            )

            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .frame(width: 62, height: 48)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                        }

                    Image(systemName: "film")
                        .font(.system(size: 29, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                }

                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.70))
                    .multilineTextAlignment(.center)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.54))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlassSurface(
            cornerRadius: 16,
            material: .ultraThinMaterial,
            tint: .black
        )
        .accessibilityLabel(isLoading ? "Loading poster" : title)
    }
}
