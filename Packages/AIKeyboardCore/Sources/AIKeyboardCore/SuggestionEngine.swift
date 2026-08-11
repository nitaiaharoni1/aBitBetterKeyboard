import Foundation
import UIKit

// MARK: - Suggestions
//
// Backs the suggestion bar with `UITextChecker`, Apple's public on-device
// spelling and completion API. Replaces `MockSuggestionEngine`.
//
// (Not "the engine the system keyboard's autocorrect draws on" — this file said
// that, and Apple documents no such relationship. It is also in tension with the
// paragraph below about QuickType being private. `UITextChecker` is the public
// API a third-party keyboard can call; what the system keyboard uses internally
// is not something this repo knows.)
//
// **Verified before writing this, not assumed:** `UITextChecker.availableLanguages`
// on the iOS 26.2 Simulator lists 42 languages including `he_IL`, and
// `completions(forPartialWordRange:in:language:)` returns real, well-formed
// Hebrew — `אנ` completes to `אני`, `אנחנו`, `אנשים`. So Hebrew is not a
// second-class case here the way it is for Foundation Models, `SpeechTranscriber`
// and Vision's text recognizer: `UITextChecker` is an older API with its own
// language list, and this one has Hebrew.
//
// **That list does not cover every keyboard this product draws, and its shape is
// its own.** Thirteen of the fourteen shipped languages are in it, under
// identifiers that have to be read rather than derived — `he_IL` and `de_DE`
// carry a region, `ar` and `hi` do not. Persian is absent altogether, so a
// Persian keyboard gets no completions and no autocorrect: the engine returns the
// keystrokes and stops. That is deliberate and it is the whole reason
// `KeyboardLanguage.spellCheckerLocale` is optional. Falling back to another
// language's dictionary would offer Arabic words to a Persian typist, which is
// worse than offering nothing, and falling back to English would be worse again.
//
// **What the checker will do for a language is not what its presence in the list
// suggests, and this was measured too.** On the iOS 26.2 Simulator
// `completions` returns real words for English, Hebrew and Hindi and an empty
// array for Arabic, Russian, Ukrainian, Greek, Turkish, Spanish, French, German,
// Portuguese and Italian — the log says `Lexicon creation for <lang> failed:
// Could not determine the location of the base unigrams file`. `guesses` still
// corrects misspellings for the Latin languages and Russian. So on a simulator
// most languages get spelling correction and no completion. Whether a device with
// those keyboards installed ships the missing unigram files is not something this
// repo has been able to check, so nothing here claims it.
//
// **Its Hebrew is not as good as that makes it sound, and two measured limits
// are handled here rather than papered over.** `guesses` ranks `שלום` third for
// the misspelling `שלומ`, behind `שלו` and `שלוש`, and the guesses branch does
// not even run when completions came back fat — which for `שלומ` they do, twelve
// of them. Left alone the bar offers `שלומדים` as the default, so pressing space
// to say "hello" commits "who are studying". `hebrewFinalFormCorrection` fixes
// that class outright, without asking the dictionary; see it for why not.
//
// **What is genuinely NOT available, and was not faked to look like it is:**
// Apple exposes no public API for predicting the *next* word from nothing typed
// — that is QuickType's job, and QuickType is `UIKitCore`-private
// (`UIDictationController` and its neighbours; there is no public
// `UITextPredictor` a third-party keyboard can call). So `nextWordSuggestions`
// is built out of what this keyboard can see for itself: what *this user* writes
// after a word (`PersonalLanguageModel`), what people generally write after it
// (`SeedLanguageModel`'s bigrams), and a handful of openers for a field with
// nothing in it. None of that is a language model and none of it is presented as
// one. **This paragraph used to end "still a small, fixed table, exactly as it
// was in the mock", and stayed that way after the table was replaced** — which
// is the failure mode the rest of this comment block exists to prevent, so it is
// worth naming.
//
// **Two other things this file no longer does alone.** `UITextChecker` has no
// frequency model, so the ranking it implied was wrong often enough to matter —
// `helo` completed to `helot` and never to `hello`. `SeedLanguageModel` supplies
// the missing prior and `SuggestionEngine+Candidates` does the ranking; this file
// only decides which sources to ask. And Hebrew needed `HebrewMorphology` before
// any of that could help it, because the language glues its commonest function
// words to the front of the next one and no dictionary lists the glued forms.
//
// **The mock's `codeSwitchVocabulary` list was dropped here and had to come
// back.** The argument for dropping it was that `en_US`'s own dictionary already
// knows every word in it — `sync`, `standup`, `roadmap` all come back
// `misspelled == false`. True, and it measures the wrong thing: a suggestion bar
// is asked about *prefixes*, every keystroke, and `sta` inside a Hebrew sentence
// offers `still`, `stay`, `start` while `standup` never appears until all seven
// letters are typed. See `codeSwitchVocabulary` in SuggestionEngine+Completions.swift.
//
// **Everything above is measurable and is measured.** `Bar/typing/harness/run.sh`
// runs this engine over the 90 frozen moments in `Bar/typing/corpus.json` and
// `score.py` grades it. Run it before and after any change here.
public enum SuggestionEngine {

