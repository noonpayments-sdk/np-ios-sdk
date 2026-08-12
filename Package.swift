// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NPMobileSDKUI",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "NPMobileSDKUI",
            targets: ["NPMobileSDKUI"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "SharedLogic",
            path: "NPMobileSDKUI/SharedLogic.xcframework"
        ),
        .target(
            name: "NPMobileSDKUI",
            dependencies: ["SharedLogic"],
            path: "NPMobileSDKUI/Sources/NPMobileSDKUI"
        )
    ]
)
