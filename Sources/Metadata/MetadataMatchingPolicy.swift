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
        let finalScore = min(0.99, titleScore.value * 0.78 + yearMatch * 0.22)

        return MetadataCandidateConfidence(
            titleScore: titleScore,
            yearMatch: yearMatch,
            mediaTypeMatches: true,
            episodeExists: false,
            seriesTitleScore: nil,
            episodeTitleScore: nil,
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
        let seriesScore = MetadataTitleSimilarity.score(
            queryTitle: seriesTitle,
            displayTitle: candidate.displayTitle,
            originalTitle: candidate.originalTitle
        )
        let localEpisodeTitle = Self.localEpisodeTitle(query: query, seriesTitle: seriesTitle)
        let episodeTitleScore = Self.episodeTitleScore(
            localEpisodeTitle: localEpisodeTitle,
            candidateEpisodeTitle: candidate.episodeTitle
        )
        let finalScore: Double
        if let episodeTitleScore {
            finalScore = min(0.99, seriesScore.value * 0.72 + episodeTitleScore.value * 0.18 + 0.10)
        } else {
            finalScore = min(0.99, seriesScore.value * 0.80 + 0.19)
        }

        return MetadataCandidateConfidence(
            titleScore: seriesScore,
            yearMatch: 0.0,
            mediaTypeMatches: true,
            episodeExists: true,
            seriesTitleScore: seriesScore,
            episodeTitleScore: episodeTitleScore,
            finalScore: finalScore
        )
    }

    private static func localEpisodeTitle(query: MetadataSearchQuery, seriesTitle: String) -> String? {
        guard query.seriesTitle != nil,
              let title = nonEmptyValue(query.title),
              title != seriesTitle else {
            return nil
        }
        return title
    }

    private static func episodeTitleScore(
        localEpisodeTitle: String?,
        candidateEpisodeTitle: String?
    ) -> MetadataTitleScore? {
        guard let localEpisodeTitle,
              let candidateEpisodeTitle = candidateEpisodeTitle.flatMap(nonEmptyValue) else {
            return nil
        }
        return MetadataTitleSimilarity.score(
            queryTitle: localEpisodeTitle,
            displayTitle: candidateEpisodeTitle,
            originalTitle: nil
        )
    }

    private static func nonEmptyValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
            return 0.9
        }
        if difference == 2 {
            return 0.6
        }
        return 0.2
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
    var seriesTitleScore: MetadataTitleScore?
    var episodeTitleScore: MetadataTitleScore?
    var finalScore: Double

    var inputs: [String: String] {
        var values = [
            "title_score": "\(titleScore.value)",
            "title_overlap_score": "\(titleScore.overlapScore)",
            "title_containment_score": "\(titleScore.containmentScore)",
            "title_prefix_score": "\(titleScore.prefixScore)",
            "title_fuzzy_score": "\(titleScore.fuzzyScore)",
            "title_score_strategy": titleScore.strategy,
            "year_match": "\(yearMatch)",
            "media_type_match": "\(mediaTypeMatches)",
            "episode_exists": "\(episodeExists)",
            "final_score": "\(finalScore)"
        ]
        if let seriesTitleScore {
            values["series_title_score"] = "\(seriesTitleScore.value)"
        }
        if let episodeTitleScore {
            values["episode_title_score"] = "\(episodeTitleScore.value)"
        }
        return values
    }

    static func zero(mediaTypeMatches: Bool) -> MetadataCandidateConfidence {
        MetadataCandidateConfidence(
            titleScore: .zero,
            yearMatch: 0.0,
            mediaTypeMatches: mediaTypeMatches,
            episodeExists: false,
            seriesTitleScore: nil,
            episodeTitleScore: nil,
            finalScore: 0.0
        )
    }
}

private struct MetadataTitleScore {
    var value: Double
    var overlapScore: Double
    var containmentScore: Double
    var prefixScore: Double
    var fuzzyScore: Double
    var strategy: String

    static let zero = MetadataTitleScore(
        value: 0.0,
        overlapScore: 0.0,
        containmentScore: 0.0,
        prefixScore: 0.0,
        fuzzyScore: 0.0,
        strategy: "none"
    )
}

