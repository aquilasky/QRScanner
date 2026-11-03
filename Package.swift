// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QRScanner",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "QRScanner", targets: ["QRScanner"])],
    targets: [
        .executableTarget(name: "QRScanner"),
        .testTarget(name: "QRScannerTests", dependencies: ["QRScanner"])
    ]
)
