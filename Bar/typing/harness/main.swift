// Runs the real SuggestionEngine over Bar/typing/corpus.json and writes what the
// three slots would hold for each of the 90 entries.
//
// **Runs on the iOS Simulator, not on macOS, and that is not a preference.**
// `SuggestionEngine` is built on `UITextChecker`, which is UIKit and therefore
// iOS-only; macOS spells with `NSSpellChecker`, a different API with a different
// dictionary and a different ranking. Scoring the engine against a checker it
// does not ship with would measure the wrong thing. `run.sh` compiles for
// `iphonesimulator` and runs the binary with `xcrun simctl spawn`.
//
// The output is deliberately dumb — ids and strings, no verdicts. `score.py`
// decides what is good, because judging is a separate step that has to be
// re-runnable against a frozen capture.

import Foundation
import UIKit

struct CorpusEntry: Decodable {
    let id: String
    let category: String
    let language: String
    let keyboard: String
    let context: String
    let prefix: String
}

struct CorpusFile: Decodable {
    let entries: [CorpusEntry]
}

struct SlotRecord: Encodable {
    let id: String
    let category: String
    let slots: [String]
    /// Index of the bold slot — what the space bar commits.
    let defaultIndex: Int
    /// What the space bar would commit, spelled out, because "index 1" is not
    /// something a reader can check against `mustNotCorrect` at a glance.
    let commits: String

    enum CodingKeys: String, CodingKey {
        case id, category, slots, defaultIndex = "default", commits
    }
}

/// The corpus names a keyboard layout per entry; the engine wants the enabled
/// list with that layout first, exactly as `KeyboardController.refreshSuggestions`
/// builds it. Every corpus entry is a Hebrew/English user, which is the product's
/// own case, so the tail is the other one of the pair.
func languages(forKeyboard keyboard: String) -> [KeyboardLanguage] {
    let front: KeyboardLanguage = keyboard.hasPrefix("he") ? .hebrew : .english
    let back: KeyboardLanguage = front == .hebrew ? .english : .hebrew
    return [front, back]
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: harness <corpus.json> <out.json>\n".utf8))
    exit(2)
}

let corpusURL = URL(fileURLWithPath: arguments[1])
let outURL = URL(fileURLWithPath: arguments[2])

let corpus = try JSONDecoder().decode(CorpusFile.self, from: Data(contentsOf: corpusURL))

/// What a stock install actually has in its personal dictionary.
///
/// Copied from `SharedStore.shippedPersonalDictionary` rather than read from it:
/// `SharedStore` pulls in Combine and most of the app's settings surface, and the
/// corpus is a question about the engine. `SuggestionEngineTests` asserts the two
/// stay equal, so this cannot drift silently.
///
/// It has to be here at all because scoring with an *empty* list measures a
/// keyboard nobody has: `nc-05` types `Nitai`, and with no dictionary the space
/// bar commits `Nit` — a real defect, but one this file would be inventing.
let shippedPersonalDictionary = ["Nitai", "Handi", "Wispr", "KeyboardKit", "סאפא", "בלי־פרופ"]

/// How long each call took, so the local tier's latency is measured rather than
/// claimed.
///
/// **It is a budget, not a curiosity.** The whole two-tier design rests on tier
/// one being fast enough to run on every keystroke, and the number people notice
/// a keyboard missing is about 20 ms for the *entire* key press — drawing
/// included. Printed as a median and a worst case, because a mean would hide the
/// one entry that scans the whole seed list.
var elapsed: [Double] = []

let records: [SlotRecord] = MainActor.assumeIsolated {
    // In-memory and empty. A scoring run must not inherit whatever the machine it
    // runs on has been typing, or two runs on two laptops disagree and neither is
    // the engine's fault.
    let personal = PersonalLanguageModel(url: nil)
    // **A warm-up per language, and the cost it absorbs is measured rather than
    // waved away.** The first call in a language pays for reading and folding
    // `LanguageModel.json` and for `UITextChecker` building that language's
    // lexicon. Measured on the iOS 26.2 Simulator: **~67 ms for the first Hebrew
    // word and ~3 ms for the first English one**, against ~0.9 ms for every word
    // after. That is a real cost a real user pays once per keyboard session on
    // their first Hebrew keystroke, and it is worth knowing; charging it to
    // whichever corpus entry happens to be first is what makes a per-keystroke
    // number wrong.
    for (label, keyboard, prefix, context) in [
        ("english", "en_US", "hel", "See you "), ("hebrew", "he_IL", "של", "אני ")
    ] {
        let started = DispatchTime.now().uptimeNanoseconds
        _ = SuggestionEngine.suggestions(
            prefix: prefix, context: context, languages: languages(forKeyboard: keyboard),
            supplementary: shippedPersonalDictionary, personal: personal)
        let cold = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        FileHandle.standardError.write(
            Data("first \(label) call: \(String(format: "%.1f", cold)) ms\n".utf8))
    }
    return corpus.entries.map { entry in
        let started = DispatchTime.now().uptimeNanoseconds
        let results = SuggestionEngine.suggestions(
            prefix: entry.prefix,
            context: entry.context,
            languages: languages(forKeyboard: entry.keyboard),
            supplementary: shippedPersonalDictionary,
            personal: personal)
        elapsed.append(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
        let defaultIndex = results.firstIndex(where: \.isDefault) ?? 0
        return SlotRecord(
            id: entry.id,
            category: entry.category,
            slots: results.map(\.text),
            defaultIndex: results.isEmpty ? -1 : defaultIndex,
            commits: results.isEmpty ? entry.prefix : results[defaultIndex].text)
    }
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
try encoder.encode(records).write(to: outURL)

let sorted = elapsed.sorted()
let median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
let slowest = zip(corpus.entries.map(\.id), elapsed)
    .sorted { $0.1 > $1.1 }
    .prefix(5)
    .map { "\($0.0) \(String(format: "%.1f", $0.1))ms" }
    .joined(separator: ", ")
FileHandle.standardError.write(
    Data(
        """
        wrote \(records.count) records to \(outURL.path)
        local tier: median \(String(format: "%.2f", median)) ms over \(elapsed.count) entries
        slowest: \(slowest)

        """.utf8))
