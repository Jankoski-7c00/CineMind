import Domain
import Foundation
import Persistence
import Shared

public struct ScannedFile: Sendable, Equatable {
    public var relativePath: String
    public var absolutePath: String
    public var fileName: String
    public var fileExtension: String
    public var fileSizeBytes: Int64
    public var modifiedAt: Date?

    public init(
        relativePath: String,
        absolutePath: String,
        fileName: String,
        fileExtension: String,
        fileSizeBytes: Int64,
        modifiedAt: Date? = nil
    ) {
        self.relativePath = relativePath
        self.absolutePath = absolutePath
        self.fileName = fileName
        self.fileExtension = fileExtension.lowercased()
        self.fileSizeBytes = fileSizeBytes
        self.modifiedAt = modifiedAt
    }
}

public protocol ScannerFileSystem {
    func folderExists(at path: String) -> Bool
    func enumerateFiles(rootPath: String) throws -> [ScannedFile]
}

public struct LocalScannerFileSystem: ScannerFileSystem {
    public init() {}

    public func folderExists(at path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    public func enumerateFiles(rootPath: String) throws -> [ScannedFile] {
        let rootURL = URL(fileURLWithPath: rootPath).standardizedFileURL
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw ScannerError.folderUnavailable(rootPath)
        }

        let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        var files: [ScannedFile] = []

        do {
            for case let fileURL as URL in enumerator {
                let values = try fileURL.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .fileSizeKey,
                    .contentModificationDateKey
                ])
                guard values.isRegularFile == true else {
                    continue
                }

                let absolutePath = fileURL.standardizedFileURL.path
                guard absolutePath.hasPrefix(rootPrefix) else {
                    continue
                }

                let relativePath = String(absolutePath.dropFirst(rootPrefix.count))
                files.append(
                    ScannedFile(
                        relativePath: relativePath,
                        absolutePath: absolutePath,
                        fileName: fileURL.lastPathComponent,
                        fileExtension: fileURL.pathExtension,
                        fileSizeBytes: Int64(values.fileSize ?? 0),
                        modifiedAt: values.contentModificationDate
                    )
                )
            }
        } catch {
            throw ScannerError.enumerationFailed(rootPath)
        }

        if enumerationError != nil {
            throw ScannerError.enumerationFailed(rootPath)
        }

        return files
    }
}

public enum ScannerError: Error, Sendable, Equatable {
    case folderUnavailable(String)
    case enumerationFailed(String)
}

public struct ParsedMediaCandidate: Sendable, Equatable {
    public var mediaType: MediaType
    public var title: String
    public var normalizedTitle: String
    public var year: Int?
    public var episodeInfo: EpisodeInfo?
}

public enum FilenameParser {
    public static func parse(relativePath: String) -> ParsedMediaCandidate {
        let fileName = URL(fileURLWithPath: relativePath).deletingPathExtension().lastPathComponent

        if let episode = parseEpisode(fileName) {
            return episode
        }

        return parseMovie(fileName)
    }

    private static func parseEpisode(_ fileName: String) -> ParsedMediaCandidate? {
        let pattern = #"(?i)^(.*?)[\s._-]*S(\d{1,2})E(\d{1,2})(?:[\s._-]+(.+))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: fileName, range: NSRange(fileName.startIndex..., in: fileName)),
              let seriesRange = Range(match.range(at: 1), in: fileName),
              let seasonRange = Range(match.range(at: 2), in: fileName),
              let episodeRange = Range(match.range(at: 3), in: fileName),
              let seasonNumber = Int(fileName[seasonRange]),
              let episodeNumber = Int(fileName[episodeRange]) else {
            return nil
        }

        let seriesTitle = cleanTitle(String(fileName[seriesRange]))
        guard !seriesTitle.isEmpty, seasonNumber > 0, episodeNumber > 0 else {
            return nil
        }

        var episodeTitle: String?
        if match.range(at: 4).location != NSNotFound,
           let titleRange = Range(match.range(at: 4), in: fileName) {
            let cleaned = cleanTitle(String(fileName[titleRange]))
            episodeTitle = cleaned.isEmpty ? nil : cleaned
        }

        let info = EpisodeInfo(
            seriesTitle: seriesTitle,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            episodeTitle: episodeTitle
        )
        let displayTitle = episodeTitle ?? "\(seriesTitle) S\(padded(seasonNumber))E\(padded(episodeNumber))"
        let normalizedSeriesTitle = MediaTitleNormalizer.normalize(seriesTitle)

        return ParsedMediaCandidate(
            mediaType: .episode,
            title: displayTitle,
            normalizedTitle: normalizedSeriesTitle,
            year: nil,
            episodeInfo: info
        )
    }

