// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Orbit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "Orbit", targets: ["Orbit"])],
    targets: [
        .target(name: "Orbit"),
        .testTarget(name: "OrbitTests", dependencies: ["Orbit"]),
    ],
    swiftLanguageModes: [.v6]
)