    // MARK: Script detection
    //
    // Pure character arithmetic over `LanguageDetector`, not a mock in the first
    // place. Kept here because `DictationPanel` needs it and this is the type
    // that replaces the one it used to call.

    /// Which language a run of text is written in, ignoring digits and punctuation.
    ///
    /// Answers with a *language*, from a script, which is a step that can only be
    /// taken with a list of candidates in hand: Cyrillic is Russian or Ukrainian
    /// and the characters cannot say which. `candidates` is ordered, the layout on
    /// screen first, and the first one written in the winning script takes it —
    /// which is the only mechanism that separates the eight Latin languages, the
    /// two Cyrillic ones and the two written in the Arabic script. When none of
    /// them is written in the script that won, the catalogue answers instead: the
    /// text is in that script whether or not the user enabled a keyboard for it.
    public static func dominantLanguage(
        in text: String, among candidates: [KeyboardLanguage] = KeyboardLanguage.allCases
    ) -> KeyboardLanguage? {
        guard let winner = scriptsByFrequency(in: text).first else { return nil }
        return language(writtenIn: winner, among: candidates)
    }

    /// Every language a run of text is written in, the one with the most letters
    /// first.
    ///
    /// The same arithmetic `dominantLanguage` does, without throwing away the
    /// runners-up — because "which two languages is this sentence in" is a question
    /// this product has to answer and there was no honest way to ask it. The
    /// dictation panel's mixed-language badge used to take the dominant language
    /// and step one row down the catalogue, which was the right answer while the
    /// catalogue held English and Hebrew and became `עב ⟷ ع` the day it held
    /// fourteen.
    ///
    /// A script the catalogue has no keyboard for is dropped rather than named, so
    /// this is shorter than the list of scripts present. `dominantLanguage` keeps
    /// the older behaviour of answering nil in that case rather than skipping to
    /// the runner-up: the two questions differ, and a Japanese sentence with an
    /// English word in it is not an English sentence.
    public static func languages(
        in text: String, among candidates: [KeyboardLanguage] = KeyboardLanguage.allCases
    ) -> [KeyboardLanguage] {
        scriptsByFrequency(in: text).compactMap { language(writtenIn: $0, among: candidates) }
    }

