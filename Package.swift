// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChatGPTProfileKeys",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ChatGPTProfileKeys", targets: ["ChatGPTProfileKeys"])],
    targets: [
        .executableTarget(name: "ChatGPTProfileKeys", path: "Sources"),
        .testTarget(name: "ChatGPTProfileKeysTests", dependencies: ["ChatGPTProfileKeys"], path: "Tests")
    ]
)
