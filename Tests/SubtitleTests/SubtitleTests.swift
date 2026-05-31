import Domain
import Subtitle
import XCTest

final class SubtitleTests: XCTestCase {
    func testModuleImportsAndBuilds() {
        XCTAssertEqual(SubtitleModule.name, "Subtitle")
    }

    func testSubtitleFormatClassifiesExternalCueSupport() {
        XCTAssertEqual(SubtitleFormat(fileExtension: ".srt"), .srt)
        XCTAssertEqual(SubtitleFormat(fileExtension: "webvtt"), .webVTT)
        XCTAssertTrue(SubtitleFormat.srt.supportsExternalCueParsing)
        XCTAssertTrue(SubtitleFormat.webVTT.supportsExternalCueParsing)
        XCTAssertFalse(SubtitleFormat.ass.supportsExternalCueParsing)
        XCTAssertFalse(SubtitleFormat.ssa.supportsExternalCueParsing)
    }

    func testSubtitleDownloadResultCarriesProviderPayloadWithoutPersistenceAsset() {
        let result = SubtitleDownloadResult(
            resultID: "provider-result-1",
            suggestedFileName: "Arrival.en.srt",
            languageCode: "en",
            format: .srt,
            content: "1\n00:00:00,000 --> 00:00:01,000\nHello"
        )

        XCTAssertEqual(result.resultID, "provider-result-1")
        XCTAssertEqual(result.suggestedFileName, "Arrival.en.srt")
        XCTAssertEqual(result.languageCode, "en")
        XCTAssertEqual(result.format, .srt)
        XCTAssertTrue(result.content.contains("Hello"))
    }

    func testSRTParserBuildsTimelineAndActiveCueText() throws {
        let timeline = try SubtitleParser.parse(
            """
            1
            00:00:01,000 --> 00:00:03,500
            Hello <i>Arrival</i>

            2
            00:00:04,000 --> 00:00:05,000
            General Shang
            """,
            format: .srt
        )

        XCTAssertEqual(timeline.cues.count, 2)
        XCTAssertNil(timeline.activeText(atMS: 999))
        XCTAssertEqual(timeline.activeText(atMS: 1_000), "Hello Arrival")
        XCTAssertEqual(timeline.activeText(atMS: 4_500), "General Shang")
        XCTAssertNil(timeline.activeText(atMS: 5_000))
    }

    func testWebVTTParserSupportsCueIDsAndMinuteTiming() throws {
        let timeline = try SubtitleParser.parse(
            """
            WEBVTT

            cue-1
            00:01.250 --> 00:02.000
            First cue
            """,
            format: .webVTT
        )

        XCTAssertEqual(timeline.activeText(atMS: 1_250), "First cue")
        XCTAssertNil(timeline.activeText(atMS: 2_000))
    }

    func testASSAndSSAAreUnsupportedForExternalCueParsing() {
        XCTAssertThrowsError(try SubtitleParser.parse("[Script Info]", format: .ass)) { error in
            XCTAssertEqual(error as? SubtitleError, .unsupportedFormat(.ass))
        }
    }

    func testSidecarMatcherMatchesSameDirectoryAndInfersLanguage() {
        let media = SubtitleSidecarMediaFile(
            mediaItemID: "item",
            mediaFileID: "file",
            libraryFolderID: "folder",
            relativePath: "Movies/Arrival (2016).mkv"
        )

        let match = SubtitleSidecarMatcher.match(
            subtitleRelativePath: "Movies/Arrival (2016).zh-Hans.srt",
            mediaFiles: [media]
        )

        XCTAssertEqual(match?.mediaFile, media)
        XCTAssertEqual(match?.languageCode, "zh-Hans")
    }

    func testSidecarMatcherDoesNotCrossDirectories() {
        let media = SubtitleSidecarMediaFile(
            mediaItemID: "item",
            mediaFileID: "file",
            libraryFolderID: "folder",
            relativePath: "Movies/Arrival (2016).mkv"
        )

        XCTAssertNil(
            SubtitleSidecarMatcher.match(
                subtitleRelativePath: "Other/Arrival (2016).en.srt",
                mediaFiles: [media]
            )
        )
    }
}
