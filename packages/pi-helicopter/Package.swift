// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PiHelicopter",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "pi-helicopter", targets: ["PiHelicopter"])
    ],
    targets: [
        .executableTarget(
            name: "PiHelicopter",
            path: "Sources/PiHelicopter"
        ),
        .testTarget(
            name: "PiHelicopterTests",
            dependencies: ["PiHelicopter"],
            path: "Tests/PiHelicopterTests"
        )
    ]
)
