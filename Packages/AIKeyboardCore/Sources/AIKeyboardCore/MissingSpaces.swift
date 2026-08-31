import Darwin
import Foundation
import UIKit
import os

/// Restores word boundaries from the bundled list.
///
/// Most repairs split a jammed token. The one exception moves a Hebrew boundary
/// one letter later when a final-form letter proves the typed boundary impossible.
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

    /// An exact suffix the keyboard may replace without reinterpreting the rest
    /// of the field.
    struct BoundaryRepair: Equatable {
        let source: String
        let replacement: String
    }

    /// `text` with missing or provably premature boundaries repaired. Identity
    /// when the bundled list cannot prove a safer boundary.
    static func restored(_ text: String) -> String {
        let tokens = EditScope.split(repairingBoundaries(in: text))
        guard !tokens.isEmpty else { return text }
        let updated = tokens.map { token -> EditScope.Token in
            let split = splitRuns(in: token.text)
            guard split != token.text else { return token }
            return EditScope.Token(text: split, spacing: token.spacing)
        }
        return EditScope.joined(updated)
    }

    /// Repairs a final-form letter typed one position too early, but only when
    /// the exact suffix ends at the caret. The controller re-runs this immediately
    /// before writing so a stale suggestion cannot delete newer text.
    static func trailingBoundaryRepair(in text: String) -> BoundaryRepair? {
        guard let space = text.lastIndex(of: " "), space < text.index(before: text.endIndex)
        else { return nil }

        let rightStart = text.index(after: space)
        let right = String(text[rightStart...])
        guard right.allSatisfy(\.isLetter) else { return nil }

        var leftStart = space
        while leftStart > text.startIndex {
            let previous = text.index(before: leftStart)
            guard !text[previous].isWhitespace else { break }
            leftStart = previous
        }
        let left = String(text[leftStart..<space])
        guard !left.isEmpty else { return nil }
        return boundaryRepair(left: left, right: right, allowingEmptyRemainder: true)
    }

    private static func repairingBoundaries(in text: String) -> String {
        var result = ""
        var cursor = text.startIndex

        while let space = text[cursor...].firstIndex(of: " ") {
            var leftStart = space
            while leftStart > cursor {
                let previous = text.index(before: leftStart)
                guard !text[previous].isWhitespace else { break }
                leftStart = previous
            }

            var rightEnd = text.index(after: space)
            while rightEnd < text.endIndex, !text[rightEnd].isWhitespace {
                rightEnd = text.index(after: rightEnd)
            }

            let left = String(text[leftStart..<space])
            let right = String(text[text.index(after: space)..<rightEnd])
            guard
                let repair = boundaryRepair(
                    left: left, right: right, allowingEmptyRemainder: false)
            else {
                result += text[cursor...space]
                cursor = text.index(after: space)
                continue
            }

            result += text[cursor..<leftStart]
            result += repair.replacement
            cursor = rightEnd
        }

        result += text[cursor...]
        return result
    }

    private static func boundaryRepair(
        left: String, right: String, allowingEmptyRemainder: Bool
    ) -> BoundaryRepair? {
        guard
            left.allSatisfy(\.isLetter),
            right.allSatisfy(\.isLetter),
            lexiconLanguage(of: left) == .hebrew,
            lexiconLanguage(of: right) == .hebrew,
            let moved = right.first,
            HebrewMorphology.finalForms.values.contains(moved)
        else { return nil }

        let remainder = String(right.dropFirst())
        guard allowingEmptyRemainder || !remainder.isEmpty else { return nil }
        let repairedLeft = left + String(moved)
        guard boundaryWordIsCommon(repairedLeft) else { return nil }
        guard remainder.isEmpty || boundaryWordIsCommon(remainder) else { return nil }

        // The final form may itself be a typo for an ordinary first letter. Keep
        // that reading when it makes a common word, but ignore one-letter entries such as מ.
        guard let ordinary = ordinaryForms[moved] else { return nil }
        let alternativeRight = String(ordinary) + remainder
        if alternativeRight.count >= 2, boundaryWordIsCommon(alternativeRight) { return nil }

        let source = left + " " + right
        let replacement = repairedLeft + (remainder.isEmpty ? "" : " " + remainder)
        return BoundaryRepair(source: source, replacement: replacement)
    }

    private static func boundaryWordIsCommon(_ word: String) -> Bool {
        guard word.count >= 2, let rank = TypoLexicon.rank(of: word, in: .hebrew) else {
            return false
        }
        // Two-letter Hebrew pieces are safe boundaries only when their corpus
        // rank marks them as exceptionally common function words.
        return word.count > 2 || rank < shortPieceRankLimit
    }

    private static let ordinaryForms: [Character: Character] = HebrewMorphology.finalForms
        .reduce(into: [:]) { $0[$1.value] = $1.key }

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
            guard let rank = ranks[key], rank < shortPieceRankLimit else { return nil }
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

    private static let shortPieceRankLimit = 250
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
