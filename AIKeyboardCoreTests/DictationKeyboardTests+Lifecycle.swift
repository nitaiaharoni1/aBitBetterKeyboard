import Foundation
import XCTest

@testable import AIKeyboardCore

extension DictationKeyboardTests {
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
