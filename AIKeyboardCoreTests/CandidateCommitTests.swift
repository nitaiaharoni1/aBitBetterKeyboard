import XCTest

@testable import AIKeyboardCore

/// Committing a candidate, which is the path that runs most: every space press
/// and every tap on the suggestion row.
///
/// **Nothing covered `replaceCurrentWord` at all**, and it carried the same two
/// defects `replaceTargetText` was rewritten to fix — a delete loop sized in
/// grapheme clusters, and no idea what a selection does to a backspace. The
/// corrections it mangles are this keyboard's own: `שלומ` → `שלום` is
/// `hebrewFinalFormCorrection`, written for Hebrew and pinned by
/// `SuggestionEngineTests`, and it fires on the space bar.
@MainActor
final class CandidateCommitTests: XCTestCase {

    private var autocorrectLevel = AutocorrectLevel.full
    private var predictions = true
    private var autocapitalise = true

    override func setUp() {
        super.setUp()
        autocorrectLevel = SharedStore.shared.autocorrectLevel
        predictions = SharedStore.shared.predictions
        autocapitalise = SharedStore.shared.autocapitalise
        SharedStore.shared.autocorrectLevel = .full
        SharedStore.shared.predictions = true
        SharedStore.shared.autocapitalise = true
    }

    override func tearDown() {
        SharedStore.shared.autocorrectLevel = autocorrectLevel
        SharedStore.shared.predictions = predictions
        SharedStore.shared.autocapitalise = autocapitalise
        super.tearDown()
    }

    /// One case, twice: against the model and against a real `UITextView`.
    private func check(
        before: String,
        selecting: String = "",
        after: String = "",
        candidate: String,
        bySpace expectedBySpace: String,
        byTap expectedByTap: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for byTap in [false, true] {
            let mock = CursorTextTarget(
                before: before, selecting: selecting.isEmpty ? nil : selecting, after: after)
            let live = LiveTextViewTarget(before: before, selecting: selecting, after: after)
            let expected = byTap ? expectedByTap : expectedBySpace

            for (target, document, name) in [
                (mock as TextTarget, { mock.document }, "the model"),
                (live as TextTarget, { live.document }, "a real UITextView")
            ] {
                let controller = KeyboardController(target: target)
                let suggestion = Suggestion(text: candidate, language: .english, isDefault: true)
                controller.suggestions = [suggestion]
                if byTap {
                    controller.apply(suggestion)
                } else {
                    controller.press(.space)
                }
                XCTAssertEqual(
                    document(), expected,
                    "\(byTap ? "tap" : "space") against \(name)", file: file, line: line)
            }
        }
    }

    /// **The measured failure, row one.** `שָׁ` is one grapheme cluster and three
    /// presses, so a loop sized `prefix.count` stops one mark short and leaves the
    /// half-deleted letter in front of the candidate: `hi שָשָׁלום`.
    func testHebrewWithNiqqudCommitsWholeCharacters() {
        check(
            before: "hi שָׁלומ", candidate: "שָׁלום",
            bySpace: "hi שָׁלום ", byTap: "hi שָׁלום ")
    }

    /// Arabic: `مُ` is two presses and `مَّ` is three.
    func testArabicHarakatCommitWholeCharacters() {
        check(
            before: "hi مُحَمَّد", candidate: "محمد",
            bySpace: "hi محمد ", byTap: "hi محمد ")
    }

    /// Devanagari: `क्षि` is four presses.
    func testDevanagariConjunctsCommitWholeCharacters() {
        check(
            before: "hi क्षिति", candidate: "क्षति",
            bySpace: "hi क्षति ", byTap: "hi क्षति ")
    }

    /// An emoji in the partial word goes in one press, so a loop sized in UTF-16
    /// would over-delete exactly where the cluster loop under-deletes.
    func testAnEmojiInThePartialWord() {
        check(
            before: "ok 🎉par", candidate: "party",
            bySpace: "ok party ", byTap: "ok party ")
    }

