@testable import Application
@testable import AppUI
import XCTest

final class LibraryFilePlaybackPresentationTests: XCTestCase {
    func testPrimaryFilePrefersActivePlayableFile() throws {
        let first = makeFile(id: "first")
        let active = makeFile(id: "active")
        let status = makeStatus(state: .playing, mediaFileID: active.mediaFileID)

        let result = LibraryFilePlaybackPresentation.primaryFile(
            in: [first, active],
            playbackStatus: status
        )

        XCTAssertEqual(result, active)
    }

    func testPrimaryFileFallsBackToFirstPlayableFile() throws {
        let unavailable = makeFile(id: "unavailable", isPlayable: false)
        let playable = makeFile(id: "playable")

        let result = LibraryFilePlaybackPresentation.primaryFile(
            in: [unavailable, playable],
            playbackStatus: .idle
        )

        XCTAssertEqual(result, playable)
    }

    func testButtonStateReflectsActivePlaybackState() {
        let file = makeFile(id: "active")

        XCTAssertEqual(
            LibraryFilePlaybackPresentation.buttonState(
                for: file,
                playbackStatus: makeStatus(state: .paused, mediaFileID: file.mediaFileID)
            ),
            .resume
        )
        XCTAssertEqual(
            LibraryFilePlaybackPresentation.buttonState(
                for: file,
                playbackStatus: makeStatus(state: .playing, mediaFileID: file.mediaFileID)
            ),
            .disabled("Playing")
        )
        XCTAssertEqual(
            LibraryFilePlaybackPresentation.buttonState(
                for: file,
                playbackStatus: makeStatus(state: .buffering, mediaFileID: file.mediaFileID)
            ),
            .disabled("Buffering")
        )
        XCTAssertEqual(
            LibraryFilePlaybackPresentation.buttonState(
                for: file,
                playbackStatus: makeStatus(state: .ended, mediaFileID: file.mediaFileID)
            ),
            .play
        )
    }

    func testButtonStateIsPlayForDifferentActiveFile() {
        let file = makeFile(id: "requested")

        let result = LibraryFilePlaybackPresentation.buttonState(
            for: file,
            playbackStatus: makeStatus(state: .playing, mediaFileID: "different")
        )

        XCTAssertEqual(result, .play)
    }

    private func makeFile(
        id: String,
        isPlayable: Bool = true
    ) -> LibraryFileSummary {
        LibraryFileSummary(
            mediaFileID: id,
            isPlayable: isPlayable,
            playabilityReason: isPlayable ? nil : "Unsupported",
            resumePositionLabel: nil,
            fileName: "\(id).mp4",
            fileExtension: "mp4",
            fileSizeLabel: "1 GB",
            availabilityLabel: isPlayable ? "available" : "unavailable"
        )
    }

    private func makeStatus(
        state: PlaybackApplicationState,
        mediaFileID: String?
    ) -> PlaybackApplicationStatus {
        PlaybackApplicationStatus(
            state: state,
            mediaFileID: mediaFileID,
            displayName: nil,
            positionMS: 0,
            durationMS: nil
        )
    }
}
