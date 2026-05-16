import AppUI
import Application
import Foundation
import Persistence

enum CineMindAppEnvironmentFactory {
    static func start() throws -> AppShellEnvironment {
        let databaseURL = try databaseURL()
        let store = try CineMindStore(path: databaseURL.path)
        _ = try store.ensureLibrary(name: "CineMind Library")
        let mediaSummaryBrowser = LibraryMediaSummaryUseCase(store: store)
        let itemDetailBrowser = LibraryItemDetailUseCase(store: store)
        return AppShellEnvironment(
            mediaSummaryBrowser: mediaSummaryBrowser,
            itemDetailBrowser: itemDetailBrowser
        )
    }

    private static func databaseURL() throws -> URL {
        let fileManager = FileManager.default
        guard let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw StartupError.applicationSupportDirectoryUnavailable
        }

        let appDirectoryURL = applicationSupportURL.appendingPathComponent(
            "CineMind",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: appDirectoryURL,
            withIntermediateDirectories: true
        )

        return appDirectoryURL.appendingPathComponent(
            "CineMind.sqlite",
            isDirectory: false
        )
    }

    static func startupFailureMessage(for error: Error) -> String {
        switch error {
        case StartupError.applicationSupportDirectoryUnavailable:
            return "CineMind could not locate your Application Support folder."
        case is CocoaError:
            return "CineMind could not create its Application Support folder. Check that your Library folder is writable."
        case let persistenceError as PersistenceError:
            return persistenceFailureMessage(for: persistenceError)
        default:
            return "CineMind could not start its local library."
        }
    }

    private static func persistenceFailureMessage(for error: PersistenceError) -> String {
        switch error {
        case .openFailed:
            return "CineMind could not open its local library database."
        case .migrationFailed:
            return "CineMind could not prepare its local library database."
        case .prepareFailed, .bindFailed, .stepFailed, .transactionFailed:
            return "CineMind could not initialize its local library database."
        case .mediaFileMediaItemMismatch,
             .duplicatePlaybackHistoryPair,
             .posterAssetNotFound:
            return "CineMind could not initialize its local library data."
        }
    }

    private enum StartupError: Error {
        case applicationSupportDirectoryUnavailable
    }
}
