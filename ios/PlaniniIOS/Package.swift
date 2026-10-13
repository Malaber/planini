// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlaniniIOS",
    platforms: [
        .iOS("27.0"),
        .watchOS("27.0"),
        .macOS(.v13)
    ],
    products: [
        .library(name: "PlaniniCore", targets: ["PlaniniCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.5.1")
    ],
    targets: [
        .target(
            name: "PlaniniCore",
            path: "Sources/PlaniniCore"
        ),
        .testTarget(
            name: "PlaniniCoreTests",
            dependencies: [
                "PlaniniCore",
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "Tests/PlaniniCoreTests"
        )
    ]
)
