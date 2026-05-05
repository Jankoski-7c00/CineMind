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
        .executable(name: "CineMindShell", targets: ["CineMindShell"])
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
        .executableTarget(
            name: "CineMindShell",
            dependencies: ["Shared", "Domain", "Persistence", "Scanner"]
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
        )
    ]
)