    /// **A live selection, which is the other half of the same bug.** The first
    /// backspace removes the selection and every press after it ate real text:
    /// `hello wor⟦ld mo⟧re` came back `hello wword re`, with the user's `or` gone.
    ///
    /// The rule now is the one typing already follows — replace the selection,
    /// touch nothing outside it. On the space bar that means the space replaces
    /// the selection and no candidate is committed, exactly as on the system
    /// keyboard; on a tap it means the candidate is typed over the selection and
    /// the partial word in front of it is left alone, because with a range
    /// selected there is no word under the cursor.
    func testASelectionIsReplacedAndNothingAroundItIs() {
        check(
            before: "hello wor", selecting: "ld mo", after: "re", candidate: "word",
            bySpace: "hello wor re", byTap: "hello worword re")
    }

    /// Space must leave the typed word alone when Autocorrect is off in Settings.
    /// A bold candidate sitting in the bar is not permission to replace — that is
    /// exactly what the toggle is for.
    ///
    /// **Writes only into the suite, behind the published copy's back.** Setting
    /// `autocorrectLevel = .off` updates both readers, so a revert to
    /// `store.autocorrectLevel` would still pass. The app's process looks like this
    /// to a keyboard already on screen: defaults say off, `@Published` is still on.
    /// See `SharedStore.storedAutocorrectLevel`.
    func testSpaceDoesNotAutocorrectWhenTheSettingIsOff() {
        SharedStore.shared.userDefaults.set(
            AutocorrectLevel.off.rawValue, forKey: SharedStore.Key.autocorrectLevel)
        XCTAssertEqual(
            SharedStore.shared.autocorrectLevel, .full,
            "the published copy must stay stale, or this proves nothing")
        XCTAssertEqual(SharedStore.shared.storedAutocorrectLevel, .off)

        let target = CursorTextTarget(before: "schedul")
        let controller = KeyboardController(target: target)
        controller.suggestions = [
            Suggestion(text: "schedul", language: .english),
            Suggestion(text: "schedule", language: .english, isDefault: true)
        ]
        controller.press(.space)
        XCTAssertEqual(
            target.document, "schedul ",
            "space committed the correction while Autocorrect was off")
    }

    /// When Autocorrect is off, the bold slot has to be the typed word — otherwise
    /// the bar advertises a correction space is no longer allowed to commit.
    ///
    /// Driving `refreshSuggestions` is load-bearing: the space-bar test above
    /// plants `isDefault` by hand and would still pass if this branch were deleted.
    /// Proving the engine would have bolded `schedule` first is what makes the
    /// second half reject a build that dropped the remapping.
    func testTheBoldSlotIsTheTypedWordWhenAutocorrectIsOff() {
        SharedStore.shared.autocorrectLevel = .full

        let controller = KeyboardController(
            target: CursorTextTarget(before: "sched"), language: .english)
        controller.refreshSuggestions()
        XCTAssertEqual(
            controller.suggestions.first(where: \.isDefault)?.text.lowercased(), "schedule",
            "the word has to be genuinely at risk, or turning the setting off proves nothing")

        SharedStore.shared.userDefaults.set(
            AutocorrectLevel.off.rawValue, forKey: SharedStore.Key.autocorrectLevel)
        XCTAssertEqual(SharedStore.shared.autocorrectLevel, .full)
        controller.refreshSuggestions()

        XCTAssertEqual(
            controller.suggestions.first(where: \.isDefault)?.text, "sched",
            "the bar bolded \(controller.suggestions.first(where: \.isDefault)?.text ?? "nothing")")
        XCTAssertTrue(
            controller.suggestions.contains { $0.text.lowercased() == "schedule" },
            "the correction still has to be offered for a tap: \(controller.suggestions.map(\.text))")
    }

    /// The Predictions switch lives in the app and this controller can already
    /// be alive in the keyboard extension. Write only to defaults so the
    /// published copy stays stale: a revert to `store.predictions` would keep
    /// returning the shipped empty-prefix suggestions and fail this assertion.
    func testSuggestionRefreshSeesPredictionsTurnedOffInTheOtherProcess() {
        let controller = KeyboardController(
            target: CursorTextTarget(before: ""), language: .english)
        controller.refreshSuggestions()
        XCTAssertFalse(
            controller.suggestions.isEmpty,
            "the fixture needs suggestions before the setting changes")

        SharedStore.shared.userDefaults.set(false, forKey: SharedStore.Key.predictions)
        XCTAssertTrue(
            SharedStore.shared.predictions,
            "the published copy must stay stale, or this proves nothing")
        XCTAssertFalse(SharedStore.shared.storedPredictions)

        controller.refreshSuggestions()
        XCTAssertTrue(
            controller.suggestions.isEmpty,
            "the keyboard kept showing predictions after the app turned them off")
    }

