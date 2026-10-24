// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "MyMusic",
  defaultLocalization: "zh-Hans",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "MyMusic", targets: ["MyMusic"]),
    .executable(name: "MusicSourceHost", targets: ["MusicSourceHost"]),
  ],
  targets: [
    .target(
      name: "MusicCore", resources: [.process("Resources")], linkerSettings: [.linkedLibrary("z")]),
    .executableTarget(name: "MyMusic", dependencies: ["MusicCore"]),
    .executableTarget(
      name: "MusicSourceHost", resources: [.copy("bridge.js")],
      linkerSettings: [.linkedLibrary("z")]),
    .testTarget(name: "MusicCoreTests", dependencies: ["MusicCore"]),
    .testTarget(name: "MyMusicUITests", dependencies: ["MyMusic"]),
  ],
  swiftLanguageModes: [.v5]
)
