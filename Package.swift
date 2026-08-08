// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SwiftFlow",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "SwiftFlow", path: "Sources/SwiftFlow")
    ]
)
