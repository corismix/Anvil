// swift-tools-version: 6.3

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .define("DEBUG", .when(configuration: .debug)),
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .swiftLanguageMode(.v5),
]

let package = Package(
    name: "Anvil",
    platforms: [
        .macOS("26.0"),
    ],
    products: [
        .executable(name: "Anvil", targets: ["Anvil"]),
    ],
    dependencies: [
        .package(url: "https://github.com/huggingface/AnyLanguageModel", from: "0.8.0"),
        .package(url: "https://github.com/mattt/JSONSchema", from: "1.3.1"),
        .package(url: "https://github.com/vtourraine/AcknowList", from: "3.4.2"),
    ],
    targets: [
        .executableTarget(
            name: "Anvil",
            dependencies: [
                .product(name: "AnyLanguageModel", package: "AnyLanguageModel"),
                .product(name: "JSONSchema", package: "JSONSchema"),
                .product(name: "AcknowList", package: "AcknowList"),
            ],
            path: "Anvil",
            exclude: [
                "Info.plist",
                "Resources",
            ],
            sources: [
                "App",
                "Core",
                "Features",
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AnvilTests",
            dependencies: [
                "Anvil",
                .product(name: "AnyLanguageModel", package: "AnyLanguageModel"),
                .product(name: "AcknowList", package: "AcknowList"),
            ],
            path: "AnvilTests",
            swiftSettings: swiftSettings
        ),
    ]
)
