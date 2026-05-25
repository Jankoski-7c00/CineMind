import SwiftUI

struct LiquidGlassButtonStyle: ButtonStyle {
    enum Variant {
        case primary
        case secondary
    }

    enum Shape {
        case capsule
        case roundedRectangle(CGFloat)

        var cornerRadius: CGFloat {
            switch self {
            case .capsule:
                24
            case .roundedRectangle(let cornerRadius):
                cornerRadius
            }
        }
    }

    private let variant: Variant
    private let shape: Shape

    init(
        variant: Variant = .secondary,
        shape: Shape = .capsule
    ) {
        self.variant = variant
        self.shape = shape
    }

    func makeBody(configuration: Configuration) -> some View {
        LiquidGlassButtonBody(
            configuration: configuration,
            variant: variant,
            cornerRadius: shape.cornerRadius
        )
    }
}

private struct LiquidGlassButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let variant: LiquidGlassButtonStyle.Variant
    let cornerRadius: CGFloat

    @State private var isHovered = false

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        configuration.label
            .font(.callout.weight(variant == .primary ? .semibold : .medium))
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(backgroundTint)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .shadow(
                color: shadowColor,
                radius: variant == .primary ? 12 : 6,
                y: variant == .primary ? 6 : 3
            )
            .scaleEffect(scale)
            .opacity(isEnabled ? 1 : 0.48)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }

    private var isWindowActive: Bool {
        controlActiveState != .inactive
    }

    private var scale: CGFloat {
        if configuration.isPressed {
            return 0.98
        }
        return isHovered && isEnabled ? 1.015 : 1
    }

    private var foregroundStyle: Color {
        switch variant {
        case .primary:
            .white
        case .secondary:
            .white.opacity(0.88)
        }
    }

    private var backgroundTint: Color {
        switch variant {
        case .primary:
            Color.accentColor.opacity(isWindowActive ? (isHovered ? 0.42 : 0.34) : 0.22)
        case .secondary:
            Color.black.opacity(isWindowActive ? (isHovered ? 0.38 : 0.30) : 0.22)
        }
    }

    private var borderColor: Color {
        switch variant {
        case .primary:
            Color.accentColor.opacity(isWindowActive ? 0.55 : 0.32)
        case .secondary:
            Color.white.opacity(isWindowActive ? 0.24 : 0.14)
        }
    }

    private var shadowColor: Color {
        switch variant {
        case .primary:
            Color.accentColor.opacity(isWindowActive ? 0.28 : 0.12)
        case .secondary:
            Color.black.opacity(isWindowActive ? 0.26 : 0.16)
        }
    }
}

extension ButtonStyle where Self == LiquidGlassButtonStyle {
    static var liquidGlass: LiquidGlassButtonStyle {
        LiquidGlassButtonStyle()
    }

    static var liquidGlassPrimary: LiquidGlassButtonStyle {
        LiquidGlassButtonStyle(variant: .primary)
    }
}
