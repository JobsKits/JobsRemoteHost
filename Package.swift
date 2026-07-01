// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "JobsRemoteHost",
    platforms: [
        .macOS("15.2")
    ],
    products: [
        .executable(
            name: "JobsRemoteHost",
            targets: ["JobsRemoteHost"]
        )
    ],
    targets: [
        .executableTarget(
            name: "JobsRemoteHost",
            path: "Sources/JobsRemoteHost",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Network"),
                .linkedFramework("ScreenCaptureKit")
            ]
        ),
        .testTarget(
            name: "JobsRemoteHostTests",
            dependencies: ["JobsRemoteHost"],
            path: "Tests/JobsRemoteHostTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
