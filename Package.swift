// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReasonDeck",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ReasonDeck", targets: ["ReasonDeck"])],
    targets: [
        .executableTarget(name: "ReasonDeck", path: "Sources"),
        .testTarget(name: "ReasonDeckTests", dependencies: ["ReasonDeck"], path: "Tests")
    ]
)
