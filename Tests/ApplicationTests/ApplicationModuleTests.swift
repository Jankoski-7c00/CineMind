import Application
import XCTest

final class ApplicationModuleTests: XCTestCase {
    func testApplicationTargetImportsAndBuilds() {
        XCTAssertEqual(ApplicationModule.name, "Application")
    }
}