    private static func parseMovie(_ fileName: String) -> ParsedMediaCandidate {
        let pattern = #"(?:[\s._\-\(\[])(19\d{2}|20\d{2})[\)\]]?\s*$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(fileName.startIndex..., in: fileName)
        var titleSource = fileName
        var year: Int?

        if let match = regex?.firstMatch(in: fileName, range: range),
           let matchRange = Range(match.range(at: 0), in: fileName),
           let yearRange = Range(match.range(at: 1), in: fileName),
           let parsedYear = Int(fileName[yearRange]) {
            titleSource = String(fileName[..<matchRange.lowerBound])
            year = parsedYear
        }

        let title = cleanTitle(titleSource).isEmpty ? cleanTitle(fileName) : cleanTitle(titleSource)
        return ParsedMediaCandidate(
            mediaType: .movie,
            title: title,
            normalizedTitle: MediaTitleNormalizer.normalize(title),
            year: year,
            episodeInfo: nil
        )
    }

    private static func cleanTitle(_ value: String) -> String {
        value
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "()[]")))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func padded(_ value: Int) -> String {
        String(format: "%02d", value)
    }
}

public struct ScanResult: Sendable, Equatable {
    public var scanRun: ScanRun
    public var counts: ScanCounts
    public var issues: [ScanIssue]
}

public struct ScanCounts: Sendable, Equatable {
    public var foldersScanned: Int
    public var filesDiscovered: Int
    public var mediaItemsCreated: Int
    public var mediaItemsUpdated: Int
    public var mediaFilesCreated: Int
    public var mediaFilesUpdated: Int
    public var filesMarkedUnavailable: Int
    public var issuesRecorded: Int

    public init(
        foldersScanned: Int = 0,
        filesDiscovered: Int = 0,
        mediaItemsCreated: Int = 0,
        mediaItemsUpdated: Int = 0,
        mediaFilesCreated: Int = 0,
        mediaFilesUpdated: Int = 0,
        filesMarkedUnavailable: Int = 0,
        issuesRecorded: Int = 0
    ) {
        self.foldersScanned = foldersScanned
        self.filesDiscovered = filesDiscovered
        self.mediaItemsCreated = mediaItemsCreated
        self.mediaItemsUpdated = mediaItemsUpdated
        self.mediaFilesCreated = mediaFilesCreated
        self.mediaFilesUpdated = mediaFilesUpdated
        self.filesMarkedUnavailable = filesMarkedUnavailable
        self.issuesRecorded = issuesRecorded
    }
}

public final class LibraryScanner {
    private let store: CineMindStore
    private let fileSystem: any ScannerFileSystem
    private let now: () -> Date
    private let supportedExtensions: Set<String>

    public init(
        store: CineMindStore,
        fileSystem: any ScannerFileSystem = LocalScannerFileSystem(),
        now: @escaping () -> Date = { Date() },
        supportedExtensions: Set<String> = ["mp4", "mkv", "mov", "avi", "m4v"]
    ) {
        self.store = store
        self.fileSystem = fileSystem
        self.now = now
        self.supportedExtensions = supportedExtensions
    }

