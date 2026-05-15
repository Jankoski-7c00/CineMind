import Application
import Domain
import Foundation
import Metadata
import Persistence
import Shared

private enum CineMindMetadataShell {
    static func main() async {
        do {
            switch try ShellArguments.parse(CommandLine.arguments) {
            case .help:
                printUsage()
            case .command(let command):
                try await run(command)
            }
        } catch let error as ShellError {
            writeError(error.description)
            if error.shouldPrintUsage {
                printUsage()
            }
            exit(error.exitCode)
        } catch let error as ApplicationMetadataError {
            writeError(applicationMetadataErrorDescription(error))
            exit(1)
        } catch let error as MetadataError {
            writeError("Metadata provider error: \(error.description)")
            exit(1)
        } catch {
            writeError("Metadata shell failed: \(error)")
            exit(1)
        }
    }

    private static func run(_ command: ShellCommand) async throws {
        let store = try openStore(path: command.databasePath)

        switch command {
        case .list:
            try list(store: store)
        case .search(_, let mediaItemID):
            let item = try fetchMediaItem(mediaItemID, store: store)
            printMediaItem(item)

            let context = try await makeLiveContext(commandName: command.name, cacheRoot: nil)
            let candidates = try await SearchMetadataCandidatesUseCase(
                store: store,
                provider: context.provider
            ).search(mediaItemID: mediaItemID, language: context.language)
            printCandidates(candidates)
        case .autoMatch(_, let mediaItemID, let cacheRoot):
            let item = try fetchMediaItem(mediaItemID, store: store)
            printMediaItem(item)

            let context = try await makeLiveContext(commandName: command.name, cacheRoot: cacheRoot)
            printPosterCacheState(context.cacheRoot)
            let result = try await AutoMatchMetadataUseCase(
                store: store,
                provider: context.provider,
                posterCache: context.posterCache
            ).match(mediaItemID: mediaItemID, language: context.language)

            printAutoMatchResult(result)
            try printMetadataState(mediaItemID: mediaItemID, store: store)
        case .manualMatch(_, let mediaItemID, let providerID, let cacheRoot):
            let item = try fetchMediaItem(mediaItemID, store: store)
            printMediaItem(item)

            let context = try await makeLiveContext(commandName: command.name, cacheRoot: cacheRoot)
            printPosterCacheState(context.cacheRoot)
            let source = try await ManualMatchMetadataUseCase(
                store: store,
                provider: context.provider,
                posterCache: context.posterCache
            ).match(mediaItemID: mediaItemID, providerID: providerID, language: context.language)

            print("Match result: manual")
            printSourceRecord(source)
            try printMetadataState(mediaItemID: mediaItemID, store: store)
        case .refresh(_, let mediaItemID, let cacheRoot):
            let item = try fetchMediaItem(mediaItemID, store: store)
            printMediaItem(item)

            let context = try await makeLiveContext(commandName: command.name, cacheRoot: cacheRoot)
            printPosterCacheState(context.cacheRoot)
            let result = try await RefreshMetadataUseCase(
                store: store,
                provider: context.provider,
                posterCache: context.posterCache
            ).refresh(mediaItemID: mediaItemID, language: context.language)

            printRefreshResult(result)
            try printMetadataState(mediaItemID: mediaItemID, store: store)
        case .refreshAll(_, let limit, let usedDefaultLimit, let force, let cacheRoot):
            if usedDefaultLimit {
                print("Using default limit: 20")
            }

            let context = try await makeLiveContext(commandName: command.name, cacheRoot: cacheRoot)
            printPosterCacheState(context.cacheRoot)
            print("Refresh all: limit=\(limit) force=\(force)")

            let result = try await RefreshLibraryMetadataUseCase(
                store: store,
                provider: context.provider,
                posterCache: context.posterCache
            ).refresh(limit: limit, force: force, language: context.language)

            print(
                "Refresh counts: refreshed=\(result.refreshed) skipped=\(result.skipped) " +
                    "unmatched=\(result.unmatched) failed=\(result.failed)"
            )
        case .override(_, let mediaItemID, let field, let value):
            let item = try fetchMediaItem(mediaItemID, store: store)
            printMediaItem(item)

            let metadata = try SetMetadataOverrideUseCase(store: store).set(
                mediaItemID: mediaItemID,
                field: field,
                value: value
            )
            print("Override set: \(field.rawShellValue)")
            printMetadataItem(metadata)
        case .clearOverride(_, let mediaItemID, let field):
            let item = try fetchMediaItem(mediaItemID, store: store)
            printMediaItem(item)

            let metadata = try ClearMetadataOverrideUseCase(store: store).clear(
                mediaItemID: mediaItemID,
                field: field
            )
            print("Override cleared: \(field.rawShellValue)")
            printMetadataItem(metadata)
        case .selectPoster(_, let mediaItemID, let posterAssetID):
            let item = try fetchMediaItem(mediaItemID, store: store)
            printMediaItem(item)

            try SelectPosterAssetUseCase(store: store).select(
                mediaItemID: mediaItemID,
                posterAssetID: posterAssetID
            )
            print("Poster selected: \(posterAssetID)")
            printPosterAssets(try store.fetchPosterAssets(mediaItemID: mediaItemID))
        }
    }

