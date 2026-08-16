import XCTest

@testable import AIKeyboardCore

/// The context-aware half of the suggestion bar: the seed model, Hebrew
/// morphology, wrong-layout detection, the learned store, and the ranking that
/// weighs them against each other.
///
/// **Every assertion here was written by first working out what the *previous*
/// engine returned for the same input, and checking the assertion rejects it.**
/// That is the standing rule in `AGENTS.md`, and this area has burned it before:
/// `SuggestionEngine` unconditionally echoes the typed prefix as candidate zero,
/// so `XCTAssertFalse(results.isEmpty)` and `contains { $0.hasPrefix(typed) }` are
/// both true of a completely dead engine. Nothing below leans on either.
///
/// The numbers quoted in the comments come from `Bar/typing/harness/run.sh`
/// against `Bar/typing/corpus.json`, which went from 47/76 to 72/76 over this
/// work. It read 73/76 until `score.py` was made to measure the commit column it
/// had been printing the offered column into; the same engine scores 71/76 under
/// the honest one.
@MainActor
final class ContextAwareSuggestionTests: XCTestCase {

    /// Empty and in memory. A test that inherited the developer's own typing would
    /// pass or fail depending on whose laptop ran it.
    private func emptyPersonal() -> PersonalLanguageModel {
        PersonalLanguageModel(url: nil)
    }

    // MARK: The seed model

    /// The whole reason the seed list exists. `UITextChecker` completes `helo` to
    /// `helot` and `helots` — both real words, which is why the correction branch
    /// never ran — and never reaches `hello`.
    func testFrequencyPriorRanksACommonWordOverARareOne() {
        XCTAssertNotNil(SeedLanguageModel.rank(of: "hello", in: .english))
        XCTAssertNil(
            SeedLanguageModel.rank(of: "helot", in: .english),
            "the seed list is a prior over the common core; a rare word must be absent, "
                + "not merely ranked low")

        let results = SuggestionEngine.suggestions(
            prefix: "helo", context: "", languages: [.english], personal: emptyPersonal())
        XCTAssertTrue(
            results.contains { $0.text.lowercased() == "hello" },
            "got \(results.map(\.text)) — the old engine returned helo/helot/helots")
    }

    /// Rank order is the only thing the seed data claims, so it is the only thing
    /// asserted about it. `the` is the commonest word in English and `address` is
    /// not, and a list that disagreed would be a list with a shuffled build step.
    func testSeedOrderIsFrequencyOrderNotAlphabetical() {
        let the = SeedLanguageModel.rank(of: "the", in: .english)
        let address = SeedLanguageModel.rank(of: "address", in: .english)
        XCTAssertNotNil(the)
        XCTAssertNotNil(address)
        XCTAssertLessThan(the ?? .max, address ?? 0)
    }

    /// Two-word keys beat one-word keys, which is what separates "See you" from
    /// the half of the language that can follow "you".
    func testLongestPhraseWins() {
        let afterYou = SeedLanguageModel.followers(after: ["you"], in: .english)
        let afterSeeYou = SeedLanguageModel.followers(after: ["see", "you"], in: .english)
        XCTAssertNotEqual(
            afterYou, afterSeeYou,
            "the two-word key is not being consulted, so `See you ` answers whatever "
                + "follows `you`")
        XCTAssertEqual(afterSeeYou.first, "tomorrow")
    }

    /// A transposition is one mistake at the keyboard and must score as one edit,
    /// **including across a Hebrew final form**: `שלמו` for `שלום` swaps two
    /// letters and also changes a mem's shape, which is two substitutions on the
    /// code points and never found without folding the shapes first.
    func testNeighbourFindsAHebrewTransposition() {
        XCTAssertTrue(
            SeedLanguageModel.neighbours(of: "תדוה", in: .hebrew, limit: 3).contains("תודה"))
        XCTAssertTrue(
            SeedLanguageModel.neighbours(of: "שלמו", in: .hebrew, limit: 3).contains("שלום"),
            "final forms are not being folded, so the commonest Hebrew slip scores as "
                + "distance 2")
    }

    /// Every prefix is a word in progress, so a shorter neighbour proposes deleting
    /// a key the user just pressed. Allowing it turned four correct Hebrew
    /// completions into corrections of half-typed words.
    func testNeighbourIsNeverShorterThanWhatWasTyped() {
        XCTAssertFalse(
            SeedLanguageModel.neighbours(of: "מונ", in: .hebrew, limit: 5).contains("מון"))
        let results = SuggestionEngine.suggestions(
            prefix: "מונ", context: "צריך להזמין ", languages: [.hebrew, .english],
            personal: emptyPersonal())
        XCTAssertTrue(
            results.contains { $0.text == "מונית" },
            "got \(results.map(\.text)) — a neighbour crowded out the word being typed")
    }

    /// **A same-length substitution is a word still being typed.** `מכונ` on the
    /// way to `מכונית` is one substitution from `נכון`, and the seed knows the
    /// neighbour and not the car. Space committing `נכון` is the delete-key
    /// undoing itself in another shape. A transposition still corrects: that is
    /// `teh` → `the` below, and `תדוה` is offered even when Apple's checker will
    /// not commit it.
    func testASameLengthSubstitutionDoesNotTakeTheBoldSlot() {
        XCTAssertFalse(SeedLanguageModel.isTransposition("נכון", of: "מכונ"))
        XCTAssertTrue(SeedLanguageModel.isTransposition("the", of: "teh"))
        XCTAssertTrue(SeedLanguageModel.isTransposition("תודה", of: "תדוה"))

        let inProgress = SuggestionEngine.suggestions(
            prefix: "מכונ", context: "", languages: [.hebrew], personal: emptyPersonal())
        XCTAssertNotEqual(
            inProgress.first(where: \.isDefault)?.text, "נכון",
            "space would replace a word in progress: \(inProgress.map(\.text))")

        let threeLetters = SuggestionEngine.suggestions(
            prefix: "מצט", context: "", languages: [.hebrew], personal: emptyPersonal())
        XCTAssertNotEqual(
            threeLetters.first(where: \.isDefault)?.text, "מצב",
            "space would replace מצט with מצב: \(threeLetters.map(\.text))")

        let english = SuggestionEngine.suggestions(
            prefix: "teh", context: "I ", languages: [.english], personal: emptyPersonal())
        XCTAssertEqual(
            english.first(where: \.isDefault)?.text, "the",
            "a transposition still has to correct: \(english.map(\.text))")
    }

    /// **A mark after the word used to switch this whole rule off.** `neighbours`
    /// refuses a candidate shorter than what it is given, so a comma counted as a
    /// letter and put every real neighbour under the floor. In English there is a
    /// second path — `UITextChecker.guesses` still reached `receive` from
    /// `recieve,` — but in Hebrew there is none, because Apple's checker calls
    /// `תדוה` and `שלמו` perfectly good words, so the whole correction disappeared:
    /// the bar came back holding one slot, the typo, with the right word never
    /// generated at all.
    ///
    /// The English half asserts on the *default*, because `the` was in the bar for
    /// `teh,` before this and simply was not what space would insert.
    func testAMarkAfterTheWordDoesNotSwitchOffTheNeighbourRule() {
        let withMark = SuggestionEngine.suggestions(
            prefix: "תדוה,", context: "", languages: [.hebrew], personal: emptyPersonal())
        XCTAssertTrue(
            withMark.contains { $0.text == "תודה" },
            "got \(withMark.map(\.text)) — one slot means the rule never ran")

        let english = SuggestionEngine.suggestions(
            prefix: "teh,", context: "I ", languages: [.english], personal: emptyPersonal())
        XCTAssertEqual(
            english.first(where: \.isDefault)?.text, "the",
            "got \(english.map(\.text)) — the mark cost the correction the bold slot")
    }

