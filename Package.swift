// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "OneCapCore",
  platforms: [.macOS(.v26)],
  products: [.library(name: "OneCapCore", targets: ["OneCapCore"])],
  dependencies: [
    .package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.20.0"),
    .package(url: "https://github.com/appstefan/HighlightSwift.git", exact: "1.1.0"),
  ],
  targets: [
    .target(
      name: "OneCapCore", dependencies: ["HighlightSwift"], path: "OneCap",
      exclude: [
        "Views", "ContentView.swift", "MyApp.swift", "Assets.xcassets",
        "Services/WorkspaceFolderPicker.swift",
      ],
      resources: [.process("Resources")]),
    .testTarget(
      name: "OneCapCoreTests",
      dependencies: ["OneCapCore", .product(name: "SwiftTerm", package: "SwiftTerm")],
      path: "Tests/OneCapCoreTests"),
  ]
)
