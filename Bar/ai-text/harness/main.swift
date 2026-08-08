// Runs the real MockAI over corpus.json and prints what it produces, so the
// mock_output field in the corpus is measured rather than guessed.
//
// It is compiled against verbatim copies of Models.swift and MockIntelligence.swift
// (see run.sh), because AIKeyboardCore itself does not build for macOS: Feedback.swift
// imports UIKit. Nothing here reimplements the mock; if the mock changes, rerun run.sh.
//
//   ./run.sh            # writes mock_outputs.json next to corpus.json

import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: harness <corpus.json> <out.json>\n".utf8))
    exit(2)
}

let corpusURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

let root = try JSONSerialization.jsonObject(with: Data(contentsOf: corpusURL)) as! [String: Any]
let entries = root["entries"] as! [[String: Any]]

func language(_ name: String) -> KeyboardLanguage {
    name == "hebrew" ? .hebrew : .english
}

func tone(_ name: String) -> ToneStyle {
    ToneStyle(rawValue: name) ?? .clearer
}

var results: [String: Any] = [:]

for entry in entries {
    let id = entry["id"] as! String
    let action = entry["action"] as! String

    switch action {
    case "fix":
        results[id] = MockAI.fix(entry["input"] as! String)

    case "rewrite":
        results[id] = MockAI.variants(for: entry["input"] as! String)
            .map { ["tone": $0.tone.rawValue, "text": $0.text] }

    case "tone":
        let style = tone(entry["tone"] as! String)
        results[id] = MockAI.variants(for: entry["input"] as! String, tone: style)
            .map { ["tone": $0.tone.rawValue, "text": $0.text] }

    case "reply":
        let raw = entry["context"] as! [String: Any]
        let context = ScreenContext(
            appName: raw["app"] as! String,
            appIcon: "message.fill",
            sender: raw["sender"] as! String,
            message: raw["message"] as! String,
            language: language(raw["language"] as! String)
        )
        results[id] = MockAI.replies(to: context)
            .map { ["intent": $0.intent, "text": $0.text] }

    default:
        FileHandle.standardError.write(Data("unknown action \(action) on \(id)\n".utf8))
        exit(1)
    }
}

let json = try JSONSerialization.data(
    withJSONObject: results,
    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
)
try json.write(to: outputURL)
print("wrote \(results.count) results to \(outputURL.path)")
