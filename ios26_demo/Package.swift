// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RealtimeInterpretationDemo",
    platforms: [
        .iOS("26.0")
    ],
    products: [
        .library(
            name: "RealtimeInterpretationDemo",
            targets: ["RealtimeInterpretationDemo"]
        )
    ],
    dependencies: [
        .package(path: "Vendor/llama.swift"),
        .package(url: "https://github.com/exPHAT/SwiftWhisper.git", branch: "master")
    ],
    targets: [
        .target(
            name: "RealtimeInterpretationDemo",
            dependencies: [
                .product(name: "LlamaSwift", package: "llama.swift"),
                .product(name: "SwiftWhisper", package: "SwiftWhisper")
            ]
        )
    ]
)