    /// **The second bug the first mark repair made, and the reason every source
    /// now sees one string.** Giving `wordCore` to the neighbour rule while the
    /// completion sources kept the keystrokes meant a word with a mark in front of
    /// it had neighbours and no completions — so for `(hel` neither `hello` nor
    /// `help` was ever generated, `her` won a race it should never have been in,
    /// and the space bar was set to insert a word sharing two letters with what
    /// was typed. Plain `hel` was left alone throughout, which is what makes this
    /// a bug about the mark rather than about the ranking.
    func testAMarkInFrontOfTheWordDoesNotHideItsCompletions() {
        for typed in ["(hel", "\"hel", "'hel"] {
            let results = SuggestionEngine.suggestions(
                prefix: typed, context: "Say ", languages: [.english],
                personal: emptyPersonal())
            XCTAssertEqual(
                results.first(where: \.isDefault)?.text, typed,
                "space would replace a three-letter word in progress: \(results.map(\.text))")
            XCTAssertTrue(
                results.contains { $0.text == "hello" },
                "the mark hid the completions: \(results.map(\.text))")
        }
    }

    /// **The four-letter gate used to finish other people's words.** `respon` is
    /// `respond`, `response` and `responsible` — three readings, none of them a
    /// typo — and space committed `respond` because it sits first in the seed.
    /// Corpus `en-comp-03` is `Thanks for the quick respon`, whose closed list
    /// is the noun. The old default is what this rejects: a verb nobody asked
    /// for. `schedule` / `scheduled` is the control, one lexeme with a tail,
    /// and still commits.
    func testAnAmbiguousUnfinishedStemIsNotCommitted() {
        XCTAssertTrue(
            SuggestionEngine.hasDistinctLexemes(["respond", "response", "responsible"]),
            "respond/response are two words; a helper that treated any shared prefix "
                + "as one lexeme would let the four-letter gate keep committing respond")
        XCTAssertFalse(
            SuggestionEngine.hasDistinctLexemes(["schedule", "scheduled"]),
            "scheduled is schedule with a tail — the four-letter gate must still "
                + "commit schedule for sched")

        let results = SuggestionEngine.suggestions(
            prefix: "respon", context: "", languages: [.english], personal: emptyPersonal())
        XCTAssertEqual(
            results.first(where: \.isDefault)?.text, "respon",
            "space would finish an unfinished word: \(results.map(\.text))")
        XCTAssertTrue(
            results.contains { $0.text.lowercased() == "respond" }
                || results.contains { $0.text.lowercased() == "response" },
            "the readings still have to be tappable: \(results.map(\.text))")

        let scheduled = SuggestionEngine.suggestions(
            prefix: "sched", context: "", languages: [.english], personal: emptyPersonal())
        XCTAssertEqual(
            scheduled.first(where: \.isDefault)?.text.lowercased(), "schedule",
            "schedule/scheduled is one lexeme and must still commit: \(scheduled.map(\.text))")
    }

    /// **Code-switch offered endings are an unfinished stem the seed cannot
    /// see.** `screensh` is not in the seed, so the seed-lexeme check never
    /// fires, and the four-letter gate committed `screenshotted`. Corpus
    /// `cs-05`. The offered slots are what names the two endings, and only
    /// inside a Hebrew sentence: the same test on `Hi Handi` is the English
    /// destruction `PersonalDictionaryTests` still has to prove. The checker's
    /// current guess for that stem moves (`Handing`, `Handicap`); the control
    /// only needs the typed letters not to stay bold.
    func testACodeSwitchAmbiguousStemIsNotCommitted() {
        let results = SuggestionEngine.suggestions(
            prefix: "screensh", context: "אני מצרף ", languages: [.english, .hebrew],
            personal: emptyPersonal())
        XCTAssertNotEqual(
            results.first(where: \.isDefault)?.text.lowercased(), "screenshotted",
            "space would finish an unfinished code-switch stem: \(results.map(\.text))")
        XCTAssertTrue(
            results.contains { $0.text.lowercased() == "screenshot" },
            "the closed list's word has to be tappable: \(results.map(\.text))")

        let english = SuggestionEngine.suggestions(
            prefix: "Handi", context: "Hi ", languages: [.english], personal: emptyPersonal())
        let englishDefault = english.first(where: \.isDefault)?.text
        XCTAssertNotEqual(
            englishDefault, "Handi",
            "English-only context must still replace Handi when the list is empty: "
                + "\(english.map(\.text))")
        XCTAssertNotNil(englishDefault)
    }

    /// The sentence is allowed to pick. `the quick` is followed by `response` in
    /// the seed, so the noun takes the bold slot and space commits it — the
    /// same context climb `לקבוע תו` already uses for `תור`. Without the
    /// bigram the frequency prior still ranks `respond` first and this would
    /// look like the test above.
    func testContextPicksTheNounReadingOfAnAmbiguousStem() {
        XCTAssertEqual(
            SeedLanguageModel.followers(after: ["the", "quick"], in: .english).first,
            "response")

        let results = SuggestionEngine.suggestions(
            prefix: "respon", context: "Thanks for the quick ",
            languages: [.english], personal: emptyPersonal())
        XCTAssertEqual(
            results.first(where: \.isDefault)?.text.lowercased(), "response",
            "got \(results.map(\.text)) — the old bar committed respond here")
    }

    /// **The last two words are not the field.** `followers(after:)` only reads
    /// the tail, so two more words after `the quick` made the collocation
    /// invisible and `respon` fell back to `respond`. Sliding the seed table
    /// over the whole token list is what keeps the noun in front. One-word
    /// keys stay at the end: `the` in the middle of a sentence must not mark
    /// `way` as context.
    func testSeedFollowersReadTheWholeFieldNotOnlyTheLastWords() {
        XCTAssertTrue(
            SeedLanguageModel.followers(
                mentionedIn: ["Thanks", "for", "the", "quick", "turnaround", "I'll", "send", "a"],
                in: .english
            ).contains("response"),
            "the quick was two words back and the seed never saw it")
        XCTAssertFalse(
            SeedLanguageModel.followers(
                mentionedIn: ["the", "quick", "turnaround"], in: .english
            ).contains("way"),
            "the interior `the` leaked its one-word row")
        XCTAssertEqual(
            SeedLanguageModel.followers(mentionedIn: ["See", "you"], in: .english).first,
            "tomorrow",
            "the last pair still has to win: see you beats you")
    }

    /// A collocation two sentences back is still this message. Space committing
    /// `respond` here is the same unfinished-stem miss as `en-comp-03`, just
    /// with two more words in the way.
    func testACollocationEarlierInTheFieldStillRanksTheCompletion() {
        let results = SuggestionEngine.suggestions(
            prefix: "respon",
            context: "Thanks for the quick turnaround. I'll send a ",
            languages: [.english], personal: emptyPersonal())
        XCTAssertEqual(
            results.first(where: \.isDefault)?.text.lowercased(), "response",
            "got \(results.map(\.text)) — the last two words hid the quick")
    }

    /// Next-word stays inside the current sentence. A newline still closes
    /// the thought — that is `testANewlineClosesTheThoughtAsAFullStopDoes` —
    /// but pairs earlier *in this sentence* still count.
    func testNextWordReadsEarlierPairsInThisSentence() {
        let later = SuggestionEngine.suggestions(
            prefix: "", context: "Thanks for the quick turnaround and ",
            languages: [.english], personal: emptyPersonal())
        XCTAssertTrue(
            later.contains { $0.text.lowercased() == "response" },
            "got \(later.map(\.text)) — next-word only asked the last two tokens")

        let afterBreak = SuggestionEngine.suggestions(
            prefix: "", context: "See you\n",
            languages: [.english], personal: emptyPersonal())
        XCTAssertFalse(
            afterBreak.contains { $0.text.lowercased() == "tomorrow" },
            "got \(afterBreak.map(\.text)) — a newline must not leak the previous line")
    }

    // MARK: Hebrew morphology

