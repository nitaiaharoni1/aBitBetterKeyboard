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
    private var savedAutocorrect = AutocorrectLevel.full
    private var savedPredictions = true

    override func setUp() {
        super.setUp()
        savedDictionary = SharedStore.shared.personalDictionary
        savedLanguages = SharedStore.shared.enabledLanguages
        savedAutocorrect = SharedStore.shared.autocorrectLevel
        savedPredictions = SharedStore.shared.predictions
        SharedStore.shared.enabledLanguages = [.english, .hebrew]
        SharedStore.shared.autocorrectLevel = .full
        SharedStore.shared.predictions = true
    }

    override func tearDown() {
        SharedStore.shared.personalDictionary = savedDictionary
        SharedStore.shared.enabledLanguages = savedLanguages
        SharedStore.shared.autocorrectLevel = savedAutocorrect
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
    ///
    /// **`בלי־פרופ` was on this list and had to come off, and that is a real
    /// change rather than a test being relaxed.** The only thing that ever
    /// threatened it was the Hebrew final-form rule, which rewrote its closing pe
    /// and gave `בלי־פרוף`; that rule now has to land on a word the seed list
    /// knows, and `בלי־פרוף` is not one, so nothing in the engine wants to touch
    /// this word any more. It is still in `shippedPersonalDictionary` and still
    /// covered by the test above — but that coverage is now vacuous *for this one
    /// word*, because it would pass with the personal dictionary deleted. The four
    /// below are the ones still carrying the proof.
    func testTheSameWordsAreDestroyedWhenTheListIsEmpty() {
        SharedStore.shared.personalDictionary = []

        for word in ["Nitai", "Handi", "Wispr", "סאפא"] {
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

    /// **The mark that got through: the curly apostrophe.** `Nitai's` was
    /// protected and `Nitai’s` committed as `Nita’s`, because the two places that
    /// were supposed to fold one apostrophe onto the other did not.
    /// `SuggestionEngine.comparable` carried its own copy of
    /// `SeedLanguageModel.fold` whose apostrophe rule was
    /// `replacingOccurrences(of: "'", with: "'")` — ASCII on both sides, so a
    /// no-op — and `wordCore` tested `hasSuffix("'s") || hasSuffix("'s")`, two
    /// branches that look like the two apostrophes and are the same eight bytes.
    ///
    /// It is not an exotic spelling. The apostrophe key's long press offers `’`,
    /// and a host field with smart quotes on — the default everywhere except this
    /// suite's own `MockTextTarget` — rewrites a typed `'` to `’` inside the
    /// document that `currentWordPrefix` reads back, so this is what an ordinary
    /// possessive looks like by the time the keyboard sees it.
    func testTheCurlyApostropheIsTheSameApostrophe() {
        SharedStore.shared.personalDictionary = SharedStore.shippedPersonalDictionary

        XCTAssertEqual(
            committed("This is Nitai\u{2019}s", in: .english), "This is Nitai\u{2019}s ",
            "the list stopped protecting the name the moment the apostrophe curled")
        XCTAssertEqual(committed("This is Nitai's", in: .english), "This is Nitai's ")
    }

    /// The negative half. With the list emptied the same words are still destroyed,
    /// so the test above is about the dictionary — and the mark itself survives
    /// either way, which is the separate repair below.
    func testTheSameWordsPlusAMarkAreStillDestroyedWithNoList() {
        SharedStore.shared.personalDictionary = []

        // The exact wrong word is `UITextChecker`'s, not ours, and it has
        // already moved once (`Handy` → `Handing` → `Handicap`). This test
        // is about the word being at risk at all, and about the mark surviving.
        let nitai = committed("Hi Nitai,", in: .english)
        XCTAssertNotEqual(nitai, "Hi Nitai, ", "the empty list left the name alone")
        XCTAssertTrue(nitai.hasSuffix(", "), "the comma was eaten: \(nitai)")
        let handi = committed("Hi Handi,", in: .english)
        XCTAssertNotEqual(handi, "Hi Handi, ", "the empty list left the name alone")
        XCTAssertTrue(handi.hasSuffix(", "), "the comma was eaten: \(handi)")
        // And the possessive survives being corrected — `wordCore` strips `'s` to
        // do the lookup and `restoringEdgeMarks` puts it back, or this line would
        // drop two characters the user typed.
        let possessive = committed("Hi Nitai's", in: .english)
        XCTAssertNotEqual(possessive, "Hi Nitai's ", "the empty list left the name alone")
        XCTAssertTrue(
            possessive.contains("'") || possessive.contains("\u{2019}"),
            "the possessive was eaten: \(possessive)")
        XCTAssertEqual(committed("שלום סאפא,", in: .hebrew), "שלום ספא, ")
    }

    /// **A separate bug, with no dictionary anywhere near it: the correction ate
    /// the mark that ended the sentence.** `replaceCurrentWord` deletes the whole
    /// prefix, and the whole prefix includes the comma. Measured before this fix:
    /// `recieve,` committed as `receive `, `helo,` as `help `, `sched,` as `she'd `.
    /// See `KeyboardController.restoringEdgeMarks`.
    ///
    /// **`helo,` reads `hello, ` now, and the change is the point of
    /// `SeedLanguageModel`.** `help` was what `UITextChecker.guesses` ranked first
    /// with no frequency model behind it; `hello` is what the person typing meant.
    /// What this test is *for* is unaffected either way — the comma survives the
    /// correction, whichever word the correction lands on.
    ///
    /// **`sched,` reads `schedule, ` now, for the same reason one step further
    /// on.** It used to commit `she'd,`: the comma was part of the string handed
    /// to `UITextChecker`, which has no completion for `sched,` and so fell
    /// through to `guesses`, and `she'd` is what a spelling guess makes of five
    /// letters it does not recognise. With every source asking about the word,
    /// `sched` completes to `schedule` and a completion outranks a correction.
    /// Nobody typing `sched,` meant `she'd,`.
    func testAnOrdinaryCorrectionKeepsTheMarkThatEndedTheSentence() {
        SharedStore.shared.personalDictionary = []

        XCTAssertEqual(committed("recieve,", in: .english), "receive, ")
        XCTAssertEqual(committed("helo,", in: .english), "hello, ")
        XCTAssertEqual(committed("sched,", in: .english), "schedule, ")
    }

    /// And the mark in *front* of the word comes home too.
    ///
    /// `replaceCurrentWord` deletes the whole prefix and the whole prefix includes
    /// the bracket, so while `restoringEdgeMarks` restored the trailing run alone
    /// this was a silent deletion: `(recieve` committed as `receive `, one
    /// character shorter than what the user typed and with the bracket they opened
    /// gone. It went unnoticed because a leading mark also hid the word from every
    /// lookup except `UITextChecker.guesses`, so it was the only path that ever got
    /// far enough to eat one.
    func testACorrectionKeepsTheMarkThatOpenedTheWord() {
        SharedStore.shared.personalDictionary = []

        XCTAssertEqual(committed("Say (recieve", in: .english), "Say (receive ")
        XCTAssertEqual(committed("Say (helo)", in: .english), "Say (hello) ")
        XCTAssertEqual(
            committed("Say \"helo\"", in: .english), "Say \"hello\" ",
            "a quote is punctuation at both ends and both ends are the user's")
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
    /// has never heard of, so the order they arrive in is the only thing deciding
    /// which of them the user sees, and the one typed by hand into Settings leads.
    ///
    /// **The array is four long because the bar draws three offers, not two.**
    /// Slot zero is the literal keystrokes and `SuggestionBar` does not draw it —
    /// see `SuggestionEngine.barSlots`. This used to end at `Zzbeta`, and both
    /// halves of that were the old shape: the engine returned three candidates,
    /// and the supplementary source was capped at two because two was all that
    /// could ever be shown.
    func testThePersonalDictionaryOutranksTheSystemLexicon() {
        SharedStore.shared.personalDictionary = ["Zzalpha"]

        let controller = KeyboardController(target: MockTextTarget(text: "zz"), language: .english)
        controller.updateSupplementaryLexicon(["Zzbeta", "Zzgamma"])

        XCTAssertEqual(
            controller.suggestions.map(\.text), ["zz", "Zzalpha", "Zzbeta", "Zzgamma"],
            "the personal dictionary has to lead the lexicon, and the literal keystrokes lead both")
    }

    /// Every slot the bar draws is filled when there is anything to fill it with.
    ///
    /// **Measured before this was written: 229 of 234 letter-by-letter keystroke
    /// moments across 30 Hebrew and 20 English words drew two candidates and a
    /// blank**, because `completions(for:)` asked `rank` for three and the first
    /// of those three was the typed echo the bar throws away. A third of the one
    /// row this keyboard has for suggestions was empty on nearly every keystroke.
    /// Asserted through `SuggestionBar.centeredSlots`, which is the drawing order,
    /// rather than through the engine array — the engine returning four proves
    /// nothing about what reaches the screen.
    ///
    /// **The echo takes one of the three when it holds the default**, which is
    /// what tells the user their word is safe, so what this has to reject is a
    /// bar that draws the echo and only *one* offer: the extra candidate the
    /// engine returns is exactly what stops that happening.
    @MainActor
    func testTheBarDrawsThreeOffersAndNotTwo() {
        SharedStore.shared.personalDictionary = []

        for (typed, language) in [("tomo", KeyboardLanguage.english), ("פגי", .hebrew)] {
            let controller = KeyboardController(
                target: MockTextTarget(text: typed), language: language)
            let drawn = SuggestionBar.centeredSlots(controller.suggestions, typed: typed)
                .compactMap { $0 }
            XCTAssertEqual(
                drawn.count, SuggestionEngine.barSlots,
                "\(typed) filled \(drawn.count) of \(SuggestionEngine.barSlots) slots: "
                    + "\(controller.suggestions.map(\.text))")
            // The echo takes at most one of the three, and only when it is the
            // word space will keep. What has to stay true either way is that the
            // rest of the row is real offers — a bar drawing the echo and one
            // completion is the same defect this test was written for, arriving
            // through the slot the echo now takes.
            let key = SuggestionEngine.comparable(typed)
            XCTAssertGreaterThanOrEqual(
                drawn.filter { SuggestionEngine.comparable($0.text) != key }.count,
                SuggestionEngine.barSlots - 1,
                "\(typed) drew the echo and one offer, not two: \(drawn.map(\.text))")
        }
    }

    /// **An entry owns the common word it is built on, for as many keystrokes as
    /// they share.** `KeyboardKit` ships in `SharedStore.shippedPersonalDictionary`
    /// on every install, and `keyb`, `keybo`, `keyboa` and `keyboar` all committed
    /// it — four consecutive keystrokes of the word *keyboard* replaced by a brand
    /// name on a stock phone, with `keyboard` sitting unbolded in slot 2 the whole
    /// way and only the eighth letter saving it, where `isKnownWord` finally
    /// refuses the four-letter gate. `Danielle` does the same to somebody typing
    /// *Daniel*. The list exists so a name is never destroyed; it was destroying
    /// the ordinary words those names are built on.
    ///
    /// The guard that was already here only ever protected an **exact** match, so
    /// it could not fire on a shared prefix, and `.personal` is the second highest
    /// source tier there is — so the entry wins the ranking outright and the gate
    /// commits the winner.
    ///
    /// **Both halves are asserted.** The entry has to still be *offered*, or a
    /// build that dropped `KeyboardKit` from the shipped list would pass this while
    /// breaking the four tests above it. Found by `Bar/typing/sweep`, which types
    /// whole words letter by letter; the frozen 90 has no entry for any of these
    /// moments.
    func testAnEntryDoesNotOwnTheCommonWordItExtends() {
        SharedStore.shared.personalDictionary = SharedStore.shippedPersonalDictionary

        for typed in ["keyb", "keybo", "keyboa", "keyboar"] {
            let controller = KeyboardController(
                target: MockTextTarget(text: typed), language: .english)
            XCTAssertTrue(
                controller.suggestions.contains { $0.text == "KeyboardKit" },
                "\(typed) no longer offers the entry at all, so this proves nothing: "
                    + "\(controller.suggestions.map(\.text))")
            XCTAssertEqual(
                committed(typed, in: .english), "\(typed) ",
                "the space bar put a brand name over the word keyboard")
        }
    }

    /// The other half, and the reason the rule above is not "an entry may never
    /// finish a word".
    ///
    /// When nothing else completes the same keystrokes, the entry is the only
    /// reading there is and finishing it is the whole point of having the list.
    /// A build that simply refused every personal completion would pass the test
    /// above and fail here.
    func testAnEntryStillFinishesAWordNothingElseIsCompeting() {
        SharedStore.shared.personalDictionary = ["Zzalpha"]

        XCTAssertEqual(
            committed("Zzalph", in: .english), "Zzalpha ",
            "nothing else in the bar starts with those letters, so the entry is the "
                + "only reading of them and the space bar should finish it")
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
