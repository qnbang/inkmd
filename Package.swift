// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MDEditor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MDEditor")
    ]
)
