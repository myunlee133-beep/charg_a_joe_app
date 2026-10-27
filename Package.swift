// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CampusCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "CampusCore", targets: ["CampusCore"])],
    targets: [
        .target(name: "CampusCore", path: "ios/Chajajwo/Core", resources: [.process("Resources")]),
        .testTarget(name: "CampusCoreTests", dependencies: ["CampusCore"], path: "ios/Tests/CampusCoreTests")
    ]
)
