// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VinylMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VinylMac",
            path: "Sources/VinylMac"
        )
    ]
)