    public func scanLibrary(libraryID: String) throws -> ScanResult {
        var scanRun = ScanRun(libraryID: libraryID, startedAt: now())
        try store.saveScanRun(scanRun)

        var totals = ScanCounters()

        do {
            let folders = try store.fetchLibraryFolders(libraryID: libraryID)

            for folder in folders {
                guard fileSystem.folderExists(at: folder.rootPath) else {
                    let timestamp = now()
                    let issue = ScanIssue(
                        scanRunID: scanRun.id,
                        libraryFolderID: folder.id,
                        pathHash: StablePathHash.hash(folder.rootPath),
                        issueType: .folderUnavailable,
                        message: "Library folder is unavailable",
                        createdAt: timestamp
                    )
                    try store.withTransaction {
                        try store.updateLibraryFolderAvailability(
                            id: folder.id,
                            isAvailable: false,
                            lastSeenAt: folder.lastSeenAt,
                            lastScanAt: timestamp,
                            updatedAt: timestamp
                        )
                        try store.saveScanIssue(issue)
                    }
                    totals.issuesRecorded += 1
                    continue
                }

                let files: [ScannedFile]
                do {
                    files = try fileSystem.enumerateFiles(rootPath: folder.rootPath)
                } catch let error as ScannerError {
                    let issue = ScanIssue(
                        scanRunID: scanRun.id,
                        libraryFolderID: folder.id,
                        pathHash: StablePathHash.hash(folder.rootPath),
                        issueType: scanIssueType(for: error),
                        message: scanIssueMessage(for: error),
                        createdAt: now()
                    )
                    try store.saveScanIssue(issue)
                    totals.issuesRecorded += 1
                    continue
                }

                let mediaFiles = files.filter { supportedExtensions.contains($0.fileExtension.lowercased()) }
                let counters = try store.withTransaction {
                    try process(folder: folder, files: mediaFiles, scanRunID: scanRun.id)
                }
                totals.merge(counters)
            }

            try finishScanRun(&scanRun, status: .completed, totals: totals)

            return ScanResult(
                scanRun: scanRun,
                counts: totals.scanCounts,
                issues: try store.fetchScanIssues(scanRunID: scanRun.id)
            )
        } catch {
            try? finishScanRun(&scanRun, status: .failed, totals: totals)
            throw error
        }
    }

    private func process(folder: LibraryFolder, files: [ScannedFile], scanRunID: String) throws -> ScanCounters {
        let timestamp = now()
        let existingFiles = try store.fetchMediaFiles(libraryFolderID: folder.id)
        var counters = ScanCounters(foldersScanned: 1, filesDiscovered: files.count)
        var seenRelativePaths = Set<String>()
        var newFiles: [MediaFile] = []

        for scannedFile in files {
            seenRelativePaths.insert(scannedFile.relativePath)
            let parsed = FilenameParser.parse(relativePath: scannedFile.relativePath)

            if var existing = try store.fetchMediaFile(
                libraryFolderID: folder.id,
                relativePath: scannedFile.relativePath
            ) {
                existing.absolutePathHash = StablePathHash.hash(scannedFile.absolutePath)
                existing.fileName = scannedFile.fileName
                existing.fileExtension = scannedFile.fileExtension
                existing.fileSizeBytes = scannedFile.fileSizeBytes
                existing.modifiedAt = scannedFile.modifiedAt
                existing.isAvailable = true
                existing.lastSeenAt = timestamp
                existing.updatedAt = timestamp
                try store.saveMediaFile(existing)
                counters.mediaFilesUpdated += 1
                continue
            }

            let mediaItemResolution = try findOrCreateMediaItem(parsed, timestamp: timestamp)
            let mediaFile = MediaFile(
                mediaItemID: mediaItemResolution.item.id,
                libraryFolderID: folder.id,
                relativePath: scannedFile.relativePath,
                absolutePathHash: StablePathHash.hash(scannedFile.absolutePath),
                fileName: scannedFile.fileName,
                fileExtension: scannedFile.fileExtension,
                fileSizeBytes: scannedFile.fileSizeBytes,
                modifiedAt: scannedFile.modifiedAt,
                isAvailable: true,
                lastSeenAt: timestamp,
                createdAt: timestamp,
                updatedAt: timestamp
            )
            try store.saveMediaFile(mediaFile)
            newFiles.append(mediaFile)
            counters.mediaFilesCreated += 1
            if mediaItemResolution.created {
                counters.mediaItemsCreated += 1
            }
        }

        let missingFiles = existingFiles.filter { $0.isAvailable && !seenRelativePaths.contains($0.relativePath) }
        for missingFile in missingFiles {
            try store.markMediaFileUnavailable(id: missingFile.id, updatedAt: timestamp)
            counters.filesMarkedUnavailable += 1
        }

        counters.issuesRecorded += try recordRenameCandidates(
            newFiles: newFiles,
            missingFiles: missingFiles,
            scanRunID: scanRunID,
            libraryFolderID: folder.id,
            timestamp: timestamp
        )

        try store.updateLibraryFolderAvailability(
            id: folder.id,
            isAvailable: true,
            lastSeenAt: timestamp,
            lastScanAt: timestamp,
            updatedAt: timestamp
        )

        return counters
    }

