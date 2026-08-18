import Darwin
import Foundation
import UIKit
import os

/// Inserts the spaces a jammed token is missing, from the bundled word list.
///
/// **The model is not the recovery.** Fix on `מהאופישלומהקורה` came back
/// unchanged: missing spaces were not in the corrections field, the model wrote
/// `none`, `EditScope` put the jammed string back, and `applyDirectly` stayed
/// quiet because the answer matched the field. Asking the model again still
/// fails when it echoes the input. The letters did not change — only the
/// boundaries — so a local split against the same frequency list grouped keys
/// already ship is the correction, and it does not wait on a sampled call.
///
/// **A word the list already knows is never split.** That is `therapist` vs
/// `the rapist`, `לעבודה` vs `ל עבודה`, and why `יאללה` — which the list does
/// not know and cannot cover with two-letter pieces — is left alone rather than
/// invented into `אל לה`. Hebrew prefixes stay glued: `המקורן` as a whole
/// token is not in the list and has no two-letter cover, so it stays; the same
/// letters in the middle of a longer jammed run can be one piece via the stem.
enum MissingSpaces {

    /// `text` with jammed letter-runs split on word boundaries. Identity when
    /// nothing in it can be covered by two or more list words.
    static func restored(_ text: String) -> String {
        let tokens = EditScope.split(text)
        guard !tokens.isEmpty else { return text }
        let updated = tokens.map { token -> EditScope.Token in
            let split = splitRuns(in: token.text)
            guard split != token.text else { return token }
            return EditScope.Token(text: split, spacing: token.spacing)
        }
        return EditScope.joined(updated)
    }

    // MARK: Runs

    /// Segment each maximal letter-run on its own, and keep punctuation where
    /// it was. A comma is already a boundary; the defect is letters with none.
    private static func splitRuns(in token: String) -> String {
        var result = ""
        var run = ""
        func flush() {
            if let parts = segment(run) {
                result += parts.joined(separator: " ")
            } else {
                result += run
            }
            run = ""
        }
        for character in token {
            if character.isLetter {
                run.append(character)
            } else {
                flush()
                result.append(character)
            }
        }
        flush()
        return result
    }

    // MARK: Segmentation

    /// Shortest clitic compounds (`מהגן`) are four letters and must not become
    /// `מה גן`. Jammed chat is longer: `מהקורה` is six, the WhatsApp screenshots
    /// are thirteen and sixteen.
    private static let minimumLetters = 6

    /// Extra cost per piece so `מה`+`או`+`פי` loses to `מה`+`אופי`. Zipf
    /// unigrams prefer two common shorts over one mid-rank long; the penalty is
    /// what makes that false.
    private static let piecePenalty = 3.0

    private static func segment(_ letters: String) -> [String]? {
        let count = letters.count
        guard count >= minimumLetters, let language = lexiconLanguage(of: letters) else {
            return nil
        }
        let ranks = index(for: language)
        // Exact list membership only. A glued `ה` is a piece inside a longer
        // run, never a reason to treat the whole jammed token as one word.
        if pieceRank(letters, language: language, ranks: ranks, ofWhole: letters) != nil {
            return nil
        }
        if isSpelledCorrectly(letters, language: language) { return nil }

        let characters = Array(letters)
        var cost = [Double](repeating: .infinity, count: count + 1)
        var prev = [Int](repeating: -1, count: count + 1)
        cost[0] = 0

        for end in 1...count {
            for start in 0..<end {
                guard cost[start].isFinite else { continue }
                let piece = String(characters[start..<end])
                guard
                    let listed = pieceRank(
                        piece, language: language, ranks: ranks, ofWhole: letters)
                else { continue }
                let next = cost[start] + log(Double(listed + 1)) + piecePenalty
                if next < cost[end] {
                    cost[end] = next
                    prev[end] = start
                }
            }
        }
        guard cost[count].isFinite else { return nil }

        var parts: [String] = []
        var cursor = count
        while cursor > 0 {
            let start = prev[cursor]
            guard start >= 0 else { return nil }
            parts.append(String(characters[start..<cursor]))
            cursor = start
        }
        parts.reverse()
        return parts.count >= 2 ? parts : nil
    }

