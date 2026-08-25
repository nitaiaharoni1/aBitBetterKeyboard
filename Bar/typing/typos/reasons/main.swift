/// Which rule decided each commit, for every entry in a typing corpus.
///
/// **The instrument the confidence prices were set from, and the reason they are
/// numbers rather than opinions.** `Bar/typing/typos/` grades the *word* the bold
/// slot holds; it cannot say which of `SuggestionEngine.commitReason`'s dozen
/// rules put it there, so "how often is this rule right" was unanswerable and the
/// first pass at `CommitReason.confidence` priced two tiers backwards. Joining
/// this output to the judge's verdicts is what found that.
///
/// It calls `commitReason` directly rather than reading the bold slot, so it
/// reports the rule that fired **regardless of** `AutocorrectLevel` — the point
/// is to see what every rule claims and then choose where to cut. Its winner
/// column is `rank`'s first offer, which is what the space bar would insert if
/// the level allowed it.
///
/// Output is one tab-separated row per entry:
/// `id, typed, intended, winner, reason, confidence, channelCost, editCount`.
///
/// **The last two columns are additions; the first six are the exact text
/// this file has always printed.** `channelCost` and `editCount` are
/// `TypoChannel.EditCost`'s two halves for the winning candidate on a
/// `.frequency` row, `-` on every other row — extra columns rather than a
/// reshaped `reason`, which is what keeps every tool already reading the
/// first six working unchanged. **The `reason` column itself is still the
/// exact text this file printed before `count` existed, and `describe` below
/// is why.** `CommitReason.frequency` now carries `count` as a third
/// associated value, and a bare `"\(reason)"` would fold it straight into
/// this column the moment the case gained it — moving every `frequency` row
/// in what is meant to be an additive change. `describe` prints exactly
/// `frequency(cost: N, transposition: B)`, the two fields this column has
/// always carried.

import Foundation
import UIKit

struct ProbeEntry: Decodable {
    let id: String
    let keyboard: String
    let context: String
    let prefix: String
    let intended: String?
}
struct ProbeFile: Decodable { let entries: [ProbeEntry] }

/// The `reason` column, byte-for-byte what this file printed before
/// `CommitReason.frequency` gained its `count` parameter. See the file's own
/// doc comment for why this cannot be `"\(reason)"`.
func describe(_ reason: CommitReason?) -> String {
    guard let reason else { return "nil" }
    switch reason {
    case .frequency(let cost, let transposition, _):
        return "frequency(cost: \(cost), transposition: \(transposition))"
    default:
        return "\(reason)"
    }
}

/// `TypoChannel.EditCost.cost` for a `.frequency` commit, `-` otherwise. An
/// extra column, appended after the six this file has always printed.
func channelCost(_ reason: CommitReason?) -> String {
    guard case .frequency(let cost, _, _) = reason else { return "-" }
    return "\(cost)"
}

/// `TypoChannel.EditCost.count` for a `.frequency` commit, `-` otherwise.
func editCount(_ reason: CommitReason?) -> String {
    guard case .frequency(_, _, let count) = reason else { return "-" }
    return "\(count)"
}

let probeFile = try JSONDecoder().decode(
    ProbeFile.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))

MainActor.assumeIsolated {
    // The same refusal `Bar/typing/harness/main.swift` carries. Without it a
    // probe run with an unloaded lexicon produces a full set of plausible rows
    // for an engine with its frequency source switched off — which is what the
    // first run of this file did.
    guard TypoLexicon.rank(of: "the", in: .english) != nil,
        TypoLexicon.rank(of: "\u{05e9}\u{05dc}\u{05d5}\u{05dd}", in: .hebrew) != nil,
        SeedLanguageModel.rank(of: "the", in: .english) != nil
    else {
        FileHandle.standardError.write(Data("resources did not load; refusing to score\n".utf8))
        exit(3)
    }
    let personal = PersonalLanguageModel(url: nil)
    var lines: [String] = []
    for entry in probeFile.entries {
        let trimmed = entry.prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        let typed: KeyboardLanguage = entry.keyboard.hasPrefix("he") ? .hebrew : .english
        let other: KeyboardLanguage = typed == .hebrew ? .english : .hebrew
        let contextLanguage =
            SuggestionEngine.dominantLanguage(in: entry.context, among: [typed, other]) ?? typed
        let preceding = SuggestionEngine.previousWords(in: entry.context)
        let ranked = SuggestionEngine.completions(
            for: trimmed, previousWords: preceding, context: entry.context,
            typedLanguage: typed, otherLanguage: other,
            supplementary: shippedPersonalDictionary, personal: personal,
            codeSwitching: contextLanguage.script == .hebrew && typed.script == .latin)
        let reason = SuggestionEngine.commitReason(
            trimmed, previousWords: preceding, context: entry.context, typedLanguage: typed,
            results: ranked, supplementary: shippedPersonalDictionary, personal: personal)
        let winner = ranked.dropFirst().first?.text ?? "-"
        lines.append(
            [
                entry.id, trimmed, entry.intended ?? "-", winner,
                describe(reason),
                reason.map { "\($0.confidence)" } ?? "-",
                channelCost(reason), editCount(reason)
            ].joined(separator: "\t"))
    }
    print(lines.joined(separator: "\n"))
}
