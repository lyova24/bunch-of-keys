// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Keepy",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Keepy", targets: ["BunchOfKeys"])],
    targets: [.executableTarget(name: "BunchOfKeys")],
    swiftLanguageModes: [.v5]
)
