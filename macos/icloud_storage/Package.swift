// swift-tools-version: 5.9
// HELLOHQ FORK — Swift Package Manager support.
//
// Upstream (deansyd/icloud_storage, last commit 2023-01-06) ships podspecs
// only, so Flutter warns "does not support Swift Package Manager ... this will
// become an error in a future version". The podspecs are kept alongside and
// point at these same sources, so CocoaPods and SwiftPM both build.
import PackageDescription

let package = Package(
    name: "icloud_storage",
    platforms: [
        .macOS("10.14")
    ],
    products: [
        // "_" becomes "-" in the library name, per the Flutter plugin convention.
        .library(name: "icloud-storage", targets: ["icloud_storage"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "icloud_storage",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
