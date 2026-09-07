import XCTest

@testable import AIKeyboardCore

extension GroupedKeysTests {
    func testAnEmptyCodeAnswersNothing() {
        XCTAssertEqual(referenceDecoder().candidates(startingWith: ""), [])
    }

    /// **A pin is the user overruling the decoder, so it filters rather than
    /// nudges.** Long-pressing a key and choosing a letter out of it is the escape
    /// hatch being used; a candidate that disagrees with the letter somebody
    /// deliberately picked is not a worse answer, it is the wrong answer. Ranking it
    /// down instead would still leave `to` in the bar after the user said the second
    /// letter is `h`.
    func testAPinnedLetterFiltersTheCandidatesRatherThanRerankingThem() throws {
        let decoder = referenceDecoder()
        let code = String(try XCTUnwrap(GroupedDecoder.code(for: "the", map: try referenceKeys())).prefix(1))

        XCTAssertEqual(decoder.candidates(startingWith: code, pinnedTo: [:]), ["the", "to", "that"])
        XCTAssertEqual(decoder.candidates(startingWith: code, pinnedTo: [1: "h"]), ["the", "that"])
        XCTAssertEqual(decoder.candidates(startingWith: code, pinnedTo: [2: "a"]), ["that"])
        // Every candidate disagreeing with the pin is an empty bar, which is honest:
        // `literal(for:)` is what goes on screen then.
        XCTAssertEqual(decoder.candidates(startingWith: code, pinnedTo: [0: "z"]), [])
    }

    /// A pin can outlive the word it was set on — the user picks a letter at position
    /// 3 and the candidate is two letters long — so the bounds check is doing real
    /// work rather than guarding a theoretical crash. A word too short to hold the
    /// pin does not satisfy it.
    func testAPinPastTheEndOfAWordRejectsThatWord() throws {
        let decoder = referenceDecoder()
        let code = String(try XCTUnwrap(GroupedDecoder.code(for: "the", map: try referenceKeys())).prefix(1))

        XCTAssertEqual(decoder.candidates(startingWith: code, pinnedTo: [3: "t"]), ["that"])
        XCTAssertFalse(GroupedDecoder.honours([3: "t"], "the"))
        XCTAssertTrue(GroupedDecoder.honours([3: "t"], "that"))
    }

    /// **The keyboard must never go blank while somebody is typing.** With no
    /// candidate at all, what goes on screen is the first letter of each cap pressed:
    /// usually not a word, always something visible that can be deleted. Joining the
    /// caps instead answers `qwertyuiop` for three keystrokes, which is ten
    /// characters the user did not type.
    func testTheFallbackIsTheFirstLetterOfEachCap() throws {
        let grouped = GroupedKeys.layout(try letterLayout(.english), language: .english, level: .l1)

        XCTAssertEqual(GroupedDecoder.literal(for: grouped.rows[0]), "qetuo")
        // With grouping off every cap is one letter, so the fallback is exactly what
        // was keyed.
        XCTAssertEqual(GroupedDecoder.literal(for: ["h", "i"]), "hi")
        XCTAssertEqual(GroupedDecoder.literal(for: []), "")
    }

    // MARK: What ends a grouped word

    /// The broken version ends the word only on space, which leaves the strokes
    /// describing a word the cursor has since left — so the next grouped press
    /// rewrites whatever now sits behind it. Return, the globe and the cursor
    /// keys are the ones that used to slip through.
    func testEverythingExceptLettersDeleteAndShiftEndsTheWord() {
        for cap in [KeyCap.character("a"), .character("qwer"), .backspace, .shift] {
            XCTAssertFalse(
                GroupedInput.interrupts(cap), "\(cap) should let the word carry on")
        }
        for cap in [
            KeyCap.space, .ret, .globe, .emoji, .copyclip, .settings, .dictation, .cursorLeft,
            .cursorRight, .quickTone, .hideKeyboard, .plane(.numbers, label: "123")
        ] {
            XCTAssertTrue(GroupedInput.interrupts(cap), "\(cap) should end the word")
        }
    }

