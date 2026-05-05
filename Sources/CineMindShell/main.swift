import Domain
import Foundation
import Persistence

private func printUsage() {
    print("Usage: CineMindShell <sqlite-database-path>")
}

private func writeError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

private func displayTitle(for item: MediaItem) -> String {
    var parts = [item.title]
    if let year = item.year {
        parts.append("(\(year))")
    }
    if let episodeInfo = item.episodeInfo {
        parts.append("S\(String(format: "%02d", episodeInfo.seasonNumber))E\(String(format: "%02d", episodeInfo.episodeNumber))")
    }
    return parts.joined(separator: " ")
}

private func availabilityLabel(for file: MediaFile) -> String {
    file.isAvailable ? "available" : "unavailable"
}

private func listLibrary(at databasePath: String) throws {
    guard FileManager.default.fileExists(atPath: databasePath) else {
        throw ShellError.databaseNotFound(databasePath)
    }

    let store = try CineMindStore(readOnlyPath: databasePath)
    guard let library = try store.fetchLibrary() else {
        print("No library found.")
        return
    }

    print("Library: \(library.name)")

    let items = try store.fetchMediaItems()
    guard !items.isEmpty else {
        print("No media items found.")
        return
    }

    for item in items {
        print("- \(displayTitle(for: item)) [\(item.mediaType.rawValue)]")
        let files = try store.fetchMediaFiles(mediaItemID: item.id)
        if files.isEmpty {
            print("  Files: none")
            continue
        }

        for file in files {
            print("  - \(file.relativePath) [\(availabilityLabel(for: file))]")
        }
    }
}

private enum ShellError: Error, CustomStringConvertible {
    case databaseNotFound(String)
    case invalidArguments

    var description: String {
        switch self {
        case .databaseNotFound(let path):
            "SQLite database not found: \(path)"
        case .invalidArguments:
            "Expected exactly one SQLite database path argument."
        }
    }
}

do {
    guard CommandLine.arguments.count == 2 else {
        throw ShellError.invalidArguments
    }

    try listLibrary(at: CommandLine.arguments[1])
} catch let error as ShellError {
    writeError(error.description)
    printUsage()
    exit(2)
} catch {
    writeError("Failed to list library: \(error)")
    exit(1)
}
