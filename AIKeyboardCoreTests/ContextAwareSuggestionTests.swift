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
    internal func emptyPersonal() -> PersonalLanguageModel {
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
    /// `תרופה` is in the seed list, which is asserted here, so "the winner must be
    /// seed-reachable" does not exclude this reading and was never the fix.
    ///
    /// **`להתרופה` is no longer in the bar at all, and that is a later change
    /// rather than a weaker test.** This used to assert the candidate was still
    /// *offered*, on the grounds that a build which fixed the commit by deleting
    /// the two-clitic reading would be throwing away `מהעבודה` with it.
    /// `readingIsSpelledOut` draws the line somewhere that argument could not
    /// reach: not at the depth of the reading but at whether the dictionary spells
    /// the glued form out at all. `מהעבודה` is Apple's own first completion for
    /// `מהעבו` and survives; `להתרופה` appears in no list and is not generated. So
    /// the control the old assertion existed to provide has moved to
    /// `testACliticReadingWithLettersBehindItStillCommits`, which is a stronger
    /// place for it — it fails on the *commit* rather than on the presence of a
    /// word in a slot.
    @MainActor
    func testAStackedCliticReadingDoesNotTakeTheSpaceBar() {
        XCTAssertTrue(
            SeedLanguageModel.knows("תרופה", in: .hebrew),
            "תרופה left the seed list — this defect is reached through it, so the test "
                + "would now pass for the wrong reason")

        let results = SuggestionEngine.suggestions(
            prefix: "להתר", context: "", languages: [.hebrew, .english],
            personal: emptyPersonal())
        XCTAssertFalse(
            results.contains { $0.text == "להתרופה" },
            "got \(results.map(\.text)) — no dictionary lists להתרופה, so a reading that "
                + "invented it must not reach the bar")
        XCTAssertEqual(
            results.first(where: \.isDefault)?.text, "להתר",
            "space committed \(results.first(where: \.isDefault)?.text ?? "nothing") "
                + "four letters into להתראות: \(results.map(\.text))")
    }

    /// **A reading is a guess, and until this gate existed nothing checked the
    /// guess against anything.** `מנ` is read as `מ` + `נ`, the seed list is asked
    /// what starts with `נ` and answers with the commonest words it has, and the
    /// clitic goes back on: `מנכון`, `מנחמד`, `מנפגש`. All three arrive `.seed`,
    /// which outscores every completion `UITextChecker` has, so all three drawn
    /// slots held a non-word and `מנהל` — Apple's second completion — was nowhere.
    /// The same shape reached a real phone as `מכסהרורי`.
    ///
    /// Both halves are asserted. The junk must be gone, and the words Apple offers
    /// for those same letters must be there, because a build that simply stopped
    /// splitting Hebrew would pass the first half and fail
    /// `testCliticSplitReachesAWordNoDictionaryLists` — which is the control, kept
    /// deliberately in another test so this one cannot quietly become it.
    @MainActor
    func testASplitReadingMayNotInventAWordTheDictionaryDoesNotList() {
        for (typed, invented) in [("מנ", "מנכון"), ("מכסה", "מכסהרורי"), ("בב", "בבבקשה")] {
            let results = SuggestionEngine.suggestions(
                prefix: typed, context: "", languages: [.hebrew, .english],
                personal: emptyPersonal())
            XCTAssertFalse(
                results.contains { $0.text == invented },
                "\(typed) offered \(invented): \(results.map(\.text))")
        }

        // A set rather than one word, because Apple's Hebrew completion list
        // reorders itself between identical runs — see the corpus's own
        // `he-comp-03/04/05`. Every member is a real word it offers for these two
        // letters, so "one of them reached the bar" is stable where "מנהל is in
        // slot 2" is not.
        let listed: Set<String> = ["מנת", "מנהל", "מנסה", "מניות", "מנסים", "מניח", "מנהלת"]
        let results = SuggestionEngine.suggestions(
            prefix: "מנ", context: "", languages: [.hebrew, .english],
            personal: emptyPersonal())
        XCTAssertTrue(
            results.contains { listed.contains($0.text) },
            "got \(results.map(\.text)) — the three slots the invented words were "
                + "holding have to come back to the words the dictionary does list")
    }

    /// **English finishes a finished word for free and Hebrew cannot.** English
    /// inflects by appending, so a prefix search reaches `walked` from `walk`;
    /// Hebrew *replaces* the ending, so `רוצה` → `רוצים` is not a prefix extension
    /// of anything and no completion source can see it. Measured over 20 common
    /// finished Hebrew words, 7 drew a bar with empty slots and in every one
    /// `UITextChecker` returned nothing at all — `מכסה`, the word in the report
    /// that opened NIT-129, being one.
    ///
    /// Four assertions, and the last three are each a cheaper version of this rule
    /// that does harm.
    ///
    /// The ending has to be **corroborated by Apple's completion list for the
    /// stem**, which is `readingIsSpelledOut` applied to the other place this
    /// engine builds a word instead of looking one up. Asking `isKnownWord` per
    /// candidate is the obvious cheaper test and it passed `בעבודים` — a masculine
    /// plural on a feminine noun — along with `להתחילה`, which hangs a gender
    /// ending on an infinitive.
    ///
    /// It may **not fire on a word still being typed**, or it invents an ending
    /// for a fragment; and it must **never reach the space bar**, which the "the
    /// word is already a word" gate gives for free, since `commitReason`
    /// returns false for every word this can fire on.
    @MainActor
    func testAFinishedHebrewWordIsOfferedTheEndingsItSwapsRatherThanAppends() {
        for (typed, wanted) in [("פגישה", "פגישות"), ("מכסה", "מכסים"), ("הודעה", "הודעות")] {
            let results = SuggestionEngine.suggestions(
                prefix: typed, context: "", languages: [.hebrew, .english],
                personal: emptyPersonal())
            XCTAssertTrue(
                results.contains { $0.text == wanted },
                "\(typed) did not offer \(wanted): \(results.map(\.text)) — Apple has no "
                    + "completions for this word at all, so the bar is empty without this rule")
            XCTAssertEqual(
                results.first(where: \.isDefault)?.text, typed,
                "space replaced a finished word with an inflection of it: "
                    + "\(results.map(\.text))")
        }

        for (typed, invented) in [("בעבודה", "בעבודים"), ("להתחיל", "להתחילה")] {
            let results = SuggestionEngine.suggestions(
                prefix: typed, context: "", languages: [.hebrew, .english],
                personal: emptyPersonal())
            XCTAssertFalse(
                results.contains { $0.text == invented },
                "\(typed) offered \(invented): \(results.map(\.text)) — the checker's "
                    + "spelling half accepts it and its completion list does not")
        }

        // `בעבו` rather than a partial that happens to be a word: `מכס` is on the
        // way to `מכסה` and is also customs duty, so it would pass the gate
        // legitimately and prove nothing about the fragment case.
        XCTAssertTrue(
            SuggestionEngine.hebrewInflections(of: "בעבו", locale: "he_IL").isEmpty,
            "an unfinished word is not an inflection of anything, and `בעבו` is four "
                + "letters on the way to `בעבודה`")
    }

    /// **A plural that is not its singular plus an ending, which no rule here can
    /// build.** `בית` → `בתים` drops a letter and changes a vowel; `אישה` → `נשים`
    /// shares no letters with its own singular.
    ///
    /// **Asserts the plural reaches a *drawn* slot, not merely that the lookup
    /// returns it**, because the first version of this table did return it and the
    /// user never saw one. Ranked at `.inflection` it lost to `בית-המשפט`,
    /// `בן-ציון` and `שנהב` — real words out of Apple's completion list, which has
    /// no frequency model — and fired on 5 of the 21 rows. `Source.irregular`
    /// carries the measurement. `SuggestionEngine.barSlots` is 3, so a candidate
    /// past index 3 in `suggestions` is a candidate nobody can tap.

}
internal struct AlwaysPredicts: TextPrediction {
    func canPredict(in language: KeyboardLanguage) -> Bool { true }
    func continuations(
        after text: String, replyingTo context: ScreenContext?, language: KeyboardLanguage
    ) async throws -> [String] { ["one", "two"] }
}

