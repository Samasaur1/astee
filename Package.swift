// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "astee",
    platforms: [.macOS(.v10_15)],
    dependencies: [
        .package(url: "https://github.com/swhitty/FlyingFox", from: "0.17.0"),
        // .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "astee",
            dependencies: [
                .product(name: "FlyingSocks", package: "FlyingFox"),
                // .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
