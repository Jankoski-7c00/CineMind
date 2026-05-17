import Application
import Domain
import Foundation
import Scanner

struct ScannerLibraryScanRunner: LibraryScanRunning, @unchecked Sendable {
    private let scanner: LibraryScanner

    init(scanner: LibraryScanner) {
        self.scanner = scanner
    }

    func runScan(libraryID: LibraryID) throws -> LibraryScanResultSummary {
        let result = try scanner.scanLibrary(libraryID: libraryID)
        return LibraryScanResultSummary(
            scanRunID: result.scanRun.id,
            statusLabel: result.scanRun.status.rawValue,
            counts: LibraryScanCountSummary(
                foldersScanned: result.counts.foldersScanned,
                filesDiscovered: result.counts.filesDiscovered,
                mediaItemsCreated: result.counts.mediaItemsCreated,
                mediaItemsUpdated: result.counts.mediaItemsUpdated,
                mediaFilesCreated: result.counts.mediaFilesCreated,
                mediaFilesUpdated: result.counts.mediaFilesUpdated,
                filesMarkedUnavailable: result.counts.filesMarkedUnavailable,
                issuesRecorded: result.counts.issuesRecorded
            ),
            issues: result.issues.map { issue in
                LibraryScanIssueSummary(
                    typeLabel: issue.issueType.rawValue,
                    message: issue.message
                )
            }
        )
    }
}
