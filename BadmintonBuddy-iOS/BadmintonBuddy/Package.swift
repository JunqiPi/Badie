// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BadmintonBuddy",
    platforms: [.iOS(.v17)],
    dependencies: [
        .package(url: "https://github.com/airbnb/lottie-ios.git", from: "4.4.0")
    ],
    targets: [
        .target(
            name: "BadmintonBuddy",
            dependencies: [
                .product(name: "Lottie", package: "lottie-ios")
            ]
        )
    ]
)
