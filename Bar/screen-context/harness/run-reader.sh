#!/bin/bash
# Compiles the shipping VisionScreenReader against the bar and scores it.
#
# Compiles the real source files rather than a copy, so a change to the reader's
# geometry shows up here rather than drifting away from the numbers in README.md.
#
# macOS is the host, and that is a limitation rather than a convenience. Vision
# does NOT behave identically on both platforms: measured over these 30 images,
# this script accepts 9 screens and answers 5, all 5 right, while the same
# sources run on the simulator by AIKeyboardCoreTests/ScreenContextBarTests
# accept 10 and answer 7, three of them wrong. Treat what follows as the macOS
# reading of the reader; the shipping number is the one from the simulator.
# VisionLanguageTests pins the iOS language list separately.
set -euo pipefail
cd /Users/nitai/REPOS/ai-keyboard/Bar/screen-context/harness
core=../../../Packages/AIKeyboardCore/Sources/AIKeyboardCore
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
cp "$core/ScreenReader.swift" "$core/VisionScreenReader.swift" "$core/LanguageDetector.swift" "$build/"
printf 'import Foundation\npublic enum KeyboardLanguage: String, Sendable { case english, hebrew }\npublic enum AIProvenance: Sendable, Equatable { case onDevice, cloud, onDeviceBestEffort\n  public var isBestEffort: Bool { self == .onDeviceBestEffort } }\npublic struct AIOutput<Value: Sendable>: Sendable { public let value: Value; public let provenance: AIProvenance\n  public init(_ v: Value, provenance: AIProvenance) { value = v; self.provenance = provenance } }\n' > "$build/Support.swift"
cp reader.swift "$build/main.swift"
xcrun -sdk macosx swiftc -O "$build"/*.swift -o "$build/reader" 2>&1 | grep -E "error" | head -20 || true
"$build/reader" ../ground-truth.json ../reader_outputs.json
