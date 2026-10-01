// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Litext",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v15),
        .macCatalyst(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .visionOS(.v1),
        .watchOS(.v8),
    ],
    products: [
        .library(name: "Litext", targets: ["Litext"]),
    ],
    targets: [
        .target(
            name: "Litext",
            resources: [.process("Resources")],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ],
        ),
        .testTarget(
            name: "LitextTests",
            dependencies: ["Litext"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ],
        ),
    ],
    swiftLanguageModes: [.v6],
)
