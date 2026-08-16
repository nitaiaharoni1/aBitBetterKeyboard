// Scores the *shipping* frame fingerprint over landscape frames.
//
// `fingerprint.swift` is the portrait twin of this and the two are deliberately
// separate files rather than one with a flag: the portrait one carries the §5.5
// acceptance criteria — `occluded == ["sl-05"]`, a shimmer witness of at least
// 25 — and none of those hold on a rotated screen, where our keyboard is 166 pt
// rather than 365 and the moving part is a chip rather than a banner. Folding
// them together would mean loosening the portrait checks to let landscape pass,
// which is the one thing a harness must never do.
//
// The question here is narrower. `frame-hash-landscape.mjs` already swept the
// six shipping landscape heights in Chromium; this asks whether the Swift that
// runs inside the broadcast extension agrees, by compiling
// `Packages/AIKeyboardCore/Sources/AIKeyboardShared/FrameFingerprint.swift`
// itself and reducing with CoreGraphics decoding and the shipping integer box
// filter instead of the browser's resampler. A result that only holds with one
// resampler is not a result.
//
// Driven by `run-fingerprint-landscape.sh`.

import CoreGraphics
import Foundation
import ImageIO

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(
        Data("usage: fingerprint-landscape <frame-hash-landscape-out dir>\n".utf8))
    exit(2)
}
let directory = URL(fileURLWithPath: arguments[1])

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(3)
}

// MARK: - Decoding

struct Frame {
    let pixels: [UInt8]
    let width: Int
    let height: Int
    var bytesPerRow: Int { width * 4 }
}

