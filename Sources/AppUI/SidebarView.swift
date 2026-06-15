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
            nativeRow(.library, title: "Library", systemImage: "books.vertical")
            nativeRow(.movies, title: "Movies", systemImage: "film")
            nativeRow(.tvEpisodes, title: "TV Episodes", systemImage: "tv")
            nativeRow(
                .recentlyPlayed,
                title: "Recently Played",
                systemImage: "clock.arrow.circlepath"
            )
            nativeRow(.needsMetadata, title: "Needs Metadata", systemImage: "tag")
            nativeRow(.favorites, title: "Favorites", systemImage: "star")
            nativeRow(.folders, title: "Folders", systemImage: "folder")

            if !collections.isEmpty {
                Section("Collections") {
                    ForEach(collections) { collection in
                        nativeRow(
                            .collection(collection.id),
                            title: collection.name,
                            systemImage: "rectangle.stack"
                        )
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func nativeRow(
        _ section: LibraryBrowserSection,
        title: String,
        systemImage: String
    ) -> some View {
        Label(title, systemImage: systemImage)
            .tag(section)
    }
}
