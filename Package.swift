// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ImportPhotos",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ImportPhotos",
            targets: ["ImportPhotos"]),
    ],
    targets: [
        .target(
            name: "ImportPhotos"),
        .testTarget(
            name:    "ImportPhotosTests",
            dependencies: ["ImportPhotos"]),
    ]
)
