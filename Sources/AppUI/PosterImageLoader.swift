import CoreGraphics
import Foundation
import ImageIO

public enum PosterImagePlaceholderReason: Equatable, Sendable {
    case noCachePath
    case fileMissing
    case decodeFailed
}

public struct PosterImageCacheKey: Hashable, Sendable {
    public let standardizedPath: String
    public let modificationDate: Date
    public let fileSize: Int64

    public init(
        standardizedPath: String,
        modificationDate: Date,
        fileSize: Int64
    ) {
        self.standardizedPath = standardizedPath
        self.modificationDate = modificationDate
        self.fileSize = fileSize
    }
}

// CGImage is immutable; this wrapper crosses cache actor boundaries without mutating the image.
public struct LoadedPosterImage: @unchecked Sendable {
    public let image: CGImage
    public let cacheKey: PosterImageCacheKey

    public init(image: CGImage, cacheKey: PosterImageCacheKey) {
        self.image = image
        self.cacheKey = cacheKey
    }
}

public enum PosterImageLoadResult: Sendable {
    case loaded(LoadedPosterImage)
    case placeholder(PosterImagePlaceholderReason)
}

public protocol PosterImageLoading: Sendable {
    func load(localCachePath: String?) async -> PosterImageLoadResult
}

public actor PosterImageMemoryCache {
    private var imagesByKey: [PosterImageCacheKey: LoadedPosterImage] = [:]

    public init() {}

    public func image(for key: PosterImageCacheKey) -> LoadedPosterImage? {
        imagesByKey[key]
    }

    public func store(_ image: LoadedPosterImage) {
        imagesByKey[image.cacheKey] = image
    }

    public func removeAll() {
        imagesByKey.removeAll()
    }
}

public struct LocalPosterImageLoader: PosterImageLoading {
    private let cache: PosterImageMemoryCache

    public init(cache: PosterImageMemoryCache = PosterImageMemoryCache()) {
        self.cache = cache
    }

    public func load(localCachePath: String?) async -> PosterImageLoadResult {
        guard let path = localCachePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return .placeholder(.noCachePath)
        }

        let fileInfo = await Task.detached(priority: .userInitiated) {
            Self.fileInfo(path: path)
        }.value

        switch fileInfo {
        case .key(let cacheKey):
            if let cachedImage = await cache.image(for: cacheKey) {
                return .loaded(cachedImage)
            }

            let decodedImage = await Task.detached(priority: .userInitiated) {
                Self.decodeImage(at: cacheKey.standardizedPath)
            }.value
            guard let decodedImage else {
                return .placeholder(.decodeFailed)
            }

            let loadedImage = LoadedPosterImage(image: decodedImage, cacheKey: cacheKey)
            await cache.store(loadedImage)
            return .loaded(loadedImage)
        case .placeholder(let reason):
            return .placeholder(reason)
        }
    }

    private static func fileInfo(path: String) -> FileInfoResult {
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(
            atPath: standardizedPath,
            isDirectory: &isDirectory
        ), !isDirectory.boolValue else {
            return .placeholder(.fileMissing)
        }

        guard FileManager.default.isReadableFile(atPath: standardizedPath) else {
            return .placeholder(.decodeFailed)
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: standardizedPath)
            guard let modificationDate = attributes[.modificationDate] as? Date,
                  let fileSize = fileSize(from: attributes),
                  fileSize > 0 else {
                return .placeholder(.decodeFailed)
            }

            return .key(
                PosterImageCacheKey(
                    standardizedPath: standardizedPath,
                    modificationDate: modificationDate,
                    fileSize: fileSize
                )
            )
        } catch {
            return .placeholder(.decodeFailed)
        }
    }

    private static func fileSize(from attributes: [FileAttributeKey: Any]) -> Int64? {
        if let size = attributes[.size] as? NSNumber {
            return size.int64Value
        }
        if let size = attributes[.size] as? Int64 {
            return size
        }
        if let size = attributes[.size] as? Int {
            return Int64(size)
        }
        return nil
    }

    private static func decodeImage(at standardizedPath: String) -> CGImage? {
        let url = URL(fileURLWithPath: standardizedPath)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            return nil
        }

        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

private enum FileInfoResult {
    case key(PosterImageCacheKey)
    case placeholder(PosterImagePlaceholderReason)
}
