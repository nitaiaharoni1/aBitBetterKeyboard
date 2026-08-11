import Foundation

/// The word you meant when you typed it on the wrong keyboard.
///
/// **The mistake this catches has no spelling in it.** Somebody types `akuo`
/// meaning `שלום`, or `יקךךם` meaning `hello`: every keystroke was the right
/// *key* and the wrong *layout*, because the globe key was one tap behind where
/// they thought it was. A spell checker cannot help — `akuo` is not a misspelling
/// of anything, it is four correct presses interpreted in the wrong alphabet — so
/// the stock keyboard offers nothing and the user deletes the word and types it
/// again. It is one of the most common things that happens on a bilingual phone
/// and one of the few keyboard problems with a completely deterministic answer.
///
/// **Only ever offered into a common word.** The result has to be in
/// `SeedLanguageModel`, not merely in a dictionary. That is a deliberately tight
/// gate: transposing arbitrary text between two alphabets produces *something*
/// almost every time, so a loose rule would put a rare Hebrew noun next to every
/// English word a user typed. Requiring the landing word to be one of the few
/// hundred common ones means the offer appears when somebody typed `shalom` on
/// the wrong plane and stays silent otherwise.
///
/// **And only when what was typed is not already a word.** `sun` transposes to
/// `דוין`, and a user typing `sun` meant `sun`.
enum LayoutTransposition {

    /// The Hebrew standard layout as it sits on the QWERTY positions.
    ///
    /// **Written out rather than derived, and the reason is that it cannot be
    /// derived from what this repo ships.** `LetterLayouts.hebrewRows` holds only
    /// the letters — 8 / 10 / 9 — while the physical correspondence people's
    /// fingers learned also covers the keys QWERTY spends on `; , . / '`, which no
    /// `LetterLayout` in this repo has a row for. Deriving from the letter rows
    /// alone would silently mis-align every row, because English's are 10 / 9 / 7.
    ///
    /// `LayoutTranspositionTests` asserts that every letter in
    /// `LetterLayouts.hebrewRows` appears here exactly once, so the table cannot
    /// drift away from the keyboard the user is actually looking at.
    static let hebrewByLatin: [Character: Character] = [
        "q": "/", "w": "'", "e": "ק", "r": "ר", "t": "א", "y": "ט", "u": "ו", "i": "ן",
        "o": "ם", "p": "פ",
        "a": "ש", "s": "ד", "d": "ג", "f": "כ", "g": "ע", "h": "י", "j": "ח", "k": "ל",
        "l": "ך", ";": "ף",
        "z": "ז", "x": "ס", "c": "ב", "v": "ה", "b": "נ", "n": "מ", "m": "צ", ",": "ת",
        ".": "ץ"
    ]

    private static let latinByHebrew: [Character: Character] = {
        hebrewByLatin.reduce(into: [:]) { $0[$1.value] = $1.key }
    }()

    /// What these keystrokes would have produced on the other layout, or nil if any
    /// of them has no counterpart there.
    ///
    /// All-or-nothing on purpose. A run where one character does not map is a run
    /// that was not simply typed on the wrong plane — a digit or an emoji in the
    /// middle of it means the user was doing something else — and translating the
    /// rest would produce a word they never keyed.
    static func transposed(_ word: String, to language: KeyboardLanguage) -> String? {
        let table = language.script == .hebrew ? hebrewByLatin : latinByHebrew
        var out = ""
        out.reserveCapacity(word.count)
        for character in word.lowercased() {
            guard let mapped = table[character] else { return nil }
            out.append(mapped)
        }
        return out.isEmpty ? nil : out
    }

    /// The word the user meant, if the evidence is strong enough to say so.
    ///
    /// - Parameters:
    ///   - typed: the word in progress, as keyed
    ///   - typedLanguage: the script the characters are actually written in
    ///   - other: the other language the user has enabled. Nil when they have only
    ///     one, in which case there is no wrong layout to have been on.
    ///   - isKnownWord: whether the spell checker recognises a word in a language.
    ///     Injected rather than called directly so this stays testable without a
    ///     `UITextChecker`, and so the one shared checker instance keeps its single
    ///     owner.
    static func correction(
        of typed: String,
        typedLanguage: KeyboardLanguage,
        other: KeyboardLanguage?,
        isKnownWord: (String, KeyboardLanguage) -> Bool
    ) -> String? {
        guard let other, other.script != typedLanguage.script, typed.count >= 3 else { return nil }
        // Three characters, not two: `hi`, `לי`, `מה` and `on` all transpose into
        // something, and at two characters the odds of landing on a common word by
        // accident stop being a signal.
        guard !isKnownWord(typed, typedLanguage), !SeedLanguageModel.knows(typed, in: typedLanguage)
        else { return nil }
        guard let candidate = transposed(typed, to: other),
            SeedLanguageModel.knows(candidate, in: other)
        else { return nil }
        return candidate
    }
}
