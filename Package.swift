// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OpenCodeHub",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "OpenCodeHub", targets: ["OpenCodeHub"])
    ],
    targets: [
        .executableTarget(name: "OpenCodeHub", path: "Sources/OpenCodeHub")
    ]
)
