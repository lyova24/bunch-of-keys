// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Keepy",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Keepy", targets: ["Keepy"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [.executableTarget(name: "Keepy", dependencies: [.product(name: "Sparkle", package: "Sparkle")])],
    swiftLanguageModes: [.v5]
)
