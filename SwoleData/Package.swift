// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "SwoleData",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "SwoleData", targets: ["SwoleData"]),
    ],
    targets: [
        .target(name: "SwoleData"),
        .testTarget(name: "SwoleDataTests", dependencies: ["SwoleData"]),
    ]
)
