// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "uswitch",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "uswitch", path: "Sources/uswitch")
    ]
)
