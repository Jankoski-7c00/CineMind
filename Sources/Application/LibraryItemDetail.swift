import Domain
import Foundation
import Persistence

public struct LibraryFileSummary: Sendable, Equatable {
    public let fileName: String
    public let fileExtension: String
    public let fileSizeLabel: String
    public let availabilityLabel: String
}

public struct LibraryItemDetailShell: Identifiable, Sendable, Equatable {
    public let id: MediaItemID
    public let displayTitle: String
    public let mediaTypeLabel: String
    public let yearOrEpisodeLabel: String?
    public let summary: String?
    public let availabilityLabel: String
    public let metadataLabel: String
    public let lastPlayedLabel: String?
    public let files: [LibraryFileSummary]
}

public protocol LibraryItemDetailBrowsing: Sendable {
    func fetchDetail(id: MediaItemID) async throws -> LibraryItemDetailShell?
}

public protocol ApplicationLibraryItemDetailStore: Sendable {
    func fetchMediaItemDetail(id: MediaItemID) throws -> PersistedMediaItemDetail?
}

extension CineMindStore: ApplicationLibraryItemDetailStore {}

public struct LibraryItemDetailUseCase: LibraryItemDetailBrowsing, Sendable {
    private let store: any ApplicationLibraryItemDetailStore
    private let queue: DispatchQueue
    private let lastPlayedLabel: @Sendable (Date) -> String
    private let fileSizeLabel: @Sendable (Int64) -> String

    public init(
        store: any ApplicationLibraryItemDetailStore,
        queueLabel: String = "CineMind.LibraryItemDetailUseCase"
    ) {
        self.init(
            store: store,
            queueLabel: queueLabel,
            lastPlayedLabel: Self.defaultLastPlayedLabel,
            fileSizeLabel: Self.defaultFileSizeLabel
        )
    }

    public init(
        store: any ApplicationLibraryItemDetailStore,
        queueLabel: String = "CineMind.LibraryItemDetailUseCase",
        lastPlayedLabel: @escaping @Sendable (Date) -> String,
        fileSizeLabel: @escaping @Sendable (Int64) -> String
    ) {
        self.store = store
        self.queue = DispatchQueue(label: queueLabel)
        self.lastPlayedLabel = lastPlayedLabel
        self.fileSizeLabel = fileSizeLabel
    }

    public func fetchDetail(id: MediaItemID) async throws -> LibraryItemDetailShell? {
        let persisted = try await fetchPersistedDetail(id: id)
        return persisted.map(map)
    }

    private func fetchPersistedDetail(
        id: MediaItemID
    ) async throws -> PersistedMediaItemDetail? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let detail = try store.fetchMediaItemDetail(id: id)
                    continuation.resume(returning: detail)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func map(_ detail: PersistedMediaItemDetail) -> LibraryItemDetailShell {
        LibraryItemDetailShell(
            id: detail.id,
            displayTitle: displayTitle(for: detail),
            mediaTypeLabel: mediaTypeLabel(for: detail.mediaType),
            yearOrEpisodeLabel: yearOrEpisodeLabel(for: detail),
            summary: detail.summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            availabilityLabel: availabilityLabel(for: detail.files),
            metadataLabel: metadataLabel(for: detail),
            lastPlayedLabel: detail.latestPlayedAt.map(lastPlayedLabel),
            files: detail.files.map(mapFile)
        )
    }

    private func mapFile(_ file: PersistedMediaFileSummary) -> LibraryFileSummary {
        LibraryFileSummary(
            fileName: file.fileName,
            fileExtension: file.fileExtension,
            fileSizeLabel: fileSizeLabel(file.fileSizeBytes),
            availabilityLabel: fileAvailabilityLabel(for: file)
        )
    }

    private func displayTitle(for detail: PersistedMediaItemDetail) -> String {
        let persistedTitle = detail.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !persistedTitle.isEmpty {
            return persistedTitle
        }

        let episodeTitle = detail.episodeTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let episodeTitle, !episodeTitle.isEmpty {
            return episodeTitle
        }

        return "Untitled"
    }

    private func mediaTypeLabel(for mediaType: MediaType) -> String {
        switch mediaType {
        case .movie:
            "Movie"
        case .episode:
            "TV Episode"
        }
    }

    private func yearOrEpisodeLabel(for detail: PersistedMediaItemDetail) -> String? {
        switch detail.mediaType {
        case .movie:
            return detail.year.map(String.init)
        case .episode:
            guard let seasonNumber = detail.seasonNumber,
                  let episodeNumber = detail.episodeNumber else {
                return nil
            }

            let episodeCode = String(format: "S%02dE%02d", seasonNumber, episodeNumber)
            let episodeTitle = detail.episodeTitle?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let episodeTitle, !episodeTitle.isEmpty else {
                return episodeCode
            }
            return "\(episodeCode) - \(episodeTitle)"
        }
    }

    private func availabilityLabel(for files: [PersistedMediaFileSummary]) -> String {
        if files.isEmpty {
            return "no files"
        }
        let availableCount = files.filter(\.isAvailable).count
        if availableCount == files.count {
            return "available"
        }
        if availableCount <= 0 {
            return "unavailable"
        }
        return "partially available"
    }

    private func metadataLabel(for detail: PersistedMediaItemDetail) -> String {
        switch (detail.hasMetadataItem, detail.hasMetadataSourceRecord) {
        case (true, true):
            "complete"
        case (true, false), (false, true):
            "partial"
        case (false, false):
            "missing"
        }
    }

    private func fileAvailabilityLabel(for file: PersistedMediaFileSummary) -> String {
        if file.folderIsAvailable == false {
            return "folder unavailable"
        }
        if file.isAvailable {
            return "available"
        }
        return "unavailable"
    }

    public static func defaultLastPlayedLabel(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withFullDate,
            .withTime,
            .withTimeZone,
            .withColonSeparatorInTime
        ]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    public static func defaultFileSizeLabel(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes) bytes"
        }
        let kb = Double(bytes) / 1024.0
        if kb < 1024.0 {
            return String(format: "%.1f KB", kb)
        }
        let mb = kb / 1024.0
        if mb < 1024.0 {
            return String(format: "%.1f MB", mb)
        }
        let gb = mb / 1024.0
        return String(format: "%.1f GB", gb)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
