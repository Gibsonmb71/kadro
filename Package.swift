// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Kadro",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Kadro", targets: ["Kadro"])
    ],
    targets: [
        .executableTarget(
            name: "Kadro",
            path: "Sources/PhotoEditor",
            exclude: [
                "Resources/Assets.xcassets",
                "Resources/AppIcon.icon"
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