func decode(_ url: URL) -> Frame {
    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { die("could not decode \(url.lastPathComponent)") }

    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let info =
        CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
    pixels.withUnsafeMutableBytes { raw in
        guard
            let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)
        else { die("could not make a bitmap context for \(url.lastPathComponent)") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return Frame(pixels: pixels, width: width, height: height)
}

func fingerprint(_ frame: Frame, bottomCrop: Double) -> FrameFingerprint {
    let value = frame.pixels.withUnsafeBytes { raw -> FrameFingerprint? in
        FrameFingerprint.make(
            base: raw.baseAddress!, width: frame.width, height: frame.height,
            bytesPerRow: frame.bytesPerRow, format: .bgra8888, bottomCrop: bottomCrop)
    }
    guard let value else { die("the reduction refused a \(frame.width)x\(frame.height) frame") }
    return value
}

// MARK: - What landscape publishes

/// `Theme.Metrics.totalHeight(for:showsBanner:orientation: .landscape)`.
///
/// 0 (no banner, at any `showsBanner`) + 30 (`Landscape.suggestionBarHeight`)
/// + 136 (`26 * 4 + 8 * 3 + 4 + 4`). Restated rather than imported because this
/// harness compiles one file out of `AIKeyboardShared` and `Theme` is not in it;
/// `LandscapeGeometryTests.testLandscapeTotalHeightIsExact` is what holds the
/// two together.
let landscapeOwnUIPoints = 166.0

/// `SuggestionBar.chipSize(for: .landscape).height` is 26 in a 30 pt row, so a
/// chip's own top edge sits 2 pt below the top of our keyboard. That 2 pt is the
/// whole threshold: an overspend smaller than it leaves only bar background in
/// the band, and an overspend larger than it puts `ControlSweep` in there.
let chipInsetFromOurTop = 2.0

// MARK: - Run

let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []

/// Renders are named `<height>-<scene>-<tag>.png`.
let heights = Set(
    names.filter { $0.hasSuffix("-base.png") }.compactMap { name -> Int? in
        Int(name.split(separator: "-").first.map(String.init) ?? "")
    }
).sorted()
guard !heights.isEmpty else { die("no renders in \(directory.path); run frame-hash-landscape.mjs KEEP=1") }

print("deployment   macOS host, shipping FrameFingerprint.swift and FrameReduction.swift")
print("our keyboard \(Int(landscapeOwnUIPoints)) pt, whatever the screen measures (Theme.Metrics.Landscape)")
print(
    "cap          FrameReduction.Band.maximumOwnUI = \(String(format: "%.4f", FrameReduction.Band.maximumOwnUI))"
)
print("")
print("height   ours     crop    ours left in band   own miss   own false")

var failed = false
for height in heights {
    let scenes = Set(
        names.filter { $0.hasPrefix("\(height)-") && $0.hasSuffix("-base.png") }
            .map { String($0.dropFirst("\(height)-".count).dropLast("-base.png".count)) }
    ).sorted()
    guard scenes.count >= 30 else {
        die("expected 30 scenes at \(height) pt, found \(scenes.count)")
    }

    let ourFraction = landscapeOwnUIPoints / Double(height)
    // The producer's own call, so a change to `bottomCrop` scores here without
    // this file being touched.
    let crop = FrameReduction.bottomCrop(ownUI: ourFraction)
    let leftInBand = max(0, (ourFraction - crop) * Double(height))

    var ownMisses: [String] = []
    var ownFalse: [String] = []
    var ownOccluded: [String] = []

    for scene in scenes {
        func load(_ tag: String) -> Frame {
            let url = directory.appendingPathComponent("\(height)-\(scene)-\(tag).png")
            guard FileManager.default.fileExists(atPath: url.path) else {
                die("missing render \(url.lastPathComponent)")
            }
            return decode(url)
        }
        let panel = load("panel")
        let panel2 = load("panel2")
        let panelLast = load("panellast")

        if panel.pixels == panelLast.pixels {
            ownOccluded.append(scene)
        }
        let panelValue = fingerprint(panel, bottomCrop: crop)
        let panel2Value = fingerprint(panel2, bottomCrop: crop)
        let panelLastValue = fingerprint(panelLast, bottomCrop: crop)

        if !ownOccluded.contains(scene), panelValue.identity == panelLastValue.identity {
            ownMisses.append(scene)
        }
        if panelValue.identity != panel2Value.identity { ownFalse.append(scene) }
    }

    let separable = scenes.count - ownOccluded.count
    print(
        "\(String(height).padding(toLength: 9, withPad: " ", startingAt: 0))"
            + "\(String(format: "%.2f%%", ourFraction * 100).padding(toLength: 9, withPad: " ", startingAt: 0))"
            + "\(String(format: "%.2f%%", crop * 100).padding(toLength: 8, withPad: " ", startingAt: 0))"
            + "\(String(format: "%.1f pt", leftInBand).padding(toLength: 20, withPad: " ", startingAt: 0))"
            + "\(("\(ownMisses.count)/\(separable)").padding(toLength: 11, withPad: " ", startingAt: 0))"
            + "\(ownFalse.count)/\(scenes.count)")

    // The one criterion this harness exists to check, and the threshold is
    // measured rather than assumed: our own `ControlSweep` must not be inside
    // the band the fingerprint is taken over.
    let sweepIsInTheBand = leftInBand > chipInsetFromOurTop
    if sweepIsInTheBand && ownFalse.isEmpty {
        print(
            "  note  \(height) pt puts \(String(format: "%.1f", leftInBand)) pt of our bar in the band and nothing moved; the sweep may not have been drawn"
        )
    }
    if !ownFalse.isEmpty {
        failed = true
        print(
            "  FAIL  \(height) pt: our own Reply sweep moves the identity on \(ownFalse.count) of \(scenes.count) frames"
        )
        print("        \(ownFalse.joined(separator: " "))")
    }
}

print("")
print(
    failed
        ? "FAIL  a landscape height retires its own reading: the freshness gate discards the answer to the tap that paid for it"
        : "PASS  no landscape height is invalidated by our own sweep")
exit(failed ? 1 : 0)
