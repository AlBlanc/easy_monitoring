// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "easy_monitoring",
    platforms: [
        .iOS("12.0")
    ],
    products: [
        .library(name: "easy-monitoring", targets: ["easy_monitoring"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "easy_monitoring",
            dependencies: [],
            path: "Sources/easy_monitoring"
        )
    ]
)
