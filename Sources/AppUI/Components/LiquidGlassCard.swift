import SwiftUI

struct LiquidGlassCard<Content: View>: View {
    private let title: String?
    private let systemImage: String?
    private let spacing: CGFloat
    private let content: () -> Content

    init(
        _ title: String? = nil,
        systemImage: String? = nil,
        spacing: CGFloat = 12,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        LiquidGlassPanel(cornerRadius: 16, material: .thinMaterial) {
            VStack(alignment: .leading, spacing: spacing) {
                if let title {
                    HStack(spacing: 8) {
                        if let systemImage {
                            Image(systemName: systemImage)
                                .imageScale(.medium)
                                .foregroundStyle(.secondary)
                        }

                        Text(title)
                            .cinemindSectionTitleStyle()
                    }
                }

                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
