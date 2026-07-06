// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PulseSDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(name: "PulseSDK", targets: ["PulseSDK"])
    ],
    targets: [
        .target(
            name: "PulseSDK",
            path: "ios/Sources/PulseSDK"
        ),
        .testTarget(
            name: "PulseSDKTests",
            dependencies: ["PulseSDK"],
            path: "ios/Tests/PulseSDKTests",
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
