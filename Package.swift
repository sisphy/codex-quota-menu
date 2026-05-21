// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ChatGPTQuotaMenu",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ChatGPTQuotaMenu", targets: ["ChatGPTQuotaMenu"])
    ],
    targets: [
        .executableTarget(
            name: "ChatGPTQuotaMenu",
            path: "Sources/ChatGPTQuotaMenu",
            exclude: [
                "Resources/casio-design-reference.png"
            ],
            resources: [
                .process("Resources/casio-skin.png"),
                .process("Resources/casio-skin-normal.png"),
                .process("Resources/casio-skin-bonus.png"),
                .process("Resources/casio-skin-caution.png"),
                .process("Resources/casio-skin-danger.png")
            ]
        ),
        .testTarget(
            name: "ChatGPTQuotaMenuTests",
            dependencies: ["ChatGPTQuotaMenu"],
            path: "Tests/ChatGPTQuotaMenuTests"
        )
    ]
)
