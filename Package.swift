// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "QOI",
    products: [
        .library(
            name: "QOI",
            targets: ["QOI"]),
        .executable(
            name: "QOIConvert",
            targets: ["QOIConvert"]),
    ],
    targets: [
        .target(name: "QOIReference"),
        .target(name: "QOI"),
        .executableTarget(name: "QOIConvert", dependencies: ["QOI", "QOIReference"]),
        .testTarget(
            name: "QOITests",
            dependencies: ["QOI", "QOIReference"]),
    ]
)
