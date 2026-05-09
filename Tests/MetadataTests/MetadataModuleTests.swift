import Domain
import Metadata
import XCTest

final class MetadataModuleTests: XCTestCase {
    func testMetadataTargetImportsAndBuilds() {
        XCTAssertEqual(MetadataModule.name, "Metadata")
    }

    func testMetadataTestsCanImportDomain() {
        XCTAssertEqual(MediaType.movie.rawValue, "movie")
    }
}
