import Foundation
import XCTest

final class CineMindMetadataShellSmokeTests: XCTestCase {
    func testHelpWorksWithoutToken() throws {
        let result = try runShell(["--help"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Usage:"))
        XCTAssertTrue(result.stdout.contains("CineMindMetadataShell --help"))
        XCTAssertFalse(result.combinedOutput.localizedCaseInsensitiveContains("bearer"))
    }

    func testMissingTokenForLiveCommandIsActionableAndSecretFree() throws {
        let databaseURL = try temporaryDatabaseURL()

        let result = try runShell([
            "--db", databaseURL.path,
            "refresh-all"
        ])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("CINEMIND_TMDB_READ_TOKEN is required"))
        XCTAssertTrue(result.stderr.contains("export CINEMIND_TMDB_READ_TOKEN=<tmdb-read-token>"))
        XCTAssertFalse(result.combinedOutput.contains("very-secret-read-token"))
        XCTAssertFalse(result.combinedOutput.localizedCaseInsensitiveContains("authorization"))
        XCTAssertFalse(result.combinedOutput.localizedCaseInsensitiveContains("bearer"))
    }

    func testInvalidArgumentsReturnNonZero() throws {
        let result = try runShell(["--not-a-real-argument"])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("Unknown argument: --not-a-real-argument"))
        XCTAssertTrue(result.stdout.contains("Usage:"))
    }

    private func temporaryDatabaseURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CineMindMetadataShellTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let databaseURL = directory.appendingPathComponent("test.sqlite", isDirectory: false)
        FileManager.default.createFile(atPath: databaseURL.path, contents: Data())
        return databaseURL
    }

    private func runShell(_ arguments: [String]) throws -> ShellResult {
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "CINEMIND_TMDB_READ_TOKEN")
        environment.removeValue(forKey: "CINEMIND_TMDB_LANGUAGE")

        let process = Process()
        process.executableURL = try shellExecutableURL()
        process.arguments = arguments
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return ShellResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }

    private func shellExecutableURL() throws -> URL {
        let root = packageRootURL()
        let defaultURL = root
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("debug", isDirectory: true)
            .appendingPathComponent("CineMindMetadataShell", isDirectory: false)
        if FileManager.default.isExecutableFile(atPath: defaultURL.path) {
            return defaultURL
        }

        let buildURL = root.appendingPathComponent(".build", isDirectory: true)
        let enumerator = FileManager.default.enumerator(
            at: buildURL,
            includingPropertiesForKeys: nil
        )
        while let candidate = enumerator?.nextObject() as? URL {
            if candidate.lastPathComponent == "CineMindMetadataShell",
               FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        throw ShellTestError.executableNotFound(defaultURL.path)
    }

    private func packageRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct ShellResult {
    var exitCode: Int32
    var stdout: String
    var stderr: String

    var combinedOutput: String {
        stdout + stderr
    }
}

private enum ShellTestError: Error {
    case executableNotFound(String)
}
