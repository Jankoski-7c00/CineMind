import Domain
import Foundation
import Persistence
import Subtitle

public struct LibrarySubtitleCandidate: Identifiable, Sendable, Equatable {
    public let id: String
    public let resultID: String
    public let title: String
    public let languageLabel: String
    public let formatLabel: String
    public let isDownloadable: Bool
    public let unavailableReason: String?

    public init(
        resultID: String,
        title: String,
        languageLabel: String,
        formatLabel: String,
        isDownloadable: Bool,
        unavailableReason: String? = nil
    ) {
        self.id = resultID
        self.resultID = resultID
        self.title = title
        self.languageLabel = languageLabel
        self.formatLabel = formatLabel
        self.isDownloadable = isDownloadable
        self.unavailableReason = unavailableReason
    }
}

public struct LibrarySubtitleActionResult: Sendable, Equatable {
    public let message: String
    public let resultID: String
    public let subtitleAssetID: SubtitleAssetID

    public init(message: String, resultID: String, subtitleAssetID: SubtitleAssetID) {
        self.message = message
        self.resultID = resultID
        self.subtitleAssetID = subtitleAssetID
    }
}

public struct LibrarySubtitleActionError: Error, LocalizedError, Sendable, Equatable {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}

public protocol LibrarySubtitleActionHandling: Sendable {
    func searchSubtitles(
        mediaItemID: MediaItemID,
        mediaFileID: MediaFileID,
        languageCode: String?
    ) async throws -> [LibrarySubtitleCandidate]

    func downloadSubtitle(
        mediaItemID: MediaItemID,
        mediaFileID: MediaFileID,
        resultID: String
    ) async throws -> LibrarySubtitleActionResult
}

public protocol ApplicationSubtitleStore {
    func fetchMediaItem(id: MediaItemID) throws -> MediaItem?
    func fetchMediaFile(id: MediaFileID) throws -> PersistedMediaFile?
    func fetchSubtitleAsset(
        libraryFolderID: LibraryFolderID,
        relativePath: String,
        source: SubtitleAssetSource
    ) throws -> SubtitleAsset?
    func saveSubtitleAsset(_ asset: SubtitleAsset) throws
}

extension CineMindStore: ApplicationSubtitleStore {}

public protocol SubtitleDownloadFileWriting: Sendable {
    func writeSubtitle(_ content: String, to url: URL) throws
}

public struct FileSystemSubtitleDownloadFileWriter: SubtitleDownloadFileWriting {
    public init() {}

    public func writeSubtitle(_ content: String, to url: URL) throws {
        let directoryURL = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}

public protocol PlaybackExternalSubtitleRefreshing: Sendable {
    func reloadExternalSubtitleOptions(mediaFileID: MediaFileID) async
}

public final class LibrarySubtitleActionService: LibrarySubtitleActionHandling, @unchecked Sendable {
    private let store: any ApplicationSubtitleStore
    private let provider: (any SubtitleSearchProviding)?
    private let fileWriter: any SubtitleDownloadFileWriting
    private let playbackSubtitleRefresher: (any PlaybackExternalSubtitleRefreshing)?
    private let now: () -> Date

    public init(
        store: any ApplicationSubtitleStore,
        provider: (any SubtitleSearchProviding)?,
        fileWriter: any SubtitleDownloadFileWriting = FileSystemSubtitleDownloadFileWriter(),
        playbackSubtitleRefresher: (any PlaybackExternalSubtitleRefreshing)? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.provider = provider
        self.fileWriter = fileWriter
        self.playbackSubtitleRefresher = playbackSubtitleRefresher
        self.now = now
    }

    public func searchSubtitles(
        mediaItemID: MediaItemID,
        mediaFileID: MediaFileID,
        languageCode: String?
    ) async throws -> [LibrarySubtitleCandidate] {
        do {
            let provider = try configuredProvider()
            let query = try subtitleSearchQuery(
                mediaItemID: mediaItemID,
                mediaFileID: mediaFileID,
                languageCode: languageCode
            )
            let results = try await provider.searchSubtitles(query: query)
            return results.map(mapCandidate)
        } catch {
            throw mapActionError(error, fallback: "Subtitle search failed.")
        }
    }

