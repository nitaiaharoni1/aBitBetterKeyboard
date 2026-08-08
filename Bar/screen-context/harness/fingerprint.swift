// Scores the *shipping* frame fingerprint against the §5.5 acceptance criteria.
//
// `frame-hash.mjs` decided which band and which value the design should use, in
// JavaScript, with the browser's resampler. This harness asks the different and
// narrower question: does the Swift that actually runs inside the broadcast
// extension reach the same two zeros? It compiles
// `Packages/AIKeyboardCore/Sources/AIKeyboardShared/FrameFingerprint.swift`
// itself rather than a copy, so the numbers below cannot drift away from the
// code that produces them.
//
// Driven by `run-fingerprint.sh`, which renders the frames if they are missing.
// Fails rather than skips: a missing render, an image that will not decode or a
// reduction that comes back the wrong size all exit non-zero.

import CoreGraphics
import Foundation
import ImageIO

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: fingerprint <frame-hash-out dir>\n".utf8))
    exit(2)
}
let directory = URL(fileURLWithPath: arguments[1])

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(3)
}

// MARK: - Decoding

/// One decoded frame, as the bytes `FrameReduction` expects: a tightly packed
/// BGRA bitmap, which is the layout ReplayKit delivers on this device.
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

func fingerprint(_ frame: Frame) -> FrameFingerprint {
    let value = frame.pixels.withUnsafeBytes { raw -> FrameFingerprint? in
        FrameFingerprint.make(
            base: raw.baseAddress!, width: frame.width, height: frame.height,
            bytesPerRow: frame.bytesPerRow, format: .bgra8888)
    }
    guard let value else { die("the reduction refused a \(frame.width)x\(frame.height) frame") }
    return value
}

// MARK: - Run

let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
let scenes = Set(
    names.filter { $0.hasSuffix("-base.png") }.map { String($0.dropLast("-base.png".count)) }
).sorted()
guard scenes.count >= 30 else {
    die("expected 30 rendered scenes in \(directory.path), found \(scenes.count)")
}

var misses: [String] = []
var falseInvalidations: [String] = []
var occluded: [String] = []
var twinCollisions: [String] = []
var settleMisses: [String] = []
var identities: [String: FrameIdentity] = [:]

for scene in scenes {
    func load(_ tag: String) -> Frame {
        let url = directory.appendingPathComponent("\(scene)-\(tag).png")
        guard FileManager.default.fileExists(atPath: url.path) else {
            die("missing render \(url.lastPathComponent)")
        }
        return decode(url)
    }

    let base = load("base")
    let last = load("last")
    let chrome = load("chrome")
    let twin = load("twin")

    // A frame whose newest message is drawn under the host keyboard has no
    // pixels to change, so its two renders are byte-identical and no
    // fingerprint of any width can separate them. That is a property of the
    // screen, and it is counted apart rather than scored against the design.
    if base.pixels == last.pixels {
        occluded.append(scene)
    }

    let baseValue = fingerprint(base)
    let lastValue = fingerprint(last)
    let chromeValue = fingerprint(chrome)
    let twinValue = fingerprint(twin)

    identities[scene] = baseValue.identity

    if !occluded.contains(scene) {
        if baseValue.identity == lastValue.identity { misses.append(scene) }
        if baseValue.identity == twinValue.identity { twinCollisions.append(scene) }
        if baseValue.settleHash == lastValue.settleHash { settleMisses.append(scene) }
    }
    if baseValue.identity != chromeValue.identity { falseInvalidations.append(scene) }
}

// Two different scenes must never share an identity either; that would be the
// same failure as a miss, arriving from the other direction.
var crossCollisions: [String] = []
for (a, identityA) in identities {
    for (b, identityB) in identities where a < b && identityA == identityB {
        crossCollisions.append("\(a)/\(b)")
    }
}

let separable = scenes.count - occluded.count
print("deployment   macOS host, shipping FrameFingerprint.swift, \(scenes.count) scenes x 4 renders")
print(
    "band         top \(FrameReduction.Band.top) / bottom \(FrameReduction.Band.bottom), reduced to \(FrameReduction.columns)x\(FrameReduction.rows) greyscale"
)
print("occluded     \(occluded.isEmpty ? "none" : occluded.joined(separator: " "))")
print("")
print("value           miss   false")
print("identity       \(misses.count)/\(separable)    \(falseInvalidations.count)/\(scenes.count)")
print(
    "settleHash    \(settleMisses.count)/\(separable)    (64-bit dHash, the settle gate's value, not the identity's)"
)
print("")

var failed = false
func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  PASS \(message)")
    } else {
        print("  FAIL \(message)")
        failed = true
    }
}

check(
    misses.isEmpty,
    "0 misses: every conversation switch moves the identity"
        + (misses.isEmpty ? "" : " — collided on \(misses.joined(separator: " "))"))
check(
    falseInvalidations.isEmpty,
    "0 false invalidations: the clock and the presence line do not move it"
        + (falseInvalidations.isEmpty
            ? "" : " — moved on \(falseInvalidations.joined(separator: " "))"))
check(
    crossCollisions.isEmpty,
    "no two scenes share an identity"
        + (crossCollisions.isEmpty ? "" : " — \(crossCollisions.joined(separator: " "))"))
check(
    twinCollisions.isEmpty,
    "a wholly different conversation is never the same identity")
check(
    occluded == ["sl-05"],
    "sl-05 is the only occluded scene, as frame-hash.mjs reports (got \(occluded))")
check(
    settleMisses.count >= 1,
    "the 64-bit settle hash still collides, which is why it is not the identity"
        + " (\(settleMisses.count)/\(separable))")

exit(failed ? 1 : 0)
