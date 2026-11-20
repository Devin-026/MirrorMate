// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MirrorMate",
    platforms: [.macOS("15.0")],
    products: [.executable(name: "MirrorMate", targets: ["MirrorMate"])],
    targets: [
        .target(name: "MirrorMateCore"),
        .executableTarget(name: "MirrorMate", dependencies: ["MirrorMateCore"], linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("SwiftUI")]),
        .executableTarget(name: "MirrorMateChecks", dependencies: ["MirrorMateCore"], path: "Tests/MirrorMateCoreTests")
    ]
)