    // MARK: A word the user is repairing by hand

    /// **The delete key undoing itself.** Backspacing the `ם` off `שלומם` leaves
    /// `שלומ`, which is not a word — `hebrewFinalFormCorrection` turns it into
    /// `שלום` and space committed that, so pressing delete to change the word
    /// changed it straight back.
    ///
    /// The control half is the same four letters reached by *typing*, which still
    /// corrects. Without it this would pass against a build that had switched
    /// autocorrect off altogether, which is not what the reprieve is.
    func testSpaceDoesNotCorrectAWordTheUserJustBackspacedInto() {
        let typed = CursorTextTarget(before: "שלומ")
        let control = KeyboardController(target: typed, language: .hebrew)
        control.refreshSuggestions()
        control.press(.space)
        XCTAssertEqual(
            typed.document, "שלום ",
            "the correction has to be live, or the repaired case proves nothing")

        let repaired = CursorTextTarget(before: "שלומם")
        let controller = KeyboardController(target: repaired, language: .hebrew)
        controller.press(.backspace)
        controller.press(.space)
        XCTAssertEqual(
            repaired.document, "שלומ ",
            "space corrected a word the delete key had just changed")
    }

    /// The bar has to say so too, or it advertises a swap that will not happen.
    ///
    /// Both halves stand on the same five letters, one reached by typing and one
    /// by deleting a sixth, so the only difference between them is the backspace.
    /// The correction stays in the list: a deliberate tap still commits it.
    func testTheBoldSlotIsTheTypedWordAfterABackspace() {
        let atRisk = KeyboardController(
            target: CursorTextTarget(before: "sched"), language: .english)
        atRisk.refreshSuggestions()
        XCTAssertEqual(
            atRisk.suggestions.first(where: \.isDefault)?.text.lowercased(), "schedule",
            "the word has to be genuinely at risk, or the backspace proves nothing")

        let controller = KeyboardController(
            target: CursorTextTarget(before: "schedu"), language: .english)
        controller.press(.backspace)
        XCTAssertEqual(
            controller.suggestions.first(where: \.isDefault)?.text, "sched",
            "the bar bolded \(controller.suggestions.first(where: \.isDefault)?.text ?? "nothing")")
        XCTAssertTrue(
            controller.suggestions.contains { $0.text.lowercased() == "schedule" },
            "the correction is still a tap away: \(controller.suggestions.map(\.text))")
    }

    /// **The reprieve is one word long, and the next word is deliberately the same
    /// five letters.** `isCorrectingWordByHand` matches on the prefix the delete
    /// left behind, so a word retyped identically after the repaired one is the
    /// case a snapshot that never expired would still be suppressing.
    func testTheNextWordIsCorrectedNormally() {
        let target = CursorTextTarget(before: "schedu")
        let controller = KeyboardController(target: target, language: .english)
        controller.shift = .off
        controller.press(.backspace)
        controller.press(.space)
        XCTAssertEqual(target.document, "sched ", "the repaired word was not left alone")

        for character in "sched" { controller.press(.character(String(character))) }
        controller.press(.space)
        XCTAssertEqual(
            target.document, "sched schedule ",
            "the reprieve outlived the word it was for")
    }

    /// Return capitalises the next word from UserDefaults, not from the copy
    /// `load()` filled at launch. Same trap as `storedAutocorrectLevel`.
    func testReturnSeesAutocapitaliseTurnedOffInTheOtherProcess() {
        SharedStore.shared.userDefaults.set(false, forKey: SharedStore.Key.autocapitalise)
        XCTAssertTrue(
            SharedStore.shared.autocapitalise,
            "the published copy must stay stale, or this proves nothing")
        XCTAssertFalse(SharedStore.shared.storedAutocapitalise)

        let controller = KeyboardController(
            target: CursorTextTarget(before: "hi"), language: .english)
        controller.shift = .off
        controller.press(.ret)
        XCTAssertEqual(
            controller.shift, .off,
            "Return still turned shift on after Auto-capitalise was switched off")
    }

    // MARK: First backspace undoes a space-bar swap

