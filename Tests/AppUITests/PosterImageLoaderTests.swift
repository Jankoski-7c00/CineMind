@testable import AppUI
import Foundation
import XCTest

final class PosterImageLoaderTests: XCTestCase {
    func testNilCachePathProducesNoCachePlaceholder() async {
        let result = await LocalPosterImageLoader().load(localCachePath: nil)

        guard case .placeholder(.noCachePath) = result else {
            return XCTFail("Expected no-cache-path placeholder")
        }
    }

    func testMissingCachePathProducesFileMissingPlaceholder() async {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
            .path

        let result = await LocalPosterImageLoader().load(localCachePath: path)

        guard case .placeholder(.fileMissing) = result else {
            return XCTFail("Expected file-missing placeholder")
        }
    }
}