    /// One seed entry for `עבודה` has to serve `לעבודה`, `בעבודה` and `מהעבודה`,
    /// because no dictionary lists the glued forms.
    func testCliticSplitReachesAWordNoDictionaryLists() {
        let readings = HebrewMorphology.splits(of: "מהג")
        XCTAssertEqual(readings.first?.prefix, "", "the unsplit reading must come first")
        XCTAssertTrue(readings.contains { $0.prefix == "מה" && $0.stem == "ג" })

        let results = SuggestionEngine.suggestions(
            prefix: "לעבו", context: "אני בדרך ", languages: [.hebrew, .english],
            personal: emptyPersonal())
        XCTAssertTrue(
            results.contains { $0.text == "לעבודה" },
            "got \(results.map(\.text)) — the old engine returned לעבוד and לעבור, two verbs")
    }

    /// **The space bar may not act on a reading the ranking itself distrusts, and
    /// `להתרופה` is what that cost.**
    ///
    /// Four letters into `להתראות` ("goodbye") the bar bolded `להתרופה` and space
    /// committed it: `ל` + `ה` + `תרופה`, "to the medicine". The four-letter gate
    /// fires because the word is over four letters and no checker calls it a word,
    /// and `rank` had already flattened to `[Suggestion]` by then, so the commit
    /// decision could not see that two of the four typed letters had been spent
    /// assuming a reading.
    ///
    /// Three premises are asserted as well as the behaviour, because each one is a
    /// cheaper fix that does not work. `תרופה` is in the seed list, so "the winner
    /// must be seed-reachable" does not exclude it. The candidate is still
    /// *offered*, so a build that fixed this by deleting the two-clitic reading
    /// would fail here rather than pass. And the bold slot is the typed word,
    /// which is the only thing that rejects the old build — `להתרופה` was in the
    /// bar either way.
    @MainActor
    func testAStackedCliticReadingDoesNotTakeTheSpaceBar() {
        XCTAssertTrue(
            SeedLanguageModel.knows("תרופה", in: .hebrew),
            "תרופה left the seed list — this defect is reached through it, so the test "
                + "would now pass for the wrong reason")

        let results = SuggestionEngine.suggestions(
            prefix: "להתר", context: "", languages: [.hebrew, .english],
            personal: emptyPersonal())
        XCTAssertTrue(
            results.contains { $0.text == "להתרופה" },
            "got \(results.map(\.text)) — the reading is still offered; only the bold "
                + "slot moves, and a build that stopped generating it proves nothing")
        XCTAssertEqual(
            results.first(where: \.isDefault)?.text, "להתר",
            "space committed \(results.first(where: \.isDefault)?.text ?? "nothing") "
                + "four letters into להתראות: \(results.map(\.text))")
    }

    /// The other half of the same defect, and it arrives through a different
    /// source: `להתרא` bolded `להתראיין`, which is `UITextChecker` completing
    /// `התרא` — a stem `HebrewMorphology.splits` invented — because the seed list
    /// had nothing to say about that reading.
    ///
    /// **The offered word is deliberately not pinned.** Apple's Hebrew completion
    /// list for a given stem moves between runs (see the `he-comp-04` /
    /// `he-comp-05` note in `.claude/rules/suggestion-bar.md`), so the premise is
    /// asserted as "something longer than the keystrokes is still offered" rather
    /// than as `להתראיין`. The typed echo is excluded from that check, because
    /// `SuggestionEngine` always returns it and `contains { $0.hasPrefix(typed) }`
    /// is true of a completely dead engine.
    @MainActor
    func testACheckerCompletionOfASplitStemDoesNotTakeTheSpaceBar() {
        let results = SuggestionEngine.suggestions(
            prefix: "להתרא", context: "", languages: [.hebrew, .english],
            personal: emptyPersonal())
        XCTAssertTrue(
            results.contains { $0.text != "להתרא" && $0.text.hasPrefix("להתרא") },
            "got \(results.map(\.text)) — the split reading has to still reach the bar, "
                + "or this test passes against an engine that offers nothing at all")
        XCTAssertEqual(
            results.first(where: \.isDefault)?.text, "להתרא",
            "space committed \(results.first(where: \.isDefault)?.text ?? "nothing") "
                + "five letters into להתראות: \(results.map(\.text))")
    }

    /// **The control half, and the case every cheap gate breaks.** A clitic
    /// reading is how Hebrew completion works at all — one seed entry for `עבודה`
    /// serves `בעבודה` and `מהעבודה`, and no dictionary lists either glued form —
    /// so a fix that simply refused to commit anything reached through a split, or
    /// that capped the letters a Hebrew correction may add, would take these two
    /// with it. `מהעבודה` matters most: it stacks *two* clitics, exactly as
    /// `להתרופה` does, so a rule that counts clitics alone fails here.
    @MainActor
    func testACliticReadingWithLettersBehindItStillCommits() {
        for (typed, context, expected) in [
            ("בעבו", "אני ", "בעבודה"), ("מהעבו", "חוזר ", "מהעבודה")
        ] {
            let results = SuggestionEngine.suggestions(
                prefix: typed, context: context, languages: [.hebrew, .english],
                personal: emptyPersonal())
            XCTAssertEqual(
                results.first(where: \.isDefault)?.text, expected,
                "space kept \(results.first(where: \.isDefault)?.text ?? "nothing") "
                    + "instead of committing \(expected): \(results.map(\.text))")
        }
    }

    /// The commit gate on its own, away from Apple's list, so a checker whose
    /// Hebrew answers moved cannot make this pass or fail for the wrong reason.
    ///
    /// Each row rejects a different cheaper rule: a gate that only refused stacked
    /// clitics loses `מהעבודה`; one that only refused the split checker keeps
    /// `להתרופה`; one that counted letters added has nothing to say about either.
    /// The last row is the reason nothing outside Hebrew changed — `cliticDepth`
    /// is zero everywhere else, so the whole rule is skipped.
    func testTheCommitGateReadsTheReadingAndNotTheLength() {
        func trusts(
            _ text: String, _ source: SuggestionEngine.Source, depth: Int, typed: String
        ) -> Bool {
            SuggestionEngine.commitTrustsReading(
                SuggestionEngine.Candidate(
                    text: text, language: .hebrew, source: source, cliticDepth: depth),
                typed: typed)
        }

        XCTAssertTrue(trusts("בעבודה", .seed, depth: 1, typed: "בעבו"))
        XCTAssertTrue(
            trusts("מהעבודה", .seed, depth: 2, typed: "מהעבו"),
            "two clitics with three letters of stem behind them is how Hebrew is "
                + "written; refusing it on depth alone is the regression")
        XCTAssertFalse(
            trusts("להתרופה", .seed, depth: 2, typed: "להתר"),
            "two of the four typed letters were spent on the reading, so the noun "
                + "rests on the other two")
        XCTAssertFalse(
            trusts("להתראיין", .checker, depth: 1, typed: "להתרא"),
            "the checker is only asked about a split stem when the seed had nothing "
                + "to say about that reading; it may be offered, never committed")
        XCTAssertTrue(
            SuggestionEngine.commitTrustsReading(
                SuggestionEngine.Candidate(text: "hello", language: .english, source: .checker),
                typed: "helo"),
            "an unsplit completion carries no clitic depth and must be untouched")
    }

