import Foundation
import UIKit

extension SuggestionEngine {

    // MARK: Completion of the word being typed

    /// One `UITextChecker` for the process. Apple's own guidance is one per
    /// document mainly so ignored/learned words stay consistent; this keyboard
    /// never calls `ignoreWord`/`learnWord`, so a single shared instance is
    /// exactly as correct and avoids re-initialising the spell-check engine on
    /// every keystroke.
    @MainActor
    static let sharedChecker = UITextChecker()

    private static let hebrewFinalForms: [Character: Character] = [
        "כ": "ך", "מ": "ם", "נ": "ן", "פ": "ף", "צ": "ץ"
    ]

    /// The word with its last letter put into final form.
    ///
    /// **Asks no dictionary, deliberately, and the first version of this did.**
    /// The obvious shape is "offer it when the typed word is misspelled and the
    /// corrected one is not". That was written, and it never fired: inside the
    /// engine `isKnownWord("שלומ")` comes back *true*, while the same call on a
    /// checker that has already been used for Hebrew comes back false. Whatever
    /// the cause — a dictionary that loads lazily is the obvious suspect — a rule
    /// whose correctness depends on `UITextChecker` having warmed up is a rule
    /// that silently does nothing on the first word a user types, which is the
    /// worst possible time.
    ///
    /// It does not need one. Five Hebrew letters change shape at the end of a
    /// word and a word may not end in the ordinary form: that is orthography, not
    /// statistics, and it is true whether or not any dictionary agrees. The cost
    /// of asking nothing is that a user midway through `שלומדים` is also offered
    /// `שלום` — which is a correct suggestion for a word that, at that instant,
    /// genuinely is spelled wrong.
    @MainActor
    static func hebrewFinalFormCorrection(of prefix: String) -> String? {
        guard let last = prefix.last, let final = hebrewFinalForms[last] else { return nil }
        return String(prefix.dropLast()) + String(final)
    }

    private static let codeSwitchVocabulary: [String] = [
        "backlog", "brief", "call", "deadline", "demo", "design", "document", "feedback",
        "follow-up", "invite", "meeting", "presentation", "product", "review", "roadmap",
        "scope", "slack", "sprint", "standup", "sync", "template", "ticket", "update"
    ]

    @MainActor
    static func completions(
        for prefix: String,
        typedLanguage: KeyboardLanguage,
        supplementary: [String],
        codeSwitching: Bool = false
    ) -> [Suggestion] {
        let lower = prefix.lowercased()
        var out: [Suggestion] = []

        // The literal keystrokes always stay available, so the engine can never
        // trap the user into a word they did not want.
        out.append(Suggestion(text: prefix, language: typedLanguage))

        // A dropped apostrophe is the most common thing worth fixing, and it
        // should sit directly next to what was typed. English only: every entry
        // in the table is an English contraction, and several of them — `dont`,
        // `cant` — are ordinary words in other languages that use this alphabet.
        if typedLanguage == .english, let contraction = contractions[lower] {
            out.append(
                Suggestion(
                    text: matchCase(of: prefix, applyingTo: contraction, in: typedLanguage),
                    language: .english))
        }

        // Hebrew's equivalent, and it has to be here for the same reason: a rule
        // that is deterministic and unambiguous should not be left to a ranking
        // that has no frequency model.
        //
        // Five Hebrew letters change shape at the end of a word, and typing the
        // ordinary form there is the language's most common keying error. It is
        // what `שלומ` is — `שלום`, "hello", with a plain mem instead of a final
        // mem. Left to `UITextChecker` alone the user is actively harmed rather
        // than merely unhelped: `שלומ` has twelve real completions
        // (`שלומדים`, `שלומד`, …), so the guesses branch below never runs, and
        // `שלומדים` is offered as the default. Pressing space to accept "hello"
        // commits "who are studying". That is the autocorrect people switch off.
        //
        // Only offered when the swap produces a word the dictionary actually
        // knows, so this cannot invent a correction for a word that was already
        // right.
        //
        // Scoped to the Hebrew script and nothing wider. Arabic and Persian also
        // change letter shape at the end of a word, but they do it in the *font*
        // rather than in the code point — there is no wrong character to correct
        // — so a rule generalised across right-to-left scripts would fire on
        // correctly spelled Arabic and mangle it.
        if typedLanguage.script == .hebrew, let final = hebrewFinalFormCorrection(of: prefix) {
            out.append(Suggestion(text: final, language: .hebrew))
        }

        // The user's own words outrank the system dictionary: `UITextChecker` has
        // never heard of "Nitai", and the personal dictionary and the user's
        // contacts both have. Emitted here, above the checker's completions, so
        // the ranking is the list's rather than Apple's — and the caller puts the
        // personal dictionary in front of `UILexicon` inside this list, so a word
        // typed by hand into Settings leads a contact that merely starts the same
        // way.
        //
        // Compared on `comparable` at both ends, so the list is still reachable
        // once a mark has been typed after the word — otherwise `בלי-פר,` offers
        // nothing at all. Skipped for a prefix that is only punctuation, which
        // reduces to "" and which every entry starts with.
        let typed = comparable(prefix)
        if !typed.isEmpty {
            out +=
                supplementary
                .filter { comparable($0).hasPrefix(typed) && comparable($0) != typed }
                .prefix(2)
                .map { Suggestion(text: $0, language: typedLanguage) }
        }

        // Latin letters inside a Hebrew sentence, ranked before the dictionary.
        // Only here: in an English sentence Apple's ranking is the better judge
        // and this list would only crowd it. See `codeSwitchVocabulary`.
        if codeSwitching {
            out +=
                codeSwitchVocabulary
                .filter { $0.hasPrefix(lower) && $0 != lower }
                .prefix(2)
                .map {
                    Suggestion(
                        text: matchCase(of: prefix, applyingTo: $0, in: typedLanguage), language: .english)
                }
        }

        // Apple ships no spell checker for every language this keyboard draws —
        // Persian is not in `UITextChecker.availableLanguages` at all. There is
        // nothing to fall back to: another language's dictionary would offer
        // another language's words, which is worse than offering none.
        guard let languageCode = typedLanguage.spellCheckerLocale else {
            return dedupe(out, limit: 3)
        }

        let nsPrefix = prefix as NSString
        let range = NSRange(location: 0, length: nsPrefix.length)

        if let wordCompletions = sharedChecker.completions(
            forPartialWordRange: range, in: prefix, language: languageCode)
        {
            out +=
                wordCompletions
                .filter { $0.lowercased() != lower }
                .prefix(3)
                .map {
                    Suggestion(
                        text: matchCase(of: prefix, applyingTo: $0, in: typedLanguage),
                        language: typedLanguage)
                }
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
                    .map {
                        Suggestion(
                            text: matchCase(of: prefix, applyingTo: $0, in: typedLanguage),
                            language: typedLanguage)
                    }
            }
        }

