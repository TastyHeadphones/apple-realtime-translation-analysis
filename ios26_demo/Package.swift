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
    targets: [
        .target(
            name: "RealtimeInterpretationDemo"
        )
    ]
)
