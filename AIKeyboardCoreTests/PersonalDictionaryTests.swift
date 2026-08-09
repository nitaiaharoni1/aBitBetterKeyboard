import XCTest

@testable import AIKeyboardCore

/// The personal dictionary, from the store the app writes to the word the space
/// bar commits.
///
/// **These go through `KeyboardController`, not through `SuggestionEngine`, and
/// that is the whole point.** The engine already took a `supplementary` list and
/// already declined to correct what was in it; `SuggestionEngineTests` has passed
/// on that for as long as the parameter has existed. What was missing was the one
/// line that put `SharedStore.personalDictionary` into that parameter, so the
/// setting was written, persisted, reset, counted in Settings and read by nothing.
/// A test that calls the engine with a list in hand cannot see that. This one
/// presses space against a document and reads the document back.
///
/// The broken build's answers are quoted on each case, measured on the iPhone 17
/// Pro simulator before any of this was written: `Nitai` came back `Nit`.
@MainActor
final class PersonalDictionaryTests: XCTestCase {

    private var savedDictionary: [String] = []
    private var savedLanguages: [KeyboardLanguage] = []
    private var savedAutocorrect = true
    private var savedPredictions = true

    override func setUp() {
        super.setUp()
        savedDictionary = SharedStore.shared.personalDictionary
        savedLanguages = SharedStore.shared.enabledLanguages
        savedAutocorrect = SharedStore.shared.autocorrect
        savedPredictions = SharedStore.shared.predictions
        SharedStore.shared.enabledLanguages = [.english, .hebrew]
        SharedStore.shared.autocorrect = true
        SharedStore.shared.predictions = true
    }

    override func tearDown() {
        SharedStore.shared.personalDictionary = savedDictionary
        SharedStore.shared.enabledLanguages = savedLanguages
        SharedStore.shared.autocorrect = savedAutocorrect
        SharedStore.shared.predictions = savedPredictions
        super.tearDown()
    }

    /// Types a word into an empty document and presses space, exactly as a user
    /// finishing that word would.
    private func committed(
        _ word: String, in language: KeyboardLanguage
    ) -> String {
        let target = MockTextTarget(text: word)
        let controller = KeyboardController(target: target, language: language)
        controller.refreshSuggestions()
        controller.press(.space)
        return target.text
    }

    // MARK: The shipped list

    /// **The defect, in the words of the phone's owner: type your own name, press
    /// space, and the field reads "Nit ".**
    ///
    /// Every word the app ships in its own personal dictionary, held to surviving
    /// the space bar. Measured answers from the build before this test existed:
    /// `Nitai` → `Nit`, `Handi` → `Handing`, `Wispr` → `Wiser`, `סאפא` → `ספא`,
    /// `בלי־פרופ` → `בלי־פרוף`. Only `KeyboardKit` came through, and only because
    /// `UITextChecker` had no second candidate to offer.
    func testEveryShippedDictionaryWordSurvivesTheSpaceBar() {
        SharedStore.shared.personalDictionary = SharedStore.shippedPersonalDictionary

        for word in SharedStore.shippedPersonalDictionary {
            let language: KeyboardLanguage =
                SuggestionEngine.dominantLanguage(in: word) ?? .english
            XCTAssertEqual(
                committed(word, in: language), "\(word) ",
                "the app's own dictionary entry was overwritten by its own autocorrect")
        }
    }

    /// The negative half, so the test above is not vacuous. With the same word and
    /// an empty dictionary the keyboard really does replace it — this is what makes
    /// each of those entries a case rather than a word autocorrect was never going
    /// to touch.
    func testTheSameWordsAreDestroyedWhenTheListIsEmpty() {
        SharedStore.shared.personalDictionary = []

        for word in ["Nitai", "Handi", "Wispr", "סאפא", "בלי־פרופ"] {
            let language: KeyboardLanguage =
                SuggestionEngine.dominantLanguage(in: word) ?? .english
            XCTAssertNotEqual(
                committed(word, in: language), "\(word) ",
                "with no dictionary this word survives on its own, so it proves nothing above")
        }
    }

    // MARK: Reaching a keyboard that is already up