        return dedupe(out, limit: 3)
    }

    /// Whether pressing space should replace what was typed.
    ///
    /// Defaulting to "yes" is how autocorrect earns its reputation: one letter in,
    /// and `I` turns into `idea`. Only override the user when there is a real
    /// reason to think they mis-typed.
    @MainActor
    static func shouldAutocorrect(
        _ prefix: String, typedLanguage: KeyboardLanguage, results: [Suggestion],
        supplementary: [String]
    ) -> Bool {
        guard results.count > 1 else { return false }
        let lower = prefix.lowercased()
        let word = wordCore(prefix)

        let typed = comparable(prefix)
        if !typed.isEmpty, supplementary.contains(where: { comparable($0) == typed }) { return false }

        if typedLanguage == .english, contractions[lower] != nil { return true }

        if typedLanguage.script == .hebrew, hebrewFinalFormCorrection(of: prefix) != nil {
            return true
        }

        guard let checkerLocale = typedLanguage.spellCheckerLocale else { return false }

        return word.count >= 4 && !isKnownWord(word, checkerLocale: checkerLocale)
    }

    /// The word inside what was typed, with the marks that sit at its edges
    /// without belonging to it taken off.
    private static func wordCore(_ typed: String) -> String {
        let trimmed = typed.trimmingCharacters(in: .punctuationCharacters)
        guard trimmed.hasSuffix("'s") || trimmed.hasSuffix("'s") else { return trimmed }
        return String(trimmed.dropLast(2)).trimmingCharacters(in: .punctuationCharacters)
    }

    /// A word reduced to the form two spellings of it have in common, for
    /// comparing what is being typed against the user's own list.
    private static func comparable(_ word: String) -> String {
        wordCore(word).lowercased()
            .replacingOccurrences(of: "־", with: "-")
            .replacingOccurrences(of: "'", with: "'")
    }

    @MainActor
    private static func isKnownWord(_ word: String, checkerLocale: String) -> Bool {
        guard !word.isEmpty else { return false }
        let range = NSRange(location: 0, length: (word as NSString).length)
        let misspelled = sharedChecker.rangeOfMisspelledWord(
            in: word, range: range, startingAt: 0, wrap: false,
            language: checkerLocale)
        return misspelled.location == NSNotFound
    }
}
