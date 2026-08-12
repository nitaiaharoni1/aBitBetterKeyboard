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

    /// **The gate's refusal has to reach the user, and must not reach the
    /// document.** This is the case the whole `SpeechGate` exists for: the model
    /// would have invented a sentence here.
    func testARecordingWithNoSpeechInItInsertsNothingAndSaysWhy() throws {
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
        XCTAssertEqual(controller.dictationFailure, SpeechGate.Verdict.silent.explanation)
        // **The banner has to say so, and the panel is no longer where it says
        // it.** A live session now reports above the suggestion bar so the keys
        // stay usable while speaking, which means the failed-recording sentence
        // moved there too. Asserting `dictationFailure` alone would not reject the
        // broken version: the property was always set correctly, and the defect
        // this guards against is nothing being *shown*.
        XCTAssertEqual(
            BannerState.resolve(
                isDictating: controller.isDictating,
                dictationIsLive: controller.dictationAvailability.isLive,
                dictationTranscript: controller.dictationTranscript,
                dictationFailure: controller.dictationFailure,
                dictationIsPaused: controller.dictationIsPaused,
                isWorking: controller.isWorking,
                runningAction: controller.runningAction,
                error: controller.aiError,
                block: controller.block,
                options: controller.bannerOptions,
                index: controller.bannerIndex,
                screenContext: nil,
                idleHint: BannerState.defaultHint),
            .dictationFailed(SpeechGate.Verdict.silent.explanation),
            "the banner has to say why nothing was inserted")

        // And the way out has to be one tap, on the button already under the
        // thumb: `SpeechGate` is tuned to refuse rather than risk an invented
        // sentence, so refusals are a normal part of using this.
        XCTAssertEqual(controller.dictationAvailability, .ready)
        controller.startDictation()
        XCTAssertTrue(controller.isDictating, "Try again did not reopen an utterance")
        XCTAssertEqual(controller.dictationFailure, "")
        XCTAssertEqual(recorder.request()?.utterance, utterance + 1)
    }

    func testAFailedTranscriptionInsertsNothingAndSaysWhy() throws {
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
        XCTAssertEqual(controller.dictationFailure, "The cloud model couldn't be reached.")
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

    /// **Live in every sense but the microphone's.** Pausing must not clear
    /// `isDictating` — the mic key is still the way to finish the recording —
    /// and once the recorder confirms the pause the session still has to read
    /// as live, or the banner would treat a paused recording as one that had
    /// ended.
    func testAPausedUtteranceIsStillLiveAndReadsAsPaused() throws {
        beginLiveSession()
        session.poll()
        controller.startDictation()
        let utterance = try XCTUnwrap(recorder.request()?.utterance)

        controller.pauseDictation()
        XCTAssertTrue(
            try XCTUnwrap(recorder.request()).isPaused, "the pause never reached the request page")
        XCTAssertTrue(
            try XCTUnwrap(recorder.request()).wantsRecording(),
            "pausing closed the utterance instead of only muting it")
        XCTAssertTrue(controller.isDictating, "pausing must not clear isDictating")

        // The recorder confirms the pause on its own poll; simulated here the
        // way every live-session test in this file stands in for
        // `DictationService`, by publishing the phase directly.
        recorder.setPhase(.paused, utterance: utterance)
        session.poll()

        XCTAssertEqual(controller.dictationAvailability, .paused)
        XCTAssertTrue(
            controller.dictationAvailability.isLive, "a paused session must still read as live")
        XCTAssertTrue(controller.dictationIsPaused)
    }

    /// Resuming clears the flag on the request page, and the recorder's own
    /// confirmation is what brings `availability` back to `.listening`.
    func testResumingAPausedUtteranceReadsAsListeningAgain() throws {
        beginLiveSession()
        session.poll()
        controller.startDictation()
        let utterance = try XCTUnwrap(recorder.request()?.utterance)
        controller.pauseDictation()
        recorder.setPhase(.paused, utterance: utterance)
        session.poll()
        XCTAssertTrue(controller.dictationIsPaused)

        controller.resumeDictation()
        XCTAssertFalse(try XCTUnwrap(recorder.request()).isPaused)

        recorder.setPhase(.listening, utterance: utterance)
        session.poll()

        XCTAssertEqual(controller.dictationAvailability, .listening)
        XCTAssertFalse(controller.dictationIsPaused)
    }

    /// **The banner has to tell "paused" and "transcribing" apart even though
    /// both read `isListening == false`.** `isPaused` is the field that
    /// carries the difference into the trailing control and the tag.
    func testTheBannerReadsPauseSeparatelyFromTranscribing() throws {
        beginLiveSession()
        session.poll()
        controller.startDictation()
        let utterance = try XCTUnwrap(recorder.request()?.utterance)
        controller.pauseDictation()
        recorder.setPhase(.paused, utterance: utterance)
        session.poll()

        XCTAssertEqual(
            BannerState.resolve(
                isDictating: controller.isDictating,
                dictationIsLive: controller.dictationAvailability.isLive,
                dictationTranscript: controller.dictationTranscript,
                dictationFailure: controller.dictationFailure,
                dictationIsPaused: controller.dictationIsPaused,
                isWorking: controller.isWorking,
                runningAction: controller.runningAction,
                error: controller.aiError,
                block: controller.block,
                options: controller.bannerOptions,
                index: controller.bannerIndex,
                screenContext: nil,
                idleHint: BannerState.defaultHint),
            .dictating(transcript: "", isListening: false, isPaused: true))
    }

    /// **The microphone key both starts and finishes a recording now.** A tap
    /// with nothing live opens an utterance; a second tap finishes it and
    /// asks for an insert, exactly as `stopDictation(insert: true)` always
    /// has — `toggleDictation` is what the key calls for both halves.
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

    /// A recording that is paused when the microphone key finishes it still
    /// asks the recorder to stop — pausing must not be a way to strand an
    /// utterance the mic key can no longer close.
    func testTogglingOffAPausedRecordingStillRequestsAStop() throws {
        beginLiveSession()
        session.poll()
        controller.startDictation()
        let utterance = try XCTUnwrap(recorder.request()?.utterance)
        controller.pauseDictation()
        recorder.setPhase(.paused, utterance: utterance)
        session.poll()

        controller.toggleDictation()
        XCTAssertFalse(controller.isDictating)
        XCTAssertEqual(recorder.request()?.stopUtterance, utterance)
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
        XCTAssertEqual(
            controller.block?.detail,
            "The dictation session timed out. Open AI Keyboard, tap Start dictation, then come back.",
            "the refusal has to name the ending, which it can only do from a fresh read")
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
                dictationTranscript: controller.dictationTranscript,
                dictationFailure: controller.dictationFailure,
                dictationIsPaused: controller.dictationIsPaused,
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
