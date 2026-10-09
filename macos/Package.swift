// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "BunchOfKeys",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "bunch-of-keys", targets: ["BunchOfKeys"])],
    targets: [.executableTarget(name: "BunchOfKeys")],
    swiftLanguageModes: [.v5]
)
