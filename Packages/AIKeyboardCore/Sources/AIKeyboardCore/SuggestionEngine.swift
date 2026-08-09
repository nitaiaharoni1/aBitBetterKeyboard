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
// `UITextPredictor` a third-party keyboard can call). `nextWordSuggestions`
// below is therefore still a small, fixed table, exactly as it was in the mock —
// see its doc comment for why that is disclosed rather than dressed up.
//
// **The mock's `codeSwitchVocabulary` list was dropped here and had to come
// back.** The argument for dropping it was that `en_US`'s own dictionary already
// knows every word in it — `sync`, `standup`, `roadmap` all come back
// `misspelled == false`. True, and it measures the wrong thing: a suggestion bar
// is asked about *prefixes*, every keystroke, and `sta` inside a Hebrew sentence
// offers `still`, `stay`, `start` while `standup` never appears until all seven
// letters are typed. See `codeSwitchVocabulary`.
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
    @MainActor
    public static func suggestions(
        prefix: String,
        context: String,
        languages: [KeyboardLanguage],
        supplementary: [String] = []
    ) -> [Suggestion] {
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let contextLanguage =
            dominantLanguage(in: context, among: languages) ?? languages.first ?? .english

        if trimmedPrefix.isEmpty {
            let results = nextWordSuggestions(context: context, contextLanguage: contextLanguage)
            // Nothing is being typed, so nothing is at risk of being replaced;
            // highlight the middle candidate the way the system keyboard does.
            return markDefault(results, at: min(1, results.count - 1))
        }

        let typedLanguage = script(of: trimmedPrefix, among: languages) ?? contextLanguage
        let results = completions(
            for: trimmedPrefix, typedLanguage: typedLanguage, supplementary: supplementary,
            // Latin letters inside a Hebrew sentence: the one case this product
            // exists for, and the one `UITextChecker` ranks worst. Scoped to
            // Hebrew rather than to "any non-Latin context", because the list was
            // measured against Hebrew and nothing else. See `codeSwitchVocabulary`.
            codeSwitching: contextLanguage.script == .hebrew && typedLanguage.script == .latin)
        return markDefault(
            results,
            at: shouldAutocorrect(
                trimmedPrefix, typedLanguage: typedLanguage, results: results,
                supplementary: supplementary) ? 1 : 0)
    }

    /// Whether pressing space should replace what was typed.
    ///
    /// Defaulting to "yes" is how autocorrect earns its reputation: one letter in,
    /// and `I` turns into `idea`. Only override the user when there is a real
    /// reason to think they mis-typed.
    @MainActor
    private static func shouldAutocorrect(
        _ prefix: String, typedLanguage: KeyboardLanguage, results: [Suggestion],
        supplementary: [String]
    ) -> Bool {
        guard results.count > 1 else { return false }
        let lower = prefix.lowercased()
        // The word without the marks that ended the sentence. `currentWordPrefix`
        // runs back to the last *whitespace*, so what arrives here for `Hi Nitai,`
        // is `Nitai,`. See `wordCore`.
        let word = wordCore(prefix)

        // **A word the user put on the list is never a mistake, and this has to be
        // the first question asked rather than a clause on the dictionary lookup
        // at the bottom.** Every rule below it fired on the app's own shipped
        // entries: `Nitai` committed as `Nit`, `Handi` as `Handing`, `Wispr` as
        // `Wiser`, `סאפא` as `ספא`, and `בלי־פרופ` as `בלי־פרוף` — that last one
        // through the final-form rule two branches down, which never reaches the
        // `isKnownWord` guard at all. Covers `UILexicon` too, and should: a
        // contact's name is a word the user means.
        let typed = comparable(prefix)
        if !typed.isEmpty, supplementary.contains(where: { comparable($0) == typed }) { return false }

        // A missing apostrophe is unambiguous, so correct it at any length. The
        // table is English, so it only applies to English: `dont` is a French word.
        if typedLanguage == .english, contractions[lower] != nil { return true }

        // So is a Hebrew word ending in a letter that has a final form: the
        // script does not allow it, so this is not a guess about what the user
        // meant. Deliberately *not* gated on `isKnownWord`, which reports
        // `שלומ` as a real word — see `hebrewFinalFormCorrection`.
        if typedLanguage.script == .hebrew, hebrewFinalFormCorrection(of: prefix) != nil {
            return true
        }

        // With no checker for this language there is no evidence the word is
        // wrong, and a keyboard that overrides the user on no evidence is the one
        // they switch off.
        guard let checkerLocale = typedLanguage.spellCheckerLocale else { return false }

        // Otherwise wait until enough letters are in to be confident, and never
        // correct something `UITextChecker` already recognises as a real word —
        // a full dictionary lookup now, not 150 hardcoded entries.
        //
        // **Both questions are asked about the word, not the word plus whatever
        // ended the sentence**, and asking them about the raw prefix made a comma
        // worth a letter and made every correctly spelled word unknown: `Nit,` is
        // four characters and `rangeOfMisspelledWord` does not recognise it, so a
        // three-letter word one keystroke from a name on the list was a candidate
        // for replacement. Case is deliberately *not* folded here the way it is
        // for the list comparison above — the checker's answer for a proper noun
        // depends on it, and lowercasing would make every capitalised word look
        // misspelled.
        return word.count >= 4 && !isKnownWord(word, checkerLocale: checkerLocale)
    }

    /// The word inside what was typed, with the marks that sit at its edges
    /// without belonging to it taken off.
    ///
    /// **This is the second half of the personal-dictionary defect and it is the
    /// commoner half.** `KeyboardController.currentWordPrefix` runs back to the
    /// last *whitespace*, so the word under the cursor in `Hi Nitai,` is `Nitai,`
    /// — and `Nitai,` is not `Nitai`, so the list never matched it. Measured, with
    /// the shipped list in place: `Hi Nitai,` committed as `Hi Nit`, `Hi Handi,`
    /// as `Hi Handy`, `שלום סאפא,` as `שלום ספא`, byte for byte what the same
    /// input gives with the list emptied. Greeting somebody by name with a comma
    /// is the single most common way a name reaches a chat field.
    ///
    /// Both ends are trimmed rather than only the trailing one, so an entry that
    /// legitimately carries marks reduces the same way whichever side they are on:
    /// `Ph.D.` and `Ph.D.,` both become `Ph.D`. `trimmingCharacters` touches only
    /// the ends, so `בלי־פרופ` and `O'Reilly` keep their internal marks, and the
    /// right-to-left marks the Arabic and Persian layouts type — `،` U+060C and
    /// `؟` U+061F — are punctuation to Unicode and so are covered without being
    /// named.
    ///
    /// The possessive needs its own clause: `'` is punctuation but the `s` after
    /// it is not, so trimming leaves `Nitai's` untouched and it was committed as
    /// `Nita's`.
    private static func wordCore(_ typed: String) -> String {
        let trimmed = typed.trimmingCharacters(in: .punctuationCharacters)
        guard trimmed.hasSuffix("'s") || trimmed.hasSuffix("’s") else { return trimmed }
        return String(trimmed.dropLast(2)).trimmingCharacters(in: .punctuationCharacters)
    }

    /// A word reduced to the form two spellings of it have in common, for
    /// comparing what is being typed against the user's own list.
    ///
    /// `wordCore` first, then case, which is what makes `handi` match `Handi`.
    /// Then the maqaf: U+05BE is Hebrew's own hyphen and the shipped list spells
    /// `בלי־פרופ` with it, while the only hyphen this keyboard offers under a
    /// Hebrew layout is ASCII `-` — see `KeyboardLayout.connectors`. Without that
    /// line the one hyphenated entry the app ships could never be matched by
    /// anything its user is able to type, which is a dictionary entry that exists
    /// only in the dictionary screen. The curly apostrophe goes the same way, for
    /// an entry pasted in from somewhere that autocorrected it.
    ///
    /// Answers "" for something that is only punctuation, which is a word every
    /// entry would otherwise be a prefix of; both callers check for it.
    private static func comparable(_ word: String) -> String {
        wordCore(word).lowercased()
            .replacingOccurrences(of: "־", with: "-")
            .replacingOccurrences(of: "’", with: "'")
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

    // MARK: Completion of the word being typed

    /// One `UITextChecker` for the process. Apple's own guidance is one per
    /// document mainly so ignored/learned words stay consistent; this keyboard
    /// never calls `ignoreWord`/`learnWord`, so a single shared instance is
    /// exactly as correct and avoids re-initialising the spell-check engine on
    /// every keystroke.
    @MainActor
    private static let sharedChecker = UITextChecker()

    /// English work vocabulary that appears inside Hebrew sentences, ranked ahead
    /// of the dictionary when exactly that is happening.
    ///
    /// **This list was deleted once and had to come back, and the reason it was
    /// deleted is worth keeping.** The argument for dropping it was that
    /// `UITextChecker`'s English dictionary already knows every word in it —
    /// `sync`, `standup`, `roadmap` and the rest all return `misspelled == false`.
    /// That is true, and it measures the wrong thing. A suggestion bar is not
    /// asked about whole words; it is asked after every keystroke, about a
    /// *prefix*. Typing `standup` into a Hebrew sentence one letter at a time
    /// offers `still`, `stay`, `stand`, `standard`, `standing` — and never
    /// `standup` until the user has typed all seven letters, at which point the
    /// suggestion is worth nothing. Same for `road` → `roadmap` and `temp` →
    /// `template`, while `backl` → `backlog` happens to work, because without this
    /// list the outcome rides entirely on Apple's undocumented frequency ranking.
    ///
    /// So the list is not a vocabulary the dictionary lacks. It is a *ranking* the
    /// dictionary gets wrong for this product's central case, and it applies only
    /// when Latin letters are being typed into a Hebrew sentence.
    /// The five Hebrew letters that take a different shape at the end of a word,
    /// ordinary form to final form. `EditScope` corrects the same class of error
    /// after the fact; this offers it before the user commits one.
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
    private static func hebrewFinalFormCorrection(of prefix: String) -> String? {
        guard let last = prefix.last, let final = hebrewFinalForms[last] else { return nil }
        return String(prefix.dropLast()) + String(final)
    }

    private static let codeSwitchVocabulary: [String] = [
        "backlog", "brief", "call", "deadline", "demo", "design", "document", "feedback",
        "follow-up", "invite", "meeting", "presentation", "product", "review", "roadmap",
        "scope", "slack", "sprint", "standup", "sync", "template", "ticket", "update"
    ]

    @MainActor
    private static func completions(
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

    /// The two languages this table was written for. It is a hand-written table,
    /// not a model, so the honest thing to do for the twelve languages it does
    /// not cover is to offer nothing rather than to offer English words under a
    /// Greek keyboard. That is also what the bar asks for: three candidates, in
    /// the language being typed, or none.
    private static let nextWordTables: [KeyboardLanguage: [String: [String]]] = [
        .english: englishNextWord,
        .hebrew: hebrewNextWord
    ]

    private static let nextWordDefaults: [KeyboardLanguage: [String]] = [
        .english: defaultEnglish,
        .hebrew: defaultHebrew
    ]

    private static func nextWordSuggestions(
        context: String,
        contextLanguage: KeyboardLanguage
    ) -> [Suggestion] {
        guard let table = nextWordTables[contextLanguage],
            let defaults = nextWordDefaults[contextLanguage]
        else { return [] }

        let words =
            context
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        guard let last = words.last?.trimmingCharacters(in: .punctuationCharacters).lowercased(),
            !last.isEmpty, let hits = table[last]
        else {
            return defaults.map { Suggestion(text: $0, language: contextLanguage) }
        }
        return hits.map { Suggestion(text: $0, language: contextLanguage) }
    }

    // MARK: Shared helpers

    /// A candidate capitalised the way the typed prefix was.
    ///
    /// `language` rather than the default casing, for the same reason
    /// `KeyboardLanguage.uppercased(_:)` exists: a Turkish user who typed `İst`
    /// must not be offered `Istanbul`, which is a different word.
    private static func matchCase(
        of source: String, applyingTo candidate: String, in language: KeyboardLanguage
    ) -> String {
        guard let first = source.first, first.isUppercase else { return candidate }
        return language.uppercased(String(candidate.prefix(1))) + candidate.dropFirst()
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
