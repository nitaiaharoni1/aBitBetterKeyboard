import XCTest

@testable import AIKeyboardCore


extension ContextAwareSuggestionTests {
    func testAnIrregularHebrewPluralIsOfferedWhereNoEndingCouldReachIt() {
        for (typed, wanted) in [
            ("בית", "בתים"), ("אישה", "נשים"), ("שנה", "שנים"), ("יום", "ימים"),
            ("בן", "בנים"), ("בתים", "בית")
        ] {
            let results = SuggestionEngine.suggestions(
                prefix: typed, context: "", languages: [.hebrew, .english],
                personal: emptyPersonal())
            XCTAssertTrue(
                results.map(\.text).contains(wanted),
                "\(typed) did not offer \(wanted) in a drawn slot: \(results.map(\.text))")
            XCTAssertEqual(
                results.first(where: \.isDefault)?.text, typed,
                "space replaced a finished word with its own plural: \(results.map(\.text))")
        }

        // The floor that makes the table necessary, still in place. `בית` looks
        // like it carries a `ת` ending; stripping it leaves `בי`, and `ביים` is a
        // real word about directing films.
        let house = SuggestionEngine.suggestions(
            prefix: "בית", context: "", languages: [.hebrew, .english],
            personal: emptyPersonal())
        XCTAssertFalse(
            house.map(\.text).contains("ביים"),
            "the three-letter stem floor stopped holding: \(house.map(\.text))")

        // A word the ending rule already reaches is deliberately absent from the
        // table, because a row that duplicates the rule is a row that can disagree
        // with it later. `hebrewShapeFolded` puts the final mem back before `ות`
        // goes on.
        XCTAssertTrue(
            SuggestionEngine.hebrewIrregulars(of: "מקום").isEmpty,
            "מקומות is reachable by the ending rule and must not be in the table too")
        XCTAssertTrue(
            SuggestionEngine.hebrewInflections(of: "מקום", locale: "he_IL").contains("מקומות"),
            "the ending rule stopped reaching מקומות, so the table's omission now costs a word")
    }

    /// Every row of a hand-written Hebrew table, against Apple's dictionary.
    ///
    /// **The one check a reader of `SuggestionEngine+Completions.swift` cannot
    /// perform.** `hebrewIrregularPlurals` is 21 pairs of Hebrew, and a
    /// transposed letter in one of them ships a non-word into the suggestion bar
    /// with nothing to catch it — the exact defect NIT-129 was about, arriving
    /// through a table instead of through morphology. `readingIsSpelledOut` and
    /// the `offered` gate both exist to stop a *built* word being wrong and
    /// neither is asked here, on purpose, so this is what stands in for them.
    func testEveryIrregularPluralInTheTableIsARealHebrewWord() {
        for (singular, plural) in SuggestionEngine.hebrewIrregularPlurals {
            XCTAssertTrue(
                SuggestionEngine.isKnownWord(singular, checkerLocale: "he_IL"),
                "\(singular) is not a Hebrew word")
            XCTAssertTrue(
                SuggestionEngine.isKnownWord(plural, checkerLocale: "he_IL"),
                "\(plural), the plural given for \(singular), is not a Hebrew word")
            XCTAssertNotEqual(singular, plural, "\(singular) is its own plural")
        }
        // Both directions, because the gap runs both ways: a regular plural finds
        // its own singular through the `ה` ending and an irregular one returned
        // nothing at all.
        XCTAssertEqual(SuggestionEngine.hebrewIrregulars(of: "אישה"), ["נשים"])
        XCTAssertEqual(SuggestionEngine.hebrewIrregulars(of: "נשים"), ["אישה"])
    }

