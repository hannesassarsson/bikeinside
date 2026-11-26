// swift-tools-version: 6.0
import PackageDescription

/// Platform-independent heart of Bikeinside: physics, Bluetooth protocol
/// parsing, routes, terrain, workouts, ride engine and file export.
/// Everything here is plain Swift + Foundation so it builds and is tested on
/// Linux CI as well as on macOS.
let package = Package(
    name: "BikeinsideCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "BikeinsideCore", targets: ["BikeinsideCore"]),
    ],
    targets: [
        .target(name: "BikeinsideCore"),
        .testTarget(name: "BikeinsideCoreTests", dependencies: ["BikeinsideCore"]),
    ]
)
