import SwiftUI

struct LibraryPosterThumbnailView: View {
    let title: String
    let mediaTypeLabel: String
    let localCachePath: String?

    @State private var loadedImage: LoadedPosterImage?

    private static let loader = LocalPosterImageLoader(cache: PosterImageMemoryCache())

    var body: some View {
        Group {
            if let loadedImage {
                Image(decorative: loadedImage.image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task(id: localCachePath) {
            loadedImage = nil
            let result = await Self.loader.load(localCachePath: localCachePath)
            guard !Task.isCancelled else { return }
            if case .loaded(let image) = result {
                loadedImage = image
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            Rectangle()
                .fill(.quaternary)

            VStack(spacing: 8) {
                Image(systemName: mediaTypeLabel == "TV Episode" ? "tv" : "film")
                    .font(.system(size: 28, weight: .medium))
                Text(titleInitial)
                    .font(.title2.weight(.semibold))
            }
            .foregroundStyle(.secondary)
        }
    }

    private var titleInitial: String {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.first.map { String($0).uppercased() } ?? "?"
    }
}
