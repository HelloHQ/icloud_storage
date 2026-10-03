// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "ICloudDownloadTests",
  platforms: [.macOS(.v10_14)],
  targets: [
    .target(name: "ICloudDownload"),
    .testTarget(name: "ICloudDownloadTests", dependencies: ["ICloudDownload"]),
  ]
)
