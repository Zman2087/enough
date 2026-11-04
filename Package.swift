// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Enough",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "FilterEngine", targets: ["FilterEngine"])
    ],
    targets: [
        .target(
            name: "FilterEngine",
            path: "Sources/FilterEngine",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "FilterEngineTests",
            dependencies: ["FilterEngine"],
            path: "Tests/FilterEngineTests",
            exclude: ["Fixtures"]
        )
    ]
)