    /// **Two real Hebrew words sharing a prefix, and space picked one of them.**
    /// `להתראות` ("goodbye") and `להתראיין` ("to be interviewed") agree for five
    /// letters, so five letters into either one the space bar inserted the other
    /// and the user was wrong whichever they had meant.
    ///
    /// **This test was written for a different mechanism and the measurement says
    /// that mechanism was never here.** It was named for a `UITextChecker`
    /// completion of a stem `HebrewMorphology.splits` invented, on the theory that
    /// `להתראיין` arrived through `ל` + `התרא`. Read out of the engine, the winner
    /// at this prefix is `.checker` at `cliticDepth` **0**, score 1000: Apple
    /// completes the *glued* form itself, and the split reading that
    /// `commitTrustsReading` does refuse scores 500 lower and never reaches the
    /// bar. So the gate this test was committed alongside cannot fail it, which is
    /// what "compiled but never run" hid. `testTheCommitGateReadsTheReadingAndNotThe
    /// Length` covers that gate directly and does not depend on Apple's list.
    ///
    /// What is left is an ambiguity, and the pair diverging in *both* directions is
    /// the proof: `Bar/typing/sweep` types both words and gets the other one at
    /// this exact keystroke either way. That is `respon` → `respond` / `response`
    /// in Hebrew. `hasDistinctHebrewLexemes` is the test that separates it from an
    /// ordinary inflection, and the winner arriving `.checker` — with no frequency
    /// prior behind it at all — is what keeps the rule off `בעבו` → `בעבודה`.
    ///
    /// **Which word is offered is deliberately not pinned.** Apple's Hebrew list
    /// moves between runs (the `he-comp-04` / `he-comp-05` note in
    /// `.claude/rules/suggestion-bar.md`), and here it moves *within* one process:
    /// the sweep measured this prefix answering `להתראיין` in one place and
    /// `להתראות` in another. So the premise is asserted as "two different
    /// completions are still offered", which is what makes the keystrokes
    /// ambiguous, rather than as either spelling. The typed echo is excluded,
    /// because `SuggestionEngine` always returns it and `contains {
    /// $0.hasPrefix(typed) }` is true of a completely dead engine.
    @MainActor
    func testTwoHebrewWordsSharingAPrefixDoNotTakeTheSpaceBar() {
        let results = SuggestionEngine.suggestions(
            prefix: "להתרא", context: "", languages: [.hebrew, .english],
            personal: emptyPersonal())
        let offered = results.map(\.text).filter { $0 != "להתרא" && $0.hasPrefix("להתרא") }
        XCTAssertGreaterThan(
            offered.count, 1,
            "got \(results.map(\.text)) — the keystrokes have to still be ambiguous for "
                + "this to be the case it is named after; one offer would make it "
                + "an ordinary completion and this test vacuous")
        XCTAssertTrue(
            SuggestionEngine.hasDistinctHebrewLexemes(offered),
            "\(offered) read as one word inflected, so the premise is gone: the bold "
                + "slot below would be right to finish it")
        XCTAssertEqual(
            results.first(where: \.isDefault)?.text, "להתרא",
            "space committed \(results.first(where: \.isDefault)?.text ?? "nothing") "
                + "five letters into a word that could still be either: \(results.map(\.text))")
    }

    /// The control, and the reason the rule above is a lexeme test rather than
    /// "Apple's list may not finish a Hebrew word".
    ///
    /// One letter further on, `להתראו` has only one word left behind it, and the
    /// forms Apple offers beside it (`להתראותם`, `להתראותן`) are that word with a
    /// possessive on the end. The space bar has to finish it. A build that refused
    /// every `.checker` completion in Hebrew would pass the test above and fail
    /// here, and it would cost four keystrokes across two words in the sweep.
    @MainActor
    func testAHebrewCompletionWithOneWordBehindItStillCommits() {
        for context in ["", "אוקיי "] {
            let results = SuggestionEngine.suggestions(
                prefix: "להתראו", context: context, languages: [.hebrew, .english],
                personal: emptyPersonal())
            XCTAssertEqual(
                results.first(where: \.isDefault)?.text, "להתראות",
                "space kept \(results.first(where: \.isDefault)?.text ?? "nothing") after "
                    + "\(context.isEmpty ? "nothing" : context): \(results.map(\.text))")
        }
    }

    /// The lexeme test on its own, away from Apple's list, so a checker whose
    /// Hebrew answers moved cannot make the two tests above pass or fail for the
    /// wrong reason.
    ///
    /// Each row rejects a different cheaper rule. **Hebrew inflects by replacing
    /// the ending, not by adding to it**, so `hasDistinctLexemes` — which compares
    /// with `hasPrefix` and is right for `schedule` / `scheduled` — reads
    /// `הודעה` / `הודעות` as two words; widening it to Hebrew is the fix that was
    /// measured and rejected, because it stops the correct `בעבו` → `בעבודה`. And
    /// a stem comparison *alone* is not enough either: a letter changes shape when
    /// it stops being last, so `להתראיינה` does not begin with `להתראיין` on the
    /// code points at all.
    func testTheHebrewLexemeTestKnowsAnInflectionFromASecondWord() {
        XCTAssertTrue(
            SuggestionEngine.hasDistinctHebrewLexemes(["להתראיין", "להתראות"]),
            "the pair this whole rule exists for read as one word")
        XCTAssertFalse(
            SuggestionEngine.hasDistinctHebrewLexemes(["הודעה", "הודעות"]),
            "a feminine singular and its plural are one word; hasPrefix says otherwise, "
                + "which is exactly why this is not hasDistinctLexemes")
        XCTAssertFalse(
            SuggestionEngine.hasDistinctHebrewLexemes(["בעבודה", "בעבודות"]),
            "the control the recorded objection is about, with the clitic still on")
        XCTAssertFalse(
            SuggestionEngine.hasDistinctHebrewLexemes(["להתראיין", "להתראיינה"]),
            "the final nun goes back to its ordinary shape the moment anything follows "
                + "it, so a prefix test without the shape fold reads one word as two")
        XCTAssertFalse(
            SuggestionEngine.hasDistinctHebrewLexemes(["להתראות", "להתראותם"]),
            "a possessive hung off the end is the English shape and the prefix half "
                + "already answers it")
        XCTAssertTrue(
            SuggestionEngine.hasDistinctHebrewLexemes(["להתחיל", "להתחייב"]),
            "to begin and to commit oneself are two words, and the bar offers both "
                + "five letters in")
        XCTAssertFalse(
            SuggestionEngine.hasDistinctHebrewLexemes(["הודעה"]),
            "one offer is not an ambiguity")
        XCTAssertEqual(
            SuggestionEngine.hebrewLexemeStem("עבודות"), "עבוד",
            "the plural ending has to come off for the two spellings to meet")
        XCTAssertEqual(
            SuggestionEngine.hebrewLexemeStem("להתראיין"), "להתראיין",
            "the five final forms are not endings; stripping the nun here would fold "
                + "this word onto להתראות and take the whole rule with it")
    }

