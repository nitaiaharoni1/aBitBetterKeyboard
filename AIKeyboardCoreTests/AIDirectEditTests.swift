import XCTest

@testable import AIKeyboardCore

/// Fix and Rewrite write their answer into the field, and the user can take it
/// back.
///
/// **They used to offer it.** The answer arrived on the 72pt strip above the keys
/// behind a Use button, so the corrected sentence was read beside the message and
/// then again inside it. Applying on arrival is the faster half of that and the
/// riskier one: the keyboard has now changed somebody's words without a second
/// tap, and `UITextDocumentProxy` has no undo of any kind — so the whole of the
/// mitigation is `KeyboardController.revertibleEdit`, and the whole of *its*
/// correctness is that it is cleared the moment the field moves on.
@MainActor
final class AIDirectEditTests: XCTestCase {

    // MARK: The answer goes in the field

    /// Both halves, and the second is what rejects the shipped build: it put the
    /// text in `aiResultText` and left the strip up, so a version that only sets
    /// the published fields passes an assertion about the document alone if the
    /// document is never checked.
    func testFixWritesTheAnswerIntoTheFieldAndLeavesNoStrip() async {
        let engine = DirectEditEngine(fixed: "I can't make the standup.")
        let controller = makeDirectEditController(
            text: "i cant make the standup", engine: engine)

        controller.run(.fix)
        await settleToneController(controller)

        XCTAssertEqual(controller.contextBefore, "I can't make the standup.")
        XCTAssertFalse(
            controller.showsActionBanner,
            "the strip is still holding an answer the field already has")
        XCTAssertEqual(controller.overlay, .none)
    }

    func testRewriteWritesTheFirstVersionIntoTheField() async {
        let engine = DirectEditEngine(rewritten: "I can't make standup today.")
        let controller = makeDirectEditController(
            text: "i cant make the standup", engine: engine)

        controller.run(.rewrite)
        await settleToneController(controller)

        XCTAssertEqual(controller.contextBefore, "I can't make standup today.")
        XCTAssertFalse(controller.showsActionBanner)
    }

    // MARK: The way back

    /// **The round trip, byte for byte.** A revert that restores *approximately*
    /// what was typed is worse than none: the user's own words are the one thing
    /// in this feature that cannot be regenerated.
    func testRevertingPutsBackExactlyWhatWasTyped() async {
        let engine = DirectEditEngine(fixed: "I can't make the standup.")
        let controller = makeDirectEditController(
            text: "i cant make the standup", engine: engine)

        controller.run(.fix)
        await settleToneController(controller)
        XCTAssertEqual(controller.revertibleEdit?.action, .fix)

        controller.revertAIEdit()

        XCTAssertEqual(controller.contextBefore, "i cant make the standup")
        XCTAssertNil(controller.revertibleEdit, "the way back is still on offer after it was taken")
    }

    /// **Until a new key is typed, and not one keystroke longer.** The revert
    /// replaces the whole field with what was there before the action ran, so
    /// letting it survive a keystroke means offering to delete what the user typed
    /// after the correction. Every path that puts a character in has to clear it,
    /// which is why this asks four of them rather than one.
    func testTheNextKeystrokeTakesTheRevertAway() async {
        for key in [KeyCap.character("a"), .space, .backspace] {
            let engine = DirectEditEngine(fixed: "Fixed.")
            let controller = makeDirectEditController(text: "fixd", engine: engine)

            controller.run(.fix)
            await settleToneController(controller)
            XCTAssertNotNil(controller.revertibleEdit, "the answer was never applied")

            controller.press(key)
            XCTAssertNil(controller.revertibleEdit, "\(key) left the revert standing")
        }

        // And the fourth: committing a candidate from the bar, which reaches the
        // document without a `KeyCap` behind it.
        let engine = DirectEditEngine(fixed: "Fixed.")
        let controller = makeDirectEditController(text: "fixd", engine: engine)
        controller.run(.fix)
        await settleToneController(controller)
        controller.apply(Suggestion(text: "later", language: .english))
        XCTAssertNil(controller.revertibleEdit, "tapping a candidate left the revert standing")
    }

    /// **A selection edit undoes five characters, not the whole message.**
    ///
    /// The replacement is what consumes the selection, so by the time the revert
    /// runs there is none — and a revert that took the whole-field path would put
    /// `previous` back as if it were the entire field, leaving `hello there wrold
    /// friend` as the single word `wrold`. That is the user's message destroyed by
    /// the button offered to protect it, which is why this test exists at all.
    func testRevertingASelectionEditLeavesTheRestOfTheMessageAlone() async {
        let target = CursorTextTarget(
            before: "hello there ", selecting: "wrold", after: " friend")
        let controller = KeyboardController(
            target: target,
            engine: RoutedIntelligence(onDevice: DirectEditEngine(fixed: "world"), cloud: nil))

        XCTAssertEqual(controller.aiTargetText, "wrold", "the selection is not the scope")
        controller.run(.fix)
        await settleToneController(controller)
        XCTAssertEqual(target.document, "hello there world friend")
        XCTAssertEqual(controller.revertibleEdit?.replacedSelection, true)

        controller.revertAIEdit()

        XCTAssertEqual(target.document, "hello there wrold friend")
    }