    /// A new `KeyCap` must end a grouped word by default rather than silently
    /// continuing one, so the switch has to be written as "which continue".
    func testAnUnknownCapEndsTheWord() {
        XCTAssertTrue(GroupedInput.interrupts(.aiFix))
        XCTAssertTrue(GroupedInput.interrupts(.aiReply))
    }

    // MARK: Case

    /// Shift is read once at the first key. The broken version read it per
    /// keystroke, and since a one-shot shift is consumed by the first press,
    /// `The` decoded as `The` and then immediately as `the`.
    func testShiftCapitalisesTheFirstLetterOnlyAndSurvivesLaterKeystrokes() {
        let input = GroupedInput()
        input.startedShifted = true
        // Not `THE`: shift on a word means a capital, not caps lock.
        XCTAssertEqual(input.cased("the", in: .english), "The")
        XCTAssertEqual(input.cased("hello", in: .english), "Hello")
        // Still capitalised however many times it is asked, because the flag is
        // the word's, not the keystroke's.
        XCTAssertEqual(input.cased("the", in: .english), "The")
        XCTAssertEqual(input.cased("", in: .english), "")

        input.startedShifted = false
        XCTAssertEqual(input.cased("the", in: .english), "the")
    }

    /// Hebrew has no case, so casing must be a no-op rather than something that
    /// mangles the word.
    func testCasingAHebrewWordChangesNothing() {
        let input = GroupedInput()
        input.startedShifted = true
        XCTAssertEqual(input.cased("שלום", in: .hebrew), "שלום")
    }

    /// `clear()` has to drop the case flag and the written text too. Leaving
    /// `lastWritten` behind makes the next press compare the field against a word
    /// that is no longer in it and conclude the cursor moved.
    func testClearingForgetsEverythingAboutTheWord() {
        let input = GroupedInput()
        input.startedShifted = true
        input.lastWritten = "The"
        input.append(cap: "qwer")
        input.clear()
        XCTAssertFalse(input.isTyping)
        XCTAssertFalse(input.startedShifted)
        XCTAssertEqual(input.lastWritten, "")
    }

    // MARK: The layout engine is a pure function of its arguments

    /// **The version this rejects read the dial out of `SharedStore` inside
    /// `KeyboardLayout`.** That made the whole layout engine depend on global
    /// mutable state: a dial left on in the simulator's App Group — which is
    /// exactly what happens on a machine where somebody has tried the feature —
    /// silently made `RenderedRowOrderTests` and `LanguageCatalogueTests` measure
    /// a grouped keyboard. The same shape as the `PersonalLanguageModel` trap,
    /// where the suite taught the store its own vocabulary and then tested
    /// against it.
    ///
    /// Asserting on the *default* argument is the whole point: it is what every
    /// existing caller and every existing test gets.
    func testTheLayoutIsUngroupedUnlessAskedRegardlessOfTheStore() {
        SharedStore.shared.groupedLevel = .l1
        defer { SharedStore.shared.groupedLevel = .off }

        for language in [KeyboardLanguage.english, .hebrew] {
            let rows = KeyboardLayout.rows(for: language, plane: .letters)
            let caps = rows.flatMap(\.keys).compactMap { spec -> String? in
                if case .character(let value) = spec.cap { return value }
                return nil
            }
            let expected = KeyboardLayout.letterLayouts[language]!.rows.flatMap { $0 }
            XCTAssertEqual(
                caps, expected,
                "\(language) drew a grouped keyboard from the store rather than its argument")
            // Every cap one letter: the grouped version merges them.
            XCTAssertTrue(caps.allSatisfy { $0.count == 1 })
        }

        XCTAssertEqual(KeyboardLayout.columns(for: .english, plane: .letters), 10)
        // And asking for grouping explicitly still works, so this is not just a
        // test that the feature is off.
        XCTAssertEqual(KeyboardLayout.columns(for: .english, plane: .letters, grouping: .l1), 10)
    }