    private static func openStore(path: String) throws -> CineMindStore {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ShellError.databaseNotFound(path)
        }
        guard !isDirectory.boolValue else {
            throw ShellError.databasePathIsDirectory(path)
        }
        return try CineMindStore(path: url.path)
    }

    private static func list(store: CineMindStore) throws {
        let items = try store.fetchMediaItems()
        guard !items.isEmpty else {
            print("No media items found.")
            return
        }

        for item in items {
            printMediaItem(item)
            try printMetadataState(mediaItemID: item.id, store: store, indent: "  ")
        }
    }

    private static func fetchMediaItem(
        _ mediaItemID: MediaItemID,
        store: CineMindStore
    ) throws -> MediaItem {
        guard let item = try store.fetchMediaItem(id: mediaItemID) else {
            throw ApplicationMetadataError.mediaItemNotFound(mediaItemID)
        }
        return item
    }

    private static func makeLiveContext(
        commandName: String,
        cacheRoot: String?
    ) async throws -> LiveMetadataContext {
        let environment = ProcessInfo.processInfo.environment
        let token = environment["CINEMIND_TMDB_READ_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else {
            throw ShellError.missingTMDBReadToken(commandName)
        }

        let language = environment["CINEMIND_TMDB_LANGUAGE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmptyValue ?? "en-US"

        let httpClient = URLSessionMetadataHTTPClient()
        let provider = TMDBMetadataProvider(
            configuration: TMDBMetadataProvider.Configuration(
                bearerToken: token,
                defaultLanguage: language
            ),
            httpClient: httpClient
        )

        guard let cacheRoot else {
            return LiveMetadataContext(
                provider: provider,
                language: language,
                posterCache: nil,
                cacheRoot: nil
            )
        }

        let cacheRootURL = try validateCacheRoot(cacheRoot)
        let imageConfiguration = try await provider.fetchImageConfiguration()
        let posterCache = ApplicationPosterCache(
            posterCache: PosterCache(
                configuration: PosterCacheConfiguration(cacheRoot: cacheRootURL),
                httpClient: httpClient
            ),
            imageConfiguration: imageConfiguration
        )

        return LiveMetadataContext(
            provider: provider,
            language: language,
            posterCache: posterCache,
            cacheRoot: cacheRootURL
        )
    }

    private static func validateCacheRoot(_ path: String) throws -> URL {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw ShellError.invalidCacheRoot(path, "path is empty")
        }

        let url = URL(fileURLWithPath: trimmedPath).standardizedFileURL
        var isDirectory = ObjCBool(false)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw ShellError.invalidCacheRoot(path, "path exists but is not a directory")
            }
        } else {
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                throw ShellError.invalidCacheRoot(path, "could not create directory")
            }
        }

        guard fileManager.isReadableFile(atPath: url.path) else {
            throw ShellError.invalidCacheRoot(path, "directory is not readable")
        }
        guard fileManager.isWritableFile(atPath: url.path) else {
            throw ShellError.invalidCacheRoot(path, "directory is not writable")
        }

        return url
    }
}

