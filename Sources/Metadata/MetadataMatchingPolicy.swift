import Domain
import Foundation

public struct MetadataCandidateRankingPolicy: Equatable, Sendable {
    public init() {}

    public func rankCandidates(
        for query: MetadataSearchQuery,
        candidates: [MetadataCandidate]
    ) -> [MetadataCandidate] {
        switch query.mediaType {
        case .movie:
            rankMovieCandidates(for: query, candidates: candidates)
        case .episode:
            rankEpisodeCandidates(for: query, candidates: candidates)
        }
    }

    public func rankMovieCandidates(
        for query: MetadataSearchQuery,
        candidates: [MetadataCandidate]
    ) -> [MetadataCandidate] {
        ranked(candidates) { candidate in
            scoreMovieCandidate(candidate, query: query)
        }
    }

    public func rankEpisodeCandidates(
        for query: MetadataSearchQuery,
        candidates: [MetadataCandidate]
    ) -> [MetadataCandidate] {
        ranked(candidates) { candidate in
            scoreEpisodeCandidate(candidate, query: query)
        }
    }

    private func ranked(
        _ candidates: [MetadataCandidate],
        score: (MetadataCandidate) -> MetadataCandidateConfidence
    ) -> [MetadataCandidate] {
        candidates.enumerated()
            .map { index, candidate in
                var rankedCandidate = candidate
                let confidence = score(candidate)
                rankedCandidate.confidence = confidence.finalScore
                rankedCandidate.confidenceInputs = confidence.inputs
                return (index: index, candidate: rankedCandidate)
            }
            .sorted {
                if $0.candidate.confidence == $1.candidate.confidence {
                    return $0.index < $1.index
                }
                return $0.candidate.confidence > $1.candidate.confidence
            }
            .map(\.candidate)
    }

    private func scoreMovieCandidate(
        _ candidate: MetadataCandidate,
        query: MetadataSearchQuery
    ) -> MetadataCandidateConfidence {
        let mediaTypeMatches = query.mediaType == .movie
            && candidate.identifier.kind == .movie
            && candidate.identifier.movieID != nil
        guard mediaTypeMatches else {
            return .zero(mediaTypeMatches: false)
        }

        let titleScore = MetadataTitleSimilarity.score(
            queryTitle: query.title,
            displayTitle: candidate.displayTitle,
            originalTitle: candidate.originalTitle
        )
        let yearMatch = Self.yearAlignment(queryYear: query.year, candidateYear: candidate.year)
        let finalScore = min(0.98, titleScore.value * 0.78 + yearMatch * 0.22)

        return MetadataCandidateConfidence(
            titleScore: titleScore,
            yearMatch: yearMatch,
            mediaTypeMatches: true,
            episodeExists: false,
            finalScore: finalScore
        )
    }

    private func scoreEpisodeCandidate(
        _ candidate: MetadataCandidate,
        query: MetadataSearchQuery
    ) -> MetadataCandidateConfidence {
        let mediaTypeMatches = query.mediaType == .episode
            && candidate.identifier.kind == .episode
            && candidate.identifier.seriesID != nil
        let episodeExists = mediaTypeMatches
            && candidate.identifier.seriesID != nil
            && candidate.identifier.seasonNumber == query.seasonNumber
            && candidate.identifier.episodeNumber == query.episodeNumber

        guard episodeExists else {
            return .zero(mediaTypeMatches: mediaTypeMatches)
        }

        let seriesTitle = query.seriesTitle ?? query.title
        let titleScore = MetadataTitleSimilarity.score(
            queryTitle: seriesTitle,
            displayTitle: candidate.displayTitle,
            originalTitle: candidate.originalTitle
        )
        let finalScore = min(0.96, titleScore.value * 0.80 + 0.20)

        return MetadataCandidateConfidence(
            titleScore: titleScore,
            yearMatch: 0.0,
            mediaTypeMatches: true,
            episodeExists: true,
            finalScore: finalScore
        )
    }

    private static func yearAlignment(queryYear: Int?, candidateYear: Int?) -> Double {
        guard let queryYear, let candidateYear else {
            return 0.5
        }

        let difference = abs(queryYear - candidateYear)
        if difference == 0 {
            return 1.0
        }
        if difference == 1 {
            return 0.7
        }
        return 0.0
    }
}

public enum MetadataAutoMatchDecision: Equatable, Sendable {
    case matched(MetadataCandidate)
    case noCandidates
    case lowConfidence
    case ambiguous
}

public struct MetadataAutoMatchPolicy: Equatable, Sendable {
    public var minimumConfidence: Double
    public var minimumConfidenceGap: Double

    private let comparisonTolerance = 0.000_000_000_001

    public init(
        minimumConfidence: Double = 0.85,
        minimumConfidenceGap: Double = 0.10
    ) {
        self.minimumConfidence = minimumConfidence
        self.minimumConfidenceGap = minimumConfidenceGap
    }

