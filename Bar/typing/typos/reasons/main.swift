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
/// `id, typed, intended, winner, reason, confidence`.

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
                reason.map { "\($0)" } ?? "nil",
                reason.map { "\($0.confidence)" } ?? "-"
            ].joined(separator: "\t"))
    }
    print(lines.joined(separator: "\n"))
}
