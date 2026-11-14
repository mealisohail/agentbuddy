// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AgentBuddy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "AgentBuddy", path: "Sources/AgentBuddy")
    ]
)
