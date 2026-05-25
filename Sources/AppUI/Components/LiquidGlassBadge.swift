import SwiftUI

struct LiquidGlassBadge: View {
    enum Variant {
        case neutral
        case accent
        case success
        case warning
        case danger
    }

    private let title: String
    private let systemImage: String?
    private let variant: Variant

    init(
        _ title: String,
        systemImage: String? = nil,
        variant: Variant = .neutral
    ) {
        self.title = title
        self.systemImage = systemImage
        self.variant = variant
    }

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }

            Text(title)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(foregroundStyle)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .fill(accentColor.opacity(0.16))
                }
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(accentColor.opacity(0.38), lineWidth: 1)
        }
    }

    private var accentColor: Color {
        switch variant {
        case .neutral:
            .white
        case .accent:
            .accentColor
        case .success:
            .green
        case .warning:
            .yellow
        case .danger:
            .red
        }
    }

    private var foregroundStyle: Color {
        switch variant {
        case .neutral:
            .white.opacity(0.86)
        case .accent, .success, .warning, .danger:
            accentColor
        }
    }
}