    /// The edit is made in the app and the keyboard is a different process, so a
    /// controller built before the word was added has to see it anyway. This is the
    /// half `@Published` cannot do: `SharedStore.load()` fills that copy once, at
    /// whichever launch asked, which for the keyboard extension is long before the
    /// user opens Settings. See `SharedStore.storedPersonalDictionary`.
    func testAWordAddedAfterTheKeyboardIsUpIsHonoured() {
        SharedStore.shared.personalDictionary = []

        let target = MockTextTarget(text: "Handi")
        let controller = KeyboardController(target: target, language: .english)
        controller.refreshSuggestions()
        XCTAssertEqual(
            controller.suggestions.first(where: \.isDefault)?.text, "Handing",
            "the word has to be genuinely at risk before adding it can prove anything")

        SharedStore.shared.personalDictionary = ["Handi"]
        controller.refreshSuggestions()
        controller.press(.space)

        XCTAssertEqual(target.text, "Handi ")
    }

    /// **The read really does go back to the store, and nothing else here proved
    /// it.** Setting `personalDictionary` moves the published copy *and* writes
    /// through, so a keyboard reading either one passes the test above. This writes
    /// only into the suite, behind the published copy's back, exactly as the app's
    /// process would look to a keyboard already on screen — and then presses space.
    func testTheKeyboardReadsTheStoreAndNotItsOwnPublishedCopy() {
        SharedStore.shared.personalDictionary = ["Zzalpha"]
        SharedStore.shared.userDefaults.set(["Handi"], forKey: SharedStore.Key.personalDictionary)

        XCTAssertEqual(
            SharedStore.shared.personalDictionary, ["Zzalpha"],
            "the published copy must be left stale, or this proves nothing")
        XCTAssertEqual(SharedStore.shared.storedPersonalDictionary, ["Handi"])
        XCTAssertEqual(committed("Handi", in: .english), "Handi ")
        XCTAssertEqual(
            committed("Zzalpha", in: .english), "Zzalpha ",
            "a one-candidate word commits either way; this only says the case is not backwards")
    }

    /// And removing the last word does not resurrect the shipped list, in either
    /// reader. `load()` guarded on `!words.isEmpty`, so a fresh app process put the
    /// six shipped words back into the published copy while the keyboard's read
    /// honoured none — Settings counted "6" that were not in force, and the next
    /// add wrote all six back into force.
    func testAnEmptiedDictionaryIsAnEmptyDictionaryInBothReaders() {
        // The state a *fresh* process is in: the published copy still holds the
        // shipped six, because that is the property's initial value, and the store
        // holds the empty list the user left behind. Assigning through
        // `personalDictionary` would move both and could not show the divergence.
        SharedStore.shared.personalDictionary = SharedStore.shippedPersonalDictionary
        SharedStore.shared.userDefaults.set([], forKey: SharedStore.Key.personalDictionary)
        XCTAssertEqual(SharedStore.shared.storedPersonalDictionary, [])

        SharedStore.shared.load()

        XCTAssertEqual(
            SharedStore.shared.personalDictionary, [],
            "load() put the shipped list back over a list the user emptied")
        XCTAssertEqual(SharedStore.shared.storedPersonalDictionary, [])
    }

    /// The other half of that rule, and the reason it is `!= nil` rather than
    /// `!isEmpty`: an *absent* key is a fresh install, and a fresh install gets the
    /// shipped list. Only the key the user emptied reads as empty.
    func testNoStoredListAtAllFallsBackToTheShippedList() {
        SharedStore.shared.personalDictionary = SharedStore.shippedPersonalDictionary
        SharedStore.shared.userDefaults.removeObject(forKey: SharedStore.Key.personalDictionary)

        XCTAssertEqual(
            SharedStore.shared.storedPersonalDictionary, SharedStore.shippedPersonalDictionary)
    }

    // MARK: What "matches" means

    /// Case is not part of a name. Typing your own name in lower case still has to
    /// come back as what you typed rather than as `handing`.
    func testMatchingIgnoresCase() {
        SharedStore.shared.personalDictionary = ["Handi"]
        XCTAssertEqual(committed("handi", in: .english), "handi ")
    }

