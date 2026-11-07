// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnagxCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "SnagxKit", targets: ["SnagxKit"]),
        .executable(name: "snagx-export", targets: ["snagx-export"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.20"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.0"),
    ],
    targets: [
        .target(
            name: "SnagxKit",
            dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")]
        ),
        .executableTarget(
            name: "snagx-export",
            dependencies: [
                "SnagxKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "SnagxKitTests",
            dependencies: ["SnagxKit", .product(name: "ZIPFoundation", package: "ZIPFoundation")]
        ),
    ]
)
