// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchDeck",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotchDeck",
            path: "Sources/NotchDeck"
        ),
        .testTarget(
            name: "NotchDeckTests",
            dependencies: ["NotchDeck"],
            path: "Tests/NotchDeckTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
