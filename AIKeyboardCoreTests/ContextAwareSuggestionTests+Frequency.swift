import XCTest

@testable import AIKeyboardCore

extension ContextAwareSuggestionTests {
    func testTheFrequencyListOverrulesApplesHebrewSpellingVerdict() {
        XCTAssertTrue(
            SuggestionEngine.isKnownWord("תדוה", checkerLocale: "he_IL"),
            "the premise: Apple calls this typo a word, which is why one dictionary "
                + "was never enough")
        XCTAssertFalse(TypoLexicon.isWord("תדוה", in: .hebrew))
        XCTAssertNotNil(TypoLexicon.rank(of: "תודה", in: .hebrew))

        let bar = SuggestionEngine.suggestions(
            prefix: "תדוה", context: "", languages: [.hebrew], personal: emptyPersonal())
        XCTAssertEqual(
            bar.first(where: \.isDefault)?.text, "תודה",
            "space kept a typo Apple vouched for: \(bar.map(\.text))")
    }

    /// A finished Hebrew word with one key slipped in it is corrected; the same
    /// shape of word still being typed is not. Both halves in one test, because
    /// the rule is the *difference* between them and either one alone is passed
    /// by a build that answers the same way to everything.
    ///
    /// **This is the largest class the typo corpus measures and it used to fail
    /// entirely**: 13 of 13 Hebrew single-key slips put the right word in slot 1
    /// and the space bar refused every one, because the same-length-substitution
    /// exclusion written for `מכונ` → `נכון` was asked about finished words too.
    /// `TypoLexicon.hasContinuation` is what separates them.
    func testAFinishedHebrewWordIsCorrectedAndAWordStillBeingTypedIsNot() {
        XCTAssertTrue(
            TypoLexicon.hasContinuation(of: "מכונ", in: .hebrew),
            "the premise: these keys are still going somewhere")
        XCTAssertFalse(TypoLexicon.hasContinuation(of: "פכישה", in: .hebrew))

        let finished = SuggestionEngine.suggestions(
            prefix: "פכישה", context: "קבענו ", languages: [.hebrew], personal: emptyPersonal())
        XCTAssertEqual(
            finished.first(where: \.isDefault)?.text, "פגישה",
            "a finished word with one key slipped has to correct: \(finished.map(\.text))")

        let inProgress = SuggestionEngine.suggestions(
            prefix: "מכונ", context: "קניתי ", languages: [.hebrew], personal: emptyPersonal())
        XCTAssertEqual(
            inProgress.first(where: \.isDefault)?.text, "מכונ",
            "space replaced a word still being typed: \(inProgress.map(\.text))")
    }

