// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AppleSpeechWhisperKitComparison",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "0.18.0")
    ],
    targets: [
        .executableTarget(
            name: "AppleSpeechWhisperKitComparison",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ]
        )
    ]
)
