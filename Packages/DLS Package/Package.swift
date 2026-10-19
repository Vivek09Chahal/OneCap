// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "DLS Package",
  platforms: [.macOS(.v14), .iOS(.v17)],
  products: [.library(name: "DLS", targets: ["DLS"])],
  targets: [.target(name: "DLS")]
)
