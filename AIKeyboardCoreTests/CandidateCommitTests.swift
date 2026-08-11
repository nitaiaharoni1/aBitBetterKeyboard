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

    private var autocorrect = true
    private var predictions = true

    override func setUp() {
        super.setUp()
        autocorrect = SharedStore.shared.autocorrect
        predictions = SharedStore.shared.predictions
        SharedStore.shared.autocorrect = true
        SharedStore.shared.predictions = true
    }

    override func tearDown() {
        SharedStore.shared.autocorrect = autocorrect
        SharedStore.shared.predictions = predictions
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
    /// `autocorrect = false` updates both readers, so a revert to
    /// `store.autocorrect` would still pass. The app's process looks like this to
    /// a keyboard already on screen: defaults say off, `@Published` is still on.
    /// See `SharedStore.storedAutocorrect`.
    func testSpaceDoesNotAutocorrectWhenTheSettingIsOff() {
        SharedStore.shared.userDefaults.set(false, forKey: SharedStore.Key.autocorrect)
        XCTAssertTrue(
            SharedStore.shared.autocorrect,
            "the published copy must stay stale, or this proves nothing")
        XCTAssertFalse(SharedStore.shared.storedAutocorrect)

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
        SharedStore.shared.autocorrect = true

        let controller = KeyboardController(
            target: CursorTextTarget(before: "sched"), language: .english)
        controller.refreshSuggestions()
        XCTAssertEqual(
            controller.suggestions.first(where: \.isDefault)?.text.lowercased(), "schedule",
            "the word has to be genuinely at risk, or turning the setting off proves nothing")

        SharedStore.shared.userDefaults.set(false, forKey: SharedStore.Key.autocorrect)
        XCTAssertTrue(SharedStore.shared.autocorrect)
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
}
