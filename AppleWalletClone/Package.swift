// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AppleWalletClone",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "AppleWalletClone",
            targets: ["AppleWalletClone"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AppleWalletClone",
            dependencies: [],
            path: "Sources",
            exclude: ["Resources/AppStoreAssets"]
        ),
        .testTarget(
            name: "AppleWalletCloneTests",
            dependencies: ["AppleWalletClone"]
        ),
    ]
)
