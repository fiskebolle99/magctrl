// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "magctrl",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "magctrl", targets: ["magctrl"]),
    .library(name: "MagCtrlCore", targets: ["MagCtrlCore"]),
    .library(name: "MagCtrlSMC", targets: ["MagCtrlSMC"]),
  ],
  targets: [
    .target(name: "MagCtrlCore"),
    .target(
      name: "MagCtrlSMC",
      dependencies: ["MagCtrlCore"],
      linkerSettings: [.linkedFramework("IOKit")]
    ),
    .executableTarget(
      name: "magctrl",
      dependencies: ["MagCtrlCore", "MagCtrlSMC"]
    ),
    .testTarget(
      name: "MagCtrlCoreTests",
      dependencies: ["MagCtrlCore"]
    ),
    .testTarget(
      name: "MagCtrlSMCTests",
      dependencies: ["MagCtrlCore", "MagCtrlSMC"]
    ),
  ]
)
