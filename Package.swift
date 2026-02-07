// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RSSReader",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/nmdias/FeedKit", from: "10.0.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup", from: "2.7.0")
    ],
    targets: [
        .executableTarget(
            name: "RSSReader",
            dependencies: ["FeedKit", "SwiftSoup"],
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