    /// Hebrew L2 commits the wrong word about three times in ten. The dial is
    /// shared, so English keeps the stop and Hebrew is clamped at L1.
    ///
    /// `@MainActor` because a `KeyboardController` is: the second half of this
    /// asks the controller what it would actually draw, which is the half that
    /// rejects a `capped(for:)` that is correct and wired to nothing.
    @MainActor
    func testHebrewIsCappedAtThreeLettersPerKey() {
        XCTAssertEqual(GroupedKeys.Level.l2.capped(for: .english), .l2)
        XCTAssertEqual(GroupedKeys.Level.l3.capped(for: .english), .l3)
        XCTAssertEqual(GroupedKeys.Level.l2.capped(for: .hebrew), .l1)
        XCTAssertEqual(GroupedKeys.Level.l3.capped(for: .hebrew), .l1)
        XCTAssertEqual(GroupedKeys.Level.l1.capped(for: .hebrew), .l1)
        XCTAssertEqual(GroupedKeys.Level.pairs.capped(for: .hebrew), .pairs)

        SharedStore.shared.groupedLevel = .l2
        defer { SharedStore.shared.groupedLevel = .off }
        let hebrew = KeyboardController(target: MockTextTarget(), language: .hebrew)
        XCTAssertEqual(hebrew.groupingLevel, .l1)
        let english = KeyboardController(target: MockTextTarget(), language: .english)
        XCTAssertEqual(english.groupingLevel, .l2)
    }

    // MARK: Which caps are grouped ones

    /// **A cap carrying several characters is not necessarily a grouped key, and
    /// reading it as one was a shipped defect.** `SlotAction.text` compiles to
    /// `.character(".com")`, and the shipped catalogue also offers `,` `?` `!` `@` —
    /// so the version that asked "does this cap hold more than one letter" fed the
    /// `.com` key to the decoder as a keystroke, on any customised layout carrying
    /// it, the moment grouping was switched on. Membership in the layout the
    /// keyboard is actually drawing is the question with an answer.
    ///
    /// The first two assertions are what stop this passing against a build that
    /// answers `false` to everything, which would switch the whole feature off.
    func testASnippetKeyIsNotAGroupedKey() {
        let input = GroupedInput()
        let caps = input.caps(language: .english, level: .l2)

        XCTAssertTrue(caps.contains("qw\nas"))
        XCTAssertTrue(caps.contains("zxcv"))
        XCTAssertFalse(caps.contains(".com"))
        XCTAssertFalse(caps.contains(","))
        // `zxcv` is four letters of the keyboard in order and still not a grouped
        // key at every level, so the set has to be per level rather than a union.
        XCTAssertFalse(input.caps(language: .english, level: .pairs).contains("zxcv"))
        XCTAssertTrue(input.caps(language: .english, level: .pairs).contains("zx"))
    }

    /// The cache is keyed by language *and* level, and answering from a stale one
    /// is the same defect the decoder cache exists to avoid. English at L2 and
    /// Hebrew at L2 share nothing, so a cache that ignored the language would fail
    /// the second call.
    func testTheCapCacheAnswersPerLanguageAndLevel() {
        let input = GroupedInput()

        XCTAssertTrue(input.caps(language: .english, level: .l2).contains("qw\nas"))
        XCTAssertFalse(input.caps(language: .hebrew, level: .l2).contains("qw\nas"))
        XCTAssertTrue(input.caps(language: .english, level: .l2).contains("qw\nas"))
        XCTAssertFalse(input.caps(language: .english, level: .l3).contains("qw\nas"))
    }