    /// Gboard and the system keyboard restore the keystrokes when delete
    /// follows a space that just corrected. We used to eat the space and
    /// leave the wrong word.
    ///
    /// The control half types the same letters and stops at space, so a build
    /// that simply turned Autocorrect off fails both sides.
    func testFirstBackspaceAfterSpaceRestoresTheKeystrokes() {
        let control = CursorTextTarget(before: "helo")
        let live = KeyboardController(target: control, language: .english)
        live.refreshSuggestions()
        live.press(.space)
        XCTAssertEqual(
            control.document, "hello ",
            "the correction has to be live, or the undo proves nothing")

        let target = CursorTextTarget(before: "helo")
        let controller = KeyboardController(target: target, language: .english)
        controller.refreshSuggestions()
        controller.press(.space)
        XCTAssertEqual(target.document, "hello ", "space did not swap, so delete cannot undo it")
        controller.press(.backspace)
        XCTAssertEqual(
            target.document, "helo",
            "delete left the correction standing: \(target.document)")
    }

    /// Space must not put the same correction back after the user undid it.
    func testSpaceDoesNotRepeatAnUndoneAutocorrect() {
        let control = CursorTextTarget(before: "helo")
        let live = KeyboardController(target: control, language: .english)
        live.refreshSuggestions()
        live.press(.space)
        XCTAssertEqual(control.document, "hello ", "the correction has to be live")

        let target = CursorTextTarget(before: "helo")
        let controller = KeyboardController(target: target, language: .english)
        controller.refreshSuggestions()
        controller.press(.space)
        controller.press(.backspace)
        XCTAssertEqual(target.document, "helo")
        controller.press(.space)
        XCTAssertEqual(
            target.document, "helo ",
            "space put the undone correction back: \(target.document)")
    }

    /// A later letter closes the undo. Delete then eats that letter, not the
    /// swapped word.
    func testALaterLetterClearsAutocorrectUndo() {
        let control = CursorTextTarget(before: "helo")
        let live = KeyboardController(target: control, language: .english)
        live.refreshSuggestions()
        live.press(.space)
        XCTAssertEqual(control.document, "hello ", "the correction has to be live")

        let target = CursorTextTarget(before: "helo")
        let controller = KeyboardController(target: target, language: .english)
        controller.shift = .off
        controller.refreshSuggestions()
        controller.press(.space)
        controller.press(.character("x"))
        controller.press(.backspace)
        XCTAssertEqual(
            target.document, "hello ",
            "delete undid an earlier word: \(target.document)")
    }

    /// Autocorrect-off never swapped, so delete is an ordinary backspace.
    func testAutocorrectOffHasNoUndoPath() {
        SharedStore.shared.userDefaults.set(
            AutocorrectLevel.off.rawValue, forKey: SharedStore.Key.autocorrectLevel)
        XCTAssertEqual(SharedStore.shared.autocorrectLevel, .full)
        XCTAssertEqual(SharedStore.shared.storedAutocorrectLevel, .off)

        let target = CursorTextTarget(before: "helo")
        let controller = KeyboardController(target: target, language: .english)
        controller.refreshSuggestions()
        controller.press(.space)
        XCTAssertEqual(target.document, "helo ", "space swapped while Autocorrect was off")
        controller.press(.backspace)
        XCTAssertEqual(
            target.document, "helo",
            "delete restored a swap that never happened: \(target.document)")
    }

    /// A tap in the host field moves the caret without a key. `selectionDidChange`
    /// is what calls `refreshSuggestions` for that; without it the bar keeps
    /// scoring the word the caret just left.
    func testAHostCaretMoveRefreshesTheBar() {
        let target = CursorTextTarget(before: "hello schedu")
        let controller = KeyboardController(target: target, language: .english)
        controller.press(.backspace)
        let stale = controller.suggestions.map(\.text)
        XCTAssertFalse(stale.isEmpty, "the bar has to have been scoring sched")

        target.placeCaret(before: "hel", after: "lo sched")
        XCTAssertEqual(
            controller.suggestions.map(\.text), stale,
            "the bar moved on its own, so this does not prove the callback")
        controller.refreshSuggestions()
        XCTAssertTrue(
            controller.suggestions.contains { $0.text.lowercased() == "hello" || $0.text == "hel" },
            "the bar is still scoring the word the caret left: \(controller.suggestions.map(\.text))")
    }
}
