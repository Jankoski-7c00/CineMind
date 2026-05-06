import Playback
import XCTest

final class PlaybackModuleTests: XCTestCase {
    func testPlaybackTargetImportsAndBuilds() {
        XCTAssertEqual(PlaybackModule.name, "Playback")
    }
}
