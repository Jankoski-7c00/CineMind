import SwiftUI

struct LibraryBrowserStatusDescriptor {
    let title: String
    let systemImage: String
    let color: Color
}

enum LibraryBrowserStatusPresentation {
    static func availability(_ label: String) -> LibraryBrowserStatusDescriptor {
        switch label.lowercased() {
        case "available":
            LibraryBrowserStatusDescriptor(
                title: "Available",
                systemImage: "checkmark.circle.fill",
                color: .green
            )
        case "unavailable", "no files":
            LibraryBrowserStatusDescriptor(
                title: "Missing File",
                systemImage: "xmark.circle.fill",
                color: .red
            )
        case "partially available":
            LibraryBrowserStatusDescriptor(
                title: "Partial",
                systemImage: "exclamationmark.circle.fill",
                color: .yellow
            )
        default:
            LibraryBrowserStatusDescriptor(
                title: CineMindDisplayText.friendlyStatus(label),
                systemImage: "info.circle",
                color: .secondary
            )
        }
    }

    static func metadata(_ label: String) -> LibraryBrowserStatusDescriptor {
        switch label.lowercased() {
        case "complete":
            LibraryBrowserStatusDescriptor(
                title: "Matched",
                systemImage: "checkmark.seal.fill",
                color: .green
            )
        case "partial":
            LibraryBrowserStatusDescriptor(
                title: "Partial",
                systemImage: "exclamationmark.circle.fill",
                color: .yellow
            )
        case "missing":
            LibraryBrowserStatusDescriptor(
                title: "Needs Metadata",
                systemImage: "tag.fill",
                color: .accentColor
            )
        default:
            LibraryBrowserStatusDescriptor(
                title: CineMindDisplayText.friendlyStatus(label),
                systemImage: "tag",
                color: .secondary
            )
        }
    }
}

struct LibraryBrowserStatusLabel: View {
    let descriptor: LibraryBrowserStatusDescriptor

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: descriptor.systemImage)
                .imageScale(.small)
            Text(descriptor.title)
                .lineLimit(1)
        }
        .font(.callout)
        .foregroundStyle(descriptor.color)
    }
}
