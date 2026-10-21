// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Pulsebar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Pulsebar",
            path: "Sources/Pulsebar",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PulsebarTests",
            dependencies: ["Pulsebar"],
            path: "Tests/PulsebarTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
