import SwiftUI

struct LiquidGlassPanel<Content: View>: View {
    private let cornerRadius: CGFloat
    private let material: Material
    private let tint: Color
    private let padding: EdgeInsets
    private let content: () -> Content

    @Environment(\.controlActiveState) private var controlActiveState

    init(
        cornerRadius: CGFloat = 18,
        material: Material = .regularMaterial,
        tint: Color = .black,
        padding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16),
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.material = material
        self.tint = tint
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .liquidGlassSurface(
                cornerRadius: cornerRadius,
                material: material,
                tint: tint,
                isActive: controlActiveState != .inactive
            )
    }
}

private struct LiquidGlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let material: Material
    let tint: Color
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(material)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(isActive ? 0.34 : 0.24))
                    }
                    .overlay(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(isActive ? 0.10 : 0.05),
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .center
                                )
                            )
                            .blendMode(.screen)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(isActive ? 0.22 : 0.12),
                                .white.opacity(isActive ? 0.05 : 0.03),
                                .clear,
                                .black.opacity(isActive ? 0.24 : 0.16)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: max(cornerRadius - 1, 1), style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(isActive ? 0.10 : 0.05),
                                .clear,
                                .black.opacity(isActive ? 0.16 : 0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.6
                    )
                    .padding(1)
            }
            .shadow(
                color: .white.opacity(isActive ? 0.035 : 0.015),
                radius: isActive ? 10 : 6,
                x: -2,
                y: -2
            )
            .shadow(
                color: .black.opacity(isActive ? 0.34 : 0.22),
                radius: isActive ? 20 : 12,
                y: isActive ? 12 : 7
            )
    }
}

extension View {
    func liquidGlassSurface(
        cornerRadius: CGFloat = 18,
        material: Material = .regularMaterial,
        tint: Color = .black,
        isActive: Bool = true
    ) -> some View {
        modifier(
            LiquidGlassSurfaceModifier(
                cornerRadius: cornerRadius,
                material: material,
                tint: tint,
                isActive: isActive
            )
        )
    }
}