    /// Most letters first, and on a tie the script that is not Latin — a sentence
    /// with as much Hebrew in it as English is a Hebrew sentence carrying
    /// loanwords, and this product exists for that sentence. Beyond that, the ISO
    /// 15924 code, only so two runs over one string cannot disagree:
    /// `sorted(by:)` is not stable and a dictionary has no order to inherit.
    private static func scriptsByFrequency(in text: String) -> [TextScript] {
        var counts: [TextScript: Int] = [:]
        for scalar in text.unicodeScalars {
            guard let script = LanguageDetector.script(ofLetter: scalar) else { continue }
            counts[script, default: 0] += 1
        }
        return
            counts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                let lhsIsLatin = lhs.key == .latin
                if lhsIsLatin != (rhs.key == .latin) { return !lhsIsLatin }
                return lhs.key.rawValue < rhs.key.rawValue
            }
            .map(\.key)
    }

    /// The first candidate written in this script, else the catalogue's, else nil
    /// — which is every script the keyboard ships no layout for, `.other` included.
    private static func language(
        writtenIn script: TextScript, among candidates: [KeyboardLanguage]
    ) -> KeyboardLanguage? {
        candidates.first { $0.script == script }
            ?? KeyboardLanguage.allCases.first { $0.script == script }
    }

    private static func script(
        of word: String, among candidates: [KeyboardLanguage]
    ) -> KeyboardLanguage? {
        dominantLanguage(in: word, among: candidates)
    }

    /// Three candidates for the suggestion bar.
    ///
    /// - Parameters:
    ///   - prefix: the word currently being typed, may be empty
    ///   - context: everything before the current word
    ///   - languages: the languages the user turned on, **the layout on screen
    ///     first**. The order is not decoration: characters name a script and
    ///     never a language, so with two languages of one script enabled this
    ///     list is the only thing that can separate them, and every resolution
    ///     below takes the first candidate written in the script it sees.
    ///     `KeyboardController.refreshSuggestions` builds it; passing the stored
    ///     list instead spell-checked a French user against `en_US`.
    ///   - supplementary: words this keyboard must not second-guess — the user's
    ///     personal dictionary from `SharedStore`, then the names and shortcuts
    ///     `UILexicon` hands back
    ///     (`UIInputViewController.requestSupplementaryLexicon`). The personal
    ///     dictionary leads because it is the list the user typed by hand; the
    ///     lexicon is contacts and text replacements and is empty outside a real
    ///     keyboard session, which is why the app's playground and most tests
    ///     pass only the first half. `KeyboardController.refreshSuggestions`
    ///     joins them.
    ///   - personal: what this user's own typing has taught the keyboard. Defaults
    ///     to the shared store; tests and `Bar/typing/harness` pass an empty
    ///     in-memory one, so a score can never quietly inherit whatever the
    ///     developer has been typing.
    @MainActor
    public static func suggestions(
        prefix: String,
        context: String,
        languages: [KeyboardLanguage],
        supplementary: [String] = [],
        // Optional rather than defaulted to `.shared`, because a default argument
        // is evaluated in the *caller's* isolation and `.shared` is main-actor
        // isolated — which is a warning today and an error under Swift 6.
        personal personalOrNil: PersonalLanguageModel? = nil
    ) -> [Suggestion] {
        let personal = personalOrNil ?? .shared
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let contextLanguage =
            dominantLanguage(in: context, among: languages) ?? languages.first ?? .english

        if trimmedPrefix.isEmpty {
            let results = nextWordSuggestions(
                context: context, contextLanguage: contextLanguage, personal: personal)
            // Nothing is being typed, so nothing is at risk of being replaced;
            // bold the middle candidate the way the system keyboard does. The best
            // guess *is* the middle one — `rank` returns best-first and this moves
            // it there, rather than boldening whatever landed in the middle.
            return markDefault(promoteToMiddle(results), at: min(1, results.count - 1))
        }

        let typedLanguage = script(of: trimmedPrefix, among: languages) ?? contextLanguage
        let preceding = previousWords(in: context)
        let results = completions(
            for: trimmedPrefix,
            previousWords: preceding,
            typedLanguage: typedLanguage,
            // The other layout the user has enabled, for the case where every key
            // was right and the plane was wrong. Nil when they have only one, in
            // which case there is no other layout they could have been on.
            otherLanguage: languages.first { $0.script != typedLanguage.script },
            supplementary: supplementary,
            personal: personal,
            // Latin letters inside a Hebrew sentence: the one case this product
            // exists for, and the one `UITextChecker` ranks worst. Scoped to
            // Hebrew rather than to "any non-Latin context", because the list was
            // measured against Hebrew and nothing else. See `codeSwitchVocabulary`.
            codeSwitching: contextLanguage.script == .hebrew && typedLanguage.script == .latin)
        return markDefault(
            results,
            at: shouldAutocorrect(
                trimmedPrefix, previousWords: preceding,
                typedLanguage: typedLanguage, results: results,
                supplementary: supplementary, personal: personal) ? 1 : 0)
    }

    /// The committed words directly before the cursor, in order, at most `limit`
    /// of them.
    ///
    /// **Stops at the end of a sentence, and that is the point of it.** A full
    /// stop, a question mark or a newline closes the thought, so the words before
    /// one are not context for the word after it: predicting `much` from
    /// `Thank you so much. ` would be reading across a boundary the writer just
    /// drew. Empty means there is nothing to predict *from*, which is a different
    /// answer from "no prediction" and the callers treat it as one.
    ///
    /// **The newline half of that was written down and not implemented.** This
    /// began by trimming the whole context, which takes the line break off the
    /// end, and then split on whitespace, which a line break also is — so a
    /// newline was invisible twice over and `See you\n` predicted `tomorrow`
    /// exactly as `See you ` does. Reading only the last line is what makes the
    /// sentence in the comment true; it also stops a space pressed at the head of
    /// a fresh line teaching `PersonalLanguageModel` the previous line's last
    /// word a second time.
    static func previousWords(in context: String, limit: Int = 2) -> [String] {
        let lineStart =
            context.lastIndex(where: \.isNewline).map { context.index(after: $0) }
            ?? context.startIndex
        let trimmed = context[lineStart...].trimmingCharacters(in: .whitespacesAndNewlines)
        var out: [String] = []
        for token in trimmed.split(whereSeparator: \.isWhitespace).suffix(limit) {
            if token.last.map({ ".!?…،؟".contains($0) }) == true {
                // The boundary is between this token and the next, so everything
                // gathered so far is on the far side of it.
                out.removeAll()
                continue
            }
            let word = String(token).trimmingCharacters(in: .punctuationCharacters)
            if !word.isEmpty { out.append(word) }
        }
        return out
    }

    /// The best candidate moved into slot 1.
    ///
    /// Only for the empty-prefix case, where iOS's own convention is that the
    /// middle slot is both bold and the likeliest word. Mid-word the convention is
    /// the opposite — slot 0 is what you typed — so this must never run there.
    private static func promoteToMiddle(_ items: [Suggestion]) -> [Suggestion] {
        guard items.count >= 2 else { return items }
        var reordered = items
        reordered.swapAt(0, 1)
        return reordered
    }

    // MARK: Shared helpers

    /// A candidate capitalised the way the typed prefix was.
    ///
    /// `language` rather than the default casing, for the same reason
    /// `KeyboardLanguage.uppercased(_:)` exists: a Turkish user who typed `İst`
    /// must not be offered `Istanbul`, which is a different word.
    static func matchCase(
        of source: String, applyingTo candidate: String, in language: KeyboardLanguage
    ) -> String {
        guard let first = source.first, first.isUppercase else { return candidate }
        return language.uppercased(String(candidate.prefix(1))) + candidate.dropFirst()
    }

    static func markDefault(_ items: [Suggestion], at defaultIndex: Int) -> [Suggestion] {
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
    ///
    /// **`id` was in here and had to come out.** Membership of this table is what
    /// makes a word get replaced on the space bar, and `id` is an ordinary English
    /// noun — so `That's a good id` committed as `That's a good I'd`, which is the
    /// corpus's `nc-02`. The rest of the table has no such reading: nobody types
    /// `dont` or `havent` meaning anything but the contraction. `I'd` is also the
    /// rarest expansion in the set, so the trade is a common wrong correction
    /// against an uncommon missing one. `were` is excluded for the same reason:
    /// distinguishing it from `we're` would require word-specific context logic
    /// this deliberately context-free table does not have.
    static let contractions: [String: String] = [
        "dont": "don't", "doesnt": "doesn't", "didnt": "didn't", "cant": "can't",
        "wont": "won't", "isnt": "isn't", "wasnt": "wasn't", "arent": "aren't",
        "werent": "weren't", "couldnt": "couldn't", "shouldnt": "shouldn't",
        "wouldnt": "wouldn't", "hasnt": "hasn't", "havent": "haven't", "hadnt": "hadn't",
        "im": "I'm", "ive": "I've", "ill": "I'll",
        "youre": "you're", "youve": "you've", "youll": "you'll",
        "theyre": "they're", "theyve": "they've", "thats": "that's",
        "whats": "what's", "hes": "he's", "shes": "she's", "lets": "let's",
        "its": "it's", "theres": "there's", "heres": "here's"
    ]
}
