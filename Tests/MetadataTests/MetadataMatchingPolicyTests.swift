import Metadata
import XCTest

final class MetadataCandidateRankingPolicyTests: XCTestCase {
    private let policy = MetadataCandidateRankingPolicy()

    func testExactMovieTitleAndYearRanksHigh() {
        let query = MetadataSearchQuery.movie(title: "Arrival", year: 2016)
        let arrival = movieCandidate(id: 1, title: "Arrival", year: 2016)
        let moon = movieCandidate(id: 2, title: "Moon", year: 2016)

        let ranked = policy.rankMovieCandidates(for: query, candidates: [moon, arrival])

        XCTAssertEqual(ranked.map(\.identifier), [arrival.identifier, moon.identifier])
        XCTAssertEqual(ranked[0].confidence, 0.98, accuracy: 0.000_001)
        XCTAssertEqual(confidenceInput(ranked[0], "title_score"), 1.0, accuracy: 0.000_001)
        XCTAssertEqual(confidenceInput(ranked[0], "year_match"), 1.0, accuracy: 0.000_001)
        XCTAssertEqual(ranked[0].confidenceInputs["media_type_match"], "true")
    }

    func testTitleNormalizationHandlesCasePunctuationAndWhitespaceOnly() {
        let query = MetadataSearchQuery.movie(
            title: "Spider-Man:  Across   The Spider-Verse",
            year: 2023
        )
        let candidate = movieCandidate(
            id: 1,
            title: "spider man across the spider verse",
            year: 2023
        )

        let ranked = policy.rankMovieCandidates(for: query, candidates: [candidate])

        XCTAssertEqual(ranked[0].confidence, 0.98, accuracy: 0.000_001)
        XCTAssertEqual(confidenceInput(ranked[0], "title_score"), 1.0, accuracy: 0.000_001)
    }

    func testTitleMismatchRanksLow() {
        let query = MetadataSearchQuery.movie(title: "Arrival", year: 2016)
        let candidate = movieCandidate(id: 1, title: "Moon", year: 2016)

        let ranked = policy.rankMovieCandidates(for: query, candidates: [candidate])

        XCTAssertLessThan(ranked[0].confidence, 0.30)
        XCTAssertEqual(confidenceInput(ranked[0], "title_score"), 0.0, accuracy: 0.000_001)
    }

    func testYearMismatchPenalizesMovie() throws {
        let query = MetadataSearchQuery.movie(title: "Arrival", year: 2016)
        let correctYear = movieCandidate(id: 1, title: "Arrival", year: 2016)
        let wrongYear = movieCandidate(id: 2, title: "Arrival", year: 1999)

        let ranked = policy.rankMovieCandidates(for: query, candidates: [wrongYear, correctYear])
        let penalized = try XCTUnwrap(ranked.first { $0.identifier == wrongYear.identifier })

        XCTAssertEqual(ranked.first?.identifier, correctYear.identifier)
        XCTAssertEqual(penalized.confidence, 0.78, accuracy: 0.000_001)
        XCTAssertLessThan(penalized.confidence, 0.85)
        XCTAssertEqual(confidenceInput(penalized, "year_match"), 0.0, accuracy: 0.000_001)
    }

    func testEpisodeSeriesTitleMatchRanksHigh() {
        let query = MetadataSearchQuery.episode(
            seriesTitle: "Severance",
            seasonNumber: 1,
            episodeNumber: 2
        )
        let candidate = episodeCandidate(seriesID: 1, title: "Severance", season: 1, episode: 2)

        let ranked = policy.rankEpisodeCandidates(for: query, candidates: [candidate])

        XCTAssertEqual(ranked[0].confidence, 0.96, accuracy: 0.000_001)
        XCTAssertEqual(confidenceInput(ranked[0], "title_score"), 1.0, accuracy: 0.000_001)
        XCTAssertEqual(ranked[0].confidenceInputs["episode_exists"], "true")
        XCTAssertEqual(ranked[0].confidenceInputs["media_type_match"], "true")
    }

