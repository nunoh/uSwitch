// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "uswitch",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.9.6"),
    ],
    targets: [
        .executableTarget(
            name: "uswitch",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/uswitch",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
    ]
)