private enum ShellArguments {
    case help
    case command(ShellCommand)

    static func parse(_ arguments: [String]) throws -> ShellArguments {
        let values = Array(arguments.dropFirst())
        if values.isEmpty || values.contains("--help") || values.contains("-h") {
            return .help
        }

        var databasePath: String?
        var commandName: String?
        var itemID: String?
        var providerID: String?
        var cacheRoot: String?
        var limit: Int?
        var force = false
        var value: String?
        var field: MetadataOverrideField?
        var posterAssetID: String?
        var index = 0

        func requireValue(for flag: String) throws -> String {
            let valueIndex = index + 1
            guard valueIndex < values.count else {
                throw ShellError.invalidArguments("Missing value for \(flag).")
            }
            return values[valueIndex]
        }

        while index < values.count {
            let argument = values[index]
            switch argument {
            case "--db":
                guard databasePath == nil else {
                    throw ShellError.invalidArguments("Duplicate --db flag.")
                }
                databasePath = try requireValue(for: argument)
                index += 1
            case "--item":
                guard itemID == nil else {
                    throw ShellError.invalidArguments("Duplicate --item flag.")
                }
                itemID = try requireValue(for: argument)
                index += 1
            case "--provider-id":
                guard providerID == nil else {
                    throw ShellError.invalidArguments("Duplicate --provider-id flag.")
                }
                providerID = try requireValue(for: argument)
                index += 1
            case "--cache-root":
                guard cacheRoot == nil else {
                    throw ShellError.invalidArguments("Duplicate --cache-root flag.")
                }
                cacheRoot = try requireValue(for: argument)
                index += 1
            case "--limit":
                guard limit == nil else {
                    throw ShellError.invalidArguments("Duplicate --limit flag.")
                }
                let rawLimit = try requireValue(for: argument)
                guard let parsedLimit = Int(rawLimit), parsedLimit > 0 else {
                    throw ShellError.invalidArguments("--limit must be a positive integer.")
                }
                limit = parsedLimit
                index += 1
            case "--force":
                guard !force else {
                    throw ShellError.invalidArguments("Duplicate --force flag.")
                }
                force = true
            case "--value":
                guard value == nil else {
                    throw ShellError.invalidArguments("Duplicate --value flag.")
                }
                value = try requireValue(for: argument)
                index += 1
            case "--field":
                guard field == nil else {
                    throw ShellError.invalidArguments("Duplicate --field flag.")
                }
                let rawField = try requireValue(for: argument)
                guard let parsedField = MetadataOverrideField(rawShellValue: rawField) else {
                    throw ShellError.invalidArguments("--field must be one of: title, summary, language.")
                }
                field = parsedField
                index += 1
            case "--poster":
                guard posterAssetID == nil else {
                    throw ShellError.invalidArguments("Duplicate --poster flag.")
                }
                posterAssetID = try requireValue(for: argument)
                index += 1
            default:
                if argument.hasPrefix("--") {
                    throw ShellError.invalidArguments("Unknown argument: \(argument)")
                }
                guard commandName == nil else {
                    throw ShellError.invalidArguments("Unexpected argument: \(argument)")
                }
                commandName = argument
            }

            index += 1
        }

        guard let commandName else {
            throw ShellError.invalidArguments("Expected a command.")
        }
        guard let databasePath, !databasePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ShellError.invalidArguments("--db <database-path> is required for \(commandName).")
        }