    public func downloadSubtitle(
        mediaItemID: MediaItemID,
        mediaFileID: MediaFileID,
        resultID: String
    ) async throws -> LibrarySubtitleActionResult {
        do {
            let provider = try configuredProvider()
            let query = try subtitleSearchQuery(
                mediaItemID: mediaItemID,
                mediaFileID: mediaFileID,
                languageCode: nil
            )
            let target = try subtitleDownloadTarget(
                mediaItemID: mediaItemID,
                mediaFileID: mediaFileID
            )
            let download = try await provider.downloadSubtitle(resultID: resultID, for: query)
            let asset = try writeAndPersist(download, target: target)
            await playbackSubtitleRefresher?.reloadExternalSubtitleOptions(mediaFileID: mediaFileID)

            return LibrarySubtitleActionResult(
                message: "Subtitle downloaded.",
                resultID: download.resultID,
                subtitleAssetID: asset.id
            )
        } catch {
            throw mapActionError(error, fallback: "Subtitle download failed.")
        }
    }

    private func configuredProvider() throws -> any SubtitleSearchProviding {
        guard let provider else {
            throw LibrarySubtitleActionError(
                message: "Subtitle search is not configured. Local and embedded subtitles are still available."
            )
        }
        return provider
    }

    private func subtitleSearchQuery(
        mediaItemID: MediaItemID,
        mediaFileID: MediaFileID,
        languageCode: String?
    ) throws -> SubtitleSearchQuery {
        let target = try subtitleDownloadTarget(mediaItemID: mediaItemID, mediaFileID: mediaFileID)
        return SubtitleSearchQuery(
            mediaItemID: mediaItemID,
            mediaFileID: target.file.id,
            title: target.item.title,
            languageCode: languageCode?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }

    private func subtitleDownloadTarget(
        mediaItemID: MediaItemID,
        mediaFileID: MediaFileID
    ) throws -> SubtitleDownloadTarget {
        guard let item = try store.fetchMediaItem(id: mediaItemID) else {
            throw LibrarySubtitleActionError(message: "Media item was not found.")
        }

        guard let file = try store.fetchMediaFile(id: mediaFileID) else {
            throw LibrarySubtitleActionError(message: "Media file was not found.")
        }

        guard file.mediaItemID == item.id else {
            throw LibrarySubtitleActionError(message: "That file is not available for this item.")
        }

        guard !file.folderRootPath.isEmpty,
              file.folderIsAvailable,
              file.isAvailable else {
            throw LibrarySubtitleActionError(
                message: "A playable local file is required before subtitles can be downloaded."
            )
        }

        return SubtitleDownloadTarget(item: item, file: file)
    }

    private func mapCandidate(_ result: SubtitleSearchResult) -> LibrarySubtitleCandidate {
        let downloadable = result.format.supportsExternalCueParsing
        return LibrarySubtitleCandidate(
            resultID: result.id,
            title: result.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "Untitled subtitle",
            languageLabel: languageLabel(result.languageCode),
            formatLabel: formatLabel(result.format),
            isDownloadable: downloadable,
            unavailableReason: downloadable
                ? nil
                : "Only SRT and WebVTT subtitles can be downloaded for playback."
        )
    }

    private func writeAndPersist(
        _ download: SubtitleDownloadResult,
        target: SubtitleDownloadTarget
    ) throws -> SubtitleAsset {
        guard download.format.supportsExternalCueParsing else {
            throw LibrarySubtitleActionError(
                message: "Only SRT and WebVTT subtitles can be downloaded for playback."
            )
        }

        let content = download.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw LibrarySubtitleActionError(message: "Subtitle provider returned an invalid download.")
        }

        let relativePath = downloadedSubtitleRelativePath(
            mediaFileID: target.file.id,
            resultID: download.resultID,
            format: download.format
        )
        let resolvedURL = try resolveDownloadedSubtitleURL(
            rootPath: target.file.folderRootPath,
            relativePath: relativePath
        )

        do {
            try fileWriter.writeSubtitle(download.content, to: resolvedURL)
        } catch {
            throw LibrarySubtitleActionError(message: "Could not save the downloaded subtitle file.")
        }

        let existing = try store.fetchSubtitleAsset(
            libraryFolderID: target.file.libraryFolderID,
            relativePath: relativePath,
            source: .downloaded
        )
        let timestamp = now()
        let fileName = (relativePath as NSString).lastPathComponent
        let asset = SubtitleAsset(
            id: existing?.id ?? downloadedSubtitleAssetID(
                mediaFileID: target.file.id,
                resultID: download.resultID,
                format: download.format
            ),
            mediaItemID: target.item.id,
            mediaFileID: target.file.id,
            libraryFolderID: target.file.libraryFolderID,
            relativePath: relativePath,
            fileName: fileName,
            fileExtension: fileExtension(download.format),
            format: download.format,
            languageCode: download.languageCode?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            displayName: displayName(for: download),
            source: .downloaded,
            isAvailable: true,
            lastSeenAt: timestamp,
            createdAt: existing?.createdAt ?? timestamp,
            updatedAt: timestamp
        )

        do {
            try store.saveSubtitleAsset(asset)
        } catch {
            throw LibrarySubtitleActionError(message: "Could not save the downloaded subtitle.")
        }

        return asset
    }