    /// **The Hebrew sentence override replaces a word; it must not finish one.**
    ///
    /// That rule is the one place in this engine where the sentence outvotes the
    /// dictionary, and it carries no length floor on purpose — `בעוד רבה` is two
    /// real words that never appear in that order. But it was also asked about a
    /// *prefix*, and `אני` → `לא` is a seed row, so one letter into `לעבודה` or
    /// `להתראות` the bold slot held `לא` and the space bar was armed with a
    /// different word. The same row turned a lone `צ` into `צריך` and `מג` into
    /// `מגיע`. Finishing a word still being typed is the four-letter gate's job,
    /// and that gate has a floor for exactly this reason.
    ///
    /// The control half is the entry the rule exists for (corpus `typo-12`), and
    /// it is what rejects a build that simply deleted the override: `רבע` does not
    /// start with `רבה`, so the keys disagree and the sentence is worth hearing.
    @MainActor
    func testTheHebrewSentenceOverrideDoesNotFinishAWordItOnlyReplacesOne() {
        XCTAssertTrue(
            SeedLanguageModel.followers(after: ["אני"], in: .hebrew).contains("לא"),
            "the seed row this is about has to exist, or the test proves nothing")

        let progress = SuggestionEngine.suggestions(
            prefix: "ל", context: "אני ", languages: [.hebrew, .english],
            personal: emptyPersonal())
        XCTAssertEqual(
            progress.first(where: \.isDefault)?.text, "ל",
            "space committed \(progress.first(where: \.isDefault)?.text ?? "nothing") "
                + "one letter into a word: \(progress.map(\.text))")

        let replacement = SuggestionEngine.suggestions(
            prefix: "רבה", context: "אני מגיע בעוד ", languages: [.hebrew, .english],
            personal: emptyPersonal())
        XCTAssertEqual(
            replacement.first(where: \.isDefault)?.text, "רבע",
            "and the override still fires on a whole word the sentence disagrees with: "
                + "\(replacement.map(\.text))")
    }

    /// **A final form may only take the bold slot when the typed letters are not
    /// still going somewhere.**
    ///
    /// The gate on `hebrewFinalFormCorrection` asks whether the *corrected* word is
    /// common, which is the wrong half of the question: `אף` ("nose") is one of the
    /// commonest words in Hebrew, so two letters into `אפשר` — with `אפשר` and
    /// `אפשרות` both sitting in the seed list — the bar bolded `אף` and space
    /// committed it. `אפ` is also how Hebrew writes "app", which is the loanword
    /// harm `testALoanwordEndingInAnOrdinaryFormIsLeftAlone` already names,
    /// arriving through the mid-word door.
    ///
    /// The control is `שלומ`, which completes to nothing: a finished word spelled
    /// with the wrong shape, and still corrected.
    @MainActor
    func testAFinalFormDoesNotOutrankTheWordTheLettersAreStillSpelling() {
        XCTAssertEqual(HebrewMorphology.inFinalForm("אפ"), "אף")
        XCTAssertTrue(
            SeedLanguageModel.knows("אף", in: .hebrew),
            "the old gate passed because אף is a common word; that is the premise")

        let progress = SuggestionEngine.suggestions(
            prefix: "אפ", context: "אני ", languages: [.hebrew, .english],
            personal: emptyPersonal())
        XCTAssertEqual(
            progress.first(where: \.isDefault)?.text, "אפ",
            "space committed \(progress.first(where: \.isDefault)?.text ?? "nothing") "
                + "while אפשר was in the bar: \(progress.map(\.text))")

        let finished = SuggestionEngine.suggestions(
            prefix: "שלומ", context: "", languages: [.hebrew, .english],
            personal: emptyPersonal())
        XCTAssertEqual(
            finished.first(where: \.isDefault)?.text, "שלום",
            "and a word that completes to nothing is still fixed: \(finished.map(\.text))")
    }

    /// The five letters, and nothing else. A rule generalised to right-to-left
    /// scripts would fire on correctly spelled Arabic, which changes letter shape
    /// in the font rather than in the code point.
    func testFinalFormAppliesOnlyToTheFiveLetters() {
        XCTAssertEqual(HebrewMorphology.inFinalForm("שלומ"), "שלום")
        XCTAssertNil(HebrewMorphology.inFinalForm("שלום"))
        XCTAssertNil(HebrewMorphology.inFinalForm("תודה"))
    }

    // MARK: Wrong layout

    /// Four correct keystrokes read in the wrong alphabet. No spell checker can
    /// help — `akuo` is not a misspelling of anything.
    ///
    /// **`,usv` is not decoration and must not be tidied away.** A mark is only a
    /// mark on the plane it was typed on: `,` on QWERTY is `ת` on the Hebrew
    /// layout, so those four characters are four Hebrew letters and no
    /// punctuation. When `completions(for:)` began handing every source the
    /// trimmed word, this rule got `usv`, which transposes to `ודה`, which is in
    /// no list — the whole rule went silent and the bar offered `use`. It reads
    /// the keystrokes, alone among the sources, because it is replaying key
    /// presses rather than asking a dictionary about a word.
    func testWrongLayoutIsCorrectedAndCommitted() {
        for (typed, meant) in [("akuo", "שלום"), (",usv", "תודה"), ("יקךךם", "hello")] {
            let results = SuggestionEngine.suggestions(
                prefix: typed, context: "", languages: [.english, .hebrew],
                personal: emptyPersonal())
            XCTAssertTrue(
                results.contains { $0.text == meant }, "\(typed) did not offer \(meant)")
            XCTAssertEqual(
                results.first(where: \.isDefault)?.text, meant,
                "\(typed) offered \(meant) but space would not commit it")
        }
    }

    /// The gate has to be tight, or every English word gets a Hebrew neighbour.
    /// `sun` transposes to `דוין`; somebody typing `sun` meant `sun`.
    func testWrongLayoutRefusesAWordThatIsAlreadyAWord() {
        XCTAssertNil(
            LayoutTransposition.correction(
                of: "sun", typedLanguage: .english, other: .hebrew,
                isKnownWord: { _, _ in true }))
        XCTAssertNil(
            LayoutTransposition.correction(
                of: "akuo", typedLanguage: .english, other: nil,
                isKnownWord: { _, _ in false }),
            "with one language enabled there is no other layout to have been on")
    }

    /// The table cannot be derived from `KeyboardLayout.hebrewRows` — English rows are 10/9/7
    /// and Hebrew's are 8/10/9 — so this is what stops it drifting from the
    /// keyboard the user is looking at.
    func testTranspositionTableCoversEveryHebrewKey() {
        let drawn = Set(KeyboardLayout.hebrewRows.joined())
        let mapped = Set(LayoutTransposition.hebrewByLatin.values)
        XCTAssertTrue(
            drawn.subtracting(mapped).isEmpty,
            "keys on the Hebrew keyboard with no Latin position: \(drawn.subtracting(mapped))")
    }

    // MARK: The learned store

    /// A word seen once may be a typo, and a keyboard that learned typos and then
    /// defended them would be worse than one that learned nothing.
    func testLearningTakesRepetitionBeforeItChangesAnything() {
        let personal = emptyPersonal()
        personal.record(word: "Tzachi", previous: "Ask", language: .english, permitted: true)
        XCTAssertEqual(
            personal.words(startingWith: "Tza", in: .english, limit: 3), [],
            "one sighting is not evidence")

        personal.record(word: "Tzachi", previous: "Ask", language: .english, permitted: true)
        XCTAssertEqual(personal.words(startingWith: "Tza", in: .english, limit: 3), ["tzachi"])
        XCTAssertFalse(personal.isProtected("Tzachi", in: .english), "two is not three")

        personal.record(word: "Tzachi", previous: nil, language: .english, permitted: true)
        XCTAssertTrue(personal.isProtected("Tzachi", in: .english))
        XCTAssertEqual(personal.followers(after: "ask", in: .english, limit: 3), ["tzachi"])
    }

    /// A word this person uses must beat an unused neighbour in the same tier.
    /// Seed rank is the only frequency `score` used to see, so a name you type
    /// every day lost to a commoner word you have never written.
    func testAFrequentlyUsedWordOutranksAnUnusedNeighbour() {
        var used = SuggestionEngine.Candidate(
            text: "zzused", language: .english, source: .neighbour)
        used.personalCount = 8
        let unused = SuggestionEngine.Candidate(
            text: "zzrare", language: .english, source: .neighbour)
        XCTAssertGreaterThan(
            SuggestionEngine.score(used), SuggestionEngine.score(unused),
            "personal count has to move rank inside a tier")
    }