        switch commandName {
        case "list":
            try rejectOptions(
                for: commandName,
                itemID: itemID,
                providerID: providerID,
                cacheRoot: cacheRoot,
                limit: limit,
                force: force,
                value: value,
                field: field,
                posterAssetID: posterAssetID
            )
            return .command(.list(databasePath: databasePath))
        case "search":
            try rejectOptions(
                for: commandName,
                providerID: providerID,
                cacheRoot: cacheRoot,
                limit: limit,
                force: force,
                value: value,
                field: field,
                posterAssetID: posterAssetID
            )
            return .command(.search(databasePath: databasePath, mediaItemID: try required(itemID, "--item")))
        case "auto-match":
            try rejectOptions(
                for: commandName,
                providerID: providerID,
                limit: limit,
                force: force,
                value: value,
                field: field,
                posterAssetID: posterAssetID
            )
            return .command(.autoMatch(
                databasePath: databasePath,
                mediaItemID: try required(itemID, "--item"),
                cacheRoot: cacheRoot
            ))
        case "manual-match":
            try rejectOptions(
                for: commandName,
                limit: limit,
                force: force,
                value: value,
                field: field,
                posterAssetID: posterAssetID
            )
            return .command(.manualMatch(
                databasePath: databasePath,
                mediaItemID: try required(itemID, "--item"),
                providerID: try required(providerID, "--provider-id"),
                cacheRoot: cacheRoot
            ))
        case "refresh":
            try rejectOptions(
                for: commandName,
                providerID: providerID,
                limit: limit,
                force: force,
                value: value,
                field: field,
                posterAssetID: posterAssetID
            )
            return .command(.refresh(
                databasePath: databasePath,
                mediaItemID: try required(itemID, "--item"),
                cacheRoot: cacheRoot
            ))
        case "refresh-all":
            try rejectOptions(
                for: commandName,
                itemID: itemID,
                providerID: providerID,
                value: value,
                field: field,
                posterAssetID: posterAssetID
            )
            let defaultLimit = 20
            return .command(.refreshAll(
                databasePath: databasePath,
                limit: limit ?? defaultLimit,
                usedDefaultLimit: limit == nil,
                force: force,
                cacheRoot: cacheRoot
            ))
        case "override-title":
            try rejectOptions(
                for: commandName,
                providerID: providerID,
                cacheRoot: cacheRoot,
                limit: limit,
                force: force,
                field: field,
                posterAssetID: posterAssetID
            )
            return .command(.override(
                databasePath: databasePath,
                mediaItemID: try required(itemID, "--item"),
                field: .title,
                value: try required(value, "--value")
            ))
        case "override-summary":
            try rejectOptions(
                for: commandName,
                providerID: providerID,
                cacheRoot: cacheRoot,
                limit: limit,
                force: force,
                field: field,
                posterAssetID: posterAssetID
            )
            return .command(.override(
                databasePath: databasePath,
                mediaItemID: try required(itemID, "--item"),
                field: .summary,
                value: try required(value, "--value")
            ))
        case "override-language":
            try rejectOptions(
                for: commandName,
                providerID: providerID,
                cacheRoot: cacheRoot,
                limit: limit,
                force: force,
                field: field,
                posterAssetID: posterAssetID
            )
            return .command(.override(
                databasePath: databasePath,
                mediaItemID: try required(itemID, "--item"),
                field: .language,
                value: try required(value, "--value")
            ))
        case "clear-override":
            try rejectOptions(
                for: commandName,
                providerID: providerID,
                cacheRoot: cacheRoot,
                limit: limit,
                force: force,
                value: value,
                posterAssetID: posterAssetID
            )
            return .command(.clearOverride(
                databasePath: databasePath,
                mediaItemID: try required(itemID, "--item"),
                field: try required(field, "--field")
            ))
        case "select-poster":
            try rejectOptions(
                for: commandName,
                providerID: providerID,
                cacheRoot: cacheRoot,
                limit: limit,
                force: force,
                value: value,
                field: field
            )
            return .command(.selectPoster(
                databasePath: databasePath,
                mediaItemID: try required(itemID, "--item"),
                posterAssetID: try required(posterAssetID, "--poster")
            ))
        default:
            throw ShellError.invalidArguments("Unknown command: \(commandName)")
        }
    }

    private static func required<T>(_ value: T?, _ flag: String) throws -> T {
        guard let value else {
            throw ShellError.invalidArguments("Missing required \(flag).")
        }
        return value
    }

    private static func rejectOptions(
        for commandName: String,
        itemID: String? = nil,
        providerID: String? = nil,
        cacheRoot: String? = nil,
        limit: Int? = nil,
        force: Bool = false,
        value: String? = nil,
        field: MetadataOverrideField? = nil,
        posterAssetID: String? = nil
    ) throws {
        if itemID != nil {
            throw ShellError.invalidArguments("--item is not supported for \(commandName).")
        }
        if providerID != nil {
            throw ShellError.invalidArguments("--provider-id is not supported for \(commandName).")
        }
        if cacheRoot != nil {
            throw ShellError.invalidArguments("--cache-root is not supported for \(commandName).")
        }
        if limit != nil {
            throw ShellError.invalidArguments("--limit is not supported for \(commandName).")
        }
        if force {
            throw ShellError.invalidArguments("--force is not supported for \(commandName).")
        }
        if value != nil {
            throw ShellError.invalidArguments("--value is not supported for \(commandName).")
        }
        if field != nil {
            throw ShellError.invalidArguments("--field is not supported for \(commandName).")
        }
        if posterAssetID != nil {
            throw ShellError.invalidArguments("--poster is not supported for \(commandName).")
        }
    }
}

