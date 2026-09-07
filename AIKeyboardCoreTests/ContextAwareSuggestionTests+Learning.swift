import XCTest

@testable import AIKeyboardCore

extension ContextAwareSuggestionTests {
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
        let saved = SharedStore.shared.autocorrectLevel
        SharedStore.shared.autocorrectLevel = .off
        defer { SharedStore.shared.autocorrectLevel = saved }

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

        assertCommitPathsAfterSend()
    }

    // MARK: The frequency corrector

    /// The report this whole source exists for. `דוגמאות` ("examples") typed with
    /// the hand one key over: `א` came out `ט` and `ו` came out `ן`, both pairs
    /// side by side on the Hebrew top row.
    ///
    /// **What the old engine did, which is what these assertions have to
    /// reject.** Every correction source was one edit deep — `SeedLanguageModel
    /// .neighbours` over 353 words, and `UITextChecker.guesses` — so nothing
    /// could reach a word two slips away. Apple's guess `דוגמטית` *is* one edit
    /// out and took the only offered slot, leaving a bar holding a single word
    /// that appears nowhere in 50,000 words of real Hebrew. So asserting that
    /// `דוגמאות` is merely *present* would be too weak in one direction and
    /// asserting the bar is non-empty would pass against the broken build
    /// outright; the test is that it holds the bold slot, which is what the space
    /// bar inserts.
    func testTwoAdjacentKeySlipsReachTheWordTheFrequencyListRanks() {
        XCTAssertTrue(
            KeyProximity.areAdjacent("א", "ט", in: .hebrew),
            "the premise: the two slipped pairs have to be adjacent keys")
        XCTAssertTrue(KeyProximity.areAdjacent("ו", "ן", in: .hebrew))
        XCTAssertNotNil(TypoLexicon.rank(of: "דוגמאות", in: .hebrew))
        XCTAssertFalse(
            TypoLexicon.isWord("דוגמטית", in: .hebrew),
            "the word the old bar offered is absent from 50,000 forms of real Hebrew; "
                + "if this ever becomes true the test is measuring something else")

        let bar = SuggestionEngine.suggestions(
            prefix: "דוגמטןת", context: "תסביר את זה בפשטות עם ", languages: [.hebrew],
            personal: emptyPersonal())
        XCTAssertEqual(
            bar.first(where: \.isDefault)?.text, "דוגמאות",
            "space has to insert the word the keys nearly spell: \(bar.map(\.text))")
    }

    /// The other half, and the one that keeps this source honest: a word the
    /// corpus *has* seen is never rewritten, however close a commoner word sits.
    ///
    /// `cat` is the case the repo already records as killing every "absent from
    /// the dictionary means typo" rule it has tried — it is not among the seed
    /// list's 353 words, `car` is one edit away and is, and the first neighbour
    /// rule quietly turned one into the other. Both halves are asserted, so this
    /// cannot pass because the seed list quietly grew a `cat`.
    func testARealWordIsNeverCorrectedEvenWhenTheSeedListHasNeverHeardOfIt() {
        XCTAssertFalse(
            SeedLanguageModel.knows("cat", in: .english),
            "the premise: the seed list is what could not answer this question")
        XCTAssertTrue(TypoLexicon.isWord("cat", in: .english))

        for (typed, context, language) in [
            ("cat", "I saw a ", KeyboardLanguage.english), ("bus", "the ", .english),
            ("קליפ", "ראיתי ", .hebrew)
        ] {
            let bar = SuggestionEngine.suggestions(
                prefix: typed, context: context, languages: [language],
                personal: emptyPersonal())
            XCTAssertEqual(
                bar.first(where: \.isDefault)?.text, typed,
                "space rewrote a real word: \(typed) -> \(bar.map(\.text))")
        }
    }

    /// **Apple's spelling verdict is overruled here and nowhere else**, and the
    /// frozen corpus's `typo-10` is the case. `UITextChecker` reports `תדוה` as
    /// perfectly good Hebrew, so every rule in `commitReason` that rests on
    /// `isKnownWord` declined to commit `תודה` and the corpus recorded that as a
    /// deliberate, accepted cost of having only one dictionary worth the name.
    ///
    /// The `isKnownWord` assertion is the important one: without it this passes
    /// on a build where Apple simply changed its mind, which would make the test
    /// green for a reason that has nothing to do with the code it is guarding.

    private func assertCommitPathsAfterSend() {
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

    private func typeHello(_ controller: KeyboardController) {
        controller.shift = .off
        for character in "hello" { controller.press(.character(String(character))) }
    }
}