    /// **The frequency list answers "is this common", not "is this a word", and
    /// for English those are different questions.**
    ///
    /// The list is a top-N, so every ordinary compound that fell off the end of
    /// it decomposes into two words that did not: `standup` is not in it,
    /// `stand` and `up` both are, and Fix wrote `stand up` over a model answer
    /// that had said `standup`. That is precisely the failure `EditScope` exists
    /// to prevent — changing a word the corrections list never called wrong —
    /// arriving through the one door built to bypass `EditScope`.
    /// `checkout`, `workout`, `backend` and `frontend` are the same shape.
    ///
    /// **Hebrew is deliberately left on the list alone.** `מהקורה` → `מה קורה`
    /// is the measured motivating case and `מהקורה` is *also* a legal Hebrew
    /// word-form, so a speller would accept it and retire the feature on the
    /// example it was built for. Hebrew's missing boundaries are prefix
    /// morphology, which the list plus `pieceRank`'s `ה` rule already models;
    /// English's are compounding, which a dictionary models and a top-N cannot.
    ///
    /// The checker is local rather than `SuggestionEngine.sharedChecker`, which
    /// is `@MainActor`: this runs at most a few times per Fix apply, behind a
    /// model round trip, so the allocation costs nothing, while pinning
    /// `restored` to an actor would cost every caller and every test.
    private static func isSpelledCorrectly(
        _ letters: String, language: KeyboardLanguage
    ) -> Bool {
        guard language == .english, let locale = language.spellCheckerLocale else {
            return false
        }
        let length = (letters as NSString).length
        let misspelled = UITextChecker().rangeOfMisspelledWord(
            in: letters, range: NSRange(location: 0, length: length),
            startingAt: 0, wrap: false, language: locale)
        return misspelled.location == NSNotFound
    }

    private static func lexiconLanguage(of letters: String) -> KeyboardLanguage? {
        let scripts = LanguageDetector.scripts(in: letters)
        if scripts == [.hebrew] { return .hebrew }
        if scripts == [.latin] { return .english }
        return nil
    }

    // MARK: Ranks

    /// Line number in the bundled list, 0 being the commonest. `nil` if this
    /// piece is not a word this splitter is allowed to emit.
    ///
    /// **Two-letter pieces are only the common function words.** `של` is the
    /// commonest Hebrew word and would otherwise glue `מהאופי` to `ומהקורה`.
    /// **A glued `ה` is allowed on a stem, never on the whole jammed token** —
    /// that is `המקורן` inside `מהמושלהמקורן`, and not `מהקורה` read as `מ`+`הקורה`.
    private static func pieceRank(
        _ piece: String, language: KeyboardLanguage, ranks: [String: Int],
        ofWhole whole: String
    ) -> Int? {
        let key = language == .english ? piece.lowercased() : piece
        if piece.count == 1 {
            guard language == .english, key == "a" || key == "i" else { return nil }
            return ranks[key]
        }
        if piece.count == 2 {
            guard let rank = ranks[key], rank < 250 else { return nil }
            return rank
        }
        if let rank = ranks[key] { return rank }
        guard language == .hebrew, piece != whole, piece.first == "ה", piece.count >= 4
        else { return nil }
        if let rank = ranks[String(piece.dropFirst())] { return rank + 50 }
        return nil
    }

    /// Drops the built indexes. See `KeyboardController.dropRebuildableCaches()`,
    /// which is the only caller and carries the reasoning.
    static func purge() {
        ranks.withLock { $0.removeAll() }
    }

    private static let ranks = OSAllocatedUnfairLock(initialState: [String: [String: Int]]())

    /// **`uncachedWords` rather than `words(for:)`, which is the same call
    /// `TypoLexicon.load` makes and for the same reason.** This reads each string
    /// exactly once, to key a dictionary, and never wants the array again — where
    /// `words(for:)` keeps all 50,000 boxed strings alive for the life of the
    /// process to serve `GroupedDecoder`, which indexes them on every grouped
    /// keystroke. Borrowing that cache made one press of Fix cost a keyboard
    /// extension two permanent 50,000-entry structures instead of one, in a
    /// process with roughly 50 MB to live in.
    private static func index(for language: KeyboardLanguage) -> [String: Int] {
        ranks.withLock { store in
            if let known = store[language.languageTag] { return known }
            var map: [String: Int] = [:]
            map.reserveCapacity(50_000)
            for (rank, word) in GroupedLexiconResource.uncachedWords(for: language).enumerated() {
                let key = language == .english ? word.lowercased() : word
                if map[key] == nil { map[key] = rank }
            }
            store[language.languageTag] = map
            return map
        }
    }
}