private enum ShellCommand {
    case list(databasePath: String)
    case search(databasePath: String, mediaItemID: MediaItemID)
    case autoMatch(databasePath: String, mediaItemID: MediaItemID, cacheRoot: String?)
    case manualMatch(databasePath: String, mediaItemID: MediaItemID, providerID: String, cacheRoot: String?)
    case refresh(databasePath: String, mediaItemID: MediaItemID, cacheRoot: String?)
    case refreshAll(databasePath: String, limit: Int, usedDefaultLimit: Bool, force: Bool, cacheRoot: String?)
    case override(databasePath: String, mediaItemID: MediaItemID, field: MetadataOverrideField, value: String)
    case clearOverride(databasePath: String, mediaItemID: MediaItemID, field: MetadataOverrideField)
    case selectPoster(databasePath: String, mediaItemID: MediaItemID, posterAssetID: PosterAssetID)

    var databasePath: String {
        switch self {
        case .list(let databasePath),
             .search(let databasePath, _),
             .autoMatch(let databasePath, _, _),
             .manualMatch(let databasePath, _, _, _),
             .refresh(let databasePath, _, _),
             .refreshAll(let databasePath, _, _, _, _),
             .override(let databasePath, _, _, _),
             .clearOverride(let databasePath, _, _),
             .selectPoster(let databasePath, _, _):
            databasePath
        }
    }

    var name: String {
        switch self {
        case .list:
            "list"
        case .search:
            "search"
        case .autoMatch:
            "auto-match"
        case .manualMatch:
            "manual-match"
        case .refresh:
            "refresh"
        case .refreshAll:
            "refresh-all"
        case .override(_, _, let field, _):
            "override-\(field.rawShellValue)"
        case .clearOverride:
            "clear-override"
        case .selectPoster:
            "select-poster"
        }
    }
}

private struct LiveMetadataContext {
    let provider: TMDBMetadataProvider
    let language: String
    let posterCache: ApplicationPosterCache?
    let cacheRoot: URL?
}

private final class URLSessionMetadataHTTPClient: MetadataHTTPClient {
    func send(_ request: URLRequest) async throws -> MetadataHTTPResponse {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SanitizedHTTPClientError.invalidResponse
            }
            return MetadataHTTPResponse(statusCode: httpResponse.statusCode, data: data)
        } catch let error as SanitizedHTTPClientError {
            throw error
        } catch {
            throw SanitizedHTTPClientError.transportFailure
        }
    }
}

