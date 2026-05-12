import Domain
import Foundation
import Metadata
import XCTest

final class PosterCacheTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PosterCacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testDeterministicCachePathUsesStableHashAndSafeLocalComponents() async throws {
        let client = PosterCacheHTTPClient { request in
            XCTAssertEqual(request.url?.absoluteString, "https://image.tmdb.test/t/p/w500/poster.jpg")
            return MetadataHTTPResponse(statusCode: 200, data: Data([1, 2, 3]))
        }
        let cache = makeCache(client: client)

        let result = try await cache.cache(
            remoteImage(path: "/poster.jpg"),
            using: imageConfiguration()
        )

        let expectedURL = expectedCacheURL(remotePath: "/poster.jpg", extension: "jpg")
        XCTAssertEqual(result.localPath, expectedURL.path)
        XCTAssertTrue(result.localPath.contains("/tmdb/poster/w500/"))
        XCTAssertFalse(result.localPath.contains("/poster.jpg"))
    }

    func testParentDirectoriesAreCreated() async throws {
        let client = PosterCacheHTTPClient { _ in
            MetadataHTTPResponse(statusCode: 200, data: Data([1]))
        }
        let cache = makeCache(client: client)
        let expectedDirectory = expectedCacheURL(remotePath: "/poster.jpg")
            .deletingLastPathComponent()

        XCTAssertFalse(FileManager.default.fileExists(atPath: expectedDirectory.path))

        _ = try await cache.cache(remoteImage(path: "/poster.jpg"), using: imageConfiguration())

        var isDirectory = ObjCBool(false)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: expectedDirectory.path, isDirectory: &isDirectory)
        )
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testFirstDownloadWritesFileAndReturnsMissResult() async throws {
        let imageBytes = Data([0xFF, 0xD8, 0xFF])
        let cachedAt = Date(timeIntervalSince1970: 1_200)
        let client = PosterCacheHTTPClient { _ in
            MetadataHTTPResponse(statusCode: 200, data: imageBytes)
        }
        let cache = makeCache(client: client, now: cachedAt)

        let result = try await cache.cache(remoteImage(path: "/poster.jpg"), using: imageConfiguration())

        XCTAssertEqual(result.state, .miss)
        XCTAssertEqual(result.cachedAt, cachedAt)
        XCTAssertEqual(result.byteCount, imageBytes.count)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: result.localPath)), imageBytes)
        XCTAssertEqual(client.requests.count, 1)
    }

    func testExistingNonEmptyFileReturnsHitWithoutHTTPCall() async throws {
        let existingBytes = Data([9, 8, 7])
        let cachedAt = Date(timeIntervalSince1970: 1_300)
        let expectedURL = expectedCacheURL(remotePath: "/poster.jpg")
        try FileManager.default.createDirectory(
            at: expectedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try existingBytes.write(to: expectedURL)

        let client = PosterCacheHTTPClient { _ in
            XCTFail("Cache hit should not send HTTP request.")
            return MetadataHTTPResponse(statusCode: 200, data: Data([1]))
        }
        let cache = makeCache(client: client, now: cachedAt)

        let result = try await cache.cache(remoteImage(path: "/poster.jpg"), using: imageConfiguration())

        XCTAssertEqual(result.localPath, expectedURL.path)
        XCTAssertEqual(result.state, .hit)
        XCTAssertEqual(result.cachedAt, cachedAt)
        XCTAssertEqual(result.byteCount, existingBytes.count)
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testMissingFileRedownloads() async throws {
        var responses = [Data([1]), Data([2, 3])]
        let client = PosterCacheHTTPClient { _ in
            MetadataHTTPResponse(statusCode: 200, data: responses.removeFirst())
        }
        let cache = makeCache(client: client)

        let firstResult = try await cache.cache(remoteImage(path: "/poster.jpg"), using: imageConfiguration())
        try FileManager.default.removeItem(at: URL(fileURLWithPath: firstResult.localPath))

        let secondResult = try await cache.cache(remoteImage(path: "/poster.jpg"), using: imageConfiguration())

        XCTAssertEqual(secondResult.state, .miss)
        XCTAssertEqual(secondResult.byteCount, 2)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: secondResult.localPath)), Data([2, 3]))
        XCTAssertEqual(client.requests.count, 2)
    }

    func testEmptyFileRedownloads() async throws {
        let expectedURL = expectedCacheURL(remotePath: "/poster.jpg")
        try FileManager.default.createDirectory(
            at: expectedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: expectedURL)

        let client = PosterCacheHTTPClient { _ in
            MetadataHTTPResponse(statusCode: 200, data: Data([4, 5, 6]))
        }
        let cache = makeCache(client: client)

        let result = try await cache.cache(remoteImage(path: "/poster.jpg"), using: imageConfiguration())

        XCTAssertEqual(result.state, .miss)
        XCTAssertEqual(result.byteCount, 3)
        XCTAssertEqual(try Data(contentsOf: expectedURL), Data([4, 5, 6]))
        XCTAssertEqual(client.requests.count, 1)
    }

    func testNonSuccessImageResponseMapsToMetadataError() async throws {
        let client = PosterCacheHTTPClient { _ in
            MetadataHTTPResponse(statusCode: 503, data: Data())
        }
        let cache = makeCache(client: client)

        do {
            _ = try await cache.cache(remoteImage(path: "/poster.jpg"), using: imageConfiguration())
            XCTFail("Expected server unavailable.")
        } catch {
            XCTAssertEqual(error as? MetadataError, .serverUnavailable(statusCode: 503))
        }
    }

    func testTransportFailureMapsToMetadataError() async throws {
        let client = PosterCacheHTTPClient { _ in
            throw URLError(.notConnectedToInternet)
        }
        let cache = makeCache(client: client)

        do {
            _ = try await cache.cache(remoteImage(path: "/poster.jpg"), using: imageConfiguration())
            XCTFail("Expected transport failure.")
        } catch {
            XCTAssertEqual(error as? MetadataError, .transportFailure)
        }
    }

    func testRemotePathExtensionIsPreservedWhenSafe() async throws {
        let client = PosterCacheHTTPClient { _ in
            MetadataHTTPResponse(statusCode: 200, data: Data([1]))
        }
        let cache = makeCache(client: client)

        let result = try await cache.cache(
            remoteImage(path: "/nested/Poster.WEBP"),
            using: imageConfiguration()
        )

        XCTAssertEqual(
            result.localPath,
            expectedCacheURL(remotePath: "/nested/Poster.WEBP", extension: "webp").path
        )
    }

    func testExtensionlessAndSuspiciousRemotePathsUseSafeDefaultExtension() async throws {
        let client = PosterCacheHTTPClient { _ in
            MetadataHTTPResponse(statusCode: 200, data: Data([1]))
        }
        let cache = makeCache(client: client)

        let extensionless = try await cache.cache(
            remoteImage(path: "/poster"),
            using: imageConfiguration()
        )
        let suspicious = try await cache.cache(
            remoteImage(path: "/poster.php"),
            using: imageConfiguration()
        )

        XCTAssertEqual(extensionless.localPath, expectedCacheURL(remotePath: "/poster", extension: "jpg").path)
        XCTAssertEqual(suspicious.localPath, expectedCacheURL(remotePath: "/poster.php", extension: "jpg").path)
    }

    func testNonFileCacheRootIsRejectedWithoutHTTPCall() async throws {
        let client = PosterCacheHTTPClient { _ in
            XCTFail("Invalid cache root should not send HTTP request.")
            return MetadataHTTPResponse(statusCode: 200, data: Data([1]))
        }
        let cache = PosterCache(
            configuration: PosterCacheConfiguration(
                cacheRoot: URL(string: "https://cache.example.test/root")!
            ),
            httpClient: client
        )

        do {
            _ = try await cache.cache(remoteImage(path: "/poster.jpg"), using: imageConfiguration())
            XCTFail("Expected invalid response.")
        } catch {
            XCTAssertEqual(error as? MetadataError, .invalidResponse)
        }
        XCTAssertTrue(client.requests.isEmpty)
    }

    private func makeCache(
        client: PosterCacheHTTPClient,
        now: Date = Date(timeIntervalSince1970: 1_000)
    ) -> PosterCache {
        PosterCache(
            configuration: PosterCacheConfiguration(
                cacheRoot: temporaryDirectory,
                now: { now }
            ),
            httpClient: client
        )
    }

    private func expectedCacheURL(
        remotePath: String,
        size: String = "w500",
        extension imageExtension: String = "jpg"
    ) -> URL {
        temporaryDirectory
            .appendingPathComponent("tmdb", isDirectory: true)
            .appendingPathComponent("poster", isDirectory: true)
            .appendingPathComponent(size, isDirectory: true)
            .appendingPathComponent("\(stablePathHash(normalizedRemotePath(remotePath))).\(imageExtension)")
    }

    private func imageConfiguration() -> TMDBImageConfiguration {
        TMDBImageConfiguration(
            secureBaseURL: URL(string: "https://image.tmdb.test/t/p/")!,
            posterSizes: ["w92", "w500", "original"]
        )
    }

    private func remoteImage(path: String) -> RemoteImage {
        RemoteImage(source: .tmdb, remotePath: path, preferredCacheSize: "w500")
    }
}

private final class PosterCacheHTTPClient: MetadataHTTPClient {
    private(set) var requests: [URLRequest] = []
    private let handler: (URLRequest) async throws -> MetadataHTTPResponse

    init(handler: @escaping (URLRequest) async throws -> MetadataHTTPResponse) {
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> MetadataHTTPResponse {
        requests.append(request)
        return try await handler(request)
    }
}

private func normalizedRemotePath(_ remotePath: String) -> String {
    remotePath.hasPrefix("/") ? String(remotePath.dropFirst()) : remotePath
}

private func stablePathHash(_ value: String) -> String {
    let bytes = value.utf8
    var hash: UInt64 = 0xcbf29ce484222325

    for byte in bytes {
        hash ^= UInt64(byte)
        hash = hash &* 0x100000001b3
    }

    return String(format: "%016llx", hash)
}
