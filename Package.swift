// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Klik",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .executableTarget(
            name: "Klik",
            dependencies: ["Sparkle"],
            path: "Sources/Klik"
        )
    ]
)