private enum SanitizedHTTPClientError: Error, CustomStringConvertible {
    case invalidResponse
    case transportFailure

    var description: String {
        switch self {
        case .invalidResponse:
            "HTTP response was invalid."
        case .transportFailure:
            "HTTP request failed."
        }
    }
}

private enum ShellError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case databaseNotFound(String)
    case databasePathIsDirectory(String)
    case missingTMDBReadToken(String)
    case invalidCacheRoot(String, String)

    var description: String {
        switch self {
        case .invalidArguments(let message):
            message
        case .databaseNotFound(let path):
            "SQLite database not found: \(path)"
        case .databasePathIsDirectory(let path):
            "SQLite database path is a directory: \(path)"
        case .missingTMDBReadToken(let command):
            """
            CINEMIND_TMDB_READ_TOKEN is required for \(command). \
            Export it with: export CINEMIND_TMDB_READ_TOKEN=<tmdb-read-token>
            """
        case .invalidCacheRoot(let path, let reason):
            "Invalid --cache-root \(path): \(reason)."
        }
    }

    var exitCode: Int32 {
        switch self {
        case .invalidArguments:
            2
        case .databaseNotFound,
             .databasePathIsDirectory,
             .missingTMDBReadToken,
             .invalidCacheRoot:
            1
        }
    }

    var shouldPrintUsage: Bool {
        if case .invalidArguments = self {
            return true
        }
        return false
    }
}

private func printUsage() {
    print("""
    Usage:
      CineMindMetadataShell --help
      CineMindMetadataShell --db <database-path> list
      CineMindMetadataShell --db <database-path> search --item <media-item-id>
      CineMindMetadataShell --db <database-path> auto-match --item <media-item-id> [--cache-root <path>]
      CineMindMetadataShell --db <database-path> manual-match --item <media-item-id> --provider-id <provider-id> [--cache-root <path>]
      CineMindMetadataShell --db <database-path> refresh --item <media-item-id> [--cache-root <path>]
      CineMindMetadataShell --db <database-path> refresh-all [--limit N] [--force] [--cache-root <path>]
      CineMindMetadataShell --db <database-path> override-title --item <media-item-id> --value <value>
      CineMindMetadataShell --db <database-path> override-summary --item <media-item-id> --value <value>
      CineMindMetadataShell --db <database-path> override-language --item <media-item-id> --value <value>
      CineMindMetadataShell --db <database-path> clear-override --item <media-item-id> --field title|summary|language
      CineMindMetadataShell --db <database-path> select-poster --item <media-item-id> --poster <poster-asset-id>

    Environment for live TMDB commands:
      CINEMIND_TMDB_READ_TOKEN
      CINEMIND_TMDB_LANGUAGE (default: en-US)
    """)
}

private func printMediaItem(_ item: MediaItem) {
    print("Item: id=\(item.id) title=\(quoted(displayTitle(for: item))) type=\(item.mediaType.rawValue)")
}

private func printMetadataState(
    mediaItemID: MediaItemID,
    store: CineMindStore,
    indent: String = ""
) throws {
    printSourceRecord(
        try store.fetchMetadataSourceRecord(mediaItemID: mediaItemID, provider: .tmdb),
        indent: indent
    )
    printMetadataItem(try store.fetchMetadataItem(mediaItemID: mediaItemID), indent: indent)
    printPosterAssets(try store.fetchPosterAssets(mediaItemID: mediaItemID), indent: indent)
}

private func printCandidates(_ candidates: [MetadataCandidate]) {
    guard !candidates.isEmpty else {
        print("Candidates: none")
        return
    }

    print("Candidates: \(candidates.count)")
    for candidate in candidates {
        printCandidate(candidate, indent: "- ")
    }
}

