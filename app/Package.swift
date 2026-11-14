// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "ReturnOfTheMac",
  platforms: [.macOS(.v14)],
  targets: [
    .target(name: "RotmCore"),
    .executableTarget(name: "ReturnOfTheMac", dependencies: ["RotmCore"]),
    .target(
      name: "RotmTestSupport",
      dependencies: ["RotmCore"],
      path: "Tests/RotmTestSupport",
      resources: [.copy("Fixtures")]
    ),
    .testTarget(name: "RotmCoreTests", dependencies: ["RotmCore", "RotmTestSupport"]),
    .testTarget(name: "ReturnOfTheMacTests", dependencies: ["ReturnOfTheMac", "RotmTestSupport"]),
  ],
  swiftLanguageVersions: [.v5]
)
