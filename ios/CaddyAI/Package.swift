// swift-tools-version:5.9
// SwiftPM manifest for the pure-Swift core library.
// The iOS app target is built separately via XcodeGen from `project.yml`.
//
// This lets us run swing-metrics tests on Linux CI without needing Xcode.
import PackageDescription

let package = Package(
    name: "CaddyAICore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "CaddyAICore", targets: ["CaddyAICore"]),
    ],
    targets: [
        .target(
            name: "CaddyAICore",
            path: "Sources/CaddyAICore"
        ),
        .testTarget(
            name: "CaddyAICoreTests",
            dependencies: ["CaddyAICore"],
            path: "Tests/CaddyAICoreTests"
        ),
    ]
)
