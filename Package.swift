// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CineMind",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AppUI", targets: ["AppUI"]),
        .library(name: "Shared", targets: ["Shared"]),
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "Scanner", targets: ["Scanner"]),
        .library(name: "Application", targets: ["Application"]),
        .library(name: "Playback", targets: ["Playback"]),
        .library(name: "PlaybackAVFoundation", targets: ["PlaybackAVFoundation"]),
        .library(name: "Metadata", targets: ["Metadata"]),
        .executable(name: "CineMindApp", targets: ["CineMindApp"]),
        .executable(name: "CineMindShell", targets: ["CineMindShell"]),
        .executable(name: "CineMindAVFoundationPlaybackSpike", targets: ["CineMindAVFoundationPlaybackSpike"]),
        .executable(name: "CineMindMetadataShell", targets: ["CineMindMetadataShell"])
    ],
    targets: [
        .target(
            name: "AppUI",
            dependencies: ["Application", "Domain", "Shared"]
        ),
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
            name: "PlaybackAVFoundation",
            dependencies: ["Playback"],
            linkerSettings: [
                .linkedFramework("AVFoundation")
            ]
        ),
        .target(
            name: "Metadata",
            dependencies: ["Domain", "Shared"]
        ),
        .target(
            name: "Application",
            dependencies: ["Domain", "Persistence", "Playback", "Metadata", "Shared"]
        ),
        .executableTarget(
            name: "CineMindApp",
            dependencies: ["AppUI", "Application", "Metadata", "Playback", "PlaybackAVFoundation", "Persistence", "Scanner", "Shared"]
        ),
        .executableTarget(
            name: "CineMindShell",
            dependencies: ["Domain", "Persistence"]
        ),
        .executableTarget(
            name: "CineMindAVFoundationPlaybackSpike",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVKit")
            ]
        ),
        .executableTarget(
            name: "CineMindMetadataShell",
            dependencies: ["Application", "Persistence", "Metadata", "Shared"]
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
        ),
        .testTarget(
            name: "PlaybackAVFoundationTests",
            dependencies: ["PlaybackAVFoundation", "Playback"]
        ),
        .testTarget(
            name: "MetadataTests",
            dependencies: ["Metadata", "Domain"]
        ),
        .testTarget(
            name: "CineMindMetadataShellTests",
            dependencies: ["CineMindMetadataShell"]
        )
    ]
)
