// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "MCPHarbor",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "MCPHarbor", targets: ["MCPHarbor"])],
    targets: [
        .executableTarget(name: "MCPHarbor"),
        .testTarget(name: "MCPHarborTests", dependencies: ["MCPHarbor"])
    ],
    swiftLanguageModes: [.v5]
)
