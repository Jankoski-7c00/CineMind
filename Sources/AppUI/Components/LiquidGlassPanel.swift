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
                            .fill(tint.opacity(isActive ? 0.32 : 0.22))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(isActive ? 0.30 : 0.18),
                                .white.opacity(0.08),
                                .black.opacity(0.30)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: .black.opacity(isActive ? 0.34 : 0.22),
                radius: isActive ? 18 : 10,
                y: isActive ? 10 : 6
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