    /// **VoiceOver has to be told this is four letters, and `KeyCap` cannot tell
    /// it.** A cap is a value holding a string: `qw\nas` and `.com` are both
    /// `.character` with several characters in them, and one has to be spelled
    /// while the other has to be read as a word. The layout that built the key is
    /// the only thing that knows which, so it says so.
    func testAGroupedKeyIsReadOutAsItsLetters() throws {
        let rows = KeyboardLayout.rows(for: .english, plane: .letters, grouping: .l2)
        let first = try XCTUnwrap(rows.first?.keys.first)

        XCTAssertEqual(first.spokenLabel, "q w a s")
        // An ordinary key says nothing extra, so its cap keeps answering for it.
        let ungrouped = try XCTUnwrap(
            KeyboardLayout.rows(for: .english, plane: .letters).first?.keys.first)
        XCTAssertNil(ungrouped.spokenLabel)
        XCTAssertEqual(ungrouped.cap.accessibilityLabel, "q")
    }

    // MARK: Which fields may be grouped

    /// A password, email or URL field is typed exactly or not at all, and in a
    /// password field the user cannot even see what a decoder got wrong.
    func testCredentialAndExactFieldsAreNeverGrouped() {
        XCTAssertFalse(GroupedKeys.permitted(secure: true, contentType: nil))
        XCTAssertFalse(GroupedKeys.permitted(secure: nil, contentType: .some(.password)))
        XCTAssertFalse(GroupedKeys.permitted(secure: nil, contentType: .some(.emailAddress)))
        XCTAssertFalse(GroupedKeys.permitted(secure: nil, contentType: .some(.URL)))
        XCTAssertFalse(GroupedKeys.permitted(secure: nil, contentType: .some(.username)))
        // A field that says nothing is an ordinary field: silence is an
        // unimplemented optional protocol member, not a password box. Same rule
        // `SecureField.permitsRead` is built on.
        XCTAssertTrue(GroupedKeys.permitted(secure: nil, contentType: nil))
        XCTAssertTrue(GroupedKeys.permitted(secure: false, contentType: .some(nil)))
        XCTAssertTrue(GroupedKeys.permitted(secure: false, contentType: .some(.name)))
    }

    // MARK: Bundled lexicon

    /// Same shape as `EmojiModeTests.testTheCatalogueLoadsOutOfTheResourceBundle`.
    /// Without this, a missing `resources:` line or a renamed file leaves
    /// grouped keys on the seed list and Settings is the only thing that says so.
    func testTheBundledLexiconLoadsOutOfTheResourceBundle() {
        XCTAssertTrue(
            GroupedKeys.hasBundledLexicon(for: .english),
            "GroupedLexicon-en.txt missing from Bundle.module")
        XCTAssertTrue(
            GroupedKeys.hasBundledLexicon(for: .hebrew),
            "GroupedLexicon-he.txt missing from Bundle.module")
        XCTAssertGreaterThan(GroupedLexiconResource.words(for: .english).count, 10_000)
        XCTAssertGreaterThan(GroupedLexiconResource.words(for: .hebrew).count, 10_000)
        XCTAssertEqual(GroupedLexiconResource.words(for: .english).first, "the")
    }

    // MARK: Session ownership

    /// The claim lives on the type. A prefix that no longer matches lastWritten
    /// is a caret move, not a key, and the strokes must die there.
    func testAStalePrefixAbandonsTheSession() {
        let input = GroupedInput()
        input.append(cap: "qw\nas")
        input.lastWritten = "as"
        XCTAssertFalse(input.abandonIfStale(prefix: "as"))
        XCTAssertTrue(input.isTyping)
        XCTAssertTrue(input.abandonIfStale(prefix: "other"))
        XCTAssertFalse(input.isTyping)
        XCTAssertTrue(input.abandonIfStale(prefix: "other"))
    }

    /// Space learns only when every letter was pinned. The flag has to survive
    /// `clear`, because `press` ends the session before `learnWordJustCommitted`.
    func testClosingAnUnpinnedWordSkipsTheNextLearn() {
        let input = GroupedInput()
        input.append(cap: "qw\nas")
        input.closeForKeyCommit()
        XCTAssertFalse(input.isTyping)
        XCTAssertTrue(input.consumeSkipLearn())
        XCTAssertFalse(input.consumeSkipLearn())
    }

