import Foundation

/// Hebrew's attached one-letter words, and how to see past them.
///
/// **This is why Hebrew completion was worse than English completion, and it is
/// not a dictionary problem.** Hebrew writes several of its commonest function
/// words as letters glued to the front of the next word: `ה` the, `ב` in, `ל` to,
/// `מ` from, `ו` and, `ש` that, `כ` as. So "to work" is one token, `לעבודה`, and
/// "from the kindergarten" is one token, `מהגן`. A completion engine that treats
/// the glued form as an atom has to have seen every combination as its own entry,
/// and no dictionary does: `UITextChecker` completed `לעבו` to `לעבוד` and
/// `לעבור` (two verbs) and never reached `לעבודה` (the noun anybody typing "I'm
/// on my way to work" meant), and `מהג` went to `מהגרים`, "immigrants", when the
/// sentence was about children coming home from kindergarten.
///
/// Splitting the clitics off first turns one impossible lookup into an ordinary
/// one: `לעבו` becomes `ל` + `עבו`, `עבו` completes to `עבודה` against a normal
/// word list, and the `ל` goes back on. One seed entry for `עבודה` then serves
/// `לעבודה`, `בעבודה`, `מהעבודה` and `שבעבודה`.
///
/// **Every split is a guess and the caller is told so.** `ב` is a preposition and
/// also the first letter of `בית`; `מהג` splits as `מ`+`הג`, `מה`+`ג`, or nothing
/// at all. So this returns *all* the readings, longest prefix last, and the
/// ranking decides — a reading whose stem completes to a common word wins over
/// one whose stem completes to nothing. Nothing here asserts that a split is
/// correct on its own.
///
/// **Scoped to Hebrew, deliberately.** Arabic attaches `ال` and `و` the same way,
/// and the same idea would work there, but nothing in this repo has measured
/// Arabic and the seed list has no Arabic words for a stem to land in. A rule
/// generalised to "right-to-left scripts" would fire on Persian, which is written
/// in the Arabic script and does not share the clitics.
enum HebrewMorphology {

    /// The single letters Hebrew glues to the front of a word.
    ///
    /// `ו` (and) is the only one that stacks in front of the others in ordinary
    /// writing — `ולעבודה`, "and to work" — which is why `splits` allows a second
    /// letter rather than stopping at one.
    static let clitics: Set<Character> = ["ה", "ב", "ל", "מ", "ו", "ש", "כ"]

    /// Every way this word could be read as clitics plus a stem, shortest prefix
    /// first, always including the empty prefix.
    ///
    /// The empty reading comes first because it is the only one that is certainly
    /// true: the word may simply be itself. `מהג` yields `("", "מהג")`,
    /// `("מ", "הג")` and `("מה", "ג")`, in that order.
    ///
    /// **A one-letter stem is included and the caller decides what to do with
    /// it.** It has to be: `מהגן` is `מ` + `ה` + `גן`, so reaching it from the
    /// three letters `מהג` means completing the single letter `ג`. Dropping those
    /// readings here made the commonest shape in the language unreachable. What
    /// stops it becoming noise is where it is *used* — `SuggestionEngine` asks the
    /// seed list about short stems, which is a few hundred ranked words, and never
    /// asks `UITextChecker`, which would answer `ל` + `א` with every word in
    /// Hebrew beginning with alef.
    static func splits(of word: String) -> [(prefix: String, stem: String)] {
        let characters = Array(word)
        var out: [(prefix: String, stem: String)] = [("", word)]
        var prefix = ""
        for index in 0..<min(2, characters.count) {
            guard clitics.contains(characters[index]) else { break }
            prefix.append(characters[index])
            let stem = String(characters[(index + 1)...])
            guard !stem.isEmpty else { break }
            out.append((prefix, stem))
        }
        return out
    }

    /// The five letters that change shape at the end of a Hebrew word, and their
    /// final forms.
    ///
    /// Held here rather than in `SuggestionEngine+Completions`, where it used to
    /// live as a private table, because it is the same fact about the same
    /// language and two callers now need it: the final-form correction that was
    /// already there, and the seed lookup, which must not ask a word list about a
    /// stem that is spelled with the wrong shape.
    static let finalForms: [Character: Character] = [
        "כ": "ך", "מ": "ם", "נ": "ן", "פ": "ף", "צ": "ץ"
    ]

    /// The word with its last letter put into final form, or nil if that letter is
    /// not one of the five.
    ///
    /// Asks no dictionary, and see `SuggestionEngine.hebrewFinalFormCorrection`
    /// for the measurement behind that: a version gated on `isKnownWord` silently
    /// did nothing on the first word of a session, which is the worst possible
    /// time for a correction rule to be asleep.
    static func inFinalForm(_ word: String) -> String? {
        guard let last = word.last, let final = finalForms[last] else { return nil }
        return String(word.dropLast()) + String(final)
    }
}
