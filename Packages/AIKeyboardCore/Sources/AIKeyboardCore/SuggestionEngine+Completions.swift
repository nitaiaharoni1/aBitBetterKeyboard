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
    ///
    /// The table itself moved to `HebrewMorphology`, which is where the rest of
    /// the facts about how Hebrew spells a word end.
    @MainActor
    static func hebrewFinalFormCorrection(of prefix: String) -> String? {
        HebrewMorphology.inFinalForm(prefix)
    }

    /// Latin words that appear inside Hebrew sentences and that `UITextChecker`
    /// ranks badly there.
    ///
    /// **Dropped once and had to come back.** The argument for dropping it was
    /// that `en_US`'s own dictionary already knows every word in it — `sync`,
    /// `standup`, `roadmap` all come back `misspelled == false`. True, and it
    /// measures the wrong thing: a suggestion bar is asked about *prefixes*, every
    /// keystroke, and `sta` inside a Hebrew sentence offers `still`, `stay`,
    /// `start` while `standup` never appears until all seven letters are typed.
    ///
    /// Place and brand names are **not** here — they went into the seed list, so
    /// they arrive ranked alongside ordinary words instead of through a second
    /// mechanism that has no opinion about which of them is common.
    private static let codeSwitchVocabulary: [String] = [
        "backlog", "brief", "call", "deadline", "demo", "deploy", "deployment", "design",
        "document", "feedback", "follow-up", "invite", "meeting", "presentation", "product",
        "review", "roadmap", "scope", "slack", "sprint", "standup", "sync", "template",
        "ticket", "update"
    ]

    /// Every candidate for the word in progress, ranked, three deep.
    ///
    /// - Parameters:
    ///   - prefix: the word being typed.
    ///   - previousWords: the committed words directly before it, in order, empty
    ///     at the start of a message or after a full stop. This is the sentence
    ///     half of "context aware": it is what lets `לקבוע תו` reach `תור` instead
    ///     of the four-times-commoner `תודה`, and `See you ` reach `tomorrow`
    ///     instead of the three words that merely follow `you`.
    ///   - typedLanguage: the language the characters are written in.
    ///   - otherLanguage: the other language the user enabled, for wrong-layout
    ///     detection. Nil when they have only one.
    ///   - supplementary: the personal dictionary, then `UILexicon`.
    ///   - personal: what this user's own typing has taught the keyboard.
    ///   - codeSwitching: Latin letters inside a Hebrew sentence.
    @MainActor
    static func completions(
        for prefix: String,
        previousWords: [String],
        typedLanguage: KeyboardLanguage,
        otherLanguage: KeyboardLanguage?,
        supplementary: [String],
        personal: PersonalLanguageModel,
        codeSwitching: Bool = false
    ) -> [Suggestion] {
        let lower = prefix.lowercased()
        var out: [Candidate] = []

        // The literal keystrokes always stay available, so the engine can never
        // trap the user into a word they did not want.
        out.append(Candidate(text: prefix, language: typedLanguage, source: .typed))

        // Every key was right and the layout was wrong. Deterministic, and the
        // strongest signal in here when it fires at all — see LayoutTransposition
        // for how narrow the gate is.
        if let other = otherLanguage,
            let transposed = LayoutTransposition.correction(
                of: prefix, typedLanguage: typedLanguage, other: other,
                isKnownWord: { word, language in
                    guard let locale = language.spellCheckerLocale else { return false }
                    return isKnownWord(word, checkerLocale: locale)
                })
        {
            out.append(Candidate(text: transposed, language: other, source: .layout))
        }

        // A dropped apostrophe is the most common thing worth fixing. English
        // only: every entry in the table is an English contraction, and several of
        // them — `dont`, `cant` — are ordinary words in other languages that use
        // this alphabet.
        if typedLanguage == .english, let contraction = contractions[lower] {
            out.append(
                Candidate(
                    text: matchCase(of: prefix, applyingTo: contraction, in: typedLanguage),
                    language: .english, source: .orthography))
        }

        // Hebrew's equivalent. Five letters change shape at the end of a word, and
        // typing the ordinary form there is the language's commonest keying error:
        // `שלומ` is `שלום`, "hello", with a plain mem. Left to `UITextChecker`
        // alone the user is actively harmed rather than merely unhelped — `שלומ`
        // has twelve real completions, so the correction branch never runs, and
        // `שלומדים` was offered as the default. Pressing space to accept "hello"
        // committed "who are studying".
        //
        // Scoped to the Hebrew script and nothing wider. Arabic and Persian also
        // change letter shape at the end of a word, but they do it in the *font*
        // rather than in the code point — there is no wrong character to correct —
        // so a rule generalised across right-to-left scripts would fire on
        // correctly spelled Arabic and mangle it.
        if typedLanguage.script == .hebrew, let final = hebrewFinalFormCorrection(of: prefix) {
            out.append(Candidate(text: final, language: .hebrew, source: .orthography))
        }

        // The user's own words outrank the system dictionary: `UITextChecker` has
        // never heard of "Nitai", and the personal dictionary and the user's
        // contacts both have. The caller puts the personal dictionary in front of
        // `UILexicon`, so a word typed by hand into Settings leads a contact that
        // merely starts the same way.
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
                .enumerated()
                .map {
                    Candidate(
                        text: $0.element, language: typedLanguage, source: .personal,
                        ordinal: $0.offset)
                }
        }

        // What this user actually types, which is the half no dictionary can
        // supply and the half that makes the bar theirs.
        out +=
            personal.words(startingWith: prefix, in: typedLanguage, limit: 3)
            .enumerated()
            .map {
                Candidate(
                    text: matchCase(of: prefix, applyingTo: $0.element, in: typedLanguage),
                    language: typedLanguage, source: .learned, ordinal: $0.offset)
            }

        // The bundled seed list, read through every Hebrew reading of the prefix.
        out += seedCandidates(for: prefix, typedLanguage: typedLanguage, personal: personal)

        // Latin letters inside a Hebrew sentence, ranked before the dictionary.
        // Only here: in an English sentence Apple's ranking is the better judge and
        // this list would only crowd it.
        if codeSwitching {
            out +=
                codeSwitchVocabulary
                .filter { $0.hasPrefix(lower) && $0 != lower }
                .prefix(2)
                .enumerated()
                .map {
                    Candidate(
                        text: matchCase(of: prefix, applyingTo: $0.element, in: typedLanguage),
                        language: .english, source: .codeSwitch, ordinal: $0.offset)
                }
        }

        out += checkerCandidates(for: prefix, typedLanguage: typedLanguage)

        // The sentence gets its say last, over everything already collected, so a
        // word the previous word is known to be followed by climbs whichever
        // source it happened to arrive from.
        let followers = Set(
            (SeedLanguageModel.followers(after: previousWords, in: typedLanguage)
                + personal.followers(after: previousWords.last ?? "", in: typedLanguage, limit: 4))
                .map(SeedLanguageModel.fold))
        if !followers.isEmpty {
            for index in out.indices where followers.contains(SeedLanguageModel.fold(out[index].text)) {
                out[index].followsContext = true
            }
        }

        return rank(out, limit: 3)
    }

    /// Seed-list completions, including the ones only reachable by taking a Hebrew
    /// word apart.
    ///
    /// For English this is a plain prefix search. For Hebrew it runs once per
    /// reading from `HebrewMorphology.splits` — `לעבו` as itself, and as `ל` +
    /// `עבו` — and puts the clitic back on whatever the stem completed to. That
    /// second reading is the one that reaches `לעבודה`; no dictionary lists the
    /// glued form, so without it the word is unreachable no matter how good the
    /// ranking is.
    @MainActor
    private static func seedCandidates(
        for prefix: String, typedLanguage: KeyboardLanguage, personal: PersonalLanguageModel
    ) -> [Candidate] {
        var out: [Candidate] = []
        let readings: [(prefix: String, stem: String)] =
            typedLanguage.script == .hebrew
            ? HebrewMorphology.splits(of: prefix) : [("", prefix)]

        for reading in readings {
            let depth = reading.prefix.count
            let seedStems = SeedLanguageModel.words(
                startingWith: reading.stem, in: typedLanguage, limit: 3)
            let personalStems = personal.words(
                startingWith: reading.stem, in: typedLanguage, limit: 2)
            for (index, stem) in seedStems.enumerated() {
                out.append(
                    Candidate(
                        text: matchCase(
                            of: prefix, applyingTo: reading.prefix + stem, in: typedLanguage),
                        language: typedLanguage, source: .seed, cliticDepth: depth,
                        ordinal: index))
            }
            for (index, stem) in personalStems.enumerated() {
                out.append(
                    Candidate(
                        text: matchCase(
                            of: prefix, applyingTo: reading.prefix + stem, in: typedLanguage),
                        language: typedLanguage, source: .learned, cliticDepth: depth,
                        ordinal: index))
            }
            // Hebrew's own dictionary, asked about the stem rather than the glued
            // word, which is the only form it has an entry for. Only for a split
            // reading: the unsplit one is what `checkerCandidates` already asks
            // about, and asking twice would double every English completion.
            //
            // **And never about a single letter.** The seed list above answers a
            // one-letter stem from a few hundred ranked words, which is how `מהג`
            // reaches `מהגן`; `UITextChecker` would answer the same question with
            // every word in Hebrew that starts with that letter, unranked.
            //
            // **And never when the seed already answered this reading**, which is
            // a latency rule with a number behind it. `UITextChecker.completions`
            // costs a few milliseconds a call, and a Hebrew word has up to three
            // readings, so asking for every one of them put `הכתו` at 15 ms on a
            // keystroke budget of about 20 ms for the whole key press — drawing
            // included. The seed is the ranked source and the checker is the
            // fallback for what it does not know; asking the fallback about a
            // question already answered was buying duplicates at the worst
            // possible moment.
            //
            // **Measured over four runs of the 90 corpus entries, warm, on the iOS
            // 26.2 Simulator — and one run is not evidence here either.** Median
            // lands at 1.1-1.3 ms and the worst entry at 10-16 ms, with *which*
            // entry is slowest changing between runs of identical code; a single
            // run also produced a 27 ms outlier that did not reproduce. What is
            // stable is the shape: the slow entries are always Hebrew words where
            // the seed has nothing and more than one reading has to be asked, and
            // `UITextChecker.completions` is what costs. The corpus score does not
            // move at all across those runs, which is the number to trust. Before
            // this rule the same measurement sat one call per reading higher.
            // The cost that remains is what morphology buys and is not removable
            // from here.
            guard depth > 0, reading.stem.count >= 2, seedStems.isEmpty,
                let locale = typedLanguage.spellCheckerLocale
            else { continue }
            for (index, completion) in checkerCompletions(of: reading.stem, locale: locale)
                .prefix(2).enumerated()
            {
                out.append(
                    Candidate(
                        text: reading.prefix + completion, language: typedLanguage,
                        source: .checker, cliticDepth: depth, ordinal: index))
            }
        }
        return out
    }

    /// `UITextChecker`'s own answers about the word as typed: completions first,
    /// and corrections only when the completions came back thin.
    ///
    /// **Measured, disclosed gap in the correction half.** `recieve` completes to
    /// nothing, so the correction branch fires and `guesses` gives `receive`.
    /// `helo` completes to `helot`/`helots` — real words, so the branch never runs
    /// — and the much likelier `hello` sits second in `guesses`. That specific
    /// failure is now caught upstream by the seed list rather than here, because
    /// `hello` is a common word and `helot` is not; the branch below is still
    /// gated the same way, since running `guesses` on every keystroke costs more
    /// than it returns once a frequency prior exists.
    @MainActor
    private static func checkerCandidates(
        for prefix: String, typedLanguage: KeyboardLanguage
    )
        -> [Candidate]
    {
        // Apple ships no spell checker for every language this keyboard draws —
        // Persian is not in `UITextChecker.availableLanguages` at all. There is
        // nothing to fall back to: another language's dictionary would offer
        // another language's words, which is worse than offering none.
        guard let locale = typedLanguage.spellCheckerLocale else { return [] }
        let lower = prefix.lowercased()
        var out: [Candidate] = []

        out +=
            checkerCompletions(of: prefix, locale: locale)
            .prefix(4)
            .enumerated()
            .map {
                Candidate(
                    text: matchCase(of: prefix, applyingTo: $0.element, in: typedLanguage),
                    language: typedLanguage, source: .checker, ordinal: $0.offset)
            }

        // A common word one keystroke away.
        //
        // **Gated on what was typed, not on how many completions came back.** Two
        // earlier placements both failed: under `rangeOfMisspelledWord` it never
        // ran for a Hebrew typo at all, because Apple's Hebrew checker does not
        // report `תדוה` as misspelled; under the "fewer than two completions" gate
        // it never ran for `שלמו`, because taking the word apart had already
        // produced two. The condition that actually matters is neither — it is
        // that the *typed* word is absent from the common core. A word that is
        // itself common needs no neighbours (`bus` must never be shown `but`), and
        // a word that is not is worth asking about however many completions it
        // happens to have.
        if !SeedLanguageModel.knows(prefix, in: typedLanguage) {
            out +=
                SeedLanguageModel.neighbours(of: prefix, in: typedLanguage, limit: 2)
                .enumerated()
                .map {
                    Candidate(
                        text: matchCase(of: prefix, applyingTo: $0.element, in: typedLanguage),
                        language: typedLanguage, source: .neighbour, ordinal: $0.offset)
                }
        }

        guard out.count < 2 else { return out }

        let nsPrefix = prefix as NSString
        let range = NSRange(location: 0, length: nsPrefix.length)
        let misspelled = sharedChecker.rangeOfMisspelledWord(
            in: prefix, range: range, startingAt: 0, wrap: false, language: locale)
        guard misspelled.location != NSNotFound else { return out }

        if let corrections = sharedChecker.guesses(
            forWordRange: range, in: prefix, language: locale)
        {
            out +=
                corrections
                .filter { $0.lowercased() != lower }
                .prefix(3)
                .enumerated()
                .map {
                    Candidate(
                        text: matchCase(of: prefix, applyingTo: $0.element, in: typedLanguage),
                        language: typedLanguage, source: .correction, ordinal: $0.offset)
                }
        }
        return out
    }

    @MainActor
    private static func checkerCompletions(of word: String, locale: String) -> [String] {
        let nsWord = word as NSString
        guard nsWord.length > 0 else { return [] }
        let range = NSRange(location: 0, length: nsWord.length)
        let lower = word.lowercased()
        return
            (sharedChecker.completions(forPartialWordRange: range, in: word, language: locale)
            ?? [])
            .filter { $0.lowercased() != lower }
    }

    /// Whether pressing space should replace what was typed.
    ///
    /// **Defaulting to "yes" is how autocorrect earns its reputation**, so this
    /// reads as a list of reasons to override the user rather than a list of
    /// reasons not to. Every `return true` below is a case where the typed
    /// characters are known to be wrong; everything else keeps what they keyed.
    @MainActor
    static func shouldAutocorrect(
        _ prefix: String, previousWords: [String], typedLanguage: KeyboardLanguage,
        results: [Suggestion], supplementary: [String], personal: PersonalLanguageModel
    ) -> Bool {
        guard results.count > 1 else { return false }
        let lower = prefix.lowercased()
        let word = wordCore(prefix)

        // The user's own list is absolute, and it is asked first rather than as a
        // clause on `isKnownWord` at the bottom: the contraction table and the
        // Hebrew final-form rule both return true above that line, and the
        // final-form rule is what used to eat `בלי־פרופ`.
        let typed = comparable(prefix)
        if !typed.isEmpty, supplementary.contains(where: { comparable($0) == typed }) { return false }
        // And so is a word this person has typed for themselves often enough to
        // mean it. Inferred rather than declared, so it takes repetition — see
        // `PersonalLanguageModel.protectThreshold`.
        if personal.isProtected(word, in: typedLanguage) { return false }

        // The wrong layout is not a spelling mistake and is not judged like one:
        // the candidate is in a different alphabet, so `isKnownWord` on the typed
        // characters can never object.
        if let first = results.dropFirst().first, first.language.script != typedLanguage.script {
            return true
        }

        // **Asked before the seed list, not after, and the order is the rule.**
        // `its`, `cant` and `ill` are all ordinary English words *and* all
        // apostrophe-dropped contractions, so a "we never correct a word" test
        // placed above this one keeps every one of them and the whole table stops
        // firing on exactly the words it was written for. Which reading is meant is
        // decided once, by whether the word is in the table at all — see
        // `contractions` — and never again at runtime.
        if typedLanguage == .english, contractions[lower] != nil { return true }

        if typedLanguage.script == .hebrew, hebrewFinalFormCorrection(of: prefix) != nil {
            return true
        }

        // A word the seed list knows is a word, and a keyboard does not correct
        // words. This is what stops `Tzachi` becoming `Teach` and `Bit` becoming
        // `Bitten`.
        if SeedLanguageModel.knows(word, in: typedLanguage) { return false }

        guard let first = results.dropFirst().first else { return false }
        let winner = SeedLanguageModel.fold(first.text)

        // **The sentence outvoting the dictionary, and the only place it does.**
        // `בעוד רבה` is two real Hebrew words that never appear in that order;
        // `בעוד רבע` ("in a quarter of an hour") is one of the commonest things
        // anybody types. Both halves of the test matter: the candidate has to be a
        // word the previous word is *known* to be followed by, and what was keyed
        // has to be absent from the common core. Neither alone is enough, and
        // together they are the only case where this engine replaces a word that
        // a spell checker was perfectly happy with.
        //
        // **Scoped to Hebrew script.** English has a real spell checker and an
        // `isKnownWord` guard further down; letting sentence context override it
        // there would replace valid-but-uncommon English words (e.g. "sorrow"
        // after "See you") with whatever the seed bigram names first.
        if typedLanguage.script == .hebrew,
            SeedLanguageModel.followers(after: previousWords, in: typedLanguage)
                .contains(where: { SeedLanguageModel.fold($0) == winner })
        {
            return true
        }

        guard let checkerLocale = typedLanguage.spellCheckerLocale else { return false }
        let known = isKnownWord(word, checkerLocale: checkerLocale)

        // **The keys were nearly right.** A *common* word one keystroke away from
        // something no dictionary has heard of is a slip rather than a word: this
        // is what corrects `תדוה` to `תודה` and `שלמו` to `שלום`, neither of which
        // Apple's Hebrew checker reports as wrong at all.
        //
        // **Both dictionaries have to disown the typed word, and the second half
        // was missing.** The seed list is a few hundred words, so "absent from the
        // seed" does not mean "not a word" — `cat` is not in it, `car` is one edit
        // away and is, and the first version of this rule quietly changed one
        // animal into a vehicle. `SuggestionEngineTests` caught it. Asking
        // `UITextChecker` as well costs one call on a path that has already
        // decided the word is unusual.
        if !known,
            SeedLanguageModel.neighbours(of: prefix, in: typedLanguage, limit: 3)
                .contains(where: { SeedLanguageModel.fold($0) == winner })
        {
            return true
        }

        // **Four letters, not three, and the three-letter typos are covered
        // above.** Lowering this to three did fix `teh` → `the`, and it also let a
        // three-letter prefix be replaced by any six-letter word starting with it:
        // `qwt` committed as `qwtxyz` the moment that entry was in the personal
        // dictionary, which `PersonalDictionaryTests` names. The distinction that
        // matters is not length but *kind* — a same-length neighbour is a slip and
        // a longer completion is a guess about a word still being typed — and the
        // neighbour rule above draws it, so `teh` still corrects with this back at
        // four.
        return word.count >= 4 && !known
    }

    /// The word inside what was typed, with the marks that sit at its edges
    /// without belonging to it taken off.
    static func wordCore(_ typed: String) -> String {
        let trimmed = typed.trimmingCharacters(in: .punctuationCharacters)
        guard trimmed.hasSuffix("'s") || trimmed.hasSuffix("'s") else { return trimmed }
        return String(trimmed.dropLast(2)).trimmingCharacters(in: .punctuationCharacters)
    }

    /// A word reduced to the form two spellings of it have in common, for
    /// comparing what is being typed against the user's own list.
    static func comparable(_ word: String) -> String {
        wordCore(word).lowercased()
            .replacingOccurrences(of: "־", with: "-")
            .replacingOccurrences(of: "'", with: "'")
    }

    @MainActor
    static func isKnownWord(_ word: String, checkerLocale: String) -> Bool {
        guard !word.isEmpty else { return false }
        let range = NSRange(location: 0, length: (word as NSString).length)
        let misspelled = sharedChecker.rangeOfMisspelledWord(
            in: word, range: range, startingAt: 0, wrap: false,
            language: checkerLocale)
        return misspelled.location == NSNotFound
    }
}