    func testClosingAFullyPinnedWordDoesNotSkipLearn() {
        let input = GroupedInput()
        input.append(cap: "qw\nas", pin: "q")
        XCTAssertTrue(input.allLettersPinned)
        input.closeForKeyCommit()
        XCTAssertFalse(input.consumeSkipLearn())
    }

    /// Delete-then-retype on the second key pinned the first key or ended the
    /// word. Pinning must keep both strokes and mark the one just pressed.
    @MainActor
    func testPinningTheSecondKeyKeepsTheWordOpen() {
        SharedStore.shared.groupedLevel = .l1
        defer { SharedStore.shared.groupedLevel = .off }
        let target = MockTextTarget()
        let controller = KeyboardController(target: target, language: .english)
        controller.pressGroupedKey("qw\nas")
        controller.pressGroupedKey("er\ndf")
        XCTAssertTrue(controller.pinGroupedLetter("e"))
        XCTAssertTrue(controller.grouped.isTyping)
        XCTAssertEqual(controller.grouped.strokes.count, 2)
        XCTAssertEqual(controller.grouped.pins[1], "e")
        XCTAssertFalse(target.text == "e", "the old path typed a lone e and closed")
    }

    /// The shipping popup path, not the controller method. The old handler
    /// deleted the stroke it was supposed to pin.
    @MainActor
    func testTheAlternateHandlerPinsTheGroupedStrokeItDoesNotDeleteIt() throws {
        SharedStore.shared.groupedLevel = .l1
        defer { SharedStore.shared.groupedLevel = .off }
        let target = MockTextTarget()
        let controller = KeyboardController(target: target, language: .english)
        let view = KeyboardView(controller: controller)
        let band = KeyboardLayout.rows(for: .english, plane: .letters, grouping: .l1)[0]
        let second = try XCTUnwrap(
            band.keys.first { $0.groupedLetters == ["e", "r", "d", "f"] })
        let handler = try XCTUnwrap(view.alternateHandler(for: second))

        controller.pressGroupedKey("qw\nas")
        controller.pressGroupedKey("er\ndf")
        handler("e")

        XCTAssertTrue(controller.grouped.isTyping)
        XCTAssertEqual(controller.grouped.strokes.count, 2)
        XCTAssertEqual(controller.grouped.pins[1], "e")
    }

    /// `textDidChange` always calls `refreshSuggestions`. The ordinary engine
    /// then treats the guess as typed letters. The grouped bar must survive.
    @MainActor
    func testRefreshSuggestionsDoesNotReplaceTheGroupedBar() {
        SharedStore.shared.groupedLevel = .l1
        defer { SharedStore.shared.groupedLevel = .off }
        let controller = KeyboardController(target: MockTextTarget(), language: .english)
        controller.pressGroupedKey("qw\nas")
        controller.pressGroupedKey("er\ndf")
        let before = controller.suggestions.map(\.text)
        XCTAssertFalse(before.isEmpty, "grouped press must fill the bar")
        controller.refreshSuggestions()
        XCTAssertEqual(controller.suggestions.map(\.text), before)
    }

