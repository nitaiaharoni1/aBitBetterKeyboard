import XCTest

@testable import AIKeyboardCore

/// `SuggestionEngine` is backed by `UITextChecker`, so these assert against
/// Apple's real dictionary rather than a table this repo controls. Every case
/// below was run once as a scratch probe against the Simulator before being
/// written down, per the standing rule: a claim about what an Apple API returns
/// needs to have actually been seen, not assumed.
@MainActor
final class SuggestionEngineTests: XCTestCase {

    // MARK: Completion of the word being typed

    func testEnglishPrefixCompletesToARealWord() {
        let results = SuggestionEngine.suggestions(
            prefix: "hel", context: "", languages: [.english])

        XCTAssertTrue(results.contains { $0.text.lowercased() == "hello" })
    }

    /// The literal keystrokes must always be a candidate, so the engine can
    /// never trap the user in a word they did not type.
    func testTheTypedPrefixIsAlwaysOffered() {
        let results = SuggestionEngine.suggestions(
            prefix: "xyzzy", context: "", languages: [.english])

        XCTAssertTrue(results.contains { $0.text == "xyzzy" })
    }

    /// `אנ` → `אני`, `אנחנו`, `אנשים`… — Hebrew word completion, verified against
    /// the Simulator before this was written. `UITextChecker` is not one of the
    /// three Apple stacks with no Hebrew; it has its own language list.
    func testHebrewPrefixCompletesToARealWord() {
        let results = SuggestionEngine.suggestions(
            prefix: "אנ", context: "", languages: [.hebrew])

        XCTAssertTrue(results.contains { $0.text == "אני" })
    }

    /// A prefix that is not the start of any dictionary word falls through to
    /// `guesses`, which corrects a misspelling rather than completing a word in
    /// progress. `recieve` completes to nothing (nothing starts with those six
    /// letters), which is what makes this case fall through rather than a
    /// prefix like `helo`, where `UITextChecker` has real completions
    /// (`helot`, `helots`) that crowd the correction out — a real, disclosed
    /// limit of a spell-checker with no frequency model behind it; see the
    /// note on `completions(for:typedLanguage:supplementary:)`.
    func testAMisspellingFallsBackToASpellingGuess() {
        let results = SuggestionEngine.suggestions(
            prefix: "recieve", context: "", languages: [.english])

        XCTAssertTrue(results.contains { $0.text.lowercased() == "receive" })
    }

    // MARK: Contractions

    /// `UITextChecker.guesses` cannot be trusted to fire on a two-letter
    /// prefix, so this is a real, hardcoded rule rather than a dictionary
    /// lookup — see the doc comment on `contractions`.
    func testMissingApostropheIsOfferedAtAnyLength() {
        let results = SuggestionEngine.suggestions(
            prefix: "im", context: "", languages: [.english])

        XCTAssertTrue(results.contains { $0.text == "I'm" })
    }

    func testDontExpandsToTheContraction() {
        let results = SuggestionEngine.suggestions(
            prefix: "dont", context: "I ", languages: [.english])

        XCTAssertTrue(results.contains { $0.text == "don't" })
    }

    // MARK: Supplementary lexicon

    /// Names from `UILexicon` outrank the system dictionary, because
    /// `UITextChecker` has never heard of them.
    func testSupplementaryWordsAreOfferedForAMatchingPrefix() {
        let results = SuggestionEngine.suggestions(
            prefix: "nit", context: "", languages: [.english],
            supplementary: ["Nitai"])

        XCTAssertTrue(results.contains { $0.text == "Nitai" })
    }

    func testSupplementaryWordsThatDoNotMatchThePrefixAreNotOffered() {
        let results = SuggestionEngine.suggestions(
            prefix: "hel", context: "", languages: [.english],
            supplementary: ["Nitai"])

        XCTAssertFalse(results.contains { $0.text == "Nitai" })
    }

    // MARK: Next word, nothing typed

    /// No public API predicts this; the table is small and disclosed. This
    /// pins the one behaviour the table promises rather than its contents,
    /// which are free to grow without breaking a test.
    func testNothingTypedOffersFollowOnWordsForARecognisedLastWord() {
        let results = SuggestionEngine.suggestions(
            prefix: "", context: "thanks ", languages: [.english])

        XCTAssertTrue(results.contains { $0.text == "for" })
    }

