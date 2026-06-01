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
        XCTAssertEqual(ranked[0].confidence, 0.99, accuracy: 0.000_001)
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

        XCTAssertEqual(ranked[0].confidence, 0.99, accuracy: 0.000_001)
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
        XCTAssertEqual(penalized.confidence, 0.824, accuracy: 0.000_001)
        XCTAssertLessThan(penalized.confidence, 0.85)
        XCTAssertEqual(confidenceInput(penalized, "year_match"), 0.2, accuracy: 0.000_001)
    }

    func testYearOffsetCurveKeepsNearYearsHighWithoutIgnoringLargeMismatch() {
        let query = MetadataSearchQuery.movie(title: "Arrival", year: 2016)
        let oneYearOff = movieCandidate(id: 1, title: "Arrival", year: 2017)
        let twoYearsOff = movieCandidate(id: 2, title: "Arrival", year: 2018)
        let farOff = movieCandidate(id: 3, title: "Arrival", year: 2020)

        let ranked = policy.rankMovieCandidates(for: query, candidates: [farOff, twoYearsOff, oneYearOff])

        XCTAssertEqual(ranked.map(\.identifier), [oneYearOff.identifier, twoYearsOff.identifier, farOff.identifier])
        XCTAssertEqual(ranked.map { confidenceInput($0, "year_match") }, [0.9, 0.6, 0.2])
        XCTAssertEqual(ranked[0].confidence, 0.978, accuracy: 0.000_001)
        XCTAssertEqual(ranked[1].confidence, 0.912, accuracy: 0.000_001)
        XCTAssertEqual(ranked[2].confidence, 0.824, accuracy: 0.000_001)
    }

    func testMovieTitleContainmentHandlesHighConfidenceAliasWithoutYear() {
        let query = MetadataSearchQuery.movie(title: "The Million Pound Bank Note")
        let candidate = movieCandidate(id: 34000, title: "The Million Pound Note")
        let distractor = movieCandidate(id: 2, title: "Million Dollar Baby")

        let ranked = policy.rankMovieCandidates(for: query, candidates: [distractor, candidate])

        XCTAssertEqual(ranked.first?.identifier, candidate.identifier)
        XCTAssertGreaterThanOrEqual(ranked[0].confidence, 0.85)
        XCTAssertEqual(ranked[0].confidence, 0.851, accuracy: 0.000_001)
        XCTAssertEqual(confidenceInput(ranked[0], "title_score"), 0.95, accuracy: 0.000_001)
        XCTAssertEqual(confidenceInput(ranked[0], "title_overlap_score"), 0.8, accuracy: 0.000_001)
        XCTAssertEqual(confidenceInput(ranked[0], "title_containment_score"), 0.95, accuracy: 0.000_001)
        XCTAssertEqual(ranked[0].confidenceInputs["title_score_strategy"], "containment")
        XCTAssertEqual(MetadataAutoMatchPolicy().decision(for: [ranked[0]]), .matched(ranked[0]))
    }

    func testTitleNormalizationFoldsDiacritics() {
        let query = MetadataSearchQuery.movie(title: "Amélie", year: 2001)
        let candidate = movieCandidate(id: 1, title: "Amelie", year: 2001)

        let ranked = policy.rankMovieCandidates(for: query, candidates: [candidate])

        XCTAssertEqual(ranked[0].confidence, 0.99, accuracy: 0.000_001)
        XCTAssertEqual(confidenceInput(ranked[0], "title_score"), 1.0, accuracy: 0.000_001)
        XCTAssertEqual(ranked[0].confidenceInputs["title_score_strategy"], "exact")
    }

    func testFuzzyTitleScoreHandlesSmallSpellingDifference() {
        let query = MetadataSearchQuery.movie(title: "The Favourite")
        let candidate = movieCandidate(id: 1, title: "The Favorite")

        let ranked = policy.rankMovieCandidates(for: query, candidates: [candidate])

        XCTAssertEqual(ranked[0].confidence, 0.89, accuracy: 0.000_001)
        XCTAssertEqual(confidenceInput(ranked[0], "title_fuzzy_score"), 1.0, accuracy: 0.000_001)
        XCTAssertEqual(ranked[0].confidenceInputs["title_score_strategy"], "fuzzy")
    }

    func testPrefixScoreHandlesSubtitleInflation() {
        let query = MetadataSearchQuery.movie(title: "Pirates of the Caribbean", year: 2003)
        let candidate = movieCandidate(
            id: 1,
            title: "Pirates of the Caribbean: The Curse of the Black Pearl",
            year: 2003
        )

        let ranked = policy.rankMovieCandidates(for: query, candidates: [candidate])

        XCTAssertEqual(ranked[0].confidence, 0.8674, accuracy: 0.000_001)
        XCTAssertEqual(confidenceInput(ranked[0], "title_prefix_score"), 0.83, accuracy: 0.000_001)
        XCTAssertEqual(ranked[0].confidenceInputs["title_score_strategy"], "prefix")
    }

    func testShortTitleContainmentDoesNotAutoMatch() {
        let query = MetadataSearchQuery.movie(title: "The Thing From Another World")
        let candidate = movieCandidate(id: 1, title: "The Thing")

        let ranked = policy.rankMovieCandidates(for: query, candidates: [candidate])

        XCTAssertLessThan(ranked[0].confidence, 0.85)
        XCTAssertEqual(confidenceInput(ranked[0], "title_containment_score"), 0.0, accuracy: 0.000_001)
        XCTAssertEqual(ranked[0].confidenceInputs["title_score_strategy"], "overlap")
        XCTAssertEqual(MetadataAutoMatchPolicy().decision(for: [ranked[0]]), .lowConfidence)
    }

    func testEpisodeSeriesTitleMatchRanksHigh() {
        let query = MetadataSearchQuery.episode(
            seriesTitle: "Severance",
            seasonNumber: 1,
            episodeNumber: 2
        )
        let candidate = episodeCandidate(seriesID: 1, title: "Severance", season: 1, episode: 2)

        let ranked = policy.rankEpisodeCandidates(for: query, candidates: [candidate])

        XCTAssertEqual(ranked[0].confidence, 0.99, accuracy: 0.000_001)
        XCTAssertEqual(confidenceInput(ranked[0], "title_score"), 1.0, accuracy: 0.000_001)
        XCTAssertEqual(ranked[0].confidenceInputs["episode_exists"], "true")
        XCTAssertEqual(ranked[0].confidenceInputs["media_type_match"], "true")
    }

    func testEpisodeTitleContributesToEpisodeRanking() {
        let query = MetadataSearchQuery.episode(
            seriesTitle: "Example Show",
            seasonNumber: 1,
            episodeNumber: 5,
            episodeTitle: "The Big Twist"
        )
        let correctEpisodeTitle = episodeCandidate(
            seriesID: 1,
            title: "Example Show",
            season: 1,
            episode: 5,
            episodeTitle: "The Big Twist"
        )
        let wrongEpisodeTitle = episodeCandidate(
            seriesID: 2,
            title: "Example Show",
            season: 1,
            episode: 5,
            episodeTitle: "A Quiet Hour"
        )

        let ranked = policy.rankEpisodeCandidates(
            for: query,
            candidates: [wrongEpisodeTitle, correctEpisodeTitle]
        )

        XCTAssertEqual(ranked.map(\.identifier), [correctEpisodeTitle.identifier, wrongEpisodeTitle.identifier])
        XCTAssertEqual(ranked[0].confidence, 0.99, accuracy: 0.000_001)
        XCTAssertEqual(ranked[1].confidence, 0.82, accuracy: 0.000_001)
        XCTAssertEqual(confidenceInput(ranked[0], "series_title_score"), 1.0, accuracy: 0.000_001)
        XCTAssertEqual(confidenceInput(ranked[0], "episode_title_score"), 1.0, accuracy: 0.000_001)
        XCTAssertEqual(confidenceInput(ranked[1], "episode_title_score"), 0.0, accuracy: 0.000_001)
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

    func testNoYearSameTitleCandidatesRemainAmbiguous() {
        let query = MetadataSearchQuery.movie(title: "Crash")
        let first = movieCandidate(id: 1, title: "Crash", year: 1996)
        let second = movieCandidate(id: 2, title: "Crash", year: 2004)

        let ranked = policy.rankMovieCandidates(for: query, candidates: [first, second])

        XCTAssertEqual(ranked[0].confidence, 0.89, accuracy: 0.000_001)
        XCTAssertEqual(ranked[1].confidence, 0.89, accuracy: 0.000_001)
        XCTAssertEqual(MetadataAutoMatchPolicy().decision(for: ranked), .ambiguous)
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
    episodeTitle: String? = nil,
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
        episodeTitle: episodeTitle,
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