private func printCandidate(_ candidate: MetadataCandidate, indent: String = "") {
    var parts = [
        "id=\(candidate.identifier.rawValue)",
        "title=\(quoted(candidate.displayTitle))",
        "confidence=\(formatConfidence(candidate.confidence))"
    ]
    if let originalTitle = candidate.originalTitle {
        parts.append("original=\(quoted(originalTitle))")
    }
    if let year = candidate.year {
        parts.append("year=\(year)")
    }
    if let airDate = candidate.airDate {
        parts.append("airDate=\(airDate)")
    }
    if !candidate.confidenceInputs.isEmpty {
        parts.append("inputs=\(confidenceInputs(candidate.confidenceInputs))")
    }
    if let overviewPreview = candidate.overviewPreview {
        parts.append("preview=\(quoted(overviewPreview, maxLength: 120))")
    }
    print("\(indent)Candidate: \(parts.joined(separator: " "))")
}

private func printAutoMatchResult(_ result: AutoMatchMetadataResult) {
    switch result {
    case .matched(let candidate):
        print("Match result: automatic matched")
        printCandidate(candidate, indent: "  ")
    case .skippedManualLock:
        print("Match result: skipped manual lock")
    case .noCandidates:
        print("Match result: no candidates")
    case .lowConfidence:
        print("Match result: low confidence")
    case .ambiguous:
        print("Match result: ambiguous")
    }
}

private func printRefreshResult(_ result: RefreshMetadataResult) {
    switch result {
    case .autoMatched(let autoMatchResult):
        print("Refresh result: auto-match")
        printAutoMatchResult(autoMatchResult)
    case .refreshed(let source):
        print("Refresh result: refreshed")
        printSourceRecord(source)
    }
}

private func printSourceRecord(_ source: MetadataSourceRecord?, indent: String = "") {
    guard let source else {
        print("\(indent)Source: none")
        return
    }

    let parts = [
        "provider=\(source.provider.rawValue)",
        "providerID=\(source.providerID)",
        "mediaType=\(source.providerMediaType.rawValue)",
        "confidence=\(formatConfidence(source.confidence))",
        "match=\(source.matchSource.rawValue)",
        "manualLock=\(source.manualMatchLocked)",
        "matchedAt=\(formatTimestamp(source.matchedAt))",
        "refreshedAt=\(formatTimestamp(source.refreshedAt))"
    ]
    print("\(indent)Source: \(parts.joined(separator: " "))")
    if let rawPayloadJSON = source.rawPayloadJSON?.nonEmptyValue {
        print("\(indent)  rawPayload=\(quoted(rawPayloadJSON, maxLength: 180))")
    }
}

private func printMetadataItem(_ metadata: MetadataItem?, indent: String = "") {
    guard let metadata else {
        print("\(indent)Metadata: none")
        return
    }

    let parts = [
        "id=\(metadata.id)",
        "title=\(quotedOptional(metadata.title))",
        "original=\(quotedOptional(metadata.originalTitle))",
        "summary=\(quotedOptional(metadata.summary, maxLength: 120))",
        "language=\(metadata.language ?? "nil")",
        "release=\(metadata.releaseDate ?? "nil")",
        "air=\(metadata.airDate ?? "nil")",
        "locks=\(overrideLocks(metadata))",
        "updatedAt=\(formatTimestamp(metadata.updatedAt))"
    ]
    print("\(indent)Metadata: \(parts.joined(separator: " "))")
}

private func printPosterAssets(_ posters: [PosterAsset], indent: String = "") {
    guard !posters.isEmpty else {
        print("\(indent)Posters: none")
        return
    }

    print("\(indent)Posters: \(posters.count)")
    for poster in posters {
        let parts = [
            "id=\(poster.id)",
            "selected=\(poster.isSelected)",
            "selection=\(poster.selectionSource.rawValue)",
            "source=\(poster.source.rawValue)",
            "remote=\(poster.remotePath)",
            "size=\(posterSize(poster))",
            "cacheSize=\(poster.preferredCacheSize)",
            "local=\(quotedOptional(poster.localCachePath))",
            "cachedAt=\(formatTimestamp(poster.cachedAt))"
        ]
        print("\(indent)- Poster: \(parts.joined(separator: " "))")
    }
}

