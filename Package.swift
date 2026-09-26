// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIResetRunner",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "AIResetRunner", path: "Sources/AIResetRunner"),
        .testTarget(
            name: "AIResetRunnerTests",
            dependencies: ["AIResetRunner"],
            path: "Tests/AIResetRunnerTests",
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
