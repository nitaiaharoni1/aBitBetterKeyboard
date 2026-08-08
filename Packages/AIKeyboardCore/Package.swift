// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIKeyboardCore",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "AIKeyboardCore", targets: ["AIKeyboardCore"]),
        // Linked on its own by the broadcast upload extension, which must never
        // link `AIKeyboardCore`: that target imports SwiftUI and UIKit from a
        // dozen files, and dragging both into a process capped at ~50 MB buys
        // nothing. `AIKeyboardShared` is Foundation and CryptoKit only.
        .library(name: "AIKeyboardShared", targets: ["AIKeyboardShared"])
    ],
    targets: [
        // Seqlock fences. See Sources/CaptureAtomics/include/CaptureAtomics.h for
        // why they cannot be written in Swift on this toolchain.
        .target(name: "CaptureAtomics"),
        .target(name: "AIKeyboardShared", dependencies: ["CaptureAtomics"]),
        .target(name: "AIKeyboardCore", dependencies: ["AIKeyboardShared"])
    ]
)
