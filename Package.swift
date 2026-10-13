// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "BarFold", platforms: [.macOS(.v14)],
    products: [.executable(name: "BarFold", targets: ["BarFold"])],
    targets: [
        .target(name: "BarFoldCore"),
        .executableTarget(name: "BarFold", dependencies: ["BarFoldCore"]),
        .executableTarget(name: "BarFoldCoreChecks", dependencies: ["BarFoldCore"], path: "Tests/BarFoldCoreChecks")
    ]
)
