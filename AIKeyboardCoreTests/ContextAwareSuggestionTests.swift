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

    /// `permitted: false` is how the credential-field refusal and the settings
    /// toggle both reach the store. Nothing is written, not a shorter version of it.
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
            Suggestion(text: "sorrow", language: .english),
            Suggestion(text: "tomorrow", language: .english, isDefault: true)
        ]
        let shouldReplace = SuggestionEngine.shouldAutocorrect(
            "sorrow", previousWords: ["See", "you"], typedLanguage: .english,
            results: results, supplementary: [], personal: personal)

        XCTAssertFalse(
            shouldReplace,
            "context replaced a valid English word outside the seed; "
                + "the followers override must be scoped to Hebrew only")
    }

    // MARK: The async tier

    /// The contract the second tier exists under. It may replace the slots the
    /// local tier is not holding, and it may not change what the space bar is
    /// about to insert — otherwise a pause in typing silently swaps the word.
    ///
    /// **The version of this test that stood here passed against the bug it is
    /// named after, which is the trap `AGENTS.md` names.** It never called
    /// `applyRefinement`: it built the merged list by hand as
    /// `[before[0], Suggestion("REFINED"), before[2]]`, handed that to
    /// `markDefault(at: 1)` and asserted the default was still at index 1 — which
    /// it was, holding `REFINED`. That is a demonstration of the defect written as
    /// an assertion that it is fine. This one drives the real controller and
    /// asserts on the default's *text*, which only the fixed build gets right: the
    /// broken one answers `REFINED`.
    func testRefinementNeverChangesWhatTheSpaceBarWouldCommit() {
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
                controller.suggestions.first(where: \.isDefault)?.text, "receive",
                "the model may not decide what space inserts: "
                    + "\(controller.suggestions.map(\.text))")
        }
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

    /// A credential field is refused before anything is sent, and an empty field
    /// with no message on screen has nothing to predict from.
    func testRefinementRefusesWhenThereIsNothingOrNoPermission() {
        let refiner = PredictiveRefiner(
            onDevice: nil, cloud: AlwaysPredicts(), apply: { _, _ in })
        func request(text: String, permitted: Bool, slots: Int = 1) -> PredictiveRefiner.Request {
            PredictiveRefiner.Request(
                textBefore: text, wordInProgress: "", language: .english, screenContext: nil,
                permitted: permitted, localSlotCount: slots)
        }
        XCTAssertFalse(refiner.shouldRefine(request(text: "Hello there", permitted: false)))
        XCTAssertFalse(refiner.shouldRefine(request(text: "   ", permitted: true)))
        XCTAssertTrue(refiner.shouldRefine(request(text: "Hello there", permitted: true)))
    }

    /// With no engine that speaks the language, the honest answer is silence and
    /// the local tier's three slots stand.
    func testRefinementRefusesALanguageNoEngineSpeaks() {
        let refiner = PredictiveRefiner(
            onDevice: nil, cloud: SpeaksOnly(.english), apply: { _, _ in })
        func request(_ language: KeyboardLanguage) -> PredictiveRefiner.Request {
            PredictiveRefiner.Request(
                textBefore: "משהו", wordInProgress: "", language: language, screenContext: nil,
                permitted: true, localSlotCount: 1)
        }
        XCTAssertTrue(refiner.shouldRefine(request(.english)))
        XCTAssertFalse(refiner.shouldRefine(request(.hebrew)))
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