    /// An empty field with no context has nothing to predict *from*, so these are
    /// openers rather than predictions and are named that way in
    /// `SuggestionEngine+NextWord`.
    ///
    /// **They used to be the answer to far more than this.** `I · The · We` was
    /// what every English sentence fell through to whenever the 26-key table had
    /// no row for the last word, which the typing corpus caught the bar doing
    /// after "Happy" and after "Have a great". Now they appear only here, with
    /// nothing typed at all, and the middle slot is the likeliest one because that
    /// is the slot the space bar and the system keyboard both treat as the default.
    func testNothingTypedAndNoContextOffersTheDefaults() {
        let results = SuggestionEngine.suggestions(
            prefix: "", context: "", languages: [.english])

        XCTAssertEqual(results.map(\.text), ["Thanks", "I", "Hi"])
    }

    // MARK: Default candidate

    /// A short prefix is never overridden regardless of whether it is a real
    /// word — this is what stops autocorrect from turning `I` into `idea`.
    func testAShortPrefixIsNotMarkedForAutocorrect() {
        let results = SuggestionEngine.suggestions(
            prefix: "cat", context: "", languages: [.english])

        XCTAssertFalse(results.contains { $0.isDefault && $0.text.lowercased() != "cat" })
    }

    /// A real, `UITextChecker`-verified known word of four or more letters is
    /// also left alone — this is the case the four-letter gate exists to
    /// protect once length stops doing it automatically.
    func testAFourLetterKnownWordIsNotMarkedForAutocorrect() {
        let results = SuggestionEngine.suggestions(
            prefix: "chair", context: "", languages: [.english])

        XCTAssertFalse(results.contains { $0.isDefault && $0.text.lowercased() != "chair" })
    }

    /// A four-or-more-letter prefix `UITextChecker` does not recognise as a
    /// word is corrected — `sched` is not in the dictionary, and its top
    /// completion is `schedule`.
    func testAMisspelledFourLetterPrefixIsMarkedForAutocorrect() {
        let results = SuggestionEngine.suggestions(
            prefix: "sched", context: "", languages: [.english])

        XCTAssertTrue(results.contains { $0.isDefault && $0.text.lowercased() == "schedule" })
    }

    // MARK: Script detection (moved from MockSuggestionEngine, unchanged)

    func testDominantLanguageReadsHebrewOverLatin() {
        XCTAssertEqual(SuggestionEngine.dominantLanguage(in: "שלום שלום world"), .hebrew)
    }

    func testDominantLanguageReadsLatinOverHebrew() {
        XCTAssertEqual(SuggestionEngine.dominantLanguage(in: "hello world שלום"), .english)
    }

    func testDominantLanguageIsNilForDigitsAndPunctuationAlone() {
        XCTAssertNil(SuggestionEngine.dominantLanguage(in: "123 !?"))
    }
}

// MARK: - Hebrew final forms, and the code-switch ranking

extension SuggestionEngineTests {

    /// **The case that made this rule exist.** `שלומ` is `שלום` — "hello" — typed
    /// with a plain mem where the final mem belongs, which is the most common
    /// keying error in the language. `UITextChecker` finds twelve real
    /// completions for it (`שלומדים`, `שלומד`, …), so the spelling-guess branch
    /// never fires, and the bar used to offer `שלומדים`: press space to say
    /// hello and commit "who are studying".
    ///
    /// An audit found the repo claiming this case was handled and pinned by a
    /// test. It was neither. This is that test.
    @MainActor
    func testAFinalFormTypoIsOfferedAndIsWhatSpaceWouldCommit() {
        let results = SuggestionEngine.suggestions(
            prefix: "שלומ", context: "", languages: [.hebrew])

        XCTAssertTrue(
            results.contains { $0.text == "שלום" },
            "the correction has to reach the bar at all: \(results.map(\.text))")
        XCTAssertEqual(
            results.first(where: \.isDefault)?.text, "שלום",
            "and it has to be the one space commits, not \(results.first(where: \.isDefault)?.text ?? "nothing")"
        )
        XCTAssertEqual(results.first?.text, "שלומ", "the literal keystrokes stay available")
    }

    /// The other letters, so the rule is not a single hardcoded word.
    ///
    /// **The pair that used to sit here was `("איפ", "אף")`, behind a
    /// `where typed != "איפ"` that skipped it** — a case somebody found wrong and
    /// switched off rather than deleted, leaving a loop that read as two letters
    /// and tested one. It was wrong twice over: `inFinalForm("איפ")` is `איף`, not
    /// `אף`, so the expectation never matched the rule under test. These four are
    /// real slips onto real words, one per remaining letter.
    @MainActor
    func testTheOtherFinalFormsAreCorrectedToo() {
        for (typed, corrected) in [
            ("צריכ", "צריך"), ("נכונ", "נכון"), ("כספ", "כסף"), ("קובצ", "קובץ")
        ] {
            let results = SuggestionEngine.suggestions(
                prefix: typed, context: "", languages: [.hebrew])
            XCTAssertTrue(
                results.contains { $0.text == corrected },
                "\(typed) should offer \(corrected): \(results.map(\.text))")
        }
    }

