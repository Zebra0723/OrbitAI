// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Orbit",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Orbit",
            path: "Sources/Orbit",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
            ]
        )
    ]
)
