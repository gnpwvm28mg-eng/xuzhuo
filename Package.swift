// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "XuZhuo",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "XuZhuo", targets: ["XuZhuo"])],
    targets: [
        .executableTarget(name: "XuZhuo", path: "Sources/XuZhuo"),
        .testTarget(name: "XuZhuoTests", dependencies: ["XuZhuo"], path: "Tests/XuZhuoTests")
    ],
    swiftLanguageVersions: [.v5]
)