    /// **The wrong-layout rule was beating the rule this product is for.**
    /// Three letters into `screenshot` after `אני מצרף `, `scr` committed `דבר`:
    /// `LayoutTransposition` fires at exactly three letters, arrives `.layout` at
    /// 9045, and `commitReason` answered on the different-script branch above
    /// every other question — outranking `codeSwitchVocabulary`, where `screenshot`
    /// was already sitting in slot 2 and which exists for this exact sentence
    /// (corpus `cs-05`). It self-heals at four letters, which is why nothing in the
    /// frozen 90 could see it.
    ///
    /// The premise is asserted as well as the behaviour: the transposition has to
    /// still be *offered*, or a build that simply stopped generating it would pass
    /// here while breaking `wl-01`.
    @MainActor
    func testADeliberateCodeSwitchIsNotTreatedAsTheWrongLayout() {
        let results = SuggestionEngine.suggestions(
            prefix: "scr", context: "אני מצרף ", languages: [.english, .hebrew],
            personal: emptyPersonal())
        XCTAssertTrue(
            results.contains { SuggestionEngine.dominantLanguage(in: $0.text)?.script == .hebrew },
            "got \(results.map(\.text)) — the transposition still has to reach the bar; "
                + "only the bold slot moves")
        XCTAssertEqual(
            results.first(where: \.isDefault)?.text, "scr",
            "space committed \(results.first(where: \.isDefault)?.text ?? "nothing") three "
                + "letters into screenshot: \(results.map(\.text))")
    }

