// Scores the shipping VisionScreenReader against the bar.
//
// Compiles the real source files rather than a copy, so a change to the reader
// that breaks the geometry shows up here. Same output shape as
// vertex_vision.py, so score_cloud.py grades both.
//
// `gated` records whether the reader's own readability check accepted the
// screen. A refused screen is not a wrong answer: it is the router's cue to
// spend a cloud call, and the point of the gate is that it refuses every screen
// this path would get wrong.

import CoreGraphics
import Foundation
import ImageIO

struct Entry: Decodable {
    let id: String
    let file: String
    let language: String
}
struct GroundTruth: Decodable { let images: [Entry] }

struct Row: Encodable {
    let id: String
    let language: String
    let config: String
    let gated: Bool
    let sender: String?
    let message: String?
    let detectedScript: String?
    let detectedLanguage: String?
    let coverage: Double
    let meanConfidence: Double
    let seconds: Double
}

let args = CommandLine.arguments
let truthURL = URL(fileURLWithPath: args[1])
let root = truthURL.deletingLastPathComponent()
let truth = try JSONDecoder().decode(GroundTruth.self, from: Data(contentsOf: truthURL))

var rows: [Row] = []
for entry in truth.images {
    guard
        let source = CGImageSourceCreateWithURL(
            root.appendingPathComponent(entry.file) as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { continue }

    let started = Date()
    let page = try VisionScreenReader.recognize(image)
    let passes = page.isTrustworthy(VisionScreenReader.Thresholds())
    let reading = passes ? VisionScreenReader.interpret(page) : nil

    rows.append(
        Row(
            id: entry.id,
            language: entry.language,
            config: "vision-reader",
            gated: passes,
            sender: reading?.sender,
            message: reading?.message,
            detectedScript: reading.map {
                $0.scripts.contains(.hebrew) && $0.scripts.contains(.latin)
                    ? "mixed" : ($0.scripts.contains(.hebrew) ? "hebrew" : "latin")
            },
            detectedLanguage: reading.map { $0.language == .hebrew ? "hebrew" : "english" },
            coverage: page.coverage,
            meanConfidence: page.meanConfidence,
            seconds: Date().timeIntervalSince(started)))
    FileHandle.standardError.write(Data(".".utf8))
}
FileHandle.standardError.write(Data("\n".utf8))

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
try encoder.encode(rows).write(to: URL(fileURLWithPath: args[2]))

let accepted = rows.filter(\.gated)
print("accepted \(accepted.count)/\(rows.count) screens on device")
for language in ["english", "mixed", "hebrew"] {
    let all = rows.filter { $0.language == language }
    print("  \(language): \(all.filter(\.gated).count)/\(all.count)")
}
