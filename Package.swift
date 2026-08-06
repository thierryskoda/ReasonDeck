// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ModelKey",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ModelKey", targets: ["ModelKey"])],
    targets: [
        .executableTarget(name: "ModelKey", path: "Sources"),
        .testTarget(name: "ModelKeyTests", dependencies: ["ModelKey"], path: "Tests")
    ]
)