    /// **A reply accepted into an empty field lights the keys that need text.**
    ///
    /// Reply is the one action that runs on an empty field, so this is the ordinary
    /// way a field goes from empty to full without a keystroke — and it takes
    /// `replaceTargetText`'s insert-only branch, the one branch there that used to
    /// skip `refreshSuggestions()`. Fix and Rewrite stayed drawn dim over a field
    /// holding a whole sentence until some later keystroke recomputed it.
    func testAcceptingAReplyIntoAnEmptyFieldLightsFixAndRewrite() {
        let controller = makeDirectEditController(text: "", engine: DirectEditEngine())
        XCTAssertTrue(controller.isActionKeyDisabled(.aiFix), "the state under test is empty")

        // What accepting a reply does: `runReply` empties `aiSourceText` because a
        // reply is inserted rather than substituted, and `applyResult` writes it in.
        controller.aiSourceText = ""
        controller.applyResult("Thursday works for me")

        XCTAssertFalse(
            controller.isActionKeyDisabled(.aiFix),
            "Fix is still drawn dim over a field holding a whole sentence")
        XCTAssertFalse(controller.isActionKeyDisabled(.quickTone))
    }

    /// **The host emptying the field is the one clearing path the user does not
    /// make**, and nothing else covers it: they tap Send in the other app, the
    /// field goes blank, `textDidChange` brings the news, and no key on this
    /// keyboard was pressed. Without `refreshDocumentState`'s second line the
    /// revert button would still be sitting in the bar, offering to type a message
    /// that has already been sent back into an empty box.
    func testAHostThatEmptiesTheFieldTakesTheRevertWithIt() async {
        let target = MockTextTarget(text: "fixd")
        let controller = KeyboardController(
            target: target,
            engine: RoutedIntelligence(onDevice: DirectEditEngine(fixed: "Fixed."), cloud: nil))

        controller.run(.fix)
        await settleToneController(controller)
        XCTAssertNotNil(controller.revertibleEdit, "the answer was never applied")

        // What the host does on Send, and then what iOS tells the keyboard about it.
        target.text = ""
        controller.refreshSuggestions()

        XCTAssertNil(
            controller.revertibleEdit,
            "the bar is still offering to put a sent message back into an empty field")
    }

    /// **An answer to a field that has moved on is offered, not applied.**
    ///
    /// A model call takes seconds and people keep typing through them, so this is
    /// the ordinary case rather than an edge: tap Fix, type the next word, and an
    /// answer written about the sentence as it was would replace the whole field
    /// and delete that word. It is not thrown away either — the banner is what a
    /// Use button is for, and this is the one state that still needs one.
    func testAnAnswerToAFieldThatMovedOnIsOfferedRatherThanApplied() async {
        let engine = DirectEditEngine(fixed: "I can't make the standup.")
        engine.hold()
        let target = MockTextTarget(text: "i cant make the standup")
        let controller = KeyboardController(
            target: target, engine: RoutedIntelligence(onDevice: engine, cloud: nil))

        controller.run(.fix)
        XCTAssertTrue(controller.isWorking, "the call never started")
        // The user carries on typing while the model thinks.
        controller.press(.character(" "))
        controller.press(.character("t"))
        engine.release()
        await settleToneController(controller)

        XCTAssertEqual(
            controller.contextBefore, "i cant make the standup t",
            "the answer overwrote what was typed while it was in flight")
        XCTAssertNil(controller.revertibleEdit)
        XCTAssertTrue(
            controller.showsActionBanner,
            "the answer was neither applied nor offered, so the call vanished")
        XCTAssertEqual(controller.bannerOptions.first?.text, "I can't make the standup.")
    }

    // MARK: Nothing to do

    /// An answer identical to the message is `EditScope` reporting that the model
    /// named no mistakes. Re-typing it would move the cursor and leave a revert
    /// button offering to change nothing, and saying nothing at all would end a
    /// shimmer in silence — so it says so.
    func testAnUnchangedAnswerChangesNothingAndSaysSo() async {
        let engine = DirectEditEngine(fixed: "Already right.")
        let controller = makeDirectEditController(text: "Already right.", engine: engine)

        controller.run(.fix)
        await settleToneController(controller)

        XCTAssertEqual(controller.contextBefore, "Already right.")
        XCTAssertNil(controller.revertibleEdit, "there is nothing to revert to")
        XCTAssertNotNil(controller.block, "the shimmer ended in silence")
        XCTAssertTrue(controller.showsActionBanner)
    }

    // MARK: The two keys that need text

