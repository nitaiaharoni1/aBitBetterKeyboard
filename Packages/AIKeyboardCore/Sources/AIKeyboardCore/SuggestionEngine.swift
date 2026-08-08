import Foundation
import UIKit

// MARK: - Suggestions
//
// Backs the suggestion bar with `UITextChecker`, the same on-device spelling and
// completion engine the system keyboard's autocorrect draws on. Replaces
// `MockSuggestionEngine`.
//
// **Verified before writing this, not assumed:** `UITextChecker.availableLanguages`
// on the iOS 26.2 Simulator lists 42 languages including `he_IL`, and
// `completions(forPartialWordRange:in:language:)` / `guesses(forWordRange:...)`
// both return real, well-formed Hebrew results — `אנ` completes to `אני`,
// `אנחנו`, `אנשים`…; the misspelling `שלומ` guesses `שלום` third. Hebrew is not
// a second-class case here the way it is for Foundation Models, `SpeechTranscriber`
// and Vision's text recognizer (see `.claude/CLAUDE.md`): `UITextChecker` is a
// different, older API with its own language list, and this one has Hebrew.
//
// **What is genuinely NOT available, and was not faked to look like it is:**
// Apple exposes no public API for predicting the *next* word from nothing typed
// — that is QuickType's job, and QuickType is `UIKitCore`-private
// (`UIDictationController` and its neighbours; there is no public
// `UITextPredictor` a third-party keyboard can call). `nextWordSuggestions`
// below is therefore still a small, fixed table, exactly as it was in the mock —
// see its doc comment for why that is disclosed rather than dressed up.
//
// **The mock's `codeSwitchVocabulary` list is gone, not ported.** It existed to
// prioritise loanwords like `sync` and `standup` when Latin letters appear mid
// Hebrew sentence. Measured before dropping it: `en_US`'s own `UITextChecker`
// dictionary already knows every word that list had — `sync`, `backlog`,
// `standup`, `roadmap`, `feedback` and eight others all come back
// `misspelled == false` with real completions — so the dedicated list bought
// nothing a plain English completion did not already cover, at the cost of a
// second hardcoded vocabulary to keep in sync with the first.
public enum SuggestionEngine {

    // MARK: Script detection
    //
    // Unchanged from `MockSuggestionEngine`: pure `CharacterSet` arithmetic, not
    // a mock in the first place. Kept here because `DictationPanel` needs it and
    // this is the type that replaces the one it used to call.

    /// Which language a run of text is written in, ignoring digits and punctuation.
    public static func dominantLanguage(in text: String) -> KeyboardLanguage? {
        var hebrew = 0
        var latin = 0
        for scalar in text.unicodeScalars {
            if (0x0590...0x05FF).contains(scalar.value) {
                hebrew += 1
            } else if CharacterSet.letters.contains(scalar) {
                latin += 1
            }
        }
        if hebrew == 0 && latin == 0 { return nil }
        return hebrew >= latin ? .hebrew : .english
    }

    private static func script(of word: String) -> KeyboardLanguage? {
        dominantLanguage(in: word)
    }

    /// `UITextChecker`'s language identifiers, read off `availableLanguages`
    /// rather than guessed: `en_US` and `he_IL`, not the bare `en`/`he` some
    /// other Apple APIs use.
    private static func checkerLanguage(for language: KeyboardLanguage) -> String {
        switch language {
        case .english: return "en_US"
        case .hebrew: return "he_IL"
        }
    }

    /// Three candidates for the suggestion bar.
    ///
    /// - Parameters:
    ///   - prefix: the word currently being typed, may be empty
    ///   - context: everything before the current word
    ///   - languages: the languages the user turned on, in priority order
    ///   - supplementary: names and shortcuts from `UILexicon`
    ///     (`UIInputViewController.requestSupplementaryLexicon`), read once by
    ///     `KeyboardViewController` and handed down. Empty in the companion
    ///     app's playground and in every test, which is correct: the lexicon is
    ///     the *user's* contacts and text replacements, and nothing outside a
    ///     real keyboard session should see them.
    @MainActor
    public static func suggestions(
        prefix: String,
        context: String,
        languages: [KeyboardLanguage],
        supplementary: [String] = []
    ) -> [Suggestion] {
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let contextLanguage = dominantLanguage(in: context) ?? languages.first ?? .english

        if trimmedPrefix.isEmpty {
            let results = nextWordSuggestions(
                context: context, contextLanguage: contextLanguage, languages: languages)
            // Nothing is being typed, so nothing is at risk of being replaced;
            // highlight the middle candidate the way the system keyboard does.
            return markDefault(results, at: min(1, results.count - 1))
        }

        let typedLanguage = script(of: trimmedPrefix) ?? contextLanguage
        let results = completions(
            for: trimmedPrefix, typedLanguage: typedLanguage, supplementary: supplementary)
        return markDefault(
            results,
            at: shouldAutocorrect(trimmedPrefix, typedLanguage: typedLanguage, results: results) ? 1 : 0)
    }

