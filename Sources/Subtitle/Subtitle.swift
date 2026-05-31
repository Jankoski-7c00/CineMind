import Domain
import Foundation

public enum SubtitleModule {
    public static let name = "Subtitle"
}

public enum SubtitleError: Error, Sendable, Equatable {
    case unsupportedFormat(SubtitleFormat)
    case invalidCueTiming(String)
    case emptyCueText
    case noCuesFound
}

public struct SubtitleCue: Sendable, Equatable {
    public let startMS: Int
    public let endMS: Int
    public let text: String

    public init(startMS: Int, endMS: Int, text: String) throws {
        guard startMS >= 0, endMS > startMS else {
            throw SubtitleError.invalidCueTiming("\(startMS) --> \(endMS)")
        }
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            throw SubtitleError.emptyCueText
        }

        self.startMS = startMS
        self.endMS = endMS
        self.text = normalizedText
    }

    public func contains(positionMS: Int) -> Bool {
        positionMS >= startMS && positionMS < endMS
    }
}

public struct SubtitleCueTimeline: Sendable, Equatable {
    public let format: SubtitleFormat
    public let cues: [SubtitleCue]

    public init(format: SubtitleFormat, cues: [SubtitleCue]) throws {
        guard !cues.isEmpty else {
            throw SubtitleError.noCuesFound
        }
        self.format = format
        self.cues = cues.sorted { lhs, rhs in
            if lhs.startMS == rhs.startMS {
                return lhs.endMS < rhs.endMS
            }
            return lhs.startMS < rhs.startMS
        }
    }

    public func activeText(atMS positionMS: Int) -> String? {
        cues
            .filter { $0.contains(positionMS: positionMS) }
            .map(\.text)
            .joined(separator: "\n")
            .nilIfEmpty
    }
}

public enum SubtitleParser {
    public static func parse(_ content: String, format: SubtitleFormat) throws -> SubtitleCueTimeline {
        switch format {
        case .srt:
            return try SubtitleCueTimeline(format: format, cues: parseSRT(content))
        case .webVTT:
            return try SubtitleCueTimeline(format: format, cues: parseWebVTT(content))
        case .ass, .ssa:
            throw SubtitleError.unsupportedFormat(format)
        }
    }