    private func findOrCreateMediaItem(_ parsed: ParsedMediaCandidate, timestamp: Date) throws -> MediaItemResolution {
        switch parsed.mediaType {
        case .movie:
            if let existing = try store.findMovieItem(normalizedTitle: parsed.normalizedTitle, year: parsed.year) {
                return MediaItemResolution(item: existing, created: false)
            }
        case .episode:
            if let episodeInfo = parsed.episodeInfo,
               let existing = try store.findEpisodeItem(
                   normalizedSeriesTitle: parsed.normalizedTitle,
                   seasonNumber: episodeInfo.seasonNumber,
                   episodeNumber: episodeInfo.episodeNumber
               ) {
                return MediaItemResolution(item: existing, created: false)
            }
        }

        let item = MediaItem(
            mediaType: parsed.mediaType,
            title: parsed.title,
            normalizedTitle: parsed.normalizedTitle,
            year: parsed.year,
            episodeInfo: parsed.episodeInfo,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        try store.saveMediaItem(item)
        return MediaItemResolution(item: item, created: true)
    }

    private func recordRenameCandidates(
        newFiles: [MediaFile],
        missingFiles: [MediaFile],
        scanRunID: String,
        libraryFolderID: String,
        timestamp: Date
    ) throws -> Int {
        var recorded = 0

        for newFile in newFiles {
            let candidates = missingFiles.filter {
                $0.mediaItemID == newFile.mediaItemID && $0.fileSizeBytes == newFile.fileSizeBytes
            }

            guard candidates.count == 1 else {
                continue
            }

            let oldFile = candidates[0]
            let issue = ScanIssue(
                scanRunID: scanRunID,
                libraryFolderID: libraryFolderID,
                pathHash: newFile.absolutePathHash,
                issueType: .renameCandidate,
                message: "Possible rename or move from \(oldFile.relativePath) to \(newFile.relativePath)",
                createdAt: timestamp
            )
            try store.saveScanIssue(issue)
            recorded += 1
        }

        return recorded
    }

    private func finishScanRun(
        _ scanRun: inout ScanRun,
        status: ScanRunStatus,
        totals: ScanCounters
    ) throws {
        scanRun.finishedAt = now()
        scanRun.status = status
        scanRun.filesSeen = totals.filesDiscovered
        scanRun.filesAdded = totals.mediaFilesCreated
        scanRun.filesUpdated = totals.mediaFilesUpdated
        scanRun.filesMissing = totals.filesMarkedUnavailable
        scanRun.issuesCount = totals.issuesRecorded
        try store.saveScanRun(scanRun)
    }

    private func scanIssueMessage(for error: ScannerError) -> String {
        switch error {
        case .folderUnavailable:
            "Library folder is unavailable"
        case .enumerationFailed:
            "Scan failed for library folder"
        }
    }

    private func scanIssueType(for error: ScannerError) -> ScanIssueType {
        switch error {
        case .folderUnavailable:
            .folderUnavailable
        case .enumerationFailed:
            .filesystemError
        }
    }
}

private struct MediaItemResolution {
    var item: MediaItem
    var created: Bool
}

private struct ScanCounters {
    var foldersScanned: Int = 0
    var filesDiscovered: Int = 0
    var mediaItemsCreated: Int = 0
    var mediaItemsUpdated: Int = 0
    var mediaFilesCreated: Int = 0
    var mediaFilesUpdated: Int = 0
    var filesMarkedUnavailable: Int = 0
    var issuesRecorded: Int = 0

    var scanCounts: ScanCounts {
        ScanCounts(
            foldersScanned: foldersScanned,
            filesDiscovered: filesDiscovered,
            mediaItemsCreated: mediaItemsCreated,
            mediaItemsUpdated: mediaItemsUpdated,
            mediaFilesCreated: mediaFilesCreated,
            mediaFilesUpdated: mediaFilesUpdated,
            filesMarkedUnavailable: filesMarkedUnavailable,
            issuesRecorded: issuesRecorded
        )
    }

    mutating func merge(_ other: ScanCounters) {
        foldersScanned += other.foldersScanned
        filesDiscovered += other.filesDiscovered
        mediaItemsCreated += other.mediaItemsCreated
        mediaItemsUpdated += other.mediaItemsUpdated
        mediaFilesCreated += other.mediaFilesCreated
        mediaFilesUpdated += other.mediaFilesUpdated
        filesMarkedUnavailable += other.filesMarkedUnavailable
        issuesRecorded += other.issuesRecorded
    }
}