    func testMismatchedProviderIdentifiersScoreZeroWithoutThrowing() {
        let movieQuery = MetadataSearchQuery.movie(title: "Arrival", year: 2016)
        let episodeIdentifierForMovie = episodeCandidate(
            seriesID: 1,
            title: "Arrival",
            season: 1,
            episode: 2
        )

        let movieRanked = policy.rankMovieCandidates(
            for: movieQuery,
            candidates: [episodeIdentifierForMovie]
        )

        XCTAssertEqual(movieRanked[0].confidence, 0.0, accuracy: 0.000_001)
        XCTAssertEqual(movieRanked[0].confidenceInputs["media_type_match"], "false")

        let episodeQuery = MetadataSearchQuery.episode(
            seriesTitle: "Severance",
            seasonNumber: 1,
            episodeNumber: 2
        )
        let movieIdentifier = movieCandidate(id: 1, title: "Severance")
        let wrongEpisodeNumber = episodeCandidate(seriesID: 2, title: "Severance", season: 1, episode: 3)

        let episodeRanked = policy.rankEpisodeCandidates(
            for: episodeQuery,
            candidates: [movieIdentifier, wrongEpisodeNumber]
        )

        XCTAssertEqual(episodeRanked.map(\.identifier), [movieIdentifier.identifier, wrongEpisodeNumber.identifier])
        XCTAssertEqual(episodeRanked.map(\.confidence), [0.0, 0.0])
        XCTAssertEqual(episodeRanked[0].confidenceInputs["media_type_match"], "false")
        XCTAssertEqual(episodeRanked[1].confidenceInputs["media_type_match"], "true")
        XCTAssertEqual(episodeRanked[1].confidenceInputs["episode_exists"], "false")
    }

    func testOrderingIsDeterministicForEqualScores() {
        let query = MetadataSearchQuery.movie(title: "Arrival", year: 2016)
        let first = movieCandidate(id: 1, title: "Arrival", year: 2016)
        let second = movieCandidate(id: 2, title: "Arrival", year: 2016)

        let ranked = policy.rankMovieCandidates(for: query, candidates: [first, second])

        XCTAssertEqual(ranked.map(\.identifier), [first.identifier, second.identifier])
        XCTAssertEqual(ranked[0].confidence, ranked[1].confidence, accuracy: 0.000_001)
    }

    func testPolicyDoesNotMutateCandidates() {
        let query = MetadataSearchQuery.movie(title: "Arrival", year: 2016)
        let candidates = [
            movieCandidate(
                id: 1,
                title: "Arrival",
                year: 2016,
                confidence: 0.42,
                confidenceInputs: ["source": "original"]
            )
        ]
        let original = candidates

        _ = policy.rankMovieCandidates(for: query, candidates: candidates)

        XCTAssertEqual(candidates, original)
    }
}

final class MetadataAutoMatchPolicyTests: XCTestCase {
    private let policy = MetadataAutoMatchPolicy()

    func testEmptyListReturnsNoCandidates() {
        XCTAssertEqual(policy.decision(for: []), .noCandidates)
    }

    func testTopScoreBelowMinimumReturnsLowConfidence() {
        let candidate = movieCandidate(id: 1, confidence: 0.84)

        XCTAssertEqual(policy.decision(for: [candidate]), .lowConfidence)
    }

    func testTopScoreGapLessThanMinimumReturnsAmbiguous() {
        let top = movieCandidate(id: 1, confidence: 0.95)
        let second = movieCandidate(id: 2, confidence: 0.8501)

        XCTAssertEqual(policy.decision(for: [top, second]), .ambiguous)
    }

    func testTopScoreGapExactlyMinimumReturnsMatched() {
        let top = movieCandidate(id: 1, confidence: 0.95)
        let second = movieCandidate(id: 2, confidence: 0.85)

        XCTAssertEqual(policy.decision(for: [top, second]), .matched(top))
    }

    func testTopScoreAtMinimumWithLargerGapReturnsMatched() {
        let top = movieCandidate(id: 1, confidence: 0.85)
        let second = movieCandidate(id: 2, confidence: 0.74)

        XCTAssertEqual(policy.decision(for: [top, second]), .matched(top))
    }
}

private func movieCandidate(
    id: Int,
    title: String = "Movie",
    originalTitle: String? = nil,
    year: Int? = nil,
    confidence: Double = 0.0,
    confidenceInputs: [String: String] = [:]
) -> MetadataCandidate {
    MetadataCandidate(
        identifier: MetadataProviderIdentifier.movie(id: id)!,
        displayTitle: title,
        originalTitle: originalTitle,
        year: year,
        confidence: confidence,
        confidenceInputs: confidenceInputs
    )
}

private func episodeCandidate(
    seriesID: Int,
    title: String,
    originalTitle: String? = nil,
    season: Int,
    episode: Int,
    confidence: Double = 0.0,
    confidenceInputs: [String: String] = [:]
) -> MetadataCandidate {
    MetadataCandidate(
        identifier: MetadataProviderIdentifier.episode(
            seriesID: seriesID,
            seasonNumber: season,
            episodeNumber: episode
        )!,
        displayTitle: title,
        originalTitle: originalTitle,
        confidence: confidence,
        confidenceInputs: confidenceInputs
    )
}

private func confidenceInput(
    _ candidate: MetadataCandidate,
    _ key: String,
    file: StaticString = #filePath,
    line: UInt = #line
) -> Double {
    guard let value = candidate.confidenceInputs[key], let double = Double(value) else {
        XCTFail("Missing numeric confidence input \(key).", file: file, line: line)
        return -1.0
    }
    return double
}