    private static func parseSRT(_ content: String) throws -> [SubtitleCue] {
        let blocks = normalizedBlocks(content)
        let cues = try blocks.compactMap { block -> SubtitleCue? in
            var lines = block
            if lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).allSatisfy(\.isNumber) == true {
                lines.removeFirst()
            }
            return try parseCue(lines: lines, separator: ",")
        }
        guard !cues.isEmpty else {
            throw SubtitleError.noCuesFound
        }
        return cues
    }

    private static func parseWebVTT(_ content: String) throws -> [SubtitleCue] {
        let blocks = normalizedBlocks(content)
        let cues = try blocks.compactMap { block -> SubtitleCue? in
            var lines = block
            if lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("WEBVTT") == true {
                lines.removeFirst()
            }
            if lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("NOTE") == true {
                return nil
            }
            if lines.first?.contains("-->") == false {
                lines.removeFirst()
            }
            return try parseCue(lines: lines, separator: ".")
        }
        guard !cues.isEmpty else {
            throw SubtitleError.noCuesFound
        }
        return cues
    }

    private static func normalizedBlocks(_ content: String) -> [[String]] {
        content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n\n")
            .map { block in
                block
                    .components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
            .filter { !$0.isEmpty }
    }

    private static func parseCue(lines: [String], separator: String) throws -> SubtitleCue? {
        guard let timingLine = lines.first(where: { $0.contains("-->") }) else {
            return nil
        }

        let timingParts = timingLine
            .components(separatedBy: "-->")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard timingParts.count == 2,
              let startMS = parseTime(timingParts[0], preferredSeparator: separator),
              let endMS = parseTime(timingParts[1], preferredSeparator: separator) else {
            throw SubtitleError.invalidCueTiming(timingLine)
        }

        guard let timingIndex = lines.firstIndex(of: timingLine) else {
            return nil
        }
        let text = lines[(timingIndex + 1)...]
            .map(cleanCueText)
            .joined(separator: "\n")

        return try SubtitleCue(startMS: startMS, endMS: endMS, text: text)
    }

    private static func parseTime(_ rawValue: String, preferredSeparator: String) -> Int? {
        let value = rawValue
            .components(separatedBy: .whitespaces)
            .first?
            .replacingOccurrences(of: preferredSeparator == "," ? "." : ",", with: preferredSeparator)
        guard let value else {
            return nil
        }

        let mainParts = value.components(separatedBy: preferredSeparator)
        guard mainParts.count == 2 else {
            return nil
        }
        let millisecondText = String(mainParts[1].padding(toLength: 3, withPad: "0", startingAt: 0).prefix(3))
        guard
              let milliseconds = Int(millisecondText) else {
            return nil
        }

        let clockParts = mainParts[0].split(separator: ":").compactMap { Int(String($0)) }
        switch clockParts.count {
        case 2:
            let totalSeconds = (clockParts[0] * 60) + clockParts[1]
            return (totalSeconds * 1_000) + milliseconds
        case 3:
            let totalSeconds = (clockParts[0] * 3_600) + (clockParts[1] * 60) + clockParts[2]
            return (totalSeconds * 1_000) + milliseconds
        default:
            return nil
        }
    }

    private static func cleanCueText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct SubtitleSidecarMediaFile: Sendable, Equatable {
    public let mediaItemID: MediaItemID
    public let mediaFileID: MediaFileID
    public let libraryFolderID: LibraryFolderID
    public let relativePath: String

    public init(
        mediaItemID: MediaItemID,
        mediaFileID: MediaFileID,
        libraryFolderID: LibraryFolderID,
        relativePath: String
    ) {
        self.mediaItemID = mediaItemID
        self.mediaFileID = mediaFileID
        self.libraryFolderID = libraryFolderID
        self.relativePath = relativePath
    }
}

public struct SubtitleSidecarMatch: Sendable, Equatable {
    public let mediaFile: SubtitleSidecarMediaFile
    public let languageCode: String?

    public init(mediaFile: SubtitleSidecarMediaFile, languageCode: String?) {
        self.mediaFile = mediaFile
        self.languageCode = languageCode
    }
}

public enum SubtitleSidecarMatcher {
    public static let discoverableExtensions: Set<String> = ["srt", "vtt", "ass", "ssa"]

    public static func isDiscoverableSubtitleExtension(_ fileExtension: String) -> Bool {
        discoverableExtensions.contains(fileExtension.lowercased())
    }

    public static func match(
        subtitleRelativePath: String,
        mediaFiles: [SubtitleSidecarMediaFile]
    ) -> SubtitleSidecarMatch? {
        let subtitleDirectory = directory(subtitleRelativePath)
        let subtitleStem = stem(subtitleRelativePath)

        let candidates = mediaFiles
            .filter { directory($0.relativePath) == subtitleDirectory }
            .filter { mediaFile in
                let mediaStem = stem(mediaFile.relativePath)
                return subtitleStem == mediaStem || subtitleStem.hasPrefix(mediaStem + ".")
            }
            .sorted { lhs, rhs in
                stem(lhs.relativePath).count > stem(rhs.relativePath).count
            }

        guard let mediaFile = candidates.first else {
            return nil
        }

        return SubtitleSidecarMatch(
            mediaFile: mediaFile,
            languageCode: inferLanguageCode(
                subtitleStem: subtitleStem,
                mediaStem: stem(mediaFile.relativePath)
            )
        )
    }

    public static func inferLanguageCode(subtitleRelativePath: String, mediaRelativePath: String) -> String? {
        inferLanguageCode(subtitleStem: stem(subtitleRelativePath), mediaStem: stem(mediaRelativePath))
    }

    private static func inferLanguageCode(subtitleStem: String, mediaStem: String) -> String? {
        guard subtitleStem.hasPrefix(mediaStem + ".") else {
            return nil
        }
        let suffix = String(subtitleStem.dropFirst(mediaStem.count + 1))
        guard let candidate = suffix.split(separator: ".").first else {
            return nil
        }
        let normalized = String(candidate).trimmingCharacters(in: .whitespacesAndNewlines)
        guard isPlausibleLanguageCode(normalized) else {
            return nil
        }
        return normalized
    }

    private static func isPlausibleLanguageCode(_ value: String) -> Bool {
        guard (2...12).contains(value.count) else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).contains(scalar)
        }
    }

    private static func directory(_ relativePath: String) -> String {
        let path = (relativePath as NSString).deletingLastPathComponent
        return path == "." ? "" : path
    }

    private static func stem(_ relativePath: String) -> String {
        ((relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
    }
}

public struct SubtitleSearchQuery: Sendable, Equatable {
    public let mediaItemID: MediaItemID
    public let mediaFileID: MediaFileID?
    public let title: String
    public let languageCode: String?

    public init(
        mediaItemID: MediaItemID,
        mediaFileID: MediaFileID? = nil,
        title: String,
        languageCode: String? = nil
    ) {
        self.mediaItemID = mediaItemID
        self.mediaFileID = mediaFileID
        self.title = title
        self.languageCode = languageCode
    }
}

public struct SubtitleSearchResult: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let languageCode: String?
    public let format: SubtitleFormat

    public init(id: String, title: String, languageCode: String?, format: SubtitleFormat) {
        self.id = id
        self.title = title
        self.languageCode = languageCode
        self.format = format
    }
}

public struct SubtitleDownloadResult: Sendable, Equatable {
    public let resultID: String
    public let suggestedFileName: String?
    public let languageCode: String?
    public let format: SubtitleFormat
    public let content: String

    public init(
        resultID: String,
        suggestedFileName: String? = nil,
        languageCode: String? = nil,
        format: SubtitleFormat,
        content: String
    ) {
        self.resultID = resultID
        self.suggestedFileName = suggestedFileName
        self.languageCode = languageCode
        self.format = format
        self.content = content
    }
}

public protocol SubtitleSearchProviding: Sendable {
    func searchSubtitles(query: SubtitleSearchQuery) async throws -> [SubtitleSearchResult]
    func downloadSubtitle(resultID: String, for query: SubtitleSearchQuery) async throws -> SubtitleDownloadResult
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