    /// Habits cannot climb a source tier. A word typed forty times is still
    /// a weaker claim than a completion that agrees with every key.
    func testPersonalFrequencyCannotClimbASourceTier() {
        var frequent = SuggestionEngine.Candidate(
            text: "zzused", language: .english, source: .correction)
        frequent.personalCount = 40
        let completion = SuggestionEngine.Candidate(
            text: "zzrare", language: .english, source: .neighbour)
        XCTAssertGreaterThan(
            SuggestionEngine.score(completion), SuggestionEngine.score(frequent),
            "300 of habit must not beat 1000 of source")
    }

    /// A name the seed has never heard of, one key off, after two real uses.
    /// One sighting still offers nothing — that is the typo floor.
    func testALearnedWordIsOfferedFromAOneKeySlip() {
        let personal = emptyPersonal()
        personal.record(word: "Zorblin", previous: nil, language: .english, permitted: true)
        XCTAssertEqual(
            personal.neighbours(of: "Zorblim", in: .english, limit: 3), [],
            "one sighting is not a neighbour")

        personal.record(word: "Zorblin", previous: nil, language: .english, permitted: true)
        XCTAssertEqual(personal.neighbours(of: "Zorblim", in: .english, limit: 3), ["zorblin"])

        let results = SuggestionEngine.suggestions(
            prefix: "Zorblim", context: "", languages: [.english], personal: personal)
        XCTAssertTrue(
            results.contains { $0.text.lowercased() == "zorblin" },
            "the bar never offered the learned name: \(results.map(\.text))")
        let slots = SuggestionBar.centeredSlots(results, typed: "Zorblim")
        XCTAssertTrue(
            slots.contains { $0?.text.lowercased() == "zorblin" },
            "the learned neighbour was not drawn: \(slots.map { $0?.text })")
    }

    /// `permitted: false` is how the credential-field refusal reaches the store.
    /// Nothing is written, not a shorter version of it.
    func testNothingIsRecordedWhenRecordingIsRefused() {
        let personal = emptyPersonal()
        for _ in 0..<5 {
            personal.record(word: "hunter2", previous: "password", language: .english, permitted: false)
        }
        XCTAssertEqual(personal.learnedWordCount, 0)
        XCTAssertEqual(personal.count(of: "hunter2", in: .english), 0)
    }

    /// Anything with a digit in it is a code, a price or an address, and is exactly
    /// what a store the user cannot read must not keep.
    func testOnlyWordsAreLearned() {
        let personal = emptyPersonal()
        personal.record(word: "0527", previous: nil, language: .english, permitted: true)
        personal.record(word: "a", previous: nil, language: .english, permitted: true)
        XCTAssertEqual(personal.learnedWordCount, 0)
    }

    /// Settings lists every stored word, including a single sighting. Ranking
    /// still ignores those; `allWords` staying empty is what fails a listing
    /// that reused the gated vocabulary.
    func testLearnedWordsListsEverySightingIncludingOnce() {
        let personal = emptyPersonal()
        personal.record(word: "once", previous: nil, language: .english, permitted: true)
        personal.record(word: "often", previous: nil, language: .english, permitted: true)
        personal.record(word: "often", previous: nil, language: .english, permitted: true)
        personal.record(word: "often", previous: nil, language: .english, permitted: true)
        personal.record(word: "mid", previous: nil, language: .english, permitted: true)
        personal.record(word: "mid", previous: nil, language: .english, permitted: true)
        personal.record(word: "שלום", previous: nil, language: .hebrew, permitted: true)

        let listed = personal.learnedWords()
        XCTAssertEqual(
            listed.map(\.word), ["often", "mid", "once", "שלום"],
            "count desc, then English before Hebrew, then A–Z: \(listed.map(\.word))")
        XCTAssertEqual(listed.map(\.count), [3, 2, 1, 1])
        XCTAssertEqual(
            personal.allWords(in: .english), ["often", "mid"],
            "the gated vocabulary must not start listing singletons")
        XCTAssertTrue(personal.allWords(in: .hebrew).isEmpty)
    }

    /// The app's in-memory copy is from launch. Without a re-read, Settings
    /// would show what it knew this morning, not what the keyboard just wrote.
    func testReloadRereadsTheFileTheKeyboardWrote() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("plm-reload-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = PersonalLanguageModel(url: url)
        writer.record(word: "hello", previous: nil, language: .english, permitted: true)
        writer.save()

        let reader = PersonalLanguageModel(url: url)
        XCTAssertEqual(reader.learnedWordCount, 1)

        writer.record(word: "world", previous: nil, language: .english, permitted: true)
        writer.save()
        XCTAssertEqual(reader.learnedWordCount, 1, "reload is what picks up the new file")
        reader.reload()
        XCTAssertEqual(Set(reader.learnedWords().map(\.word)), ["hello", "world"])
    }

    /// Forget deletes the file. A keyboard that is still alive must not keep
    /// ranking words the user just wiped.
    func testReloadTreatsAMissingFileAsEmpty() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("plm-gone-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = PersonalLanguageModel(url: url)
        writer.record(word: "hello", previous: nil, language: .english, permitted: true)
        writer.save()

        let reader = PersonalLanguageModel(url: url)
        XCTAssertEqual(reader.learnedWordCount, 1)
        writer.clear()
        reader.reload()
        XCTAssertEqual(reader.learnedWordCount, 0, "reload kept the wiped store")
    }

    /// One word, not the whole store. Pairs that used it go with it.
    func testForgetRemovesOneWordAndItsPairs() {
        let personal = emptyPersonal()
        personal.record(word: "hello", previous: nil, language: .english, permitted: true)
        personal.record(word: "hello", previous: nil, language: .english, permitted: true)
        personal.record(word: "world", previous: "hello", language: .english, permitted: true)
        personal.record(word: "world", previous: "hello", language: .english, permitted: true)
        personal.record(word: "later", previous: nil, language: .english, permitted: true)
        personal.record(word: "later", previous: nil, language: .english, permitted: true)

        personal.forget("hello", in: .english)
        XCTAssertEqual(personal.count(of: "hello", in: .english), 0)
        XCTAssertEqual(personal.count(of: "world", in: .english), 2)
        XCTAssertEqual(personal.count(of: "later", in: .english), 2)
        XCTAssertEqual(
            personal.followers(after: "hello", in: .english, limit: 3), [],
            "the pair survived the word: \(personal.followers(after: "hello", in: .english, limit: 3))")
        XCTAssertEqual(Set(personal.learnedWords().map(\.word)), ["later", "world"])
    }

