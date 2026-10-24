// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "easy_monitoring",
    platforms: [
        .macOS("10.15")
    ],
    products: [
        .library(name: "easy-monitoring", targets: ["easy_monitoring"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "easy_monitoring",
            dependencies: [],
            path: "Sources/easy_monitoring",
            resources: [
                .copy("Resources/libeasy_monitoring.dylib")
            ]
        )
    ]
)
