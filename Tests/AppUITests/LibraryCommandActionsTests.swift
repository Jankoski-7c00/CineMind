import AppUI
import XCTest

final class LibraryCommandActionsTests: XCTestCase {
    func testRoutesEachCommandToItsFocusedAction() {
        var invocations: [String] = []
        let actions = LibraryCommandActions(
            canAddFolder: true,
            canScanLibrary: true,
            canTogglePresentation: true,
            addFolder: { invocations.append("add") },
            scanLibrary: { invocations.append("scan") },
            togglePresentation: { invocations.append("presentation") },
            toggleInspector: { invocations.append("inspector") }
        )

        actions.addFolder()
        actions.scanLibrary()
        actions.togglePresentation()
        actions.toggleInspector()

        XCTAssertEqual(invocations, ["add", "scan", "presentation", "inspector"])
    }

    func testExposesCommandAvailabilityWithoutChangingRouting() {
        let actions = LibraryCommandActions(
            canAddFolder: false,
            canScanLibrary: false,
            canTogglePresentation: false,
            addFolder: {},
            scanLibrary: {},
            togglePresentation: {},
            toggleInspector: {}
        )

        XCTAssertFalse(actions.canAddFolder)
        XCTAssertFalse(actions.canScanLibrary)
        XCTAssertFalse(actions.canTogglePresentation)
    }
}