    private func downloadedSubtitleRelativePath(
        mediaFileID: MediaFileID,
        resultID: String,
        format: SubtitleFormat
    ) -> String {
        [
            ".cinemind",
            "subtitles",
            sanitizedPathComponent(mediaFileID, fallback: "media-file"),
            sanitizedPathComponent(resultID, fallback: "subtitle") + "." + fileExtension(format)
        ].joined(separator: "/")
    }

    private func downloadedSubtitleAssetID(
        mediaFileID: MediaFileID,
        resultID: String,
        format: SubtitleFormat
    ) -> SubtitleAssetID {
        [
            "downloaded",
            sanitizedPathComponent(mediaFileID, fallback: "media-file"),
            sanitizedPathComponent(resultID, fallback: "subtitle"),
            fileExtension(format)
        ].joined(separator: ":")
    }

    private func resolveDownloadedSubtitleURL(rootPath: String, relativePath: String) throws -> URL {
        guard (rootPath as NSString).isAbsolutePath,
              !(relativePath as NSString).isAbsolutePath else {
            throw LibrarySubtitleActionError(message: "Subtitle provider returned an invalid download.")
        }

        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
        let resolvedURL = rootURL
            .appendingPathComponent(relativePath, isDirectory: false)
            .standardizedFileURL

        let rootPath = rootURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        let resolvedPath = resolvedURL.path
        guard resolvedPath == rootPath || resolvedPath.hasPrefix(rootPrefix) else {
            throw LibrarySubtitleActionError(message: "Subtitle provider returned an invalid download.")
        }

        return resolvedURL
    }

    private func sanitizedPathComponent(_ value: String, fallback: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitizedScalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let sanitized = String(sanitizedScalars)
            .split(separator: "-")
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return sanitized.nilIfEmpty ?? fallback
    }

    private func displayName(for download: SubtitleDownloadResult) -> String {
        if let suggestedFileName = download.suggestedFileName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty {
            return (suggestedFileName as NSString).lastPathComponent
        }

        if let languageCode = download.languageCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty {
            return "\(languageCode.uppercased()) downloaded subtitle"
        }

        return "Downloaded subtitle"
    }

    private func languageLabel(_ languageCode: String?) -> String {
        if let languageCode = languageCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty {
            return languageCode.uppercased()
        }
        return "Unknown language"
    }

    private func formatLabel(_ format: SubtitleFormat) -> String {
        switch format {
        case .srt:
            "SRT"
        case .webVTT:
            "WebVTT"
        case .ass:
            "ASS"
        case .ssa:
            "SSA"
        }
    }

    private func fileExtension(_ format: SubtitleFormat) -> String {
        switch format {
        case .srt:
            "srt"
        case .webVTT:
            "vtt"
        case .ass:
            "ass"
        case .ssa:
            "ssa"
        }
    }

    private func mapActionError(_ error: Error, fallback: String) -> LibrarySubtitleActionError {
        if let actionError = error as? LibrarySubtitleActionError {
            return actionError
        }
        return LibrarySubtitleActionError(message: fallback)
    }
}

private struct SubtitleDownloadTarget {
    let item: MediaItem
    let file: PersistedMediaFile
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
