import Application
import XCTest

final class LibraryItemDetailFileSizeLabelTests: XCTestCase {
    func testZeroBytes() {
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(0), "0 bytes")
    }

    func testBytesBelow1024() {
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(1), "1 bytes")
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(500), "500 bytes")
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(1023), "1023 bytes")
    }

    func testOneKB() {
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(1024), "1.0 KB")
    }

    func testKB() {
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(1536), "1.5 KB")
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(1024 * 1023), "1023.0 KB")
    }

    func testOneMB() {
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(1024 * 1024), "1.0 MB")
    }

    func testMB() {
        let oneMB: Int64 = 1024 * 1024
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(oneMB * 3 / 2), "1.5 MB")
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(oneMB * 100 + oneMB / 2), "100.5 MB")
    }

    func testOneGB() {
        let oneGB: Int64 = 1024 * 1024 * 1024
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(oneGB), "1.0 GB")
    }

    func testGB() {
        let oneGB: Int64 = 1024 * 1024 * 1024
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(oneGB * 2 + oneGB / 2), "2.5 GB")
    }

    func testDecimalSeparatorIsDot() {
        let oneMB: Int64 = 1024 * 1024
        let label = LibraryItemDetailUseCase.defaultFileSizeLabel(oneMB + oneMB / 2)
        XCTAssertTrue(label.contains("."), "decimal separator must be dot, got: \(label)")
        XCTAssertFalse(label.contains(","), "decimal separator must not be comma, got: \(label)")
    }

    func testExactBoundaries() {
        let oneKB: Int64 = 1024
        let oneMB: Int64 = 1024 * 1024
        let oneGB: Int64 = 1024 * 1024 * 1024

        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(oneKB - 1), "1023 bytes")
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(oneKB), "1.0 KB")
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(oneMB - oneKB), "1023.0 KB")
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(oneMB), "1.0 MB")
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(oneGB - oneMB), "1023.0 MB")
        XCTAssertEqual(LibraryItemDetailUseCase.defaultFileSizeLabel(oneGB), "1.0 GB")
    }
}