    /// Complete on pause off: the field is exact-length or the literal, never a
    /// longer word. Backspace shortens. The bar still offers the next most
    /// likely words (including longer ones you can tap). Nothing is bold, and
    /// the field word is not repeated when there are alternatives.
    @MainActor
    func testGroupedPressWritesExactLengthAndBackspaceNeverCompletes() {
        SharedStore.shared.groupedLevel = .l1
        let savedComplete = SharedStore.shared.completeOnIdle
        SharedStore.shared.completeOnIdle = false
        defer {
            SharedStore.shared.groupedLevel = .off
            SharedStore.shared.completeOnIdle = savedComplete
        }
        let target = MockTextTarget()
        let controller = KeyboardController(target: target, language: .english)
        controller.shift = .off

        func assertExactOrLiteral() {
            let field = target.text
            let literal = controller.grouped.cased(controller.grouped.literal, in: .english)
            XCTAssertTrue(
                field.count == controller.grouped.strokes.count || field == literal,
                "field \(field) must match stroke count or literal \(literal)")
            XCTAssertFalse(controller.suggestions.contains { $0.isDefault })
            if !controller.suggestions.isEmpty {
                XCTAssertFalse(
                    controller.suggestions.map(\.text).contains(field),
                    "bar must not repeat the field word")
            }
        }

        controller.pressGroupedKey("ty\ngh")
        assertExactOrLiteral()
        XCTAssertFalse(
            controller.suggestions.isEmpty,
            "bar must offer the next most likely words, including longer ones")
        let afterOne = target.text
        controller.pressGroupedKey("ty\ngh")
        assertExactOrLiteral()
        controller.pressGroupedKey("er\ndf")
        assertExactOrLiteral()
        XCTAssertTrue(controller.deleteGroupedStroke())
        assertExactOrLiteral()
        XCTAssertTrue(controller.deleteGroupedStroke())
        assertExactOrLiteral()
        XCTAssertEqual(target.text.count, afterOne.count)
        XCTAssertNotEqual(target.text, "the")
    }

    /// The first stroke of a new session must not delete the word already in
    /// the field. `replaceCurrentWord` did, because the prefix was that word.
    @MainActor
    func testAGroupedPressDoesNotEatTheWordAlreadyInTheField() {
        SharedStore.shared.groupedLevel = .l1
        defer { SharedStore.shared.groupedLevel = .off }
        let target = MockTextTarget(text: "hello ")
        let controller = KeyboardController(target: target, language: .english)
        controller.shift = .off
        controller.pressGroupedKey("ty\ngh")
        XCTAssertTrue(target.text.hasPrefix("hello "), target.text)
        XCTAssertGreaterThan(target.text.count, 6)
    }

    /// Idle completion writes a longer word and closes the session. The next
    /// grouped press is a new word, not a rewrite of the one just finished.
    @MainActor
    func testIdleCompletionSurvivesTheNextGroupedPress() {
        SharedStore.shared.groupedLevel = .l1
        SharedStore.shared.completeOnIdle = true
        defer {
            SharedStore.shared.groupedLevel = .off
            SharedStore.shared.completeOnIdle = false
        }
        let target = MockTextTarget()
        let controller = KeyboardController(target: target, language: .english)
        controller.shift = .off
        controller.pressGroupedKey("ty\ngh")
        controller.performIdleTyping()
        let completed = target.text
        XCTAssertFalse(completed.isEmpty)
        XCTAssertFalse(controller.grouped.isTyping)
        controller.pressGroupedKey("qw\nas")
        XCTAssertTrue(target.text.hasPrefix(completed), target.text)
    }

    /// A bar tap used to leave the strokes live. The next delete then
    /// re-decoded and inserted a shorter guess after the space.
    @MainActor
    func testApplyingASuggestionEndsTheGroupedSession() {
        SharedStore.shared.groupedLevel = .l1
        defer { SharedStore.shared.groupedLevel = .off }
        let target = MockTextTarget()
        let controller = KeyboardController(target: target, language: .english)
        controller.pressGroupedKey("qw\nas")
        controller.pressGroupedKey("er\ndf")
        let pick = Suggestion(text: "we", language: .english)
        controller.apply(pick)
        XCTAssertFalse(controller.grouped.isTyping)
        XCTAssertEqual(target.text, "we ")
        controller.deleteBackward()
        XCTAssertEqual(target.text, "we")
    }