    /// Fix and Rewrite are drawn off on an empty field and come back the moment
    /// there is anything to work on. Reply is deliberately not one of them —
    /// answering a message you have not started writing is the whole point of it.
    func testFixAndRewriteAreDisabledOnlyWhileTheFieldIsEmpty() {
        let controller = makeDirectEditController(text: "", engine: DirectEditEngine())

        XCTAssertTrue(controller.isActionKeyDisabled(.aiFix))
        XCTAssertTrue(controller.isActionKeyDisabled(.quickTone))
        XCTAssertFalse(controller.isActionKeyDisabled(.aiReply), "Reply needs no text")
        XCTAssertFalse(controller.isActionKeyDisabled(.dictation))

        controller.press(.character("h"))

        XCTAssertFalse(controller.isActionKeyDisabled(.aiFix), "one character is something to fix")
        XCTAssertFalse(controller.isActionKeyDisabled(.quickTone))
    }

    /// **Whitespace is not text.** A field holding a space is empty as far as these
    /// two are concerned, and the published mirror has to agree with
    /// `hasTextToWorkWith` about that or the key and the action disagree — which is
    /// D8's own defect, one surface believing something about the field that
    /// another does not.
    func testThePublishedMirrorAgreesWithTheActionsOwnQuestion() {
        for text in ["", " ", "\n", "hi", " hi "] {
            let controller = makeDirectEditController(text: text, engine: DirectEditEngine())
            XCTAssertEqual(
                controller.documentHasText, controller.hasTextToWorkWith,
                "the key and the action disagree about \"\(text)\"")
        }
    }
}

// MARK: - The dictation strip's trailing control

/// **What the slot beside a recording offers, in each of the three states
/// `.dictating` covers.**
///
/// A decision rather than a screenshot, for the reason `SuggestionBar.ToneTap` is
/// one: a button's action and a `.disabled()` modifier cannot be read back off a
/// SwiftUI view, so a control that renders and answers nothing looks exactly like
/// one that works. That is what shipped here — replacing the × with Pause drew a
/// live-looking Pause button over the *transcription*, where `pauseDictation()`
/// returns at its own guard because no utterance is open, and where the × had been
/// the only way to call the pending insert off.
final class DictationTrailingControlTests: XCTestCase {

    func testARunningRecordingOffersPause() {
        XCTAssertEqual(
            ActionBanner.dictationControl(isListening: true, isPaused: false), .pause)
    }

    func testAPausedRecordingOffersResume() {
        XCTAssertEqual(
            ActionBanner.dictationControl(isListening: false, isPaused: true), .resume)
    }

    /// The state between the stop tap and the words arriving: nothing is open, so
    /// there is nothing to pause, and Cancel is the last chance to stop the
    /// transcript landing in the document.
    func testATranscriptionOffersCancelRatherThanADeadPauseButton() {
        XCTAssertEqual(
            ActionBanner.dictationControl(isListening: false, isPaused: false), .cancel,
            "the strip draws Pause over a transcription, and the tap does nothing")
    }
}

// MARK: - Helpers

@MainActor
private func makeDirectEditController(
    text: String, engine: DirectEditEngine
) -> KeyboardController {
    KeyboardController(
        target: MockTextTarget(text: text),
        engine: RoutedIntelligence(onDevice: engine, cloud: nil))
}

/// An engine that answers with whatever the test told it to, so the assertions are
/// about where the answer lands rather than about what it says.
private final class DirectEditEngine: TextIntelligence, @unchecked Sendable {

    private let fixed: String
    private let rewritten: String
    private let lock = NSLock()
    private var released = true

    init(fixed: String = "", rewritten: String = "") {
        self.fixed = fixed
        self.rewritten = rewritten
    }

    /// Holds the next call open until `release()`, so a test can type into the
    /// field while the model is genuinely still thinking. Same shape as
    /// `ToneRecorder.hold()`.
    func hold() {
        lock.lock()
        released = false
        lock.unlock()
    }

    func release() {
        lock.lock()
        released = true
        lock.unlock()
    }

    private var isReleased: Bool {
        lock.lock()
        defer { lock.unlock() }
        return released
    }

    /// Bounded, so a mistake in a test times out rather than wedging the suite.
    private func waitForRelease() async {
        let deadline = Date().addingTimeInterval(5)
        while !isReleased, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func canHandle(_ text: String, action: AIAction) -> Bool { true }

    func fix(_ text: String) async throws -> String {
        await waitForRelease()
        return fixed.isEmpty ? text : fixed
    }

    func variants(
        for text: String, tone: ToneStyle?, instruction: String?
    ) async throws
        -> [RewriteVariant]
    {
        [RewriteVariant(tone: tone ?? .clearer, text: rewritten.isEmpty ? text : rewritten)]
    }

    func replies(to context: ScreenContext) async throws -> [ReplyOption] { [] }
}
