// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Platter",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Platter",
            path: "Sources/Platter"
        )
    ]
)