    /// The control, and the case the wrong-layout rule was written for: the same
    /// Hebrew sentence, the same Latin keystrokes, and this time they spell nothing
    /// at all in the alphabet they were keyed in.
    ///
    /// **The frozen corpus only asks this of an empty field** (`wl-01`, `wl-02`,
    /// `wl-03` all type into nothing), so the sentence signal the rule above turns
    /// on was never under test. A gate that refused the transposition whenever the
    /// sentence is in the other script would pass every corpus entry and destroy
    /// the feature on the phone, because a person who forgot the globe key is
    /// almost always mid-Hebrew-message. `Bar/typing/sweep/words.json` carries both
    /// of these now.
    @MainActor
    func testTheWrongLayoutIsStillCorrectedInsideAHebrewSentence() {
        for (typed, meant) in [("akuo", "שלום"), (",usv", "תודה")] {
            let results = SuggestionEngine.suggestions(
                prefix: typed, context: "אני רוצה להגיד ", languages: [.english, .hebrew],
                personal: emptyPersonal())
            XCTAssertEqual(
                results.first(where: \.isDefault)?.text, meant,
                "space kept \(results.first(where: \.isDefault)?.text ?? "nothing") for "
                    + "\(typed), which spells nothing in the alphabet it was typed in: "
                    + "\(results.map(\.text))")
        }
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
    /// clitics loses `מהעבודה`; one that counted letters added has nothing to say
    /// about either. The last row is the reason nothing outside Hebrew changed —
    /// `cliticDepth` is zero everywhere else, so the whole rule is skipped, which
    /// is also why an unsplit `.checker` completion (no `cliticDepth` argument,
    /// hence zero) is untouched — the gate no longer asks about source at all.
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

    /// **A reason named about the typed word does not entitle the space bar to
    /// insert a different candidate, and the final-form rule was doing exactly
    /// that.**
    ///
    /// `SuggestionEngine.evaluate` marks the default at slot 1 whenever
    /// `commitReason` answers, so the reason decides *whether* to swap and the
    /// ranking decides *what* to swap in. `Source.personal` is 8000 and
    /// `.orthography` 7000, so a contact or a hand-typed entry that merely
    /// extends the keystrokes wins the ranking outright — and `שלומ` with a
    /// contact `שלומית` handed the space bar that name at confidence 96, which is
    /// above the shipped floor, on a rule that had asked one question about the
    /// letters and none about the winner.
    ///
    /// **Asked of `commitReason` directly, because the end-to-end route cannot
    /// reject the old build on its own.** Apple's checker lists completions of
    /// `שלומ` (`שלומדים` and friends), which makes the entry *contested* and trips
    /// the guard one block above this one, so the whole-engine answer is already
    /// nil today for a second reason. A two-candidate results array is the case
    /// that guard cannot see: nothing else continues the keystrokes, so only the
    /// rule under test can answer.
    ///
    /// The control is the same call with the orthography candidate winning, which
    /// still commits — a build that answered nil to everything here would fail it.
    func testAContactExtendingTheKeystrokesDoesNotCommitThroughTheHebrewFinalForm() {
        XCTAssertEqual(
            SuggestionEngine.hebrewFinalFormCorrection(of: "שלומ"), "שלום",
            "the rule under test has to fire at all for either half to mean anything")

        let personal = emptyPersonal()
        let contactWins = [
            SuggestionEngine.Candidate(text: "שלומ", language: .hebrew, source: .typed),
            SuggestionEngine.Candidate(text: "שלומית", language: .hebrew, source: .personal)
        ]
        XCTAssertNil(
            SuggestionEngine.commitReason(
                "שלומ", previousWords: [], typedLanguage: .hebrew,
                results: contactWins, supplementary: ["שלומית"], personal: personal),
            "the final-form rule armed the space bar with שלומית, a name it never "
                + "asked a question about, at confidence 96")

        let correctionWins = [
            SuggestionEngine.Candidate(text: "שלומ", language: .hebrew, source: .typed),
            SuggestionEngine.Candidate(text: "שלום", language: .hebrew, source: .orthography)
        ]
        XCTAssertEqual(
            SuggestionEngine.commitReason(
                "שלומ", previousWords: [], typedLanguage: .hebrew,
                results: correctionWins, supplementary: [], personal: personal),
            CommitReason.hebrewFinalForm,
            "and the rule still fires when the orthography candidate is the winner")
    }

    /// The same defect through the contraction table, where the whole engine can
    /// see it: `dont` is uncontested, because `don't` does not continue `dont`
    /// once the apostrophe is in it and Apple lists no completion that does.
    ///
    /// So the old build ran the table's rule, marked slot 1 as the default, and
    /// space inserted the contact `Dontrell` at confidence 98 — the highest price
    /// anywhere in `CommitReason`, paid for a candidate the table had never heard
    /// of. The control types the same four letters with an empty list and still
    /// gets `don't`.
    func testAContactExtendingTheKeystrokesDoesNotCommitThroughTheContractionTable() {
        XCTAssertEqual(
            SuggestionEngine.contractions["dont"], "don't",
            "the table is what makes this word correctable at all")

        // Asked of the rule first, with a results array nothing else contests, so
        // this half cannot be carried by Apple's completion list happening to
        // trip the contested guard one block above it.
        let contactWins = [
            SuggestionEngine.Candidate(text: "dont", language: .english, source: .typed),
            SuggestionEngine.Candidate(text: "Dontrell", language: .english, source: .personal)
        ]
        XCTAssertNil(
            SuggestionEngine.commitReason(
                "dont", previousWords: ["I"], typedLanguage: .english,
                results: contactWins, supplementary: ["Dontrell"], personal: emptyPersonal()),
            "the contraction table armed the space bar with Dontrell at confidence 98")

        let withContact = SuggestionEngine.suggestions(
            prefix: "dont", context: "I ", languages: [.english],
            supplementary: ["Dontrell"], personal: emptyPersonal())
        XCTAssertEqual(
            withContact.first(where: \.isDefault)?.text, "dont",
            "space committed \(withContact.first(where: \.isDefault)?.text ?? "nothing") "
                + "on a rule about the apostrophe: \(withContact.map(\.text))")
        XCTAssertTrue(
            withContact.contains { $0.text == "Dontrell" },
            "the entry must still be offered — a build that simply dropped it from the "
                + "bar would pass the assertion above for the wrong reason")

        let withoutContact = SuggestionEngine.suggestions(
            prefix: "dont", context: "I ", languages: [.english], personal: emptyPersonal())
        XCTAssertEqual(
            withoutContact.first(where: \.isDefault)?.text, "don't",
            "and the table still commits with nothing outranking it: "
                + "\(withoutContact.map(\.text))")
    }

    /// The five letters, and nothing else. A rule generalised to right-to-left
    /// scripts would fire on correctly spelled Arabic, which changes letter shape
    /// in the font rather than in the code point.

}
