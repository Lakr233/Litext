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
        .library(name: "LitextAnimation", targets: ["LitextAnimation"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Lakr233/DisplayLink.git", from: "3.0.1"),
    ],
    targets: [
        .target(
            name: "Litext",
            resources: [.process("Resources")],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ],
        ),
        .target(
            name: "LitextAnimation",
            dependencies: [
                "Litext",
                .product(
                    name: "DisplayLink",
                    package: "DisplayLink",
                    condition: .when(platforms: [.iOS, .macCatalyst, .macOS, .tvOS, .visionOS]),
                ),
            ],
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