    /// Typing a word and finishing it has to count, not only tapping a candidate.
    /// A tap always inserts a space, so that path was the only one that used to
    /// reach the store; Return, a full stop, and going away with the word still
    /// under the cursor are how a chat message actually ends.
    func testATypedWordIsLearnedWhenItIsFinishedNotOnlyWhenACandidateIsTapped() {
        let saved = SharedStore.shared.autocorrect
        SharedStore.shared.autocorrect = false
        defer { SharedStore.shared.autocorrect = saved }

        func typeHello(_ controller: KeyboardController) {
            controller.shift = .off
            for character in "hello" { controller.press(.character(String(character))) }
        }

        let spaced = KeyboardController(target: CursorTextTarget(before: ""), language: .english)
        typeHello(spaced)
        XCTAssertEqual(
            spaced.personal.count(of: "hello", in: .english), 0,
            "learned a prefix before the word was finished")
        spaced.press(.space)
        XCTAssertEqual(
            spaced.personal.count(of: "hello", in: .english), 1,
            "space after typing did not record: the store only counted candidate taps")

        let returned = KeyboardController(target: CursorTextTarget(before: ""), language: .english)
        typeHello(returned)
        returned.press(.ret)
        XCTAssertEqual(
            returned.personal.count(of: "hello", in: .english), 1,
            "Return did not record the word it finished")

        let stopped = KeyboardController(target: CursorTextTarget(before: ""), language: .english)
        typeHello(stopped)
        stopped.press(.character("."))
        XCTAssertEqual(
            stopped.personal.count(of: "hello", in: .english), 1,
            "a full stop did not record")
        stopped.press(.space)
        XCTAssertEqual(
            stopped.personal.count(of: "hello", in: .english), 1,
            "space after a full stop counted the same word twice")

        let apostrophe = KeyboardController(
            target: CursorTextTarget(before: ""), language: .english)
        apostrophe.shift = .off
        for character in "don" { apostrophe.press(.character(String(character))) }
        apostrophe.press(.character("'"))
        XCTAssertEqual(
            apostrophe.personal.count(of: "don", in: .english), 0,
            "an apostrophe is inside the word and must not finish it")

        let sent = KeyboardController(target: CursorTextTarget(before: ""), language: .english)
        typeHello(sent)
        sent.learnWordJustCommitted()
        XCTAssertEqual(
            sent.personal.count(of: "hello", in: .english), 1,
            "a send without a trailing space did not record")
        sent.learnWordJustCommitted()
        XCTAssertEqual(
            sent.personal.count(of: "hello", in: .english), 1,
            "the keyboard going away twice counted the same open word twice")

        let tapped = KeyboardController(
            target: CursorTextTarget(before: "hel"), language: .english)
        tapped.apply(Suggestion(text: "hello", language: .english))
        XCTAssertEqual(
            tapped.personal.count(of: "hello", in: .english), 1,
            "a candidate tap stopped recording")

        let sentField = CursorTextTarget(before: "")
        let hostSent = KeyboardController(target: sentField, language: .english)
        typeHello(hostSent)
        XCTAssertEqual(hostSent.personal.count(of: "hello", in: .english), 0)
        // The host emptied the field, the way a chat Send does. No space, no
        // Return, no `viewWillDisappear` — `textDidChange` is the only news.
        sentField.placeCaret(before: "", after: "")
        hostSent.refreshSuggestions()
        XCTAssertEqual(
            hostSent.personal.count(of: "hello", in: .english), 1,
            "a send that cleared the field did not record the last word")

        let erased = KeyboardController(
            target: CursorTextTarget(before: ""), language: .english)
        erased.shift = .off
        for character in "hi" { erased.press(.character(String(character))) }
        erased.press(.backspace)
        erased.press(.backspace)
        XCTAssertEqual(
            erased.personal.count(of: "hi", in: .english), 0,
            "deleting a word counted it as committed")

        let emoji = KeyboardController(
            target: CursorTextTarget(before: ""), language: .english)
        typeHello(emoji)
        emoji.insertEmoji("😊")
        XCTAssertEqual(
            emoji.personal.count(of: "hello", in: .english), 1,
            "an emoji after a word did not finish it")
    }

    // MARK: Ranking

    /// The rule that predates the ranking and does not depend on it: whatever the
    /// model believes, somebody who typed `qwt` must be able to keep `qwt`.
    func testTheLiteralKeystrokesAreAlwaysSlotZero() {
        for typed in ["qwt", "helo", "מונ", "Nitai", "akuo"] {
            let results = SuggestionEngine.suggestions(
                prefix: typed, context: "", languages: [.english, .hebrew],
                personal: emptyPersonal())
            XCTAssertEqual(results.first?.text, typed, "slot 0 was not the literal for \(typed)")
        }
    }

    /// The sentence outranking the dictionary. `תודה` is four times commoner than
    /// `תור`, and after `לקבוע` ("to schedule") it is the wrong word.
    func testThePreviousWordDecidesBetweenTwoCommonCompletions() {
        let scheduling = SuggestionEngine.suggestions(
            prefix: "תו", context: "אני צריך לקבוע ", languages: [.hebrew, .english],
            personal: emptyPersonal())
        XCTAssertTrue(
            scheduling.contains { $0.text == "תור" },
            "got \(scheduling.map(\.text)) — the bar ignored the word before it")
    }

    /// A capitalised name the dictionary has never heard of was being replaced with
    /// a word that merely looks like it. This is corpus entry `nc-06`.
    func testAKnownNameIsNotCorrectedAway() {
        let results = SuggestionEngine.suggestions(
            prefix: "Tzachi", context: "Ask ", languages: [.english, .hebrew],
            personal: emptyPersonal())
        XCTAssertEqual(
            results.first(where: \.isDefault)?.text, "Tzachi",
            "got \(results.map(\.text)) — the old engine committed `Teach`")
    }

    /// Three letters, not four. The gate used to be four, and `teh` is three — so
    /// the commonest typo in English was the one autocorrect refused to touch.
    func testThreeLetterTypoIsCorrected() {
        let results = SuggestionEngine.suggestions(
            prefix: "teh", context: "Send me ", languages: [.english], personal: emptyPersonal())
        XCTAssertEqual(results.first(where: \.isDefault)?.text, "the")
    }

    /// And the other side of that gate: a short word that is right stays right.
    func testShortCorrectWordsAreLeftAlone() {
        for (typed, context) in [("bus", "Take the "), ("id", "That's a good "), ("in", "Coming ")] {
            let results = SuggestionEngine.suggestions(
                prefix: typed, context: context, languages: [.english], personal: emptyPersonal())
            XCTAssertEqual(
                results.first(where: \.isDefault)?.text, typed,
                "space would have changed \(typed) to "
                    + "\(results.first(where: \.isDefault)?.text ?? "-")")
        }
    }

    /// Openers are for an empty field. After a real word they are the bar giving up
    /// in a way that looks like an answer, which is what `I · The · We` after
    /// "Happy" was.
    func testOpenersDoNotAppearAfterARealWord() {
        let results = SuggestionEngine.suggestions(
            prefix: "", context: "Thank you so ", languages: [.english], personal: emptyPersonal())
        XCTAssertTrue(results.contains { $0.text == "much" }, "got \(results.map(\.text))")
        // The exact list the old engine fell through to for every English sentence
        // it had no row for. Asserting on the *set* rather than on any one word,
        // because `I` alone is a legitimate prediction in other sentences.
        XCTAssertNotEqual(
            results.map(\.text), ["I", "The", "We"],
            "the bar fell through to the openers instead of reading the sentence")
    }

    /// A full stop closes the thought, so the words before it are not context for
    /// the word after it.
    func testSentenceEndResetsTheContext() {
        XCTAssertEqual(SuggestionEngine.previousWords(in: "Thank you so much. "), [])
        // Case is preserved here and folded at the point of lookup, so a sentence
        // that starts with a capital still finds its row.
        XCTAssertEqual(SuggestionEngine.previousWords(in: "See you "), ["See", "you"])
        XCTAssertEqual(
            SeedLanguageModel.followers(after: ["See", "you"], in: .english).first, "tomorrow",
            "a capitalised first word must not miss the phrase key")
    }

    /// **A newline closes the thought too, and the code said so in a comment while
    /// doing the opposite.** `previousWords` trimmed the whole context, which takes
    /// the line break off the end, and then split on whitespace, which a line break
    /// also is — so the boundary was invisible twice over and `See you\n` predicted
    /// `tomorrow` exactly as `See you ` does. The second assertion is the one that
    /// rejects the old build; the first is here so a fix that simply stopped
    /// reading context cannot pass.
    func testANewlineClosesTheThoughtAsAFullStopDoes() {
        XCTAssertEqual(SuggestionEngine.previousWords(in: "See you "), ["See", "you"])
        XCTAssertEqual(SuggestionEngine.previousWords(in: "See you\n"), [])
        XCTAssertEqual(
            SuggestionEngine.previousWords(in: "Thanks. See you\nI am "), ["I", "am"],
            "a line break must not hide the line the cursor is actually on")
    }

