// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AinkradKit",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ainkrad", targets: ["ainkrad"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        // TODO(release): repin to pushed AinkradAppKit revision
        .package(name: "AinkradAppKit", path: "/Users/ahmedmelhalaby/Herd/AinkradAppKit"),
    ],
    targets: [
        .executableTarget(
            name: "ainkrad",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "AinkradAppKit", package: "AinkradAppKit"),
            ]
        ),
        .testTarget(
            name: "AinkradKitTests",
            dependencies: ["ainkrad"]
        ),
    ]
)
