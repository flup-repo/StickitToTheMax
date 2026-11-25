// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StickitToTheMax",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "StickitToTheMax", targets: ["StickitToTheMax"])
    ],
    targets: [
        .executableTarget(
            name: "StickitToTheMax",
            path: "Sources/StickitToTheMax",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "StickitToTheMaxTests",
            dependencies: ["StickitToTheMax"],
            path: "Tests/StickitToTheMaxTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