    public func decision(for candidates: [MetadataCandidate]) -> MetadataAutoMatchDecision {
        guard !candidates.isEmpty else {
            return .noCandidates
        }

        let ranked = candidates.enumerated().sorted {
            if $0.element.confidence == $1.element.confidence {
                return $0.offset < $1.offset
            }
            return $0.element.confidence > $1.element.confidence
        }

        let top = ranked[0].element
        guard top.confidence >= minimumConfidence else {
            return .lowConfidence
        }

        if ranked.count > 1 {
            let second = ranked[1].element
            let gap = top.confidence - second.confidence
            if gap + comparisonTolerance < minimumConfidenceGap {
                return .ambiguous
            }
        }

        return .matched(top)
    }
}

private struct MetadataCandidateConfidence {
    var titleScore: MetadataTitleScore
    var yearMatch: Double
    var mediaTypeMatches: Bool
    var episodeExists: Bool
    var finalScore: Double

    var inputs: [String: String] {
        [
            "title_score": "\(titleScore.value)",
            "title_overlap_score": "\(titleScore.overlapScore)",
            "title_containment_score": "\(titleScore.containmentScore)",
            "title_score_strategy": titleScore.strategy,
            "year_match": "\(yearMatch)",
            "media_type_match": "\(mediaTypeMatches)",
            "episode_exists": "\(episodeExists)",
            "final_score": "\(finalScore)"
        ]
    }

    static func zero(mediaTypeMatches: Bool) -> MetadataCandidateConfidence {
        MetadataCandidateConfidence(
            titleScore: .zero,
            yearMatch: 0.0,
            mediaTypeMatches: mediaTypeMatches,
            episodeExists: false,
            finalScore: 0.0
        )
    }
}

private struct MetadataTitleScore {
    var value: Double
    var overlapScore: Double
    var containmentScore: Double
    var strategy: String

    static let zero = MetadataTitleScore(
        value: 0.0,
        overlapScore: 0.0,
        containmentScore: 0.0,
        strategy: "none"
    )
}

private enum MetadataTitleSimilarity {
    private static let weakStopwords: Set<String> = ["the", "a", "an"]

    static func score(queryTitle: String, displayTitle: String, originalTitle: String?) -> MetadataTitleScore {
        let displayScore = score(queryTitle, displayTitle)
        guard let originalTitle, !originalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return displayScore
        }

        let originalScore = score(queryTitle, originalTitle)
        return originalScore.value > displayScore.value ? originalScore : displayScore
    }

    private static func score(_ lhs: String, _ rhs: String) -> MetadataTitleScore {
        let left = normalize(lhs)
        let right = normalize(rhs)
        guard !left.isEmpty, !right.isEmpty else {
            return .zero
        }

        let leftTokenList = tokens(left)
        let rightTokenList = tokens(right)
        let leftTokens = Set(leftTokenList)
        let rightTokens = Set(rightTokenList)
        let denominator = max(leftTokens.count, rightTokens.count)
        guard denominator > 0 else {
            return .zero
        }

        let overlapScore = Double(leftTokens.intersection(rightTokens).count) / Double(denominator)
        let containmentScore = orderedContainmentScore(leftTokenList, rightTokenList)

        if left == right {
            return MetadataTitleScore(
                value: 1.0,
                overlapScore: overlapScore,
                containmentScore: containmentScore,
                strategy: "exact"
            )
        }

        if containmentScore > overlapScore {
            return MetadataTitleScore(
                value: containmentScore,
                overlapScore: overlapScore,
                containmentScore: containmentScore,
                strategy: "containment"
            )
        }

        return MetadataTitleScore(
            value: overlapScore,
            overlapScore: overlapScore,
            containmentScore: containmentScore,
            strategy: "overlap"
        )
    }

    private static func normalize(_ value: String) -> String {
        let separator = UnicodeScalar(32)!
        var normalized = String.UnicodeScalarView()

        for scalar in value.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                normalized.append(scalar)
            } else {
                normalized.append(separator)
            }
        }

        return String(normalized)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func tokens(_ value: String) -> [String] {
        value.split(separator: " ").map(String.init)
    }

    private static func orderedContainmentScore(_ lhs: [String], _ rhs: [String]) -> Double {
        let left = contentTokens(lhs)
        let right = contentTokens(rhs)
        let shorter: [String]
        let longer: [String]

        if left.count <= right.count {
            shorter = left
            longer = right
        } else {
            shorter = right
            longer = left
        }

        guard shorter.count >= 3 else {
            return 0.0
        }

        let extraTokenCount = longer.count - shorter.count
        guard extraTokenCount <= 2,
              containsOrderedSubsequence(shorter, in: longer) else {
            return 0.0
        }

        return max(0.0, 1.0 - 0.05 * Double(extraTokenCount))
    }

    private static func contentTokens(_ tokens: [String]) -> [String] {
        tokens.filter { !weakStopwords.contains($0) }
    }

    private static func containsOrderedSubsequence(_ subsequence: [String], in tokens: [String]) -> Bool {
        var currentIndex = 0
        for token in tokens where currentIndex < subsequence.count {
            if token == subsequence[currentIndex] {
                currentIndex += 1
            }
        }
        return currentIndex == subsequence.count
    }
}
