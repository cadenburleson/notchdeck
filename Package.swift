// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchDeck",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "NotchDeck",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/NotchDeck",
            linkerSettings: [
                // The Makefile copies Sparkle.framework into Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "NotchDeckTests",
            dependencies: ["NotchDeck"],
            path: "Tests/NotchDeckTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
