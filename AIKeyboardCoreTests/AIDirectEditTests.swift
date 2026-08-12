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
        XCTAssertEqual(controller.revertibleEdit?.undo, .spanAtCursor)

        controller.revertAIEdit()

        XCTAssertEqual(target.document, "hello there wrold friend")
    }

    /// **A reply landing in an empty field lights the keys that need text.**
    ///
    /// Reply is the one action that runs on an empty field, so this is the ordinary
    /// way a field goes from empty to full without a keystroke — and it takes
    /// `replaceTargetText`'s insert-only branch, the one branch there that used to
    /// skip `refreshSuggestions()`. Fix and Rewrite stayed drawn dim over a field
    /// holding a whole sentence until some later keystroke recomputed it.
    func testAReplyLandingInAnEmptyFieldLightsFixAndRewrite() {
        let controller = makeDirectEditController(text: "", engine: DirectEditEngine())
        XCTAssertTrue(controller.isActionKeyDisabled(.aiFix), "the state under test is empty")

        // What a reply does: `runReply` empties `aiSourceText` because a reply is
        // inserted rather than substituted, and `applyDirectly` writes it in.
        controller.aiSourceText = ""
        controller.applyDirectly("Thursday works for me", for: .reply)

        XCTAssertFalse(
            controller.isActionKeyDisabled(.aiFix),
            "Fix is still drawn dim over a field holding a whole sentence")
        XCTAssertFalse(controller.isActionKeyDisabled(.quickTone))
    }

    /// **A reply writes itself in now, and its undo takes back the reply and
    /// nothing else.**
    ///
    /// Reply was the last of the three actions still offering its answer behind a
    /// Use button, and it is the one with the most to lose from applying itself: it
    /// is *inserted* rather than substituted, so `aiSourceText` is deliberately
    /// empty and there is no "what was there before" to put back. A revert that
    /// took the whole-field path on that empty string would replace the user's
    /// entire message with nothing.
    func testAReplyIsInsertedAndItsUndoTakesBackOnlyTheReply() {
        let controller = makeDirectEditController(text: "see you ", engine: DirectEditEngine())

        controller.aiSourceText = ""
        controller.applyDirectly("Thursday works for me", for: .reply)

        XCTAssertEqual(controller.contextBefore, "see you Thursday works for me")
        XCTAssertEqual(
            controller.revertibleEdit?.undo, .spanAtCursor,
            "a reply replaced nothing, so its undo cannot be a whole-field one")

        controller.revertAIEdit()
        XCTAssertEqual(controller.contextBefore, "see you ")
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

    /// **A call already in flight when the microphone is tapped is dropped, and
    /// the alternative is the user's dictated message being replaced by a
    /// correction of what they had typed before it.**
    ///
    /// `run(_:)` refuses to start an action during a recording, which covers the
    /// tap that has not happened yet. This is the other half. The call keeps
    /// running, answers about the sentence as it was, and `applyDirectly` rightly
    /// refuses to apply it — the field has filled with spoken words since — so it
    /// falls through to the strip. The strip is suppressed for the length of the
    /// recording and comes back the instant it ends, with a Use button over a field
    /// the user has just dictated into. `aiSourceText` still holds the
    /// pre-recording sentence at that point, so accepting it takes the whole-field
    /// branch and deletes everything that was said.
    func testStartingARecordingDropsACallThatIsAlreadyRunning() async {
        let engine = DirectEditEngine(fixed: "I can't make the standup.")
        engine.hold()
        let target = MockTextTarget(text: "i cant make the standup")
        let controller = KeyboardController(
            target: target, engine: RoutedIntelligence(onDevice: engine, cloud: nil))

        controller.run(.fix)
        XCTAssertTrue(controller.isWorking, "the call never started")

        // What the microphone key does, minus the session this test has no
        // recorder for: `startDictation` reaches `cancelAIWork()` only on the path
        // where an utterance actually opened, so the call is made directly.
        controller.cancelAIWork()
        engine.release()
        await settleToneController(controller)

        XCTAssertFalse(controller.isWorking, "the progress bar runs for ever after a cancel")
        XCTAssertFalse(
            controller.showsActionBanner,
            "a Use button is on offer over a field the recording has since filled")
        XCTAssertTrue(controller.bannerOptions.isEmpty)
        XCTAssertEqual(
            controller.aiSourceText, "",
            "the pre-recording sentence is still standing as a whole-field replacement")
        XCTAssertEqual(target.text, "i cant make the standup", "the answer applied anyway")
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

// MARK: - The pause control beside the candidates

/// **What the suggestion bar offers beside a recording, in each of the four
/// states the microphone key can be in.**
///
/// A decision rather than a screenshot, for the reason `SuggestionBar.ToneTap` is
/// one: a button's action and a `.disabled()` modifier cannot be read back off a
/// SwiftUI view, so a control that renders and answers nothing looks exactly like
/// one that works. That is what shipped here once — a live-looking Pause button
/// drawn over the *transcription*, where `pauseDictation()` returns at its own
/// guard because no utterance is open.
///
/// The control moved out of the strip and into the bar with the strip's deletion,
/// and the defect did not move with it: `.finishing` is the same state and it
/// still has to answer nothing.
final class DictationBarControlTests: XCTestCase {

    func testARunningRecordingOffersPause() {
        XCTAssertEqual(
            SuggestionBar.dictationControl(for: .recording(secondsLeft: nil)), .pause)
        XCTAssertEqual(
            SuggestionBar.dictationControl(for: .recording(secondsLeft: 12)), .pause,
            "the countdown changed which control is offered")
    }

    func testAPausedRecordingOffersResume() {
        XCTAssertEqual(SuggestionBar.dictationControl(for: .paused), .resume)
    }

    /// The state between the stop tap and the words arriving: nothing is open, so
    /// there is nothing to pause. The microphone key is captioned Cancel there,
    /// which is what calls the pending insert off.
    func testATranscriptionOffersNothingRatherThanADeadPauseButton() {
        XCTAssertNil(
            SuggestionBar.dictationControl(for: .finishing),
            "the bar draws Pause over a transcription, and the tap does nothing")
    }

    func testNothingIsOfferedWhenNothingIsRunning() {
        XCTAssertNil(SuggestionBar.dictationControl(for: .idle))
    }
}

// MARK: - The microphone key

/// **What the one control this feature has left is showing.**
///
/// The strip that carried a waveform, a countdown, a Pause button and a Cancel
/// button is not drawn for a recording any more, so all of it is this key — and a
/// key that says the wrong thing about a live microphone is the worst mistake this
/// keyboard can make. `DictationKeyState` resolves it in one place so that a test
/// can ask, which is the whole reason it is a value rather than three `if`s inside
/// a `ViewBuilder`.
final class DictationKeyStateTests: XCTestCase {

    /// Red is reserved for a microphone that is keeping what it hears, and each of
    /// the other three states is a way of not being that.
    func testOnlyALiveMicrophoneIsDrawnInRed() {
        XCTAssertTrue(DictationKeyState.recording(secondsLeft: nil).isRecording)
        XCTAssertTrue(DictationKeyState.recording(secondsLeft: 5).isRecording)
        XCTAssertFalse(DictationKeyState.paused.isRecording, "a paused microphone is not listening")
        XCTAssertFalse(DictationKeyState.finishing.isRecording)
        XCTAssertFalse(DictationKeyState.idle.isRecording)
    }

    /// The lit cap covers one state more than the red one does. A key that went
    /// dark while the last words were in flight would be offering to start a second
    /// recording over the first one's answer.
    func testTheKeyStaysLitUntilTheWordsHaveLanded() {
        XCTAssertFalse(DictationKeyState.idle.isActive)
        XCTAssertTrue(DictationKeyState.recording(secondsLeft: nil).isActive)
        XCTAssertTrue(DictationKeyState.paused.isActive)
        XCTAssertTrue(DictationKeyState.finishing.isActive)
    }

    /// **The caption is what a tap does, and it may never say Dictate over a
    /// recording.** That is not hypothetical: the key was captioned from a single
    /// `isActionActive` flag before the strip was deleted, and a flag has two
    /// values where this has four.
    func testTheCaptionNamesTheStateRatherThanTheAction() {
        XCTAssertEqual(DictationKeyState.idle.title, "Dictate")
        XCTAssertEqual(DictationKeyState.recording(secondsLeft: nil).title, "Stop")
        XCTAssertEqual(DictationKeyState.paused.title, "Paused")
        XCTAssertEqual(DictationKeyState.finishing.title, "Cancel")
    }

    /// **Four appearances, four things said — and it used to be four appearances
    /// and one.**
    ///
    /// `KeyView`'s label comes from `KeyCap`, which is a value and cannot know a
    /// recording is running, so this key read "Dictate" to VoiceOver whether the
    /// microphone was idle, live, paused or finishing. Everything that told the
    /// four apart was a colour, a glyph and a nine-point caption. The one state
    /// where being wrong matters most is the one where a microphone is on.
    ///
    /// The split is the conventional one and worth keeping: the **label** is what
    /// a tap does, the **value** is the state. A countdown is not what a tap does,
    /// which is why the visible caption cannot serve as the label.
    func testEveryStateSaysSomethingDifferentOutLoud() {
        let states: [DictationKeyState] = [
            .idle, .recording(secondsLeft: nil), .recording(secondsLeft: 12), .paused, .finishing
        ]
        let spoken = states.map { "\($0.accessibilityLabel)|\($0.accessibilityValue)" }
        XCTAssertEqual(
            Set(spoken).count, states.count,
            "two states of a live microphone are indistinguishable to VoiceOver")

        XCTAssertEqual(DictationKeyState.idle.accessibilityLabel, "Dictate")
        XCTAssertEqual(
            DictationKeyState.recording(secondsLeft: nil).accessibilityLabel, "Stop recording",
            "the button that stops a live microphone offered to start one")
        XCTAssertEqual(DictationKeyState.paused.accessibilityLabel, "Stop recording")
        XCTAssertEqual(DictationKeyState.finishing.accessibilityLabel, "Cancel transcription")

        XCTAssertEqual(DictationKeyState.idle.accessibilityValue, "")
        XCTAssertEqual(DictationKeyState.recording(secondsLeft: nil).accessibilityValue, "Recording")
        XCTAssertEqual(
            DictationKeyState.recording(secondsLeft: 12).accessibilityValue,
            "Recording, 12 seconds left")
        XCTAssertEqual(DictationKeyState.paused.accessibilityValue, "Paused")
    }

    /// **The countdown survived the strip, and it is the one thing in it that had
    /// to.** A session closes itself, so without a warning a recording stops
    /// mid-sentence and nothing ever said it would.
    func testTheLastMinuteIsCountedOnTheKey() {
        XCTAssertEqual(DictationKeyState.recording(secondsLeft: 12).title, "12s left")
        XCTAssertEqual(
            DictationKeyState.recording(secondsLeft: nil).title, "Stop",
            "a clock running for the whole session is one the user is invited to watch")
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