    /// Whether pressing space should replace what was typed.
    ///
    /// Defaulting to "yes" is how autocorrect earns its reputation: one letter in,
    /// and `I` turns into `idea`. Only override the user when there is a real
    /// reason to think they mis-typed.
    @MainActor
    private static func shouldAutocorrect(
        _ prefix: String, typedLanguage: KeyboardLanguage, results: [Suggestion]
    ) -> Bool {
        guard results.count > 1 else { return false }
        let lower = prefix.lowercased()

        // A missing apostrophe is unambiguous, so correct it at any length.
        if contractions[lower] != nil { return true }

        // Otherwise wait until enough letters are in to be confident, and never
        // correct something `UITextChecker` already recognises as a real word —
        // a full dictionary lookup now, not 150 hardcoded entries.
        return prefix.count >= 4 && !isKnownWord(prefix, language: typedLanguage)
    }

    @MainActor
    private static func isKnownWord(_ word: String, language: KeyboardLanguage) -> Bool {
        guard !word.isEmpty else { return false }
        let range = NSRange(location: 0, length: (word as NSString).length)
        let misspelled = sharedChecker.rangeOfMisspelledWord(
            in: word, range: range, startingAt: 0, wrap: false,
            language: checkerLanguage(for: language))
        return misspelled.location == NSNotFound
    }

    // MARK: Completion of the word being typed

    /// One `UITextChecker` for the process. Apple's own guidance is one per
    /// document mainly so ignored/learned words stay consistent; this keyboard
    /// never calls `ignoreWord`/`learnWord`, so a single shared instance is
    /// exactly as correct and avoids re-initialising the spell-check engine on
    /// every keystroke.
    @MainActor
    private static let sharedChecker = UITextChecker()

    @MainActor
    private static func completions(
        for prefix: String,
        typedLanguage: KeyboardLanguage,
        supplementary: [String]
    ) -> [Suggestion] {
        let lower = prefix.lowercased()
        var out: [Suggestion] = []

        // The literal keystrokes always stay available, so the engine can never
        // trap the user into a word they did not want.
        out.append(Suggestion(text: prefix, language: typedLanguage))

        // A dropped apostrophe is the most common thing worth fixing, and it
        // should sit directly next to what was typed.
        if let contraction = contractions[lower] {
            out.append(Suggestion(text: matchCase(of: prefix, applyingTo: contraction), language: .english))
        }

        // Names and shortcuts from the user's own lexicon outrank the system
        // dictionary: `UITextChecker` has never heard of "Nitai", the user's
        // contacts have.
        out +=
            supplementary
            .filter { $0.lowercased().hasPrefix(lower) && $0.lowercased() != lower }
            .prefix(2)
            .map { Suggestion(text: $0, language: typedLanguage) }

        let nsPrefix = prefix as NSString
        let range = NSRange(location: 0, length: nsPrefix.length)
        let languageCode = checkerLanguage(for: typedLanguage)

        if let wordCompletions = sharedChecker.completions(
            forPartialWordRange: range, in: prefix, language: languageCode)
        {
            out +=
                wordCompletions
                .filter { $0.lowercased() != lower }
                .prefix(3)
                .map { Suggestion(text: matchCase(of: prefix, applyingTo: $0), language: typedLanguage) }
        }

        // `completions` only extends a word already headed somewhere real. If
        // nothing did — the prefix does not start any dictionary word — it may
        // instead be a misspelling of one, which is what `guesses` corrects.
        //
        // Measured, disclosed gap: this only helps when `completions` came back
        // thin. `recieve` completes to nothing, so this fires and `guesses`
        // corrects it to `receive`. `helo` completes to `helot`/`helots` — real
        // words, so this branch never runs — and the much likelier intended
        // word, `hello`, sits second in `guesses` and never gets shown.
        // `UITextChecker` has no frequency model to say "hello" is common and
        // "helot" is not; the private QuickType model that does is not
        // reachable from here (see the file-level comment). Not worked around,
        // because every fix tried traded a different, harder-to-notice case for
        // this one.
        if out.count < 2 {
            let misspelled = sharedChecker.rangeOfMisspelledWord(
                in: prefix, range: range, startingAt: 0, wrap: false, language: languageCode)
            if misspelled.location != NSNotFound,
                let corrections = sharedChecker.guesses(
                    forWordRange: range, in: prefix, language: languageCode)
            {
                out +=
                    corrections
                    .filter { $0.lowercased() != lower }
                    .prefix(2)
                    .map { Suggestion(text: matchCase(of: prefix, applyingTo: $0), language: typedLanguage) }
            }
        }

        return dedupe(out, limit: 3)
    }