private func printPosterCacheState(_ cacheRoot: URL?) {
    if let cacheRoot {
        print("Poster cache: enabled root=\(cacheRoot.path)")
    } else {
        print("Poster cache: disabled; poster files will not be downloaded")
    }
}

private func displayTitle(for item: MediaItem) -> String {
    var parts = [item.title]
    if let year = item.year {
        parts.append("(\(year))")
    }
    if let episodeInfo = item.episodeInfo {
        parts.append(
            "S\(String(format: "%02d", episodeInfo.seasonNumber))E" +
                "\(String(format: "%02d", episodeInfo.episodeNumber))"
        )
    }
    return parts.joined(separator: " ")
}

private func overrideLocks(_ metadata: MetadataItem) -> String {
    var locks: [String] = []
    if metadata.titleOverrideLocked {
        locks.append("title")
    }
    if metadata.summaryOverrideLocked {
        locks.append("summary")
    }
    if metadata.languageOverrideLocked {
        locks.append("language")
    }
    return locks.isEmpty ? "none" : locks.joined(separator: ",")
}

private func posterSize(_ poster: PosterAsset) -> String {
    guard let width = poster.width, let height = poster.height else {
        return "unknown"
    }
    return "\(width)x\(height)"
}

private func confidenceInputs(_ inputs: [String: String]) -> String {
    inputs
        .sorted { $0.key < $1.key }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: ",")
}

private func formatConfidence(_ value: Double) -> String {
    String(format: "%.3f", value)
}

private func formatTimestamp(_ date: Date?) -> String {
    guard let date else {
        return "nil"
    }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}

private func quotedOptional(_ value: String?, maxLength: Int = 80) -> String {
    guard let value else {
        return "nil"
    }
    return quoted(value, maxLength: maxLength)
}

private func quoted(_ value: String, maxLength: Int = 80) -> String {
    "\"\(compact(value, maxLength: maxLength))\""
}

private func compact(_ value: String, maxLength: Int) -> String {
    let singleLine = value
        .replacingOccurrences(of: "\r", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\t", with: " ")
    guard singleLine.count > maxLength else {
        return singleLine
    }
    return String(singleLine.prefix(maxLength)) + "..."
}

private func applicationMetadataErrorDescription(_ error: ApplicationMetadataError) -> String {
    switch error {
    case .mediaItemNotFound(let id):
        "Media item not found: \(id)"
    case .posterAssetMediaItemMismatch(let mediaItemID, let posterAssetID):
        "Poster asset \(posterAssetID) does not belong to media item \(mediaItemID)."
    case .missingEpisodeInfo(let id):
        "Media item is missing episode info: \(id)"
    case .invalidProviderID(let providerID):
        "Invalid provider id: \(providerID). Expected movie:<tmdb-id> or tv:<series-id>:s<season>:e<episode>."
    case .providerMismatch(let mediaItemID, let expected, let actual):
        "Provider mismatch for \(mediaItemID): expected \(expected.rawValue), found \(actual.rawValue)."
    case .providerMediaTypeMismatch(let mediaItemID, let providerID):
        "Provider id \(providerID) does not match media item type for \(mediaItemID)."
    case .episodeProviderIDMismatch(let mediaItemID, let expectedSeason, let expectedEpisode, let providerID):
        "Provider id \(providerID) does not match \(mediaItemID): expected S\(expectedSeason)E\(expectedEpisode)."
    }
}

private func writeError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

private extension MetadataOverrideField {
    init?(rawShellValue: String) {
        switch rawShellValue {
        case "title":
            self = .title
        case "summary":
            self = .summary
        case "language":
            self = .language
        default:
            return nil
        }
    }

    var rawShellValue: String {
        switch self {
        case .title:
            "title"
        case .summary:
            "summary"
        case .language:
            "language"
        }
    }
}

private extension String {
    var nonEmptyValue: String? {
        isEmpty ? nil : self
    }
}

await CineMindMetadataShell.main()