    /// Context must not replace a valid English word that sits outside the seed.
    ///
    /// "sorrow" is absent from the seed (uncommon in chat), so it clears the
    /// early-return guard, and "tomorrow" follows "See you" in the bigrams. On
    /// the broken build the followers check fires on all scripts and replaces
    /// "sorrow" with "tomorrow". With the Hebrew-only scope it is skipped, the
    /// `isKnownWord` guard at the bottom protects it, and space keeps "sorrow".
    ///
    /// This test calls `shouldAutocorrect` directly so the synthetic results
    /// array controls which candidate is `winner`, isolating the one code path
    /// being examined.
    func testContextDoesNotReplaceAValidEnglishWordOutsideSeed() {
        XCTAssertNil(
            SeedLanguageModel.rank(of: "sorrow", in: .english),
            "sorrow entered the seed — pick another word outside it, or the guard fires first")

        let personal = emptyPersonal()
        // Slot 0 is always the literal; slot 1 is "tomorrow", which the seed
        // bigrams say follows "See you" and which the broken code treats as
        // proof the user meant to type it instead of "sorrow".
        let results = [
            SuggestionEngine.Candidate(text: "sorrow", language: .english, source: .typed),
            SuggestionEngine.Candidate(text: "tomorrow", language: .english, source: .seed)
        ]
        let shouldReplace = SuggestionEngine.shouldAutocorrect(
            "sorrow", previousWords: ["See", "you"], typedLanguage: .english,
            results: results, supplementary: [], personal: personal)

        XCTAssertFalse(
            shouldReplace,
            "context replaced a valid English word outside the seed; "
                + "the followers override must be scoped to Hebrew only")
    }

    // MARK: The field is a lexicon

    /// **The seed list is a prior, not the dictionary, and the field is a better
    /// prior than either.** `Zorblin` is in no list this keyboard ships — not the
    /// seed, not Apple's checker, not the personal dictionary — so the only way
    /// it can appear in the bar is if the engine read the words already typed.
    /// The old build scored the last two tokens against the seed and offered
    /// whatever `Zor` happens to complete to, never the name sitting two words
    /// back.
    ///
    /// A made-up name rather than `elephant`: `ele` completes to `electricity`
    /// from the seed, and asserting "elephant is offered" would pass or fail
    /// with Apple's list rather than with this engine.
    func testAWordAlreadyTypedInThisFieldIsOfferedAgain() {
        XCTAssertNil(
            SeedLanguageModel.rank(of: "Zorblin", in: .english),
            "Zorblin entered the seed — pick another word outside it")

        let results = SuggestionEngine.suggestions(
            prefix: "Zor", context: "Please call Zorblin about ",
            languages: [.english], personal: emptyPersonal())
        XCTAssertTrue(
            results.contains { $0.text == "Zorblin" },
            "got \(results.map(\.text)) — a word already in the field must be completable")
    }

    /// Same claim in Hebrew, including across a clitic the seed list never
    /// stores. `לקוואק` is `ל` + a name no dictionary has; typing the name
    /// without the preposition has to reach the stem that was already written.
    func testAHebrewWordAlreadyTypedInThisFieldIsOfferedAgain() {
        let results = SuggestionEngine.suggestions(
            prefix: "קוו", context: "שלחתי לקוואק את ",
            languages: [.hebrew, .english], personal: emptyPersonal())
        XCTAssertTrue(
            results.contains { $0.text == "קוואק" },
            "got \(results.map(\.text)) — the clitic has to come off before the "
                + "field is searched, or לקוואק never matches קוו")
    }

    /// Completing from the field must still honour the prefix. A word two
    /// sentences back that does not start with what was typed is not a
    /// suggestion for this word.
    func testADocumentWordThatDoesNotMatchThePrefixIsNotOffered() {
        let results = SuggestionEngine.suggestions(
            prefix: "hel", context: "Zorblin said ",
            languages: [.english], personal: emptyPersonal())
        XCTAssertFalse(
            results.contains { $0.text == "Zorblin" },
            "got \(results.map(\.text))")
    }

    /// **A full stop closes `previousWords` and must not close the field.**
    /// `I booked Zorblin yesterday. I booked ` has no seed row for `booked`, so
    /// the old build fell through to the openers — `I · Thanks · Hi` — as if
    /// the first sentence had been erased. The name that followed `booked`
    /// earlier in this field is the prediction.
    func testTheFieldItselfTeachesWhatFollowsAWord() {
        let results = SuggestionEngine.suggestions(
            prefix: "", context: "I booked Zorblin yesterday. I booked ",
            languages: [.english], personal: emptyPersonal())
        XCTAssertTrue(
            results.contains { $0.text == "Zorblin" },
            "got \(results.map(\.text)) — the old bar fell through to the openers "
                + "because previousWords stops at the full stop")
    }

    func testAHebrewFieldTeachesWhatFollowsAWord() {
        let results = SuggestionEngine.suggestions(
            prefix: "", context: "שלחתי לקוואק אתמול. שלחתי ",
            languages: [.hebrew, .english], personal: emptyPersonal())
        XCTAssertTrue(
            results.contains { $0.text == "לקוואק" },
            "got \(results.map(\.text)) — a name after שלחתי earlier in this "
                + "field has to beat the openers")
    }

    /// Line breaks are the same: `previousWords` reads only the last line, so
    /// without a field-wide lexicon a name on the line above is gone. Completing
    /// it is why the line above was typed.
    func testAWordOnThePreviousLineIsStillCompletable() {
        let results = SuggestionEngine.suggestions(
            prefix: "Zor", context: "Zorblin called.\nPlease ring ",
            languages: [.english], personal: emptyPersonal())
        XCTAssertTrue(
            results.contains { $0.text == "Zorblin" },
            "got \(results.map(\.text)) — a newline must not hide words already "
                + "in the field from completion")
    }

    /// `UITextChecker` is the English and Hebrew dictionary. The seed is a few
    /// hundred ranked words and absence from it proves nothing — `elephant` is
    /// a real word, `eleph` is an unambiguous prefix of it, and a bar that only
    /// knows the seed cannot offer it.
    func testADictionaryWordOutsideTheSeedIsStillCompleted() {
        XCTAssertNil(
            SeedLanguageModel.rank(of: "elephant", in: .english),
            "elephant entered the seed — pick another dictionary word outside it")
        let results = SuggestionEngine.suggestions(
            prefix: "eleph", context: "", languages: [.english], personal: emptyPersonal())
        XCTAssertTrue(
            results.contains { $0.text.lowercased() == "elephant" },
            "got \(results.map(\.text)) — the checker is the dictionary; "
                + "the seed is only a prior")
    }

    /// The helpers the tests above rest on, pinned separately so a bar-level
    /// miss can be told from a tokenisation miss.
    func testDocumentWordsReadAcrossSentencesAndLines() {
        XCTAssertEqual(
            SuggestionEngine.documentWords(in: "Please call Zorblin about "),
            ["Please", "call", "Zorblin", "about"])
        XCTAssertEqual(
            SuggestionEngine.documentWords(in: "Zorblin called.\nPlease ring "),
            ["Zorblin", "called", "Please", "ring"])
        XCTAssertEqual(
            SuggestionEngine.documentFollowers(
                after: "booked", in: "I booked Zorblin yesterday. I booked ", limit: 3),
            ["Zorblin"])
        XCTAssertEqual(
            SuggestionEngine.previousWords(in: "I booked Zorblin yesterday. I booked "),
            ["I", "booked"],
            "previousWords still stops at the full stop; the field lexicon is "
                + "the other function")
    }

    // MARK: The async tier

