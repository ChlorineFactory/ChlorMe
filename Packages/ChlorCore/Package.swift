// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ChlorCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ChlorCore",
            targets: ["ChlorCore"]
        )
    ],
    targets: [
        .target(
            name: "ChlorCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "ChlorCoreTests",
            dependencies: ["ChlorCore"]
        )
    ]
)