    /// A caret move does not go through a key. Backspace must fall through to
    /// ordinary delete rather than rewrite the word now under the cursor.
    @MainActor
    func testBackspaceAfterACaretMoveDoesNotRewriteTheNewWord() {
        SharedStore.shared.groupedLevel = .l1
        defer { SharedStore.shared.groupedLevel = .off }
        let target = MockTextTarget()
        let controller = KeyboardController(target: target, language: .english)
        controller.pressGroupedKey("qw\nas")
        XCTAssertTrue(controller.grouped.isTyping)
        target.text = "hello"
        XCTAssertFalse(controller.deleteGroupedStroke())
        XCTAssertFalse(controller.grouped.isTyping)
        XCTAssertEqual(target.text, "hello")
    }

    /// The decoder wrote the field. Learning that guess made the next collision
    /// prefer it over the corpus.
    @MainActor
    func testSpaceDoesNotLearnAnUnpinnedGroupedGuess() {
        SharedStore.shared.groupedLevel = .l1
        defer { SharedStore.shared.groupedLevel = .off }
        let target = MockTextTarget()
        let controller = KeyboardController(target: target, language: .english)
        controller.pressGroupedKey("qw\nas")
        controller.pressGroupedKey("er\ndf")
        // The host fires `textDidChange` after every rewrite. That is what
        // puts the guess in `openWord`; skip-learn alone does not close that door.
        controller.refreshSuggestions()
        let guess = target.text
        XCTAssertGreaterThanOrEqual(guess.count, 2)
        controller.insertSpace()
        XCTAssertEqual(controller.personal.count(of: guess, in: .english), 0)
    }

    /// Every letter named is a word the user typed.
    @MainActor
    func testSpaceLearnsAFullyPinnedGroupedWord() {
        SharedStore.shared.groupedLevel = .l1
        defer { SharedStore.shared.groupedLevel = .off }
        let target = MockTextTarget()
        let controller = KeyboardController(target: target, language: .english)
        controller.shift = .off
        controller.pressGroupedKey("qw\nas")
        XCTAssertTrue(controller.pinGroupedLetter("w"))
        controller.pressGroupedKey("er\ndf")
        XCTAssertTrue(controller.pinGroupedLetter("e"))
        XCTAssertEqual(target.text, "we")
        controller.refreshSuggestions()
        controller.insertSpace()
        XCTAssertEqual(controller.personal.count(of: "we", in: .english), 1)
    }

    /// A full stop commits the word the same way space does. The old path
    /// closed the session and then learned the guess.
    @MainActor
    func testPeriodDoesNotLearnAnUnpinnedGroupedGuess() {
        SharedStore.shared.groupedLevel = .l1
        defer { SharedStore.shared.groupedLevel = .off }
        let target = MockTextTarget()
        let controller = KeyboardController(target: target, language: .english)
        controller.pressGroupedKey("qw\nas")
        controller.pressGroupedKey("er\ndf")
        controller.refreshSuggestions()
        let guess = target.text
        XCTAssertGreaterThanOrEqual(guess.count, 2)
        controller.press(.character("."))
        XCTAssertEqual(controller.personal.count(of: guess, in: .english), 0)
        XCTAssertFalse(controller.grouped.isTyping)
    }

    /// Space after a caret move used to close the old session against the new
    /// word, so skip-learn attached to `hello`.
    @MainActor
    func testSpaceAfterACaretMoveDoesNotSkipLearnOnTheNewWord() {
        SharedStore.shared.groupedLevel = .l1
        defer { SharedStore.shared.groupedLevel = .off }
        let target = MockTextTarget()
        let controller = KeyboardController(target: target, language: .english)
        controller.pressGroupedKey("qw\nas")
        controller.pressGroupedKey("er\ndf")
        controller.refreshSuggestions()
        let guess = target.text
        target.text = "hello"
        controller.insertSpace()
        XCTAssertEqual(controller.personal.count(of: "hello", in: .english), 1)
        XCTAssertEqual(controller.personal.count(of: guess, in: .english), 0)
        XCTAssertFalse(controller.grouped.isTyping)
    }
}
