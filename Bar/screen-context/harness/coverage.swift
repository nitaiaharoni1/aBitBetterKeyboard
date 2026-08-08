// Measures whether Vision knows it missed something.
//
// The routing question at runtime is not "is this screen Hebrew" — nothing
// on-device can answer that, because the only tool that reads text is the one
// that is blind to the script. It is "did the recogniser read everything that
// looks like text?" Vision can answer that: rectangle detection finds text
// regions by shape alone, with no idea what language they are in, so a screen
// where many regions produce no recognised string is a screen holding text
// Vision cannot read.

import CoreGraphics
import Foundation
import ImageIO
import Vision

struct Entry: Decodable {
    let id: String
    let file: String
    let language: String
}
struct GroundTruth: Decodable { let images: [Entry] }

struct Row: Encodable {
    let id: String
    let language: String
    let rectangles: Int
    let recognized: Int
    let coverage: Double
    let meanConfidence: Double
    let seconds: Double
}

func loadImage(_ url: URL) -> CGImage? {
    CGImageSourceCreateWithURL(url as CFURL, nil).flatMap {
        CGImageSourceCreateImageAtIndex($0, 0, nil)
    }
}

/// Two boxes overlap enough to call the region "read".
func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
    let intersection = a.intersection(b)
    guard !intersection.isNull else { return false }
    let area = intersection.width * intersection.height
    return area > 0.3 * min(a.width * a.height, b.width * b.height)
}

let args = CommandLine.arguments
let truthURL = URL(fileURLWithPath: args[1])
let root = truthURL.deletingLastPathComponent()
let truth = try JSONDecoder().decode(GroundTruth.self, from: Data(contentsOf: truthURL))

var rows: [Row] = []
for entry in truth.images {
    guard let image = loadImage(root.appendingPathComponent(entry.file)) else { continue }
    let started = Date()

    let rectangles = VNDetectTextRectanglesRequest()
    let recognize = VNRecognizeTextRequest()
    recognize.recognitionLevel = .accurate
    recognize.recognitionLanguages = ["en-US"]
    recognize.automaticallyDetectsLanguage = true

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try? handler.perform([rectangles, recognize])

    let regions = (rectangles.results ?? []).map(\.boundingBox)
    let read = (recognize.results ?? []).map(\.boundingBox)
    let candidates = (recognize.results ?? []).compactMap { $0.topCandidates(1).first }

    let covered = regions.filter { region in read.contains { overlaps(region, $0) } }.count
    let mean =
        candidates.isEmpty
        ? 0 : candidates.map { Double($0.confidence) }.reduce(0, +) / Double(candidates.count)

    rows.append(
        Row(
            id: entry.id,
            language: entry.language,
            rectangles: regions.count,
            recognized: covered,
            coverage: regions.isEmpty ? 1 : Double(covered) / Double(regions.count),
            meanConfidence: mean,
            seconds: Date().timeIntervalSince(started)))
    FileHandle.standardError.write(Data(".".utf8))
}
FileHandle.standardError.write(Data("\n".utf8))

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(rows).write(to: URL(fileURLWithPath: args[2]))
print("wrote \(rows.count) rows")
