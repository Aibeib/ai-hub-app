// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AI-Agent-Hub",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "AIAgentHubCore",
            targets: ["AIAgentHubCore"]
        ),
        .executable(
            name: "AIAgentHubCoreValidation",
            targets: ["AIAgentHubCoreValidation"]
        )
    ],
    targets: [
        .target(
            name: "AIAgentHubCore"
        ),
        .executableTarget(
            name: "AIAgentHubCoreValidation",
            dependencies: ["AIAgentHubCore"]
        )
    ]
)