    /// **The maqaf, which is the one thing about this list that is not obvious.**
    /// U+05BE is Hebrew's own hyphen and the shipped entry `בלי־פרופ` is spelled
    /// with it, while the only hyphen this keyboard offers under a Hebrew layout is
    /// ASCII `-` — see `KeyboardLayout.connectors`. Without folding the two
    /// together the entry is unreachable by anything its owner can type, and the
    /// final-form rule rewrites the last letter: `בלי-פרופ` came back `בלי-פרוף`.
    func testTheHebrewHyphenAndTheOneTheKeyboardTypesAreTheSameWord() {
        SharedStore.shared.personalDictionary = ["בלי־פרופ"]
        XCTAssertEqual(committed("בלי-פרופ", in: .hebrew), "בלי-פרופ ")
    }

    /// **The commonest shape a name is typed in, and the list stopped protecting it
    /// the instant a mark touched the word.** `currentWordPrefix` runs back to the
    /// last whitespace, so `Hi Nitai,` arrives at the engine as `Nitai,`, which is
    /// not `Nitai`. Measured before this: `Hi Nitai,` committed as `Hi Nit`,
    /// identical to the same input with the list emptied. Greeting somebody by name
    /// with a comma is how a name usually reaches a chat field.
    func testAMarkAfterTheWordDoesNotStopTheListProtectingIt() {
        SharedStore.shared.personalDictionary = SharedStore.shippedPersonalDictionary

        for typed in ["Nitai,", "Nitai.", "Nitai!", "Nitai?", "Nitai...", "Nitai's", "Handi,", "Wispr,"] {
            XCTAssertEqual(
                committed("Hi \(typed)", in: .english), "Hi \(typed) ",
                "a mark after the word put it back at the mercy of the dictionary")
        }
        XCTAssertEqual(committed("שלום סאפא,", in: .hebrew), "שלום סאפא, ")
        XCTAssertEqual(committed("שלום בלי-פרופ.", in: .hebrew), "שלום בלי-פרופ. ")
    }

    /// The negative half. With the list emptied the same words are still destroyed,
    /// so the test above is about the dictionary — and the mark itself survives
    /// either way, which is the separate repair below.
    func testTheSameWordsPlusAMarkAreStillDestroyedWithNoList() {
        SharedStore.shared.personalDictionary = []

        XCTAssertEqual(committed("Hi Nitai,", in: .english), "Hi Nit, ")
        XCTAssertEqual(committed("Hi Handi,", in: .english), "Hi Handy, ")
        XCTAssertEqual(committed("Hi Nitai's", in: .english), "Hi Nita's ")
        XCTAssertEqual(committed("שלום סאפא,", in: .hebrew), "שלום ספא, ")
    }

    /// **A separate bug, with no dictionary anywhere near it: the correction ate
    /// the mark that ended the sentence.** `replaceCurrentWord` deletes the whole
    /// prefix, and the whole prefix includes the comma. Measured before this fix:
    /// `recieve,` committed as `receive `, `helo,` as `help `, `sched,` as `she'd `.
    /// See `KeyboardController.restoringTrailingMarks`.
    func testAnOrdinaryCorrectionKeepsTheMarkThatEndedTheSentence() {
        SharedStore.shared.personalDictionary = []

        XCTAssertEqual(committed("recieve,", in: .english), "receive, ")
        XCTAssertEqual(committed("helo,", in: .english), "help, ")
        XCTAssertEqual(committed("sched,", in: .english), "she'd, ")
    }

    /// And tapping the first candidate — which *is* the literal keystrokes, mark
    /// and all — must not paste the mark on twice. This is the path the restore
    /// above would double if it appended unconditionally.
    func testTappingTheLiteralCandidateDoesNotDoubleTheMark() {
        SharedStore.shared.personalDictionary = SharedStore.shippedPersonalDictionary

        for typed in ["Nitai,", "Nitai...", "bonjour…"] {
            let target = MockTextTarget(text: "Hi \(typed)")
            let controller = KeyboardController(target: target, language: .english)
            controller.refreshSuggestions()
            XCTAssertEqual(
                controller.suggestions.first?.text, typed, "the first candidate is the keystrokes")
            controller.apply(Suggestion(text: typed, language: .english))
            XCTAssertEqual(target.text, "Hi \(typed) ")
        }
    }