    /// The model is allowed to change the bold word. Slot 0 stays the typed
    /// letters. A build that still pins the local default fails the last
    /// assertion: it would keep `receive` bold after the model said `REFINED`.
    func testRefinementCanChangeTheBoldWord() {
        withBarSettingsOn {
            let target = MockTextTarget(text: "recieve")
            let controller = KeyboardController(target: target, language: .english)
            controller.refreshSuggestions()

            XCTAssertEqual(
                controller.suggestions.first(where: \.isDefault)?.text, "receive",
                "the local tier has to be autocorrecting for this test to be about anything")

            controller.applyRefinement(["REFINED", "REFINEDER"], for: "recieve")

            XCTAssertEqual(
                controller.suggestions.first?.text, "recieve",
                "slot 0 is the literal keystrokes")
            XCTAssertEqual(
                controller.suggestions.first(where: \.isDefault)?.text, "REFINED",
                "the model has to be able to take the bold slot: "
                    + "\(controller.suggestions.map(\.text))")
        }
    }

    /// Autocorrect-off means space will not commit, so the bar must not bold a
    /// model word after refine. The word still lands in the bar for a tap.
    func testRefinementKeepsTheTypedWordBoldWhenAutocorrectIsOff() {
        let store = SharedStore.shared
        let (autocorrect, predictions) = (store.autocorrect, store.predictions)
        store.autocorrect = false
        store.predictions = true
        defer {
            store.autocorrect = autocorrect
            store.predictions = predictions
        }
        let target = MockTextTarget(text: "hel")
        let controller = KeyboardController(target: target, language: .english)
        controller.refreshSuggestions()
        XCTAssertEqual(
            controller.suggestions.first(where: \.isDefault)?.text, "hel",
            "Autocorrect off has to pin the bold slot before refine is asked")

        controller.applyRefinement(["hello", "help"], for: "hel")

        XCTAssertEqual(controller.suggestions.first?.text, "hel")
        XCTAssertEqual(
            controller.suggestions.first(where: \.isDefault)?.text, "hel",
            "refine must not bold a model word that space is not allowed to insert: "
                + "\(controller.suggestions.map(\.text))")
        XCTAssertTrue(
            controller.suggestions.contains { $0.text == "hello" },
            "the model's word still has to be tappable: "
                + "\(controller.suggestions.map(\.text))")
    }

    /// The other half of the same rule. With nothing typed the bold slot is a tap
    /// target and not something the space bar will insert — `insertSpace` leaves an
    /// empty prefix alone — so refining the likeliest next word is exactly what the
    /// tier is for and must still happen.
    func testRefinementMayReplaceTheNextWordPrediction() {
        withBarSettingsOn {
            let target = MockTextTarget(text: "See you ")
            let controller = KeyboardController(target: target, language: .english)
            controller.refreshSuggestions()
            XCTAssertFalse(controller.suggestions.isEmpty)

            controller.applyRefinement(["Thursday"], for: "")

            XCTAssertTrue(
                controller.suggestions.contains { $0.text == "Thursday" },
                "with no word in progress the model's answer has to reach the bar: "
                    + "\(controller.suggestions.map(\.text))")
        }
    }

    /// Pins the two settings the controller re-reads at every keystroke, and puts
    /// them back. Both ship on, but both are *stored*, so a developer who turned
    /// either off in the app would otherwise watch the two tests above fail for a
    /// reason that has nothing to do with the async tier.
    private func withBarSettingsOn(_ body: () -> Void) {
        let store = SharedStore.shared
        let (autocorrect, predictions) = (store.autocorrect, store.predictions)
        store.autocorrect = true
        store.predictions = true
        defer {
            store.autocorrect = autocorrect
            store.predictions = predictions
        }
        body()
    }

    /// Mid-word, a suggestion that does not start with what has been typed is not a
    /// suggestion for this word — it would replace the letters the user is still
    /// typing rather than continue them.
    func testRefinementDropsWordsThatDoNotContinueThePrefix() {
        XCTAssertEqual(
            PredictiveRefiner.cleaned(["receive", "reject", "arrive"], continuing: "rec"),
            ["receive"])
        XCTAssertEqual(
            PredictiveRefiner.cleaned(
                ["  soon ", "soon", "a whole sentence that will never fit"], continuing: ""),
            ["soon"], "duplicates and sentences both have to go")
    }

    /// **The model is guessing the next word of this message, and iOS already
    /// windows `documentContextBeforeInput`.** Chopping it again to 40 words
    /// threw away the start of anything longer than a short paragraph — the
    /// names, the question, the reason the current sentence exists. The
    /// keyboard can only see what the host hands over; that *is* the full
    /// typed input, and the refiner has to send it.
    func testRefinementKeepsTheWholeTypedField() {
        let words = (1...50).map { "w\($0)" }.joined(separator: " ")
        XCTAssertEqual(
            PredictiveRefiner.tail(of: words), words,
            "a 40-word tail would have dropped w1 through w10")
    }

    /// A credential field is refused before anything is sent, and an empty field
    /// with no message on screen has nothing to predict from.
    func testRefinementRefusesWhenThereIsNothingOrNoPermission() {
        let refiner = PredictiveRefiner(
            onDevice: AlwaysPredicts(), apply: { _, _ in })
        func request(text: String, permitted: Bool) -> PredictiveRefiner.Request {
            PredictiveRefiner.Request(
                textBefore: text, wordInProgress: "", language: .english, screenContext: nil,
                permitted: permitted)
        }
        XCTAssertFalse(refiner.shouldRefine(request(text: "Hello there", permitted: false)))
        XCTAssertFalse(refiner.shouldRefine(request(text: "   ", permitted: true)))
        XCTAssertTrue(refiner.shouldRefine(request(text: "Hello there", permitted: true)))
    }

    /// With no engine that speaks the language, the honest answer is silence and
    /// the local tier's three slots stand.
    func testRefinementRefusesALanguageNoEngineSpeaks() {
        let refiner = PredictiveRefiner(
            onDevice: SpeaksOnly(.english), apply: { _, _ in })
        func request(_ language: KeyboardLanguage) -> PredictiveRefiner.Request {
            PredictiveRefiner.Request(
                textBefore: "משהו", wordInProgress: "", language: language, screenContext: nil,
                permitted: true)
        }
        XCTAssertTrue(refiner.shouldRefine(request(.english)))
        XCTAssertFalse(refiner.shouldRefine(request(.hebrew)))
    }

    /// The shipping refiner has no cloud engine, and Apple's on-device model
    /// does not list Hebrew. A true here means someone wired `CloudIntelligence`
    /// back into `standard()`.
    func testTheShippingRefinerDoesNotServeHebrew() {
        let refiner = PredictiveRefiner.standard { _, _ in }
        let request = PredictiveRefiner.Request(
            textBefore: "משהו", wordInProgress: "", language: .hebrew, screenContext: nil,
            permitted: true)
        XCTAssertFalse(
            refiner.shouldRefine(request),
            "Hebrew in the bar is a cloud call; the local tier already filled the slots")
    }

    /// The corpus harness copies this list rather than importing `SharedStore`,
    /// which pulls in Combine and most of the settings surface. This is what stops
    /// the copy drifting and quietly changing what a score means.
    func testHarnessPersonalDictionaryMatchesTheShippedOne() {
        XCTAssertEqual(
            SharedStore.shippedPersonalDictionary,
            ["Nitai", "Handi", "Wispr", "KeyboardKit", "סאפא", "בלי־פרופ"],
            "Bar/typing/harness/main.swift carries a copy of this list and must be updated too")
    }
}

// MARK: - Stubs

private struct AlwaysPredicts: TextPrediction {
    func canPredict(in language: KeyboardLanguage) -> Bool { true }
    func continuations(
        after text: String, replyingTo context: ScreenContext?, language: KeyboardLanguage
    ) async throws -> [String] { ["one", "two"] }
}

private struct SpeaksOnly: TextPrediction {
    let language: KeyboardLanguage
    init(_ language: KeyboardLanguage) { self.language = language }
    func canPredict(in language: KeyboardLanguage) -> Bool { language == self.language }
    func continuations(
        after text: String, replyingTo context: ScreenContext?, language: KeyboardLanguage
    ) async throws -> [String] { ["one"] }
}
