import Foundation
import XCTest

@testable import AIKeyboardCore
@testable import AIKeyboardShared

/// Dictation as the keyboard experiences it, driven through `KeyboardController`
/// rather than through the session underneath it.
///
/// **Written against what the broken version did, not against what the fixed one
/// does.** For the whole of this feature's life `startDictation()` played
/// `MockDictation`'s word list on a timer: half a second later the transcript
/// was non-empty and Insert typed a Hebrew sentence nobody had said, into
/// whatever field was focused. Every assertion below is chosen so that build
/// would fail it — which is the lesson three earlier tests in this repo learned
/// the hard way, each having passed against the bug it was named after.
@MainActor
final class DictationKeyboardTests: XCTestCase {

    private var directory: URL!
    private var recorder: DictationChannelWriter!
    private var session: DictationSession!
    private var target: MockTextTarget!
    private var controller: KeyboardController!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictation-kb-\(UUID().uuidString)", isDirectory: true)
        recorder = try XCTUnwrap(DictationChannelWriter(directory: directory))
        session = DictationSession(reader: DictationChannelReader(directory: directory))
        target = MockTextTarget()
        controller = KeyboardController(target: target, dictation: session)
    }

    override func tearDownWithError() throws {
        controller = nil
        session = nil
        recorder = nil
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: No session

    /// The state a stock install is in every time until the user opens the app.
    ///
    /// **The explanation moved from a panel to the banner, and it still has to be an
    /// explanation.** With no session running, the keyboard offers an "Open AI
    /// Keyboard" button rather than a dead end — the host wires `onOpenContainingApp`
    /// to do the actual opening. Asserting the block alone would pass against the build
    /// that set one *and* opened `DictationPanel` over every key, so the overlay is
    /// asserted with it.
    func testWithNoSessionTheBannerExplainsAndNothingIsDictated() async throws {
        controller.startDictation()

        XCTAssertEqual(controller.overlay, .none, "the keys must stay visible")
        XCTAssertNil(controller.block?.action, "dictation is not an AIAction")
        XCTAssertTrue(
            controller.block?.detail.contains("swipe back") ?? false,
            "the way out is not described: \(controller.block?.detail ?? "nothing was said")")
        if case .openApp(let url) = controller.block?.remedy {
            XCTAssertEqual(url, SharedStore.dictationStartURL, "remedy must carry the dictation URL")
        } else {
            XCTFail(
                "expected .openApp remedy for noSession, got \(String(describing: controller.block?.remedy))")
        }
        XCTAssertFalse(controller.isDictating)
        guard case .noSession = controller.dictationAvailability else {
            return XCTFail("expected noSession, got \(controller.dictationAvailability)")
        }

        // Longer than the scripted version took to put its first four words on
        // screen. It filled the transcript 500 ms in and finished inside two
        // seconds; anything non-empty here is that build.
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertEqual(
            controller.dictationTranscript, "",
            "something is producing a transcript without a recording")
    }

    /// **The host callback fires on the first no-session tap**, not only when the
    /// banner button is tapped. The banner `Link` is a second user-tapped path;
    /// this pins the automatic one so a build that records the request but never
    /// calls the callback leaves the user staring at the blocked strip with no
    /// app opening.
    func testNoSessionTapImmediatelyRequestsHandoffURL() {
        var openedURLs: [URL] = []
        controller.onOpenContainingApp = { openedURLs.append($0) }

        controller.startDictation()

        XCTAssertEqual(openedURLs.count, 1, "exactly one open request on the first no-session tap")
        XCTAssertEqual(
            openedURLs.first, SharedStore.dictationStartURL,
            "the URL must be the stable dictation start deep link")
    }

    /// **A refusal from a session that closed itself must not resurface on the
    /// next one.** `dictation.$failure` only ever sets `dictationFailure`, and the
    /// Dismiss button that clears it is drawn only while a session is live — so a
    /// failure the user never dismissed sat in the property, and the next live
    /// session brought it straight back on screen attached to a recording that had
    /// not failed. `startDictation` resets it before the availability guard, which
    /// is where it always was until the guard moved above it.
    ///
    /// Asserting `dictationFailure == ""` alone would not reject that build: it is
    /// empty on a fresh controller too. The failure has to be *put there* first,
    /// which is what the first line does.
    func testAStaleFailureDoesNotSurviveTheNextTapOnTheMicrophone() {
        controller.dictationFailure = "I didn't catch that"

        controller.startDictation()

        XCTAssertEqual(
            controller.dictationFailure, "",
            "a refusal from an earlier session is still on the controller")
    }

    /// The half that reaches the user's document, asserted separately: a panel
    /// that shows invented words is bad, and a panel that *types* them is the
    /// actual harm.
    func testWithNoSessionInsertTypesNothing() async throws {
        controller.startDictation()
        try await Task.sleep(for: .milliseconds(900))
        controller.stopDictation(insert: true)
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(target.text, "", "text reached the document with no recording behind it")
    }

    // MARK: A live session

    private func beginLiveSession() -> UUID {
        recorder.begin(seconds: 900, microphoneAuthorized: true)
    }

    func testWithALiveSessionTappingTheMicrophoneOpensAnUtterance() {
        beginLiveSession()
        session.poll()

        controller.startDictation()
        XCTAssertTrue(controller.isDictating)
        XCTAssertEqual(controller.dictationAvailability, .listening)
        XCTAssertEqual(recorder.request()?.utterance, 1)
        XCTAssertTrue(recorder.request()?.wantsRecording() ?? false)
    }

    /// The whole round trip: speak, stop, the app answers, the words land in the
    /// document.
    func testATranscriptIsInsertedWhenItArrives() throws {
        let id = beginLiveSession()
        session.poll()
        controller.startDictation()
        let utterance = try XCTUnwrap(recorder.request()?.utterance)

        controller.stopDictation(insert: true)
        XCTAssertEqual(target.text, "", "nothing may be inserted before the words exist")

        recorder.setPhase(.idle)
        try recorder.publish(
            DictationTranscriptRecord(
                sessionID: id, utterance: utterance, text: "בוא נעשה sync על ה-roadmap",
                languages: "he,en", recordedAt: 1, completedAt: 2, seconds: 3))
        session.poll()

        XCTAssertEqual(target.text, "בוא נעשה sync על ה-roadmap")
        XCTAssertEqual(controller.overlay, .none, "the panel should close once the words are in")
        XCTAssertEqual(controller.language, .english, "the keys did not move")
        XCTAssertEqual(
            controller.hostLanguage, .hebrew,
            "WhatsApp follows hostLanguage, not the keys. Leaving it English is a mixed Hebrew sentence stuck on the left."
        )
        // Not incidental: this exact sentence has ten Hebrew letters and eleven
        // Latin ones, so a direction decided by counting letters lays it out
        // left to right. See `KeyboardController.isRightToLeft`.
        XCTAssertTrue(controller.dictationIsRightToLeft)
        XCTAssertFalse(
            SuggestionEngine.languages(in: "בוא נעשה sync על ה-roadmap").first?.isRightToLeft == true,
            "the letter count no longer gets this backwards, so the fix above is now untested")
    }

    /// The keyboard is inserting into a document somebody was already typing in.
    func testASpaceIsAddedWhenTheDocumentNeedsOne() throws {
        target.text = "Hi,"
        let id = beginLiveSession()
        session.poll()
        controller.startDictation()
        let utterance = try XCTUnwrap(recorder.request()?.utterance)
        controller.stopDictation(insert: true)

        try recorder.publish(
            DictationTranscriptRecord(
                sessionID: id, utterance: utterance, text: "I'll send it tomorrow",
                recordedAt: 1, completedAt: 2, seconds: 3))
        session.poll()

        XCTAssertEqual(target.text, "Hi, I'll send it tomorrow")
    }

    /// **The gate's refusal must not reach the document, and it must not raise a
    /// strip either.** This is the case the whole `SpeechGate` exists for: the
    /// model would have invented a sentence here. "Nothing to insert" used to
    /// say why; a second tap is the recovery now, and a 69pt row for it was the
    /// banner coming back for a case the microphone key already settled.
    func testARecordingWithNoSpeechInItInsertsNothingAndShowsNoBanner() throws {
        let id = beginLiveSession()
        session.poll()
        controller.startDictation()
        let utterance = try XCTUnwrap(recorder.request()?.utterance)
        controller.stopDictation(insert: true)

        try recorder.publish(
            DictationTranscriptRecord(
                sessionID: id, utterance: utterance, outcome: .nothing, text: "",
                detail: SpeechGate.Verdict.silent.explanation, recordedAt: 1, completedAt: 2,
                seconds: 1))
        session.poll()

        XCTAssertEqual(target.text, "")
        XCTAssertEqual(
            controller.dictationFailure, "",
            "a silent take still raised Nothing to insert")
        XCTAssertFalse(
            controller.bannerState.isPresented,
            "the banner has to stay down: a silent take is a second tap, not a strip")

        // Try again still works: `refresh()` re-reads the live session the
        // sink stopped watching.
        controller.startDictation()
        XCTAssertTrue(controller.isDictating, "Try again did not reopen an utterance")
        XCTAssertEqual(recorder.request()?.utterance, utterance + 1)
    }

    func testAFailedTranscriptionInsertsNothingAndShowsNoBanner() throws {
        let id = beginLiveSession()
        session.poll()
        controller.startDictation()
        let utterance = try XCTUnwrap(recorder.request()?.utterance)
        controller.stopDictation(insert: true)

        try recorder.publish(
            DictationTranscriptRecord(
                sessionID: id, utterance: utterance, outcome: .failed, text: "",
                detail: "The cloud model couldn't be reached.", recordedAt: 1, completedAt: 2,
                seconds: 3))
        session.poll()

        XCTAssertEqual(target.text, "")
        XCTAssertEqual(controller.dictationFailure, "")
        XCTAssertFalse(controller.bannerState.isPresented)
    }

    // MARK: Streaming

    /// **The whole streaming path, both processes, through the real channel.**
    ///
    /// Everything else about streaming is unit-tested against the controller
    /// directly, which cannot see the half that crosses the App Group: a partial
    /// written by the recorder, noticed through `DictationState.partialSequence`,
    /// decoded, matched to this keyboard's own utterance, and put into the field.
    /// Each reading replaces the last, and the final transcript replaces all of
    /// them — a build that appended instead would leave the field holding four
    /// versions of one sentence and would pass any assertion about the last words
    /// having arrived.
    func testPartialsLandInTheFieldAndTheTranscriptReplacesThem() throws {
        let id = beginLiveSession()
        session.poll()
        controller.startDictation()
        let utterance = try XCTUnwrap(recorder.request()?.utterance)

        try recorder.publishPartial(
            DictationPartialRecord(
                sessionID: id, utterance: utterance, sequence: 1, text: "hi", seconds: 1.5))
        session.poll()
        XCTAssertEqual(target.text, "hi", "the first reading never reached the field")
        XCTAssertEqual(controller.hostLanguage, .english)

        try recorder.publishPartial(
            DictationPartialRecord(
                sessionID: id, utterance: utterance, sequence: 2, text: "hi mami", seconds: 3.5))
        session.poll()
        XCTAssertEqual(target.text, "hi mami", "the second reading was appended to the first")

        controller.stopDictation(insert: true)
        try recorder.publish(
            DictationTranscriptRecord(
                sessionID: id, utterance: utterance, text: "Hi Mami, what's up?",
                recordedAt: 1, completedAt: 2, seconds: 4))
        session.poll()

        XCTAssertEqual(target.text, "Hi Mami, what's up?")
        XCTAssertNil(controller.revertibleEdit)
    }

    /// **The microphone tap must not rewrite what is already in the field.**
    /// The old tap called `stopDictation(insert: true)`, waited for the cloud
    /// sentence, and replaced the live words with it. That is the "fix" this
    /// test is named against: after a partial, a second tap just stops, and a
    /// transcript that arrives anyway is ignored.
    func testAStopAfterStreamingKeepsTheDraftAndIgnoresTheTranscript() throws {
        let id = beginLiveSession()
        session.poll()
        controller.toggleDictation()
        let utterance = try XCTUnwrap(recorder.request()?.utterance)

        try recorder.publishPartial(
            DictationPartialRecord(
                sessionID: id, utterance: utterance, sequence: 1, text: "hi mami",
                seconds: 2))
        session.poll()
        XCTAssertEqual(target.text, "hi mami")

        controller.toggleDictation()
        XCTAssertEqual(
            controller.dictationKeyState, .idle,
            "a stop after streaming still waited for a cloud rewrite")
        XCTAssertEqual(
            recorder.request()?.cancelUtterance, utterance,
            "the second tap asked the recorder to transcribe instead of just stop")
        XCTAssertEqual(target.text, "hi mami")

        try recorder.publish(
            DictationTranscriptRecord(
                sessionID: id, utterance: utterance, text: "Hi Mami, what's up?",
                recordedAt: 1, completedAt: 2, seconds: 4))
        session.poll()

        XCTAssertEqual(
            target.text, "hi mami",
            "the cloud sentence still replaced the live words after stop")
    }

    /// The first partial is what WhatsApp lays out. Languages have to be on
    /// `transcriptLanguages` before that text is published: counting letters in
    /// this sentence says Latin, and a host that is still English parks it on
    /// the left until the final transcript arrives.
    func testAMixedHebrewPartialTellsTheHostBeforeTheWordsLand() throws {
        let id = beginLiveSession()
        session.poll()
        controller.startDictation()
        let utterance = try XCTUnwrap(recorder.request()?.utterance)

        try recorder.publishPartial(
            DictationPartialRecord(
                sessionID: id, utterance: utterance, sequence: 1,
                text: "בוא נעשה sync על ה-roadmap", languages: "he,en", seconds: 1.5))
        session.poll()

        XCTAssertEqual(target.text, "בוא נעשה sync על ה-roadmap")
        XCTAssertEqual(controller.language, .english, "the keys did not move")
        XCTAssertEqual(
            controller.hostLanguage, .hebrew,
            "the first partial is what the host lays out, and letter-counting this sentence is English")
        XCTAssertTrue(controller.dictationIsRightToLeft)
    }

    /// **Nothing edits the field while it is still being spoken into.**
    ///
    /// Fix over a half-finished message replaces the whole field with a correction
    /// of it; `streamedDictation` then points at text that is no longer there, the
    /// transcript that lands a second later cannot find its draft, and the user
    /// ends up with two versions of one sentence. Reply is in the list too, even
    /// though it is the action that deliberately needs no text, because it inserts
    /// at the caret — which is exactly where the next reading is about to go.
    ///
    /// The keys are drawn off, which is where the user is told, and `run(_:)`
    /// guards as well: the register popup and the bar's one-tap button reach it
    /// without going through a key.
    func testTheTextActionsAreOffForTheLengthOfARecording() throws {
        target.text = "hello wrold"
        beginLiveSession()
        session.poll()
        controller.refreshSuggestions()
        XCTAssertFalse(controller.isActionKeyDisabled(.aiFix), "the state under test is wrong")

        controller.startDictation()

        XCTAssertTrue(controller.isActionKeyDisabled(.aiFix))
        XCTAssertTrue(controller.isActionKeyDisabled(.quickTone))
        XCTAssertTrue(
            controller.isActionKeyDisabled(.aiReply),
            "a reply would insert at the caret the next reading is about to use")
        XCTAssertEqual(
            controller.actionKeyDisabledReason(.aiFix), "Not while you're dictating",
            "the words behind the dim cap still say to type something first")

        controller.run(.fix)
        XCTAssertFalse(controller.isWorking, "a route that is not a key started a call anyway")

        // **The one-tap rewrite key does not go through `run(_:)`, and a guard
        // written only there would have covered two actions while reading as though
        // it covered three.** `press(.quickTone)` calls `runDefaultTone()` and the
        // register popup calls `selectTone(named:)`; both reach `runTone(_:)`
        // instead, which is where the second copy of the guard lives.
        controller.runDefaultTone()
        XCTAssertFalse(controller.isWorking, "the one-tap rewrite route is not guarded")
        controller.selectTone(.shorter)
        XCTAssertFalse(controller.isWorking, "the register popup is not guarded")
        controller.selectFix(named: FixStyle.spelling.title)
        XCTAssertFalse(controller.isWorking, "the Fix popup is not guarded")

        XCTAssertNil(controller.revertibleEdit)
        XCTAssertEqual(target.text, "hello wrold")

        controller.stopDictation(insert: false)
        XCTAssertFalse(controller.isActionKeyDisabled(.aiFix), "the keys never came back")
    }

    /// **A partial belonging to an utterance this keyboard is not listening to is
    /// ignored**, which is the same defence `testATranscriptFromAPreviousSessionIsNotInserted`
    /// makes one level down. A partial is published every couple of seconds rather
    /// than once, so there are far more chances for one to arrive late.
    func testAPartialFromAnotherUtteranceIsNotStreamed() throws {
        let id = beginLiveSession()
        session.poll()
        controller.startDictation()
        let utterance = try XCTUnwrap(recorder.request()?.utterance)

        try recorder.publishPartial(
            DictationPartialRecord(
                sessionID: id, utterance: utterance &+ 1, sequence: 1, text: "somebody else",
                seconds: 2))
        session.poll()

        XCTAssertEqual(target.text, "")
    }

    /// **A transcription that fails after the words are already in the field says
    /// nothing, and it still has to stop the poll.**
    ///
    /// Not raising "Nothing to insert" over a sentence the user can see is the easy
    /// half — the trap is what falls out of it. Leaving `dictationFailure` empty is
    /// also what makes `stopDictation` return at its own guard, so unless this path
    /// stops the watch itself nothing ever does, **not even the keyboard being
    /// dismissed** — and a `RunLoop` timer in a dismissed keyboard goes on
    /// refreshing `DictationRequest.keyboardAliveAt`, which is exactly the one thing
    /// that defeats the dead-man's switch holding the microphone open in the other
    /// process. `.noSession(.notEnded)` is reachable here only through
    /// `stopWatching()`; the build that skips it leaves `.ready` behind.
    func testAFailureAfterStreamingIsSilentAndStillStopsTheWatch() throws {
        let id = beginLiveSession()
        session.poll()
        controller.startDictation()
        let utterance = try XCTUnwrap(recorder.request()?.utterance)

        try recorder.publishPartial(
            DictationPartialRecord(
                sessionID: id, utterance: utterance, sequence: 1, text: "hi mami", seconds: 2))
        session.poll()
        XCTAssertEqual(target.text, "hi mami", "nothing was streamed, so this proves nothing")

        controller.stopDictation(insert: true)
        try recorder.publish(
            DictationTranscriptRecord(
                sessionID: id, utterance: utterance, outcome: .failed, text: "",
                detail: "The cloud model couldn't be reached.", recordedAt: 1, completedAt: 2,
                seconds: 3))
        session.poll()

        XCTAssertEqual(target.text, "hi mami", "the words the user said were taken away")
        XCTAssertEqual(
            controller.dictationFailure, "",
            "a refusal was raised over a sentence standing in the field")
        XCTAssertFalse(controller.showsActionBanner)
        XCTAssertEqual(
            controller.dictationAvailability, .noSession(.notEnded),
            "the poll outlived the recording, and it is what keeps the microphone alive")
    }

    /// **The second half of the same defence the recorder makes.** A transcript
    /// can outlive the session it was recorded in — a stop and a restart inside
    /// the couple of seconds a transcription takes is all it needs — and the
    /// utterance number alone does not rule it out, because the keyboard's
    /// counter is not reset by a new session. Matching the session as well is
    /// what stops a sentence from before being typed into whatever the user is
    /// writing now.
    func testATranscriptFromAPreviousSessionIsNotInserted() throws {
        let old = beginLiveSession()
        session.poll()
        controller.startDictation()
        let utterance = try XCTUnwrap(recorder.request()?.utterance)
        controller.stopDictation(insert: true)

        // A new session, and the keyboard opens the same utterance number in it —
        // which it does, because `begin()` resets the recorder's page and not the
        // keyboard's.
        recorder.begin(seconds: 900, microphoneAuthorized: true)
        session.poll()
        try recorder.publish(
            DictationTranscriptRecord(
                sessionID: old, utterance: utterance, text: "said in the session before",
                recordedAt: 1, completedAt: 2, seconds: 3))
        session.poll()

        XCTAssertEqual(
            target.text, "", "a transcript from an ended session reached the document")
    }

    /// Cancel means cancel: the utterance is withdrawn so the recorder drops the
    /// audio rather than transcribing and publishing it.
    func testCancellingWithdrawsTheUtterance() throws {
        beginLiveSession()
        session.poll()
        controller.startDictation()

        controller.stopDictation(insert: false)
        XCTAssertFalse(controller.isDictating)
        XCTAssertFalse(try XCTUnwrap(recorder.request()).wantsRecording())
    }

    func testSendWhileRecordingDoesNotInsertTheTranscript() throws {
        let id = beginLiveSession()
        session.poll()
        controller.startDictation()
        let utterance = try XCTUnwrap(recorder.request()?.utterance)

        try recorder.publishPartial(
            DictationPartialRecord(
                sessionID: id, utterance: utterance, sequence: 1, text: "hi", seconds: 1.5))
        session.poll()
        XCTAssertFalse(target.text.isEmpty, "nothing was streamed, so emptying proves nothing")
        XCTAssertTrue(controller.isDictating)

        target.text = ""
        controller.refreshSuggestions()

        XCTAssertFalse(controller.isDictating)

        try recorder.publish(
            DictationTranscriptRecord(
                sessionID: id, utterance: utterance, text: "hi there",
                recordedAt: 1, completedAt: 2, seconds: 3))
        session.poll()

        XCTAssertEqual(target.text, "", "the cloud sentence landed in a field the host had emptied")
    }

    func testSendWhileFinishingDoesNotInsertTheTranscript() throws {
        let id = beginLiveSession()
        session.poll()
        controller.startDictation()
        let utterance = try XCTUnwrap(recorder.request()?.utterance)

        try recorder.publishPartial(
            DictationPartialRecord(
                sessionID: id, utterance: utterance, sequence: 1, text: "hi", seconds: 1.5))
        session.poll()
        XCTAssertFalse(target.text.isEmpty, "nothing was streamed, so emptying proves nothing")

        controller.stopDictation(insert: true)
        target.text = ""
        controller.refreshSuggestions()

        try recorder.publish(
            DictationTranscriptRecord(
                sessionID: id, utterance: utterance, text: "hi there",
                recordedAt: 1, completedAt: 2, seconds: 3))
        session.poll()

        XCTAssertEqual(target.text, "", "a finishing insert typed a sent message back")
    }

    func testBackspaceToEmptyKeepsTheRecording() throws {
        let id = beginLiveSession()
        session.poll()
        controller.startDictation()
        let utterance = try XCTUnwrap(recorder.request()?.utterance)

        try recorder.publishPartial(
            DictationPartialRecord(
                sessionID: id, utterance: utterance, sequence: 1, text: "hi", seconds: 1.5))
        session.poll()
        XCTAssertFalse(target.text.isEmpty, "nothing was streamed, so the delete proves nothing")

        controller.deletePreviousWord()
        XCTAssertEqual(target.text, "")
        XCTAssertTrue(
            controller.isDictating,
            "backspace-to-empty stopped the recording as if it were Send")
    }

    /// **`dismissOverlay()` calls `stopDictation` on every panel close**, so
    /// closing the emoji grid used to take the channel's write lock and bump a
    /// sequence in a shared page. It must do nothing at all when dictation was
    /// never up.
    func testClosingAnUnrelatedPanelWritesNothingToTheChannel() throws {
        beginLiveSession()
        session.poll()

        controller.overlay = .emoji
        controller.dismissOverlay()
        XCTAssertEqual(recorder.request()?.utterance, 0, "an unrelated panel opened an utterance")
        XCTAssertEqual(recorder.request()?.cancelUtterance, 0)
    }

    /// The dead-man's switch only works if the keyboard stops refreshing it, and
    /// a `RunLoop` timer in a dismissed keyboard does not stop on its own —
    /// `KeyboardViewController.viewWillDisappear` calls this.
    func testLeavingTheKeyboardWithdrawsAnOpenUtterance() throws {
        beginLiveSession()
        session.poll()
        controller.startDictation()
        XCTAssertTrue(try XCTUnwrap(recorder.request()).wantsRecording())

        controller.stopDictation(insert: false)
        XCTAssertFalse(
            try XCTUnwrap(recorder.request()).wantsRecording(),
            "the microphone would have stayed open for a keyboard nobody can see")
    }

    /// A session that stopped between the tap and the answer must not leave the
    /// panel claiming to listen.
    func testASessionThatDiesMidUtteranceIsReportedAsGone() throws {
        beginLiveSession()
        session.poll()
        controller.startDictation()
        XCTAssertTrue(controller.isDictating)

        recorder.end(.interrupted)
        session.poll()

        XCTAssertEqual(controller.dictationAvailability, .noSession(.interrupted))
        XCTAssertEqual(target.text, "")
    }

    // MARK: Pause and resume

    /// **The microphone key both starts and finishes a recording now.** A tap
    /// with nothing live opens an utterance; a second tap with nothing streamed
    /// still asks for an insert, because that is the only copy of the words.
    /// `toggleDictation` is what the key calls for both halves.
    func testToggleDictationStartsThenFinishesWithInsert() throws {
        let id = beginLiveSession()
        session.poll()

        controller.toggleDictation()
        XCTAssertTrue(controller.isDictating, "toggling with nothing live should start a recording")
        let utterance = try XCTUnwrap(recorder.request()?.utterance)

        controller.toggleDictation()
        XCTAssertFalse(controller.isDictating, "a second tap should finish the recording")
        XCTAssertEqual(
            recorder.request()?.stopUtterance, utterance,
            "the second tap did not ask the recorder to stop")

        try recorder.publish(
            DictationTranscriptRecord(
                sessionID: id, utterance: utterance, text: "noted",
                recordedAt: 1, completedAt: 2, seconds: 1))
        session.poll()

        XCTAssertEqual(target.text, "noted", "toggling must still insert what was said")
    }

    /// **A third tap used to cancel, and the tap before that used to start a
    /// second recording.** Between pause and the words arriving, `isDictating` is
    /// already false. Asking only that question opened a new utterance on top of
    /// the first one's transcription; the × that replaced it cancelled the insert.
    /// The tap is ignored now: record and pause, nothing else.
    func testATapWhileTheWordsAreInFlightDoesNotCancelOrStartAgain() throws {
        let id = beginLiveSession()
        session.poll()
        controller.toggleDictation()
        let utterance = try XCTUnwrap(recorder.request()?.utterance)

        controller.toggleDictation()
        XCTAssertEqual(controller.dictationKeyState, .finishing)

        controller.toggleDictation()
        XCTAssertEqual(
            recorder.request()?.utterance, utterance,
            "a tap while transcribing opened a second utterance")
        XCTAssertNotEqual(
            recorder.request()?.cancelUtterance ?? 0, utterance,
            "a tap while transcribing cancelled the insert")
        XCTAssertEqual(controller.dictationKeyState, .finishing)

        try recorder.publish(
            DictationTranscriptRecord(
                sessionID: id, utterance: utterance, text: "noted",
                recordedAt: 1, completedAt: 2, seconds: 1))
        session.poll()
        XCTAssertEqual(target.text, "noted", "the ignored tap threw the sentence away")
    }

    /// **The waveform is the open microphone, not the transcription in flight.**
    /// `dictationKeyState.isRecording` stays true through `.finishing` so the
    /// key does not flash Record. Activity follows `isDictating`, so pause
    /// leaves the pause icon and no bars.
    func testTheWaveformHidesTheMomentPauseIsTapped() throws {
        beginLiveSession()
        session.poll()
        controller.toggleDictation()
        recorder.setLevel(0.1)
        session.poll()
        XCTAssertFalse(
            controller.dictationLevels.isEmpty, "the recording never reached the waveform")

        controller.toggleDictation()
        XCTAssertEqual(controller.dictationKeyState, .finishing)
        XCTAssertEqual(
            KeyActivity.resolve(for: .dictation, controller: controller),
            .idle,
            "the waveform stayed up while the last words were in flight")
        XCTAssertTrue(
            controller.dictationLevels.isEmpty,
            "frozen levels kept the last waveform drawn through finishing")
    }

    /// **`$level` is Equatable and drops a held note.** The waveform is a history
    /// of polls, not of changes; three identical bars and a pause is a dashed
    /// line that does not move.
    func testTheWaveformKeepsASampleWhenLoudnessDoesNotChange() {
        beginLiveSession()
        session.poll()
        controller.startDictation()
        XCTAssertTrue(controller.isDictating)

        recorder.setLevel(0.1)
        session.poll()
        let count = controller.dictationLevels.count
        XCTAssertGreaterThan(count, 0, "the first poll after speaking did not reach the waveform")

        recorder.setLevel(0.1)
        session.poll()
        XCTAssertEqual(
            controller.dictationLevels.count, count + 1,
            "a held note dropped samples and the strip froze")
    }

    // MARK: The tap has to read the page

    /// **The one live-session test here with no `session.poll()` before the tap,
    /// and that absence is the whole test.** Every case above polls by hand
    /// first — the one thing the shipping keyboard never does, and so the reason
    /// a defect that refused *every* tap on a real phone passed all of them.
    /// `availability` is only written by a poll; the poll was started two lines
    /// below the check that reads it, and the refusal returned before reaching
    /// it. So the check read the `.noSession(.notEnded)` a fresh `DictationSession`
    /// carries, the microphone key answered "No dictation session" over a session
    /// running in the app, and it went on answering it for as long as the keyboard
    /// was up.
    func testTheFirstTapFindsASessionNobodyHasPolledFor() {
        beginLiveSession()

        controller.startDictation()

        XCTAssertTrue(
            controller.isDictating,
            "the first tap refused a live session: \(controller.block?.detail ?? "no reason given")")
        XCTAssertNil(controller.block, "a live session must not produce a refusal")
        XCTAssertEqual(controller.dictationAvailability, .listening)
        XCTAssertEqual(recorder.request()?.utterance, 1)
        XCTAssertTrue(recorder.request()?.wantsRecording() ?? false)
    }

    /// The other end of the same cache, and it fails the old build for the
    /// opposite reason — so the `session.poll()` below is deliberate, to warm
    /// availability the way the tests above do and leave this test about the
    /// *second* tap.
    ///
    /// `stopWatching()` used to leave whatever the last poll saw in place, and the
    /// transcript sink calls it the moment the words land. `.ready` outlived the
    /// session it described, the next tap walked through a guard about a session
    /// that could have been gone for an hour, and `beginUtterance` answers a
    /// number whether or not a recorder exists — so the keyboard showed Listening,
    /// the speech went nowhere, and no transcript could arrive to say so.
    func testATapAfterTheSessionDiedRefusesInsteadOfRecordingIntoNothing() throws {
        beginLiveSession()
        session.poll()
        controller.startDictation()
        controller.stopDictation(insert: false)

        recorder.end(.expired)
        controller.startDictation()

        XCTAssertFalse(
            controller.isDictating, "an utterance was opened in a session that had ended")
        XCTAssertFalse(
            try XCTUnwrap(recorder.request()).wantsRecording(),
            "the recorder was asked to record for a session no process is holding")
        // **The reason by symbol, not by copy, and only the half this test is
        // about.** It pinned the whole sentence and went red the day the second
        // half was rewritten — a copy edit is not this defect. What the stale
        // `.ready` build gets wrong is the *reason*: with no fresh read there is
        // nothing to explain the ending with, so `dictationRefusalDetail` prints
        // the ordinary "no session" sentence and this prefix is absent. The
        // remedy sentence after it is asserted where it belongs, on the refusal
        // test at the top of this file.
        XCTAssertTrue(
            controller.block?.detail.hasPrefix(DictationEndReason.expired.explanation) ?? false,
            "the refusal has to name the ending, which it can only do from a fresh read: "
                + (controller.block?.detail ?? "nothing was said"))
    }

    /// **The same stale `.ready`, where the user actually saw it.**
    /// `BannerState.resolve` reads `dictationIsLive`, so after the words were
    /// inserted the strip went on showing the sentence already in the document —
    /// over a microphone tag, hiding the screen-context line and the idle hint,
    /// until the next tap on the microphone. Asserting the availability alone
    /// would not reject that build for the right reason; the banner is the thing
    /// that was wrong.
    func testTheBannerLetsGoOfDictationOnceTheWordsAreIn() throws {
        let id = beginLiveSession()
        controller.startDictation()
        let utterance = try XCTUnwrap(recorder.request()?.utterance)
        controller.stopDictation(insert: true)

        recorder.setPhase(.idle)
        try recorder.publish(
            DictationTranscriptRecord(
                sessionID: id, utterance: utterance, text: "on my way",
                recordedAt: 1, completedAt: 2, seconds: 3))
        session.poll()

        XCTAssertEqual(target.text, "on my way")
        XCTAssertFalse(
            controller.dictationAvailability.isLive,
            "the keyboard still claims a session it stopped watching")
        XCTAssertEqual(
            BannerState.resolve(
                isDictating: controller.isDictating,
                dictationIsLive: controller.dictationAvailability.isLive,
                isWorking: controller.isWorking,
                runningAction: controller.runningAction,
                error: controller.aiError,
                block: controller.block,
                options: controller.bannerOptions,
                index: controller.bannerIndex,
                screenContext: nil,
                idleHint: BannerState.defaultHint),
            .hint(BannerState.defaultHint),
            "the strip stayed on a sentence that is already in the document")
    }
}
