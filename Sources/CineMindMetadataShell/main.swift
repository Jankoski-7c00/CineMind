import Application
import Foundation
import Metadata
import Persistence
import Shared

private enum ShellArguments {
    case help

    static func parse(_ arguments: [String]) throws -> ShellArguments {
        let values = Array(arguments.dropFirst())
        if values.isEmpty || values == ["--help"] || values == ["-h"] {
            return .help
        }

        throw ShellError.invalidArguments("CineMindMetadataShell currently supports --help only.")
    }
}

private enum ShellError: Error, CustomStringConvertible {
    case invalidArguments(String)

    var description: String {
        switch self {
        case .invalidArguments(let message):
            message
        }
    }
}

private func printUsage() {
    print("""
    Usage:
      CineMindMetadataShell --help

    Future Phase 3 commands:
      list
      search
      auto-match
      manual-match
      refresh
      refresh-all
      set-override
      clear-override
      select-poster

    Future environment:
      CINEMIND_TMDB_READ_TOKEN
      CINEMIND_TMDB_LANGUAGE
    """)
}

private func writeError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

do {
    switch try ShellArguments.parse(CommandLine.arguments) {
    case .help:
        printUsage()
    }
} catch let error as ShellError {
    writeError(error.description)
    printUsage()
    exit(2)
} catch {
    writeError("Metadata shell failed: \(error)")
    exit(1)
}
