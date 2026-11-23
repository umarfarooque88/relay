// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Relay",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "MemoryKit"),
        .executableTarget(name: "Relay", dependencies: ["MemoryKit"]),
        .testTarget(name: "MemoryKitTests", dependencies: ["MemoryKit"]),
    ]
)
