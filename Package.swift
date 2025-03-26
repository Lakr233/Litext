// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Litext",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v13),
        .macCatalyst(.v13),
        .macOS(.v12),
    ],
    products: [
        .library(name: "Litext", targets: ["Litext"]),
    ],
    targets: [
        .target(name: "Litext"),
    ]
)
