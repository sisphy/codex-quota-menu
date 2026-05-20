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
            path: "Sources/ChatGPTQuotaMenu"
        ),
        .testTarget(
            name: "ChatGPTQuotaMenuTests",
            dependencies: ["ChatGPTQuotaMenu"],
            path: "Tests/ChatGPTQuotaMenuTests"
        )
    ]
)
