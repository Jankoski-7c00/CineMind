import Foundation
import Shared

public struct PosterCacheConfiguration {
    public var cacheRoot: URL
    public var now: () -> Date

    public init(
        cacheRoot: URL,
        now: @escaping () -> Date = { Date() }
    ) {
        self.cacheRoot = cacheRoot
        self.now = now
    }
}

public struct PosterCacheResult: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case hit
        case miss
    }

    public var localPath: String
    public var cachedAt: Date
    public var byteCount: Int
    public var state: State

    public init(localPath: String, cachedAt: Date, byteCount: Int, state: State) {
        self.localPath = localPath
        self.cachedAt = cachedAt
        self.byteCount = byteCount
        self.state = state
    }
}

public struct PosterCache {
    private let configuration: PosterCacheConfiguration
    private let httpClient: any MetadataHTTPClient
    private let fileManager: FileManager

    public init(configuration: PosterCacheConfiguration, httpClient: any MetadataHTTPClient) {
        self.init(configuration: configuration, httpClient: httpClient, fileManager: .default)
    }

    init(
        configuration: PosterCacheConfiguration,
        httpClient: any MetadataHTTPClient,
        fileManager: FileManager
    ) {
        self.configuration = configuration
        self.httpClient = httpClient
        self.fileManager = fileManager
    }

    public func cache(
        _ image: RemoteImage,
        using imageConfiguration: TMDBImageConfiguration
    ) async throws -> PosterCacheResult {
        guard configuration.cacheRoot.isFileURL else {
            throw MetadataError.invalidResponse
        }
        guard let imageURL = TMDBImageURLResolver.imageURL(for: image, using: imageConfiguration) else {
            throw MetadataError.invalidResponse
        }

        let cacheURL = try localCacheURL(for: image)
        if let byteCount = try existingNonEmptyFileByteCount(at: cacheURL) {
            return PosterCacheResult(
                localPath: cacheURL.path,
                cachedAt: configuration.now(),
                byteCount: byteCount,
                state: .hit
            )
        }

        let data = try await downloadImage(from: imageURL)
        guard !data.isEmpty else {
            throw MetadataError.invalidResponse
        }

        try writeAtomically(data, to: cacheURL)
        return PosterCacheResult(
            localPath: cacheURL.path,
            cachedAt: configuration.now(),
            byteCount: data.count,
            state: .miss
        )
    }

    private func localCacheURL(for image: RemoteImage) throws -> URL {
        guard let sizeComponent = safeCachePathComponent(image.preferredCacheSize) else {
            throw MetadataError.invalidResponse
        }

        let normalizedRemotePath = TMDBImageURLResolver.normalizedRemotePath(image.remotePath)
        let hash = StablePathHash.hash(normalizedRemotePath)
        let fileName = "\(hash).\(safeExtension(for: normalizedRemotePath))"

        return configuration.cacheRoot
            .appendingPathComponent("tmdb", isDirectory: true)
            .appendingPathComponent("poster", isDirectory: true)
            .appendingPathComponent(sizeComponent, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private func downloadImage(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let response: MetadataHTTPResponse
        do {
            response = try await httpClient.send(request)
        } catch {
            throw MetadataError.transportFailure
        }

        switch response.statusCode {
        case 200...299:
            return response.data
        case 401:
            throw MetadataError.unauthorized
        case 404:
            throw MetadataError.notFound
        case 429:
            throw MetadataError.rateLimited
        case 500...599:
            throw MetadataError.serverUnavailable(statusCode: response.statusCode)
        default:
            throw MetadataError.invalidResponse
        }
    }

    private func existingNonEmptyFileByteCount(at url: URL) throws -> Int? {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return nil
        }
        guard !isDirectory.boolValue else {
            throw MetadataError.invalidResponse
        }

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: url.path)
        } catch {
            throw MetadataError.invalidResponse
        }

        let byteCount = (attributes[.size] as? NSNumber)?.intValue ?? 0
        return byteCount > 0 ? byteCount : nil
    }

    private func writeAtomically(_ data: Data, to finalURL: URL) throws {
        let directoryURL = finalURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )

            let temporaryURL = directoryURL.appendingPathComponent(
                ".\(finalURL.lastPathComponent).\(UUID().uuidString).tmp",
                isDirectory: false
            )

            do {
                try data.write(to: temporaryURL, options: [])
                if fileManager.fileExists(atPath: finalURL.path) {
                    _ = try fileManager.replaceItemAt(
                        finalURL,
                        withItemAt: temporaryURL,
                        backupItemName: nil
                    )
                } else {
                    try fileManager.moveItem(at: temporaryURL, to: finalURL)
                }
            } catch {
                try? fileManager.removeItem(at: temporaryURL)
                throw error
            }
        } catch let error as MetadataError {
            throw error
        } catch {
            throw MetadataError.invalidResponse
        }
    }

    private func safeCachePathComponent(_ value: String) -> String? {
        guard !value.isEmpty else {
            return nil
        }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        return value
    }

    private func safeExtension(for remotePath: String) -> String {
        let pathWithoutQuery = remotePath
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let fileName = pathWithoutQuery.split(separator: "/").last.map(String.init) ?? ""
        guard let dotIndex = fileName.lastIndex(of: "."),
              dotIndex != fileName.startIndex,
              dotIndex < fileName.index(before: fileName.endIndex) else {
            return "jpg"
        }

        let imageExtension = String(fileName[fileName.index(after: dotIndex)...]).lowercased()
        let allowedExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "avif"]
        return allowedExtensions.contains(imageExtension) ? imageExtension : "jpg"
    }
}

enum TMDBImageURLResolver {
    static func imageURL(
        for image: RemoteImage,
        using imageConfiguration: TMDBImageConfiguration,
        size requestedSize: String? = nil
    ) -> URL? {
        guard !image.remotePath.isEmpty else {
            return nil
        }

        let size = requestedSize
            ?? preferredImageSize(for: image, availableSizes: imageConfiguration.posterSizes)
        let trimmedPath = normalizedRemotePath(image.remotePath)

        return imageConfiguration.secureBaseURL
            .appendingPathComponent(size)
            .appendingPathComponent(trimmedPath)
    }

    static func preferredImageSize(for image: RemoteImage, availableSizes: [String]) -> String {
        if availableSizes.contains(image.preferredCacheSize) {
            return image.preferredCacheSize
        }
        if availableSizes.contains("original") {
            return "original"
        }
        return availableSizes.last ?? image.preferredCacheSize
    }

    static func normalizedRemotePath(_ remotePath: String) -> String {
        remotePath.hasPrefix("/") ? String(remotePath.dropFirst()) : remotePath
    }
}