    // MARK: Prediction of the next word
    //
    // Next-word-suggestions is the case documented at the top of this file
    // as genuinely unavailable: no public on-device API predicts a word from
    // nothing typed. This table is deliberately small — the handful of openers
    // a chat keyboard sees constantly — and is disclosed as a table, not
    // presented as prediction. It is the one piece of `MockSuggestionEngine`
    // that stays exactly as it was, for that reason.

    /// Next-word predictions with nothing typed yet. Keyed by the last word.
    private static let englishNextWord: [String: [String]] = [
        "i": ["think", "would", "will"],
        "to": ["know", "see", "make"],
        "would": ["like", "be", "you"],
        "like": ["to", "this", "that"],
        "we": ["should", "can", "need"],
        "should": ["be", "do", "have"],
        "can": ["you", "we", "be"],
        "you": ["can", "want", "know"],
        "the": ["team", "meeting", "same"],
        "is": ["not", "the", "a"],
        "it": ["is", "was", "would"],
        "for": ["the", "you", "me"],
        "this": ["is", "one", "week"],
        "let": ["me", "us", "them"],
        "thanks": ["for", "a", "so"]
    ]

    private static let hebrewNextWord: [String: [String]] = [
        "אני": ["חושב", "רוצה", "אשלח"],
        "אנחנו": ["צריכים", "נדבר", "יכולים"],
        "צריך": ["לבדוק", "לשלוח", "להיות"],
        "רוצה": ["לדבר", "לשאול", "לבדוק"],
        "יש": ["לי", "לנו", "משהו"],
        "מה": ["קורה", "השעה", "נשמע"],
        "את": ["ה", "זה", "כל"],
        "לא": ["בטוח", "נכון", "יודע"],
        "תודה": ["רבה", "לך", "על"],
        "אפשר": ["לבדוק", "לדבר", "מחר"],
        "בוא": ["נדבר", "נעשה", "נבדוק"]
    ]

    private static let defaultEnglish = ["I", "The", "We"]
    private static let defaultHebrew = ["אני", "מה", "תודה"]

    private static func nextWordSuggestions(
        context: String,
        contextLanguage: KeyboardLanguage,
        languages: [KeyboardLanguage]
    ) -> [Suggestion] {
        let words =
            context
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        guard let last = words.last?.trimmingCharacters(in: .punctuationCharacters).lowercased(),
            !last.isEmpty
        else {
            let defaults = contextLanguage == .hebrew ? defaultHebrew : defaultEnglish
            return defaults.map { Suggestion(text: $0, language: contextLanguage) }
        }

        let table = contextLanguage == .hebrew ? hebrewNextWord : englishNextWord
        if let hits = table[last] {
            return hits.map { Suggestion(text: $0, language: contextLanguage) }
        }

        let defaults = contextLanguage == .hebrew ? defaultHebrew : defaultEnglish
        return defaults.map { Suggestion(text: $0, language: contextLanguage) }
    }

    // MARK: Shared helpers

    private static func matchCase(of source: String, applyingTo candidate: String) -> String {
        guard let first = source.first, first.isUppercase else { return candidate }
        return candidate.prefix(1).uppercased() + candidate.dropFirst()
    }

    private static func dedupe(_ items: [Suggestion], limit: Int) -> [Suggestion] {
        var seen = Set<String>()
        var out: [Suggestion] = []
        for item in items where !seen.contains(item.text.lowercased()) {
            seen.insert(item.text.lowercased())
            out.append(item)
            if out.count == limit { break }
        }
        return out
    }

    private static func markDefault(_ items: [Suggestion], at defaultIndex: Int) -> [Suggestion] {
        guard !items.isEmpty else { return items }
        let index = max(0, min(defaultIndex, items.count - 1))
        return items.enumerated().map { position, item in
            Suggestion(text: item.text, language: item.language, isDefault: position == index)
        }
    }

    /// Offered as autocorrections in the suggestion bar. Real product behaviour,
    /// not a stand-in: the system keyboard hardcodes the same class of rule, and
    /// `UITextChecker.guesses` cannot be trusted to fire on a two-letter prefix
    /// like `im`, which this needs to for `I'm` to correct the way users expect.
    static let contractions: [String: String] = [
        "dont": "don't", "doesnt": "doesn't", "didnt": "didn't", "cant": "can't",
        "wont": "won't", "isnt": "isn't", "wasnt": "wasn't", "arent": "aren't",
        "werent": "weren't", "couldnt": "couldn't", "shouldnt": "shouldn't",
        "wouldnt": "wouldn't", "hasnt": "hasn't", "havent": "haven't", "hadnt": "hadn't",
        "im": "I'm", "ive": "I've", "ill": "I'll", "id": "I'd",
        "youre": "you're", "youve": "you've", "youll": "you'll",
        "theyre": "they're", "theyve": "they've", "thats": "that's",
        "whats": "what's", "hes": "he's", "shes": "she's", "lets": "let's",
        "its": "it's", "theres": "there's", "heres": "here's"
    ]
}
