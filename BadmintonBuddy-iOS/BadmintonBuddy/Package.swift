// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BadmintonBuddy",
    platforms: [.iOS(.v17)],
    dependencies: [
        .package(url: "https://github.com/airbnb/lottie-ios.git", from: "4.4.0"),
        // SwiftCheck for property-based testing (PBT)
        // Used to verify correctness properties across randomly generated inputs
        .package(url: "https://github.com/typelift/SwiftCheck.git", from: "0.14.0")
    ],
    targets: [
        .target(
            name: "BadmintonBuddy",
            dependencies: [
                .product(name: "Lottie", package: "lottie-ios")
            ]
        ),
        // Test target for unit tests and property-based tests
        .testTarget(
            name: "BadmintonBuddyTests",
            dependencies: [
                "BadmintonBuddy",
                .product(name: "SwiftCheck", package: "SwiftCheck")
            ]
        )
    ]
)