    /// **A word in progress ends in whatever was typed last, and this rule used to
    /// treat that as a spelling mistake.** Five letters change shape at the end of
    /// a Hebrew word, and 20% of the mid-word keystrokes across the seed
    /// vocabulary land on one of them, so an ungated rule fired on a fifth of all
    /// Hebrew typing: it took the bold slot, because `.orthography` outranks every
    /// completion source and `shouldAutocorrect` answered on it above the seed
    /// check, and it pushed the word being typed out of the bar.
    ///
    /// Measured on the build before the gate: `פ` bolded `ף` while `פגישה` sat
    /// unbolded beside it, `מכ` bolded `מך`, `נכ` bolded `נך`, `כמ` bolded `כם`.
    /// Asserting on the *default* rather than on membership is what rejects that
    /// build — the correction was in the bar either way.
    @MainActor
    func testAWordInProgressIsNotCorrectedToItsOwnFinalForm() {
        for (typed, nonWord) in [("פ", "ף"), ("מכ", "מך"), ("נכ", "נך"), ("כמ", "כם")] {
            let results = SuggestionEngine.suggestions(
                prefix: typed, context: "", languages: [.hebrew])
            XCTAssertFalse(
                results.contains { $0.text == nonWord },
                "\(nonWord) is not a word and must not be offered: \(results.map(\.text))")
            XCTAssertNotEqual(
                results.first(where: \.isDefault)?.text, nonWord,
                "and above all it must not be what the space bar commits")
        }
    }

    /// The other side of that gate, in the language's own loanwords. Hebrew writes
    /// a borrowed word ending in `p` with the ordinary form — `קליפ` is "clip" —
    /// so an ungated rule did not merely add noise mid-word, it committed a
    /// different word for a finished one.
    @MainActor
    func testALoanwordEndingInAnOrdinaryFormIsLeftAlone() {
        let results = SuggestionEngine.suggestions(
            prefix: "קליפ", context: "ראיתי ", languages: [.hebrew, .english])
        XCTAssertNotEqual(
            results.first(where: \.isDefault)?.text, "קליף",
            "space committed קליף for קליפ: \(results.map(\.text))")
    }

    /// It must not fire on a word that is already right. A Hebrew word ending in
    /// a plain mem mid-sentence is ordinary; offering to "fix" it is the exact
    /// behaviour that makes people turn autocorrect off.
    @MainActor
    func testAWordThatIsAlreadyCorrectIsNotOfferedAFinalForm() {
        // `אימ` is not a word, `אים` is not either — nothing should be invented.
        let results = SuggestionEngine.suggestions(prefix: "שלום", context: "", languages: [.hebrew])
        XCTAssertFalse(
            results.contains { $0.text != "שלום" && $0.text.hasSuffix("ם") && $0.text.count == 4 },
            "a correctly spelled word must not be 'corrected' again")
        XCTAssertEqual(results.first?.text, "שלום")
    }

    /// **The product's central case.** Latin letters inside a Hebrew sentence.
    /// Without a deliberate ranking, `sta` offers `still`/`stay`/`start` and
    /// `standup` never appears until all seven letters are typed — by which point
    /// the suggestion is worthless. A critic found this by typing the word one
    /// keystroke at a time; the whole-word check that justified deleting the list
    /// could not see it.
    @MainActor
    func testALoanwordSurfacesEarlyWhenTypedInsideAHebrewSentence() {
        let hebrewContext = "בוא נעשה"

        for (prefix, expected) in [("sta", "standup"), ("road", "roadmap"), ("temp", "template")] {
            let results = SuggestionEngine.suggestions(
                prefix: prefix, context: hebrewContext, languages: [.hebrew, .english])
            XCTAssertTrue(
                results.contains { $0.text == expected },
                "\(prefix) inside a Hebrew sentence should offer \(expected): \(results.map(\.text))")
        }
    }

    /// …and it stays out of the way in an English sentence, where Apple's own
    /// ranking is the better judge and this list would only crowd it.
    @MainActor
    func testTheLoanwordListDoesNotOverrideEnglishContext() {
        let results = SuggestionEngine.suggestions(
            prefix: "sta", context: "let us have a", languages: [.english])

        XCTAssertFalse(
            results.contains { $0.text == "standup" },
            "in English the dictionary ranks this, not our list: \(results.map(\.text))")
    }
}
