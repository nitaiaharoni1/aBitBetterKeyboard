// Runs Apple's Vision OCR over the screen-context bar and writes vision_outputs.json.
//
// This measures the *foundation* of the on-device path, not a finished engine:
// if Vision cannot read the pixels, no parser stacked on top recovers the text.
// Scored as character recall of the expected message inside the OCR output.
//
// macOS is the right host: Vision ships the same recognition models on both
// platforms, and VisionLanguageTests proves the iOS language list matches.

import CoreGraphics
import Foundation
import ImageIO
import Vision

struct Entry: Decodable {
    let id: String
    let file: String
    let language: String
    let expected: Expected?

    struct Expected: Decodable {
        let sender: String?
        let message: String?
        let language: String?
    }
}

struct GroundTruth: Decodable { let images: [Entry] }

struct Output: Encodable {
    let id: String
    let language: String
    let config: String
    let text: String
    let observations: Int
    let meanConfidence: Double
    let seconds: Double
}

func loadImage(_ url: URL) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

func recognize(_ image: CGImage, languages: [String]) throws -> (String, Int, Double) {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = languages
    request.automaticallyDetectsLanguage = true

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])

    let observations = request.results ?? []
    let candidates = observations.compactMap { $0.topCandidates(1).first }
    let text = candidates.map(\.string).joined(separator: "\n")
    let mean =
        candidates.isEmpty
        ? 0 : Double(candidates.map { Double($0.confidence) }.reduce(0, +)) / Double(candidates.count)
    return (text, candidates.count, mean)
}

// MARK: - main

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: vision <ground-truth.json> <out.json>\n".utf8))
    exit(2)
}
let truthURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])
let root = truthURL.deletingLastPathComponent()

let truth = try JSONDecoder().decode(GroundTruth.self, from: Data(contentsOf: truthURL))

// Two configurations. Hebrew is not in supportedRecognitionLanguages at all, so
// the second exists only to check whether the nearest available RTL model picks
// up anything a Hebrew screen contains.
let configs: [(String, [String])] = [
    ("en", ["en-US"]),
    ("en+ar", ["en-US", "ar-SA"])
]

var outputs: [Output] = []
for entry in truth.images {
    guard let image = loadImage(root.appendingPathComponent(entry.file)) else {
        FileHandle.standardError.write(Data("missing image: \(entry.file)\n".utf8))
        continue
    }
    for (name, languages) in configs {
        let started = Date()
        let (text, count, mean) = (try? recognize(image, languages: languages)) ?? ("", 0, 0)
        outputs.append(
            Output(
                id: entry.id,
                language: entry.language,
                config: name,
                text: text,
                observations: count,
                meanConfidence: mean,
                seconds: Date().timeIntervalSince(started)))
    }
    FileHandle.standardError.write(Data(".".utf8))
}
FileHandle.standardError.write(Data("\n".utf8))

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
try encoder.encode(outputs).write(to: outURL)
print("wrote \(outputs.count) results to \(outURL.path)")
