import Application
import SwiftUI

public struct SidebarView: View {
    @Binding var selectedSection: LibraryBrowserSection
    let collections: [LibraryCollectionSummary]

    public init(
        selectedSection: Binding<LibraryBrowserSection>,
        collections: [LibraryCollectionSummary]
    ) {
        self._selectedSection = selectedSection
        self.collections = collections
    }

    public var body: some View {
        List(selection: $selectedSection) {
            sidebarRow(.library, title: "Library", systemImage: "books.vertical")
            sidebarRow(.movies, title: "Movies", systemImage: "film")
            sidebarRow(.tvEpisodes, title: "TV Episodes", systemImage: "tv")
            sidebarRow(.recentlyPlayed, title: "Recently Played", systemImage: "clock.arrow.circlepath")
            sidebarRow(.needsMetadata, title: "Needs Metadata", systemImage: "tag")
            sidebarRow(.favorites, title: "Favorites", systemImage: "star")
            sidebarRow(.folders, title: "Folders", systemImage: "folder")

            if !collections.isEmpty {
                Section("Collections") {
                    ForEach(collections) { collection in
                        sidebarRow(
                            .collection(collection.id),
                            title: collection.name,
                            systemImage: "rectangle.stack"
                        )
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .tint(.accentColor)
        .scrollContentBackground(.hidden)
        .background(.thinMaterial)
    }

    private func sidebarRow(
        _ section: LibraryBrowserSection,
        title: String,
        systemImage: String
    ) -> some View {
        SidebarItemRow(
            title: title,
            systemImage: systemImage,
            isSelected: selectedSection == section
        )
        .tag(section)
        .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
        .listRowBackground(Color.clear)
    }
}

private struct SidebarItemRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        Label {
            Text(title)
                .font(.callout.weight(isSelected ? .semibold : .regular))
        } icon: {
            Image(systemName: systemImage)
                .imageScale(.medium)
        }
        .foregroundStyle(isSelected ? .white : .white.opacity(isHovered ? 0.88 : 0.72))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected || isHovered {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(isSelected ? 0.10 : 0.045))
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isSelected ? 0.22 : 0.12),
                                        Color.clear,
                                        Color.black.opacity(0.18)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
