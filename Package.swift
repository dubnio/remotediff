// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RemoteDiff",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "RemoteDiff",
            path: "RemoteDiff",
            exclude: ["RemoteDiff.entitlements", "Info.plist"],
            resources: [.process("Assets.xcassets")]
        ),
        .testTarget(
            name: "RemoteDiffTests",
            dependencies: ["RemoteDiff"],
            path: "RemoteDiffTests"
        ),
    ]
)
