import Application
import SwiftUI

public struct SidebarView: View {
    @Binding var selectedSection: LibraryBrowserSection

    public init(selectedSection: Binding<LibraryBrowserSection>) {
        self._selectedSection = selectedSection
    }

    public var body: some View {
        List(selection: $selectedSection) {
            Label("Library", systemImage: "books.vertical")
                .tag(LibraryBrowserSection.library)
            Label("Movies", systemImage: "film")
                .tag(LibraryBrowserSection.movies)
            Label("TV Episodes", systemImage: "tv")
                .tag(LibraryBrowserSection.tvEpisodes)
            Label("Recently Played", systemImage: "clock.arrow.circlepath")
                .tag(LibraryBrowserSection.recentlyPlayed)
            Label("Needs Metadata", systemImage: "tag")
                .tag(LibraryBrowserSection.needsMetadata)
            Label("Folders", systemImage: "folder")
                .tag(LibraryBrowserSection.folders)
        }
        .listStyle(.sidebar)
        .tint(.accentColor)
    }
}
