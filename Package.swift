// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CineMind",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "Shared", targets: ["Shared"]),
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "Scanner", targets: ["Scanner"]),
        .library(name: "Application", targets: ["Application"]),
        .library(name: "Playback", targets: ["Playback"]),
        .library(name: "LibMPVPlayback", targets: ["LibMPVPlayback"]),
        .executable(name: "CineMindShell", targets: ["CineMindShell"]),
        .executable(name: "CineMindPlaybackShell", targets: ["CineMindPlaybackShell"])
    ],
    targets: [
        .target(name: "Shared"),
        .target(
            name: "Domain",
            dependencies: ["Shared"]
        ),
        .target(
            name: "Persistence",
            dependencies: ["Domain", "Shared"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "Scanner",
            dependencies: ["Domain", "Persistence", "Shared"]
        ),
        .target(
            name: "Playback",
            dependencies: ["Domain", "Shared"]
        ),
        .target(
            name: "Application",
            dependencies: ["Domain", "Persistence", "Playback", "Shared"]
        ),
        .systemLibrary(
            name: "CLibMPV",
            pkgConfig: "mpv",
            providers: [
                .brew(["mpv"])
            ]
        ),
        .target(
            name: "LibMPVPlayback",
            dependencies: ["Playback", "CLibMPV"]
        ),
        .executableTarget(
            name: "CineMindShell",
            dependencies: ["Domain", "Persistence"]
        ),
        .executableTarget(
            name: "CineMindPlaybackShell",
            dependencies: ["Application", "Playback", "LibMPVPlayback", "Shared"]
        ),
        .testTarget(
            name: "DomainTests",
            dependencies: ["Domain"]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence", "Domain"]
        ),
        .testTarget(
            name: "ScannerTests",
            dependencies: ["Scanner", "Persistence", "Domain"]
        ),
        .testTarget(
            name: "ApplicationTests",
            dependencies: ["Application"]
        ),
        .testTarget(
            name: "PlaybackTests",
            dependencies: ["Playback"]
        )
    ]
)
