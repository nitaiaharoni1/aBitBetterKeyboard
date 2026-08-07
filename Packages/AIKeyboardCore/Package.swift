// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIKeyboardCore",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "AIKeyboardCore", targets: ["AIKeyboardCore"])
    ],
    targets: [
        .target(name: "AIKeyboardCore")
    ]
)
