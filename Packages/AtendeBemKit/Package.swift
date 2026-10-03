// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AtendeBemKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AtendeBemCore", targets: ["AtendeBemCore"]),
        .library(name: "AtendeBemUI", targets: ["AtendeBemUI"])
    ],
    targets: [
        .target(name: "AtendeBemCore"),
        .target(name: "AtendeBemUI", dependencies: ["AtendeBemCore"], resources: [.process("Resources")]),
        .testTarget(name: "AtendeBemCoreTests", dependencies: ["AtendeBemCore"]),
        .testTarget(name: "AtendeBemStateTests", dependencies: ["AtendeBemUI", "AtendeBemCore"])
    ]
)
