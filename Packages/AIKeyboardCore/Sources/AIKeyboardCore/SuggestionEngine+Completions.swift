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

    /// The word with its last letter put into final form, when that lands on a
    /// word the seed list knows.
    ///
    /// **It asks the seed list and it must never ask `UITextChecker`, and the
    /// difference between those two is the whole history of this function.** The
    /// obvious shape is "offer it when the typed word is misspelled and the
    /// corrected one is not". That was written against the checker, and it never
    /// fired: inside the engine `isKnownWord("שלומ")` comes back *true*, while
    /// the same call on a checker that has already been used for Hebrew comes
    /// back false. A rule whose correctness depends on `UITextChecker` having
    /// warmed up is a rule that silently does nothing on the first word a user
    /// types, which is the worst possible time. So it was rewritten to ask
    /// nothing at all.
    ///
    /// **Asking nothing was worse, and it was measured over the whole
    /// vocabulary.** Five letters change shape at the end of a Hebrew word, and
    /// a *finished* word may not end in the ordinary form — but a word in
    /// progress ends in whatever letter was typed last, and 20% of the mid-word
    /// keystrokes in the 353-word seed list end in one of those five. This lands
    /// as `.orthography`, which outranks every completion source, and
    /// `shouldAutocorrect` returns true on it above the seed check, so it took
    /// the bold slot: typing `פגישה` bolded `ף` at the first letter, `מכונית`
    /// bolded `מך`, `נכון` bolded `נך`, and `לפגישה` bolded `לף` while `לפגישה`
    /// itself never reached the bar. 17 of 35 measured keystroke moments bolded
    /// a non-word. Worse than the noise, it *committed* on real input: `אפ`
    /// ("app") went to `אף` ("nose") and `קליפ` to `קליף`, because Hebrew writes
    /// its loanwords with the ordinary form at the end.
    ///
    /// The seed list settles it without reintroducing the cold-checker problem:
    /// it is a bundled JSON, folded once at load, and it answers the same on the
    /// first keystroke of a session as on the thousandth. 66 of its words end in
    /// a final form, which is the common core this slip happens in — `שלומ` →
    /// `שלום`, `צריכ` → `צריך`, `כספ` → `כסף`, `דרכ` → `דרך`. It is the same gate
    /// `SeedLanguageModel.neighbours` and `LayoutTransposition` already use, and
    /// for the same reason: a rule that rewrites what the user typed may only
    /// ever land on a word that is common enough to be worth the interruption.
    ///
    /// The table itself moved to `HebrewMorphology`, which is where the rest of
    /// the facts about how Hebrew spells a word end.
    @MainActor
    static func hebrewFinalFormCorrection(of word: String) -> String? {
        guard let corrected = HebrewMorphology.inFinalForm(word),
            SeedLanguageModel.knows(corrected, in: .hebrew)
        else { return nil }
        return corrected
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
        "review", "roadmap", "scope", "screenshot", "screenshots", "slack", "sprint",
        "standup", "sync", "template", "ticket", "update"
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
    ///   - context: everything before the current word, including earlier
    ///     sentences and lines. `previousWords` stops at a full stop; this does
    ///     not. It is how a name two sentences back is still completable.
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
        context: String,
        typedLanguage: KeyboardLanguage,
        otherLanguage: KeyboardLanguage?,
        supplementary: [String],
        personal: PersonalLanguageModel,
        codeSwitching: Bool = false
    ) -> [Suggestion] {
        // **Every source below is asked about the word, and mixing that with the
        // keystrokes is a defect all of its own.** The marks that sit at the edges
        // of what was typed belong to the sentence, not to the word: a lookup
        // handed `teh,` or `(hel` is a lookup that will find nothing, because no
        // dictionary and no word list has an entry with a comma in it. The first
        // repair here gave the *neighbour* rule the trimmed word and left the
        // completion sources on the keystrokes, which is worse than either
        // consistently: for `(hel` the completions went silent while the
        // neighbours did not, so `hello` and `help` never arrived, `her` had no
        // competition, and the bold slot — which is what the space bar inserts —
        // became a word the user had not typed a single letter of. Plain `hel` was
        // and is left alone. One string, asked of everything.
        //
        // Slot zero stays the literal keystrokes, marks and all, and
        // `KeyboardController.restoringEdgeMarks` puts them back around whatever
        // is committed, so trimming here never costs the user a character.
        let core = wordCore(prefix)
        let lower = core.lowercased()
        var out: [Candidate] = []

        // The literal keystrokes always stay available, so the engine can never
        // trap the user into a word they did not want.
        out.append(Candidate(text: prefix, language: typedLanguage, source: .typed))

        // Every key was right and the layout was wrong. Deterministic, and the
        // strongest signal in here when it fires at all — see LayoutTransposition
        // for how narrow the gate is.
        //
        // **The one source that must see the keystrokes and not the word, and the
        // corpus caught it within a run of being handed `core`.** A mark is only a
        // mark on the plane it was typed on: `,` on QWERTY is `ת` on the Hebrew
        // layout, so `,usv` — corpus `wl-02`, somebody typing `תודה` without
        // noticing the globe — is four Hebrew letters and no punctuation at all.
        // Trimming its leading comma left `usv`, which transposes to `ודה`, which
        // is in no list, so the whole rule went silent and the bar offered `use`
        // instead. Every other source here is asking a dictionary a question about
        // a word; this one is replaying a sequence of key presses, and a key press
        // has no edges to trim.
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
                    text: matchCase(of: core, applyingTo: contraction, in: typedLanguage),
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
        if typedLanguage.script == .hebrew, let final = hebrewFinalFormCorrection(of: core) {
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
            personal.words(startingWith: core, in: typedLanguage, limit: 3)
            .enumerated()
            .map {
                Candidate(
                    text: matchCase(of: core, applyingTo: $0.element, in: typedLanguage),
                    language: typedLanguage, source: .learned, ordinal: $0.offset)
            }

        // Words already in this field. A name two sentences back is not in the
        // seed list and is not in `previousWords` once a full stop has landed;
        // the field itself is the only list that still has it.
        out += documentCandidates(for: core, in: context, typedLanguage: typedLanguage)

        // The bundled seed list, read through every Hebrew reading of the prefix.
        out += seedCandidates(for: core, typedLanguage: typedLanguage, personal: personal)

        // Latin letters inside a Hebrew sentence, ranked before the dictionary.
        // Only here: in an English sentence Apple's ranking is the better judge and
        // this list would only crowd it.
        // `lower` is empty for a prefix that is only punctuation, and every word
        // in the list starts with "", so the guard is what stops `...` offering two
        // arbitrary English nouns — the same trap `comparable` carries next door.
        if codeSwitching, !lower.isEmpty {
            out +=
                codeSwitchVocabulary
                .filter { $0.hasPrefix(lower) && $0 != lower }
                .prefix(2)
                .enumerated()
                .map {
                    Candidate(
                        text: matchCase(of: core, applyingTo: $0.element, in: typedLanguage),
                        language: .english, source: .codeSwitch, ordinal: $0.offset)
                }
        }

        out += checkerCandidates(for: core, in: context, typedLanguage: typedLanguage)

        // The field gets its say last, over everything already collected, so a
        // word any earlier pair is known to be followed by climbs whichever
        // source it happened to arrive from. The last two tokens still lead;
        // earlier sentences are how `the quick` still reaches `response` after
        // two more words have landed.
        let followers = Set(
            contextFollowers(
                last: previousWords, field: documentWords(in: context), context: context,
                language: typedLanguage, personal: personal
            ).map(SeedLanguageModel.fold))
        if !followers.isEmpty {
            for index in out.indices where followers.contains(SeedLanguageModel.fold(out[index].text)) {
                out[index].followsContext = true
            }
        }

        return rank(out, limit: 3)
    }

    /// Completions drawn from words already in this field.
    ///
    /// Most recent first, so a name used in the sentence being typed outranks
    /// the same prefix from a paragraph above. Hebrew clitics are stripped the
    /// same way `seedCandidates` strips them: `לקוואק` in the field is how
    /// `קוו` reaches `קוואק`. The document spelling is kept rather than
    /// recased to the prefix — `Zorblin` stays `Zorblin` even if the user has
    /// only typed `zor`.
    private static func documentCandidates(
        for prefix: String, in context: String, typedLanguage: KeyboardLanguage
    ) -> [Candidate] {
        let typed = comparable(prefix)
        guard !typed.isEmpty else { return [] }
        var seen = Set<String>()
        var out: [Candidate] = []
        for word in documentWords(in: context).reversed() {
            guard let offered = documentOffer(word, matching: typed, language: typedLanguage)
            else { continue }
            let key = comparable(offered)
            guard key != typed, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(
                Candidate(
                    text: offered, language: typedLanguage, source: .document,
                    ordinal: out.count))
            if out.count == 3 { break }
        }
        return out
    }

    /// The form of a field word that continues this prefix, if any.
    private static func documentOffer(
        _ word: String, matching typed: String, language: KeyboardLanguage
    ) -> String? {
        if comparable(word).hasPrefix(typed) { return word }
        guard language.script == .hebrew else { return nil }
        for reading in HebrewMorphology.splits(of: word) where !reading.prefix.isEmpty {
            if comparable(reading.stem).hasPrefix(typed) { return reading.stem }
        }
        return nil
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

    /// `UITextChecker`'s own answers about the word: completions first, and
    /// corrections only when the completions came back thin.
    ///
    /// Takes the word rather than the keystrokes — `completions(for:)` trims the
    /// edge marks once and hands the same string to every source, for the reason
    /// written there.
    ///
    /// **The surrounding sentence is the string Apple's API is for.** Passing
    /// only the word in progress made every completion context-free, so
    /// `completions(forPartialWordRange:in:language:)` could not see `The
    /// elephant ate. The ele` and had no way to prefer `elephant` over
    /// `election`. The current word is appended to `context` and the range
    /// points at it; a split Hebrew stem still asks about the stem alone,
    /// because that stem is not a span of the document.
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
        for word: String, in context: String, typedLanguage: KeyboardLanguage
    )
        -> [Candidate]
    {
        // Apple ships no spell checker for every language this keyboard draws —
        // Persian is not in `UITextChecker.availableLanguages` at all. There is
        // nothing to fall back to: another language's dictionary would offer
        // another language's words, which is worse than offering none.
        guard let locale = typedLanguage.spellCheckerLocale else { return [] }
        let lower = word.lowercased()
        var out: [Candidate] = []
        let query = checkerQuery(of: word, in: context)

        out +=
            checkerCompletions(of: word, locale: locale, query: query)
            .prefix(8)
            .enumerated()
            .map {
                Candidate(
                    text: matchCase(of: word, applyingTo: $0.element, in: typedLanguage),
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
        //
        // **Asked about `wordCore`, not the keystrokes, and a comma was the whole
        // bug.** `neighbours` refuses a candidate shorter than what was typed, so
        // a trailing mark counted as a letter and pushed every real neighbour
        // under the floor: `teh` corrected to `the` and `teh,` corrected to
        // nothing. In Hebrew there is no second path to fall back on — Apple's
        // checker calls `תדוה` and `שלמו` perfectly good words, so this rule is
        // the only one that sees them — and `תדוה,` came back holding one slot,
        // the typo, with `תודה` never generated at all. Greeting somebody or
        // ending a clause is the commonest way a word meets a mark, so this was
        // most of the ground the rule was written to cover.
        if !SeedLanguageModel.knows(word, in: typedLanguage) {
            out +=
                SeedLanguageModel.neighbours(of: word, in: typedLanguage, limit: 2)
                .enumerated()
                .map {
                    Candidate(
                        text: matchCase(of: word, applyingTo: $0.element, in: typedLanguage),
                        language: typedLanguage, source: .neighbour, ordinal: $0.offset,
                        keyAdjacent: KeyProximity.isAdjacentSubstitution(
                            word, $0.element, in: typedLanguage))
                }
        }

        guard out.count < 2, query.range.length > 0 else { return out }

        let misspelled = sharedChecker.rangeOfMisspelledWord(
            in: query.text, range: query.range, startingAt: query.range.location, wrap: false,
            language: locale)
        guard misspelled.location != NSNotFound else { return out }

        if let corrections = sharedChecker.guesses(
            forWordRange: query.range, in: query.text, language: locale)
        {
            out +=
                corrections
                .filter { $0.lowercased() != lower }
                .prefix(3)
                .enumerated()
                .map {
                    Candidate(
                        text: matchCase(of: word, applyingTo: $0.element, in: typedLanguage),
                        language: typedLanguage, source: .correction, ordinal: $0.offset)
                }
        }
        return out
    }

    /// The string and range `UITextChecker` is asked about.
    ///
    /// The current word is always the tail, so a second occurrence of the same
    /// letters earlier in the field cannot steal the range. An empty context
    /// keeps the isolated-word shape the split-stem path still needs.
    private struct CheckerQuery {
        let text: String
        let range: NSRange
    }

    private static func checkerQuery(of word: String, in context: String) -> CheckerQuery {
        let nsWord = word as NSString
        guard !context.isEmpty else {
            return CheckerQuery(text: word, range: NSRange(location: 0, length: nsWord.length))
        }
        let nsContext = context as NSString
        return CheckerQuery(
            text: nsContext.appending(word),
            range: NSRange(location: nsContext.length, length: nsWord.length))
    }

    @MainActor
    private static func checkerCompletions(
        of word: String, locale: String, query: CheckerQuery? = nil
    ) -> [String] {
        let nsWord = word as NSString
        guard nsWord.length > 0 else { return [] }
        let asked = query ?? CheckerQuery(text: word, range: NSRange(location: 0, length: nsWord.length))
        let lower = word.lowercased()
        return
            (sharedChecker.completions(
                forPartialWordRange: asked.range, in: asked.text, language: locale)
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
        _ prefix: String, previousWords: [String], context: String = "",
        typedLanguage: KeyboardLanguage,
        results: [Suggestion], supplementary: [String], personal: PersonalLanguageModel
    ) -> Bool {
        guard results.count > 1 else { return false }
        // The word, not the keystrokes, for every question below — the same string
        // `completions(for:)` asks its sources about. A mark at either edge is the
        // sentence's, and both the contraction table and the final-form rule used
        // to miss on it: `dont,` reached neither, so the correction that did arrive
        // came from whatever the checker guessed instead.
        let word = wordCore(prefix)
        let lower = word.lowercased()

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

        if typedLanguage.script == .hebrew, hebrewFinalFormCorrection(of: word) != nil {
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
        //
        // **`word`, not `prefix`** — the same trailing-mark trap the offer side
        // fell into. `neighbours` measures length against what it is given, so
        // `teh,` was four characters against a three-letter `the` and the rule
        // that fixes the commonest English typo stopped firing the moment a comma
        // followed it.
        let neighbourMatch =
            !known
            && SeedLanguageModel.neighbours(of: word, in: typedLanguage, limit: 3)
                .contains(where: { SeedLanguageModel.fold($0) == winner })
        // **Same-length substitutions are a word still being typed.** `מכונ` on
        // the way to `מכונית` is one substitution from `נכון`, four letters
        // against four, and the seed knows the neighbour and not the word — so
        // the neighbour took the bold slot. A transposition (`teh`/`the`,
        // `תדוה`/`תודה`) is two keys swapped and is the slip this rule is for.
        // `helo` → `hello` is longer, so it still returns true below. Asking
        // "does the typed word have completions" does not draw this line:
        // `helo` has them and should still correct.
        let typedFolded = SeedLanguageModel.fold(word)
        let sameLengthSubstitution =
            neighbourMatch && typedFolded.count == winner.count
            && !SeedLanguageModel.isTransposition(winner, of: word)
        // Seed completions of the typed letters, most common first. Asked
        // before the neighbour return because `respond` is one insertion from
        // `respon` and used to skip the unfinished-stem check entirely.
        let continuations = SeedLanguageModel.words(
            startingWith: word, in: typedLanguage, limit: 3)
        let ambiguousStem = hasDistinctLexemes(continuations)
        // `helo` → `hello` is a missing letter, not a prefix. `respon` →
        // `respond` is the letters so far plus one more. Only the second is
        // an unfinished word, and only that one must reach the stem check.
        let prefixCompletion =
            typedFolded.count < winner.count && winner.hasPrefix(typedFolded)

        if neighbourMatch {
            // Same-length substitutions are a Hebrew word still being typed
            // (`מכונ` → `נכון`). Measured at 2/35 Hebrew keystrokes and 0/24
            // English. `definately` → `definitely` is English and must still
            // commit. An ambiguous prefix completion (`respon` → `respond`)
            // is not a slip in any language.
            let hebrewUnfinished = sameLengthSubstitution && typedLanguage.script == .hebrew
            if !hebrewUnfinished, !(prefixCompletion && ambiguousStem) {
                return true
            }
        }

        // **An unfinished word with two different endings is not a typo.**
        // `respon` is the start of `respond`, `response` and `responsible`.
        // The four-letter gate used to commit whichever the seed ranked first
        // (`respond`), which is a guess about a word still being typed — corpus
        // `en-comp-03`, `Thanks for the quick respon`. Inflections of one
        // lexeme (`schedule` / `scheduled`) still commit: they are one word
        // with a tail, not two readings. Context can still pick: if the
        // previous words are known to be followed by the winner, that is the
        // same sentence signal the Hebrew path already uses, applied only to
        // this unfinished-stem case rather than to valid English words.
        if ambiguousStem {
            let contextual = Set(
                contextFollowers(
                    last: previousWords, field: documentWords(in: context), context: context,
                    language: typedLanguage, personal: personal
                ).map(SeedLanguageModel.fold))
            if !contextual.contains(winner) { return false }
        }

        // **A Latin stem inside a Hebrew sentence is unfinished the same way,
        // and the seed list cannot say so.** `screensh` is not in the seed, so
        // the block above never sees `screenshotted` / `screenshotting` — two
        // endings the checker offered, neither of them a typo, and space
        // committed the first. Corpus `cs-05`. Asking the offered slots rather
        // than the seed is what finds them, and only here: the same test in
        // an English sentence is `Handi` → `Handing`, which the personal
        // dictionary is what stops, and which this must not spare when the
        // list is empty.
        if prefixCompletion, typedLanguage.script == .latin,
            SuggestionEngine.dominantLanguage(in: context)?.script == .hebrew
        {
            let offered = Array(results.dropFirst().map(\.text))
            if hasDistinctLexemes(offered) {
                let contextual = Set(
                    contextFollowers(
                        last: previousWords, field: documentWords(in: context), context: context,
                        language: typedLanguage, personal: personal
                    ).map(SeedLanguageModel.fold))
                if !contextual.contains(winner) { return false }
            }
        }

        // **An unfinished word with two different endings is not a typo.**
        // `respon` is the start of `respond`, `response` and `responsible`.
        // The four-letter gate used to commit whichever the seed ranked first
        // (`respond`), which is a guess about a word still being typed — corpus
        // `en-comp-03`, `Thanks for the quick respon`. Inflections of one
        // lexeme (`schedule` / `scheduled`) still commit: they are one word
        // with a tail, not two readings. Context can still pick: if the
        // previous words are known to be followed by the winner, that is the
        // same sentence signal the Hebrew path already uses, applied only to
        // this unfinished-stem case rather than to valid English words.
        let continuations = SeedLanguageModel.words(
            startingWith: word, in: typedLanguage, limit: 3)
        if hasDistinctLexemes(continuations) {
            let contextual = Set(
                contextFollowers(
                    last: previousWords, field: documentWords(in: context), context: context,
                    language: typedLanguage, personal: personal
                ).map(SeedLanguageModel.fold))
            if !contextual.contains(winner) { return false }
        }

        // **Four letters, not three, and the three-letter typos are covered
        // above.** Lowering this to three did fix `teh` → `the`, and it also let a
        // three-letter prefix be replaced by any six-letter word starting with it:
        // `qwt` committed as `qwtxyz` the moment that entry was in the personal
        // dictionary, which `PersonalDictionaryTests` names. The distinction that
        // matters is not length but *kind* — a same-length neighbour is a slip and
        // a longer completion is a guess about a word still being typed — and the
        // neighbour rule above draws it, so `teh` still corrects with this back at
        // four. The same-length *substitution* half is Hebrew-only, or the
        // four-letter gate would commit `נכון` for `מכונ` the moment the neighbour
        // clause stopped doing it.
        return word.count >= 4 && !known
            && !(sameLengthSubstitution && typedLanguage.script == .hebrew)
    }

    /// Whether these completions are more than one word with a suffix stuck on.
    ///
    /// `schedule` / `scheduled` is one lexeme. `respond` / `response` is two:
    /// neither string begins with the other. Asked of the seed list's own
    /// answers, most-common first, so the head is the one the four-letter gate
    /// would have committed.
    static func hasDistinctLexemes(_ words: [String]) -> Bool {
        guard words.count >= 2 else { return false }
        let folded = words.map(SeedLanguageModel.fold)
        let head = folded[0]
        return folded.dropFirst().contains { other in
            !other.hasPrefix(head) && !head.hasPrefix(other)
        }
    }

    /// Whether these completions are more than one word with a suffix stuck on.
    ///
    /// `schedule` / `scheduled` is one lexeme. `respond` / `response` is two:
    /// neither string begins with the other. Asked of the seed list's own
    /// answers, most-common first, so the head is the one the four-letter gate
    /// would have committed.
    static func hasDistinctLexemes(_ words: [String]) -> Bool {
        guard words.count >= 2 else { return false }
        let folded = words.map(SeedLanguageModel.fold)
        let head = folded[0]
        return folded.dropFirst().contains { other in
            !other.hasPrefix(head) && !head.hasPrefix(other)
        }
    }

    /// The word inside what was typed, with the marks that sit at its edges
    /// without belonging to it taken off.
    ///
    /// **Both apostrophes, spelled as an escape, because the curly one did not
    /// survive being written literally.** This read
    /// `hasSuffix("'s") || hasSuffix("'s")` — two branches that look like the two
    /// apostrophes and are the same eight bytes, so the second was dead and
    /// `Nitai’s` was never reduced to `Nitai`. That is not a hypothetical
    /// spelling: the apostrophe key's long press offers `’`
    /// (`KeyboardLayout+NumbersSymbols`), and a host field with smart quotes on —
    /// the default everywhere except this repo's own test helper — turns a typed
    /// `'` into `’` inside the document that `currentWordPrefix` reads back.
    static func wordCore(_ typed: String) -> String {
        let trimmed = typed.trimmingCharacters(in: .punctuationCharacters)
        guard trimmed.hasSuffix("'s") || trimmed.hasSuffix("\u{2019}s") else { return trimmed }
        return String(trimmed.dropLast(2)).trimmingCharacters(in: .punctuationCharacters)
    }

    /// A word reduced to the form two spellings of it have in common, for
    /// comparing what is being typed against the user's own list.
    ///
    /// **`SeedLanguageModel.fold` rather than a second spelling of it.** This
    /// carried its own copy of the same three moves, and the copy's apostrophe
    /// rule was `replacingOccurrences(of: "'", with: "'")` — ASCII on both sides,
    /// so it did nothing. The measured cost was the personal dictionary silently
    /// letting go of a word the moment it wore a curly apostrophe: `Nitai's` was
    /// protected and `Nitai’s` committed as `Nita’s`.
    static func comparable(_ word: String) -> String {
        SeedLanguageModel.fold(wordCore(word))
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
