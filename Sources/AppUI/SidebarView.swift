import SwiftUI

public struct SidebarView: View {
    public init() {}

    public var body: some View {
        List {
            Label("Library", systemImage: "books.vertical")
            Label("Movies", systemImage: "film")
            Label("TV Episodes", systemImage: "tv")
            Label("Recently Played", systemImage: "clock")
            Label("Needs Metadata", systemImage: "exclamationmark.triangle")
            Label("Folders", systemImage: "folder")
        }
    }
}
