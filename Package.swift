// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RSSReader",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/nmdias/FeedKit", from: "10.0.0")
    ],
    targets: [
        .executableTarget(
            name: "RSSReader",
            dependencies: ["FeedKit"],
            path: "Sources"
        )
    ]
)