    /// The marks the right-to-left layouts type are punctuation to Unicode, so they
    /// are covered without being named anywhere. `،` U+060C and `؟` U+061F.
    func testTheArabicCommaAndQuestionMarkAreMarksToo() {
        SharedStore.shared.personalDictionary = ["Wispr"]

        for mark in ["\u{060C}", "\u{061F}"] {
            let typed = "Wispr\(mark)"
            let controller = KeyboardController(
                target: MockTextTarget(text: typed), language: .english)
            controller.refreshSuggestions()

            XCTAssertGreaterThan(
                controller.suggestions.count, 1,
                "with one candidate nothing could have been committed over it, so this proves nothing")
            XCTAssertEqual(controller.suggestions.first(where: \.isDefault)?.text, typed)
        }
    }

    // MARK: Where the trim must not reach

    /// A prefix that is only punctuation reduces to nothing, and nothing is a
    /// prefix of every entry on the list. Left unguarded the bar would offer two
    /// arbitrary names to somebody who typed an ellipsis.
    func testAPrefixThatIsOnlyPunctuationMatchesNoEntry() {
        SharedStore.shared.personalDictionary = SharedStore.shippedPersonalDictionary

        let controller = KeyboardController(target: MockTextTarget(text: "..."), language: .english)
        controller.refreshSuggestions()

        XCTAssertEqual(controller.suggestions.map(\.text), ["..."])
        XCTAssertEqual(committed("...", in: .english), "... ")
    }

    /// **Trimming the mark must not pull a shorter word onto a longer entry.** The
    /// length gate and the `isKnownWord` lookup are asked about the trimmed word
    /// too, so `qwt,` is three letters and is left alone. Asked about the raw
    /// prefix it is four characters and unknown to `UITextChecker` — a comma worth
    /// a letter — and with the entry newly reachable as a candidate the space bar
    /// committed `qwtxyz,` over it.
    ///
    /// The case has to be a word the checker does not know *with the mark
    /// attached*, which is narrower than it sounds: measured, `Nit,`, `Wis,`,
    /// `Han,` and even `zzz,` all come back known, so none of them can show this.
    /// `qwt,` does not.
    func testAShortWordOneMarkFromAnEntryIsNotPulledOntoIt() {
        SharedStore.shared.personalDictionary = ["Nitai", "qwtxyz"]

        XCTAssertEqual(committed("Hi qwt,", in: .english), "Hi qwt, ")
        XCTAssertEqual(committed("Hi Nit,", in: .english), "Hi Nit, ")
        XCTAssertEqual(committed("Hi Nita,", in: .english), "Hi Nita, ")
    }

    /// And a correctly spelled word followed by a mark is a correctly spelled word.
    /// Asked about the raw prefix, `hello,` is misspelled and four-plus characters,
    /// so it was one `UITextChecker` guess away from being replaced.
    func testACorrectlySpelledWordPlusAMarkIsNotACandidateForCorrection() {
        SharedStore.shared.personalDictionary = []

        for typed in ["hello,", "Thanks,", "team's", "don't", "sure!", "yes?"] {
            XCTAssertEqual(committed(typed, in: .english), "\(typed) ")
        }
    }

    // MARK: Ranking

    /// The user's own list leads `UILexicon`. Both are words the system dictionary
    /// has never heard of, and only two of them fit in the bar; the one typed by
    /// hand into Settings is the one that gets a slot.
    func testThePersonalDictionaryOutranksTheSystemLexicon() {
        SharedStore.shared.personalDictionary = ["Zzalpha"]

        let controller = KeyboardController(target: MockTextTarget(text: "zz"), language: .english)
        controller.updateSupplementaryLexicon(["Zzbeta", "Zzgamma"])

        XCTAssertEqual(
            controller.suggestions.map(\.text), ["zz", "Zzalpha", "Zzbeta"],
            "the personal dictionary has to lead the lexicon, and the literal keystrokes lead both")
    }

    /// And it protects only the words on it. A keyboard that stopped correcting
    /// everything the moment the list was non-empty would be a worse bug than the
    /// one this fixes, and it is the shape a misplaced early `return` would take.
    func testAWordThatIsNotOnTheListIsStillCorrected() {
        SharedStore.shared.personalDictionary = ["Nitai"]

        XCTAssertEqual(
            committed("recieve", in: .english), "receive ",
            "ordinary autocorrect stopped working once the dictionary had a word in it")
    }
}
