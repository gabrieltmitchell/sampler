// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Sampler",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "Sampler",
            targets: ["Sampler"]
        )
    ],
    targets: [
        .target(
            name: "Sampler"
        )
    ]
)