private enum MetadataTitleSimilarity {
    private static let weakStopwords: Set<String> = [
        "the", "a", "an", "and", "of", "in", "on", "to", "is", "at", "for", "from"
    ]

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
        let prefixScore = orderedPrefixScore(leftTokenList, rightTokenList)
        let fuzzyScore = fuzzyTokenScore(leftTokenList, rightTokenList)

        if left == right {
            return MetadataTitleScore(
                value: 1.0,
                overlapScore: overlapScore,
                containmentScore: containmentScore,
                prefixScore: prefixScore,
                fuzzyScore: fuzzyScore,
                strategy: "exact"
            )
        }

        return bestScore(
            overlapScore: overlapScore,
            containmentScore: containmentScore,
            prefixScore: prefixScore,
            fuzzyScore: fuzzyScore
        )
    }

    private static func bestScore(
        overlapScore: Double,
        containmentScore: Double,
        prefixScore: Double,
        fuzzyScore: Double
    ) -> MetadataTitleScore {
        var best = (strategy: "overlap", value: overlapScore)
        if fuzzyScore > best.value {
            best = ("fuzzy", fuzzyScore)
        }
        if prefixScore > best.value {
            best = ("prefix", prefixScore)
        }
        if containmentScore > best.value {
            best = ("containment", containmentScore)
        }

        return MetadataTitleScore(
            value: best.value,
            overlapScore: overlapScore,
            containmentScore: containmentScore,
            prefixScore: prefixScore,
            fuzzyScore: fuzzyScore,
            strategy: best.value > 0.0 ? best.strategy : "none"
        )
    }

    private static func normalize(_ value: String) -> String {
        let separator = UnicodeScalar(32)!
        var normalized = String.UnicodeScalarView()

        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        for scalar in folded.lowercased().unicodeScalars {
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

    private static func orderedPrefixScore(_ lhs: [String], _ rhs: [String]) -> Double {
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

        guard shorter.count >= 2,
              longer.count > shorter.count,
              Array(longer.prefix(shorter.count)) == shorter else {
            return 0.0
        }

        let extraTokenCount = longer.count - shorter.count
        return max(0.0, 0.92 - 0.03 * Double(extraTokenCount))
    }

    private static func fuzzyTokenScore(_ lhs: [String], _ rhs: [String]) -> Double {
        var matchedRightIndices = Set<Int>()
        var matchCount = 0

        for leftToken in lhs {
            guard let matchIndex = rhs.indices.first(where: { index in
                !matchedRightIndices.contains(index)
                    && tokensMatchFuzzily(leftToken, rhs[index])
            }) else {
                continue
            }
            matchedRightIndices.insert(matchIndex)
            matchCount += 1
        }

        let denominator = max(lhs.count, rhs.count)
        guard denominator > 0 else {
            return 0.0
        }
        return Double(matchCount) / Double(denominator)
    }

    private static func tokensMatchFuzzily(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs {
            return true
        }
        guard lhs.count >= 4,
              rhs.count >= 4,
              lhs.first == rhs.first else {
            return false
        }
        let maxLength = max(lhs.count, rhs.count)
        guard maxLength > 0 else {
            return false
        }
        let distance = levenshteinDistance(lhs, rhs)
        let similarity = 1.0 - Double(distance) / Double(maxLength)
        return similarity >= 0.84
    }

    private static func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        guard !left.isEmpty else {
            return right.count
        }
        guard !right.isEmpty else {
            return left.count
        }

        var previous = Array(0...right.count)
        var current = Array(repeating: 0, count: right.count + 1)

        for leftIndex in 1...left.count {
            current[0] = leftIndex
            for rightIndex in 1...right.count {
                let substitutionCost = left[leftIndex - 1] == right[rightIndex - 1] ? 0 : 1
                current[rightIndex] = min(
                    previous[rightIndex] + 1,
                    current[rightIndex - 1] + 1,
                    previous[rightIndex - 1] + substitutionCost
                )
            }
            swap(&previous, &current)
        }

        return previous[right.count]
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