internal struct SpeaksOnly: TextPrediction {
    let language: KeyboardLanguage
    init(_ language: KeyboardLanguage) { self.language = language }
    func canPredict(in language: KeyboardLanguage) -> Bool { language == self.language }
    func continuations(
        after text: String, replyingTo context: ScreenContext?, language: KeyboardLanguage
    ) async throws -> [String] { ["one"] }
}

/// Records the `text` it was actually asked about, so a test can check what
/// `PredictiveRefiner.ask(_:)` sends rather than assume it.
internal final class CapturingPredictor: TextPrediction, @unchecked Sendable {
    private(set) var textReceived: String?
    func canPredict(in language: KeyboardLanguage) -> Bool { true }
    func continuations(
        after text: String, replyingTo context: ScreenContext?, language: KeyboardLanguage
    ) async throws -> [String] {
        textReceived = text
        return ["one"]
    }
}

internal actor PausedPredictor: TextPrediction {
    let asked: XCTestExpectation
    let returned: XCTestExpectation
    internal var continuation: CheckedContinuation<[String], Never>?

    init(asked: XCTestExpectation, returned: XCTestExpectation) {
        self.asked = asked
        self.returned = returned
    }

    nonisolated func canPredict(in language: KeyboardLanguage) -> Bool { true }

    func continuations(
        after text: String, replyingTo context: ScreenContext?, language: KeyboardLanguage
    ) async throws -> [String] {
        let words = await withCheckedContinuation { continuation in
            self.continuation = continuation
            asked.fulfill()
        }
        returned.fulfill()
        return words
    }

    func finish() {
        continuation?.resume(returning: ["tomorrow"])
        continuation = nil
    }
}
