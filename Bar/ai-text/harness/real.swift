// Runs the real engine over corpus.json and writes real_outputs.json in exactly
// the shape mock_outputs.json uses, so the two can be diffed directly.
//
// It runs on macOS, not in the simulator, and that is not a shortcut: every iOS
// Simulator reports `SystemLanguageModel.availability == .available` and then
// throws `ModelManagerError 1026` on the first `respond` call, because no
// simulator runtime ships model assets. macOS 26 runs the same on-device model
// for real, so this is the only place the engine can actually be measured.
//
// Compiled against verbatim copies of the engine sources (see run-real.sh),
// because AIKeyboardCore does not build for macOS — Feedback.swift imports UIKit.
//
//   ./run-real.sh          # writes real_outputs.json and real_outputs.meta.json

import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    FileHandle.standardError.write(Data("usage: real <corpus.json> <out.json> <meta.json>\n".utf8))
    exit(2)
}

let corpusURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
let metaURL = URL(fileURLWithPath: arguments[3])

let root = try JSONSerialization.jsonObject(with: Data(contentsOf: corpusURL)) as! [String: Any]
let entries = root["entries"] as! [[String: Any]]

func language(_ name: String) -> KeyboardLanguage {
    name == "hebrew" ? .hebrew : .english
}

func tone(_ name: String) -> ToneStyle {
    ToneStyle(rawValue: name) ?? .clearer
}

func describe(_ provenance: AIProvenance) -> String {
    switch provenance {
    case .onDevice: return "on-device"
    case .cloud: return "cloud"
    case .onDeviceBestEffort: return "on-device-best-effort"
    }
}

// The cloud half is Vertex, called directly from this machine with a gcloud
// token. That is a scoring arrangement, not the shipping one: the app talks to
// a backend instead (BackendTransport), because a keyboard cannot hold a cloud
// credential. Without a token the run degrades to on-device only and every
// Hebrew entry reports that, which is what the app does today.
let vertex = VertexTransport.fromEnvironment()
if vertex == nil {
    FileHandle.standardError.write(
        Data("no VERTEX_ACCESS_TOKEN: running on-device only\n".utf8))
}
let engine = RoutedIntelligence.standard(
    cloud: vertex.map { CloudIntelligence(transport: $0) },
    deadline: .seconds(120)
)

var results: [String: Any] = [:]
var meta: [String: Any] = [:]

func record(_ id: String, _ provenance: AIProvenance, _ elapsed: TimeInterval) {
    meta[id] = ["provenance": describe(provenance), "seconds": (elapsed * 100).rounded() / 100]
}

func record(_ id: String, failure: Error) {
    let described: String
    if let error = failure as? AIEngineError {
        described = "\(error.title): \(error.message)"
    } else {
        described = String(describing: failure)
    }
    meta[id] = ["error": described]
    FileHandle.standardError.write(Data("[\(id)] \(described)\n".utf8))
}

for entry in entries {
    let id = entry["id"] as! String
    let action = entry["action"] as! String
    let start = Date()

    do {
        switch action {
        case "fix":
            let output = try await engine.fix(entry["input"] as! String)
            results[id] = output.value
            record(id, output.provenance, Date().timeIntervalSince(start))

        case "rewrite":
            let output = try await engine.variants(for: entry["input"] as! String, tone: nil)
            results[id] = output.value.map {
                ["tone": $0.tone.rawValue, "label": $0.label ?? "", "text": $0.text]
            }
            record(id, output.provenance, Date().timeIntervalSince(start))

        case "tone":
            let style = tone(entry["tone"] as! String)
            let output = try await engine.variants(for: entry["input"] as! String, tone: style)
            results[id] = output.value.map {
                ["tone": $0.tone.rawValue, "label": $0.label ?? "", "text": $0.text]
            }
            record(id, output.provenance, Date().timeIntervalSince(start))

        case "reply":
            let raw = entry["context"] as! [String: Any]
            let context = ScreenContext(
                appName: raw["app"] as! String,
                appIcon: "message.fill",
                sender: raw["sender"] as! String,
                message: raw["message"] as! String,
                language: language(raw["language"] as! String)
            )
            let output = try await engine.replies(to: context)
            results[id] = output.value.map { ["intent": $0.intent, "text": $0.text] }
            record(id, output.provenance, Date().timeIntervalSince(start))

        default:
            FileHandle.standardError.write(Data("unknown action \(action) on \(id)\n".utf8))
            exit(1)
        }
        print("\(id) ok")
    } catch {
        // A failed entry is a result too: an engine that refuses a third of the
        // corpus has to show that in the output rather than crash the run.
        record(id, failure: error)
        results[id] = NSNull()
    }
}

for (url, payload) in [(outputURL, results), (metaURL, meta)] {
    let json = try JSONSerialization.data(
        withJSONObject: payload,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    )
    try json.write(to: url)
}
print("wrote \(results.count) results to \(outputURL.path)")