    /// A longer word that starts with the keystrokes is a word in progress, not a
    /// slip, and the frequency corrector may not finish one.
    ///
    /// `קליפ` is how Hebrew writes "clip" and `אפ` is how it writes "app"; the
    /// repo already records both as words an earlier over-eager rule destroyed.
    /// `helot` is the English shape of the same thing — a real, rare word whose
    /// only cheap neighbour is its own plural.
    func testTheFrequencyCorrectorDoesNotFinishAWordItOnlyRepairsOne() {
        for (typed, language) in [
            ("קליפ", KeyboardLanguage.hebrew), ("אפ", .hebrew), ("helot", .english)
        ] {
            let bar = SuggestionEngine.suggestions(
                prefix: typed, context: "", languages: [language], personal: emptyPersonal())
            XCTAssertEqual(
                bar.first(where: \.isDefault)?.text, typed,
                "space finished a word instead of repairing it: \(typed) -> \(bar.map(\.text))")
        }
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
    /// This test calls `commitReason` directly so the synthetic results
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
        let reason = SuggestionEngine.commitReason(
            "sorrow", previousWords: ["See", "you"], typedLanguage: .english,
            results: results, supplementary: [], personal: personal)

        XCTAssertNil(
            reason,
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

    func testRefinementPreservesOnlyTheLocalAutomaticCorrection() {
        let local = [
            Suggestion(text: "recieve", language: .english),
            Suggestion(text: "receive", language: .english, isDefault: true)
        ]
        let refined = SuggestionEngine.refinedSuggestions(
            local: local, words: ["reciever", "recievers"], prefix: "recieve", language: .english)
        XCTAssertEqual(refined.first?.text, "recieve")
        XCTAssertEqual(refined.first(where: \.isDefault)?.text, "receive")
        XCTAssertEqual(refined.first { $0.text == "reciever" }?.commit, .tapOnly)

        let crowded = SuggestionEngine.refinedSuggestions(
            local: local, words: ["reciever", "recievers", "recieving"],
            prefix: "recieve", language: .english)
        XCTAssertEqual(crowded.first(where: \.isDefault)?.text, "recieve")
    }

    func testRefinementCannotExtendAKnownOrPersonalWordOnSpace() {
        withBarSettingsOn {
            for (typed, completion) in [("car", "career"), ("Nitai", "Nitaim")] {
                let target = MockTextTarget(text: typed)
                let controller = KeyboardController(target: target, language: .english)
                controller.suggestions = [Suggestion(text: typed, language: .english, isDefault: true)]
                controller.applyRefinement([completion], for: typed)
                XCTAssertEqual(controller.suggestions.first(where: \.isDefault)?.text, typed)
                XCTAssertEqual(controller.suggestions.first { $0.text == completion }?.commit, .tapOnly)
                controller.press(.space)
                XCTAssertEqual(target.text, typed + " ")
            }
        }
    }

    func testRefinementKeepsASafeLocalDefaultWhenModelRepeatsIt() {
        let local = [
            Suggestion(text: "recieve", language: .english),
            Suggestion(text: "receive", language: .english, isDefault: true)
        ]
        let refined = SuggestionEngine.refinedSuggestions(
            local: local, words: ["receive"], prefix: "recieve", language: .english)
        XCTAssertEqual(refined.first(where: \.isDefault)?.text, "receive")
        XCTAssertEqual(refined.first(where: \.isDefault)?.commit, .contextual)
    }

    /// Autocorrect-off means space will not commit, so the bar must not bold a
    /// model word after refine. The word still lands in the bar for a tap.
    func testRefinementKeepsTheTypedWordBoldWhenAutocorrectIsOff() {
        let store = SharedStore.shared
        let (autocorrectLevel, predictions) = (store.autocorrectLevel, store.predictions)
        store.autocorrectLevel = .off
        store.predictions = true
        defer {
            store.autocorrectLevel = autocorrectLevel
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

    func testNextWordRefinementUsesAllThreeSlotsWithoutPinningALocalWord() {
        withBarSettingsOn {
            let target = MockTextTarget(text: "See you ")
            let controller = KeyboardController(target: target, language: .english)
            controller.suggestions = [
                Suggestion(text: "later", language: .english),
                Suggestion(text: "tomorrow", language: .english, isDefault: true),
                Suggestion(text: "soon", language: .english)
            ]
            controller.applyRefinement(["Thursday", "Friday"], for: "")
            XCTAssertEqual(controller.suggestions.map(\.text), ["Thursday", "Friday", "later"])
            XCTAssertEqual(controller.suggestions.first(where: \.isDefault)?.text, "Thursday")
            controller.suggestions = []
            controller.applyRefinement(["Thursday"], for: "")
            XCTAssertEqual(controller.suggestions.map(\.text), ["Thursday"])
        }
    }

    func testRefinedPersonalTokensAndPhrasesStayTapOnly() {
        withBarSettingsOn {
            for word in ["hello@example.com", "hello there", "hello"] {
                let target = MockTextTarget(text: "hel")
                let controller = KeyboardController(target: target, language: .english)
                controller.suggestions = [Suggestion(text: "hel", language: .english, isDefault: true)]
                controller.applyRefinement([word], for: "hel")
                XCTAssertTrue(controller.suggestions.contains { $0.text == word })
                XCTAssertEqual(
                    controller.suggestions.first(where: \.isDefault)?.text,
                    "hel")
                controller.press(.space)
                XCTAssertEqual(target.text, "hel ")
            }
        }
    }

    func testPendingRefinementBelongsToTheExactDocumentPositionAndLanguage() {
        withBarSettingsOn {
            for change in ["none", "before", "after", "document", "language", "cancel", "prepare"] {
                let target = CursorTextTarget(before: "say hel", after: " there")
                let controller = KeyboardController(target: target, language: .english)
                controller.suggestions = [Suggestion(text: "hel", language: .english, isDefault: true)]
                controller.pendingRefinementPosition = controller.suggestionPosition
                switch change {
                case "before": target.placeCaret(before: "other hel", after: " there")
                case "after": target.placeCaret(before: "say hel", after: " elsewhere")
                case "document": target.documentIdentifier = UUID()
                case "language": controller.language = .hebrew
                case "cancel": controller.cancelRefinement()
                case "prepare": controller.prepareForNewDocument()
                default: break
                }
                let original = controller.suggestions
                controller.applyPendingRefinement(["hello"], for: "hel")
                if change == "none" {
                    XCTAssertTrue(controller.suggestions.contains { $0.text == "hello" })
                    XCTAssertEqual(controller.suggestions.first(where: \.isDefault)?.text, "hel")
                } else {
                    XCTAssertEqual(controller.suggestions, original, change)
                }
            }
        }
    }

    func testPartialAndMultiwordSelectionsCancelPendingPrediction() {
        withBarSettingsOn {
            for selected in ["lo", "hello world"] {
                let target = CursorTextTarget(before: "say hel", selecting: selected, after: " there")
                let controller = KeyboardController(target: target, language: .english)
                controller.refiner = PredictiveRefiner(onDevice: AlwaysPredicts(), apply: { _, _ in })
                controller.pendingRefinementPosition = controller.suggestionPosition
                XCTAssertNil(controller.selectedWord)
                controller.refreshSuggestions()
                XCTAssertNil(controller.pendingRefinementPosition)
                controller.cancelRefinement()
            }
        }
    }

    func testCancelledPredictionCannotApplyEvenWhenPredictorIgnoresCancellation() async {
        let asked = expectation(description: "predictor started")
        let returned = expectation(description: "predictor returned")
        let applied = expectation(description: "cancelled answer must not apply")
        applied.isInverted = true
        let predictor = PausedPredictor(asked: asked, returned: returned)
        let refiner = PredictiveRefiner(onDevice: predictor) { _, _ in applied.fulfill() }
        refiner.refine(
            .init(
                textBefore: "See you ", wordInProgress: "", language: .english,
                screenContext: nil, permitted: true))
        await fulfillment(of: [asked], timeout: 2)
        refiner.cancel()
        await predictor.finish()
        await fulfillment(of: [returned], timeout: 2)
        await fulfillment(of: [applied], timeout: 0.1)
    }

    func testPredictionCacheSeparatesTextFromPrefixEvenWithSeparatorCharacters() {
        let first = PredictiveRefiner.Request(
            textBefore: "there", wordInProgress: "hello\u{1F}over", language: .english,
            screenContext: nil, permitted: true)
        let second = PredictiveRefiner.Request(
            textBefore: "over\u{1F}there", wordInProgress: "hello", language: .english,
            screenContext: nil, permitted: true)
        XCTAssertNotEqual(first.cacheKey, second.cacheKey)
    }

    func testRefinementCanStartOnTheFirstWord() {
        let refiner = PredictiveRefiner(onDevice: AlwaysPredicts(), apply: { _, _ in })
        for prefix in ["hel", "", "   "] {
            let request = PredictiveRefiner.Request(
                textBefore: "", wordInProgress: prefix, language: .english,
                screenContext: nil, permitted: true)
            XCTAssertEqual(refiner.shouldRefine(request), prefix == "hel")
        }
    }

    /// Pins the two settings the controller re-reads at every keystroke, and puts
    /// them back. Both ship on, but both are *stored*, so a developer who turned
    /// either off in the app would otherwise watch the two tests above fail for a
    /// reason that has nothing to do with the async tier.
    private func withBarSettingsOn(_ body: () -> Void) {
        let store = SharedStore.shared
        let (autocorrectLevel, predictions) = (store.autocorrectLevel, store.predictions)
        store.autocorrectLevel = .full
        store.predictions = true
        defer {
            store.autocorrectLevel = autocorrectLevel
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
    ///
    /// **`PredictiveRefiner.tail(of:)` used to be the thing this pinned, and it was
    /// an identity function with one production call and one test asserting it
    /// returned its own argument — deleted rather than kept as a shell.** What is
    /// worth rejecting is not that some function returns its input unchanged, it is
    /// that `ask(_:)` hands the predictor the *whole* context rather than a chopped
    /// one, so this asks the predictor itself what it received.
    func testRefinementSendsTheWholePausedContextToThePredictor() {
        let words = (1...50).map { "w\($0)" }.joined(separator: " ")
        let capture = CapturingPredictor()
        let arrived = expectation(description: "the predictor was asked")
        let refiner = PredictiveRefiner(onDevice: capture) { _, _ in arrived.fulfill() }
        let request = PredictiveRefiner.Request(
            textBefore: words, wordInProgress: "", language: .english, screenContext: nil,
            permitted: true)

        refiner.refine(request)
        wait(for: [arrived], timeout: 2)

        XCTAssertEqual(
            capture.textReceived, words,
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

