import Foundation
import XCTest

@testable import AIKeyboardCore
@testable import AIKeyboardShared

/// The dictation channel's protocol, driven from both ends.
///
/// **What this proves and what it does not.** Both ends run in this process
/// against a temporary directory, because the test target carries no App Group
/// entitlement — the same arrangement `CaptureChannelTests` uses. So it proves
/// the *protocol*: the sequencing, the liveness rules, the dead-man's switch,
/// and that a transcript is matched to the tap that asked for it. It cannot
/// prove two processes share a page; a process always sees its own writes. That
/// half is `Scripts/prove-dictation.sh`, which reads a line out of the log
/// emitted by the process that did *not* write it.
final class DictationChannelTests: XCTestCase {

    private var directory: URL!
    private var recorder: DictationChannelWriter!
    private var keyboard: DictationChannelReader!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictation-\(UUID().uuidString)", isDirectory: true)
        recorder = try XCTUnwrap(DictationChannelWriter(directory: directory))
        keyboard = DictationChannelReader(directory: directory)
    }

    override func tearDownWithError() throws {
        recorder = nil
        keyboard = nil
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Liveness

    /// The starting state, and the one the keyboard has to render as an
    /// explanation rather than a spinner.
    func testAChannelNothingHasRunAgainstIsNotAlive() {
        let state = keyboard.state()
        XCTAssertEqual(state?.sessionID, nil)
        XCTAssertFalse(state?.isAlive() ?? true)
    }

    func testASessionIsAliveOnceItBeginsAndHeartbeats() {
        let id = recorder.begin(seconds: 900, microphoneAuthorized: true)
        let state = keyboard.state()
        XCTAssertEqual(state?.sessionID, id)
        XCTAssertTrue(state?.isAlive() ?? false)
        XCTAssertTrue(state?.isMicrophoneAuthorized ?? false)
    }

    /// **The single most load-bearing rule in the page.** iOS jetsams a
    /// backgrounded app without running any of its code, so `phase` stays
    /// `listening` and `endReason` stays `notEnded` while the microphone has
    /// been gone for a minute. Only a stopped heartbeat says so.
    ///
    /// Asserted by advancing *now* rather than by sleeping, so the test is not a
    /// three-second wait and cannot flake on a loaded machine.
    func testASessionWhoseHeartbeatStoppedIsNotAlive() throws {
        recorder.begin(seconds: 900, microphoneAuthorized: true)
        recorder.setPhase(.listening, utterance: 1)
        let state = try XCTUnwrap(keyboard.state())

        // Measured from the heartbeat the page actually carries, not from
        // `now()`: the microseconds between `begin` and this line would
        // otherwise push the "just inside" case over the window and fail a
        // correct implementation.
        XCTAssertTrue(state.isAlive(now: state.heartbeatAt + DictationState.heartbeatWindow - 1))
        XCTAssertFalse(
            state.isAlive(now: state.heartbeatAt + DictationState.heartbeatWindow + 1),
            "a page still saying phase=listening was read as a live session")
        // And the phase really does still claim to be listening, or the
        // assertion above would pass for the wrong reason.
        XCTAssertEqual(state.phase, .listening)
        XCTAssertEqual(state.endReason, .notEnded)
    }

    /// Expiry on its own, with the heartbeat held fresh at the same instant —
    /// otherwise this would pass on a stale heartbeat and prove nothing about
    /// expiry at all.
    func testAnExpiredSessionIsNotAlive() throws {
        recorder.begin(seconds: 900, microphoneAuthorized: true)
        let expiresAt = try XCTUnwrap(keyboard.state()).expiresAt

        // The heartbeat is written fresh at each instant, so the only thing
        // differing between the two assertions is the expiry. Writing it once,
        // in the future, would make both fail — `CaptureClock.elapsed` reads a
        // timestamp ahead of now as infinitely old on purpose.
        recorder.heartbeat(now: expiresAt - 1)
        XCTAssertTrue(try XCTUnwrap(keyboard.state()).isAlive(now: expiresAt - 1))

        recorder.heartbeat(now: expiresAt + 1)
        XCTAssertFalse(try XCTUnwrap(keyboard.state()).isAlive(now: expiresAt + 1))
    }

    func testEndingASessionRecordsWhyAndStopsItBeingAlive() {
        recorder.begin(seconds: 900, microphoneAuthorized: true)
        recorder.end(.interrupted)
        let state = keyboard.state()
        XCTAssertEqual(state?.endReason, .interrupted)
        XCTAssertFalse(state?.isAlive() ?? true)
    }

    // MARK: Utterances

    func testAnUtteranceIsOpenedClosedAndAnswered() throws {
        let id = recorder.begin(seconds: 900, microphoneAuthorized: true)

        let utterance = keyboard.beginUtterance()
        XCTAssertEqual(utterance, 1)
        XCTAssertTrue(try XCTUnwrap(recorder.request()).wantsRecording())

        keyboard.stopUtterance()
        XCTAssertFalse(try XCTUnwrap(recorder.request()).wantsRecording())

        try recorder.publish(
            DictationTranscriptRecord(
                sessionID: id, utterance: utterance, text: "שלחתי לך את ה-document",
                languages: "he,en", recordedAt: 1, completedAt: 2, seconds: 3))

        let record = try XCTUnwrap(keyboard.transcript())
        XCTAssertEqual(record.utterance, utterance)
        XCTAssertEqual(record.text, "שלחתי לך את ה-document")
        XCTAssertEqual(keyboard.state()?.completedUtterance, utterance)
    }

    /// **The answer to the previous tap is not an answer.** The keyboard matches
    /// on its own number precisely so a transcript left over from the utterance
    /// before cannot be inserted into a field the user has since moved on from.
    func testATranscriptFromAnEarlierUtteranceDoesNotMatchTheCurrentOne() throws {
        let id = recorder.begin(seconds: 900, microphoneAuthorized: true)
        let first = keyboard.beginUtterance()
        try recorder.publish(
            DictationTranscriptRecord(
                sessionID: id, utterance: first, text: "the first thing said",
                recordedAt: 1, completedAt: 2, seconds: 1))

        let second = keyboard.beginUtterance()
        XCTAssertEqual(second, first + 1)
        XCTAssertEqual(keyboard.transcript()?.utterance, first)
        XCTAssertNotEqual(keyboard.transcript()?.utterance, second)
    }

    /// The dead-man's switch. A keyboard extension is killed rather than
    /// dismissed all the time, and an utterance left open by one is a microphone
    /// recording for nobody.
    func testAnOpenUtteranceStopsWantingAudioWhenTheKeyboardGoesQuiet() throws {
        recorder.begin(seconds: 900, microphoneAuthorized: true)
        keyboard.beginUtterance()
        let request = try XCTUnwrap(recorder.request())

        XCTAssertTrue(request.wantsRecording())
        let later = CaptureClock.now() + DictationRequest.keyboardWindow + 1
        XCTAssertFalse(
            request.wantsRecording(now: later),
            "a recording stayed open for a keyboard that had stopped answering")
    }

    func testCancellingAnUtteranceStopsIt() throws {
        recorder.begin(seconds: 900, microphoneAuthorized: true)
        keyboard.beginUtterance()
        keyboard.cancelUtterance()
        XCTAssertFalse(try XCTUnwrap(recorder.request()).wantsRecording())
    }

    // MARK: The transcript on disk

    /// A privacy rule, not tidiness: the shared container is backed up, and a
    /// transcript is a sentence somebody dictated.
    func testEndingASessionRemovesTheTranscript() throws {
        let id = recorder.begin(seconds: 900, microphoneAuthorized: true)
        try recorder.publish(
            DictationTranscriptRecord(
                sessionID: id, utterance: 1, text: "something private",
                recordedAt: 1, completedAt: 2, seconds: 1))
        XCTAssertNotNil(keyboard.transcript())

        recorder.end(.stoppedByUser)
        XCTAssertNil(keyboard.transcript())
    }

    func testPublishingAfterTheSessionEndedIsRefused() {
        let id = recorder.begin(seconds: 900, microphoneAuthorized: true)
        recorder.end(.stoppedByUser)
        XCTAssertThrowsError(
            try recorder.publish(
                DictationTranscriptRecord(
                    sessionID: id, utterance: 1, text: "landed too late",
                    recordedAt: 1, completedAt: 2, seconds: 1)))
        XCTAssertNil(keyboard.transcript())
    }

    /// The ending the recorder never sees: a jetsam kill leaves the transcript
    /// on disk with nothing to delete it, so the reader sweeps it.
    func testATranscriptWhoseSessionDiedIsSweptByTheReader() throws {
        let id = recorder.begin(seconds: 900, microphoneAuthorized: true)
        try recorder.publish(
            DictationTranscriptRecord(
                sessionID: id, utterance: 1, text: "outlived its session",
                recordedAt: 1, completedAt: 2, seconds: 1))

        let afterTheHeartbeatStopped = CaptureClock.now() + DictationState.heartbeatWindow + 1
        XCTAssertTrue(keyboard.discardTranscriptOfADeadSession(now: afterTheHeartbeatStopped))
        XCTAssertNil(keyboard.transcript())
    }

    func testALiveSessionsTranscriptIsNotSwept() throws {
        let id = recorder.begin(seconds: 900, microphoneAuthorized: true)
        try recorder.publish(
            DictationTranscriptRecord(
                sessionID: id, utterance: 1, text: "still current",
                recordedAt: 1, completedAt: 2, seconds: 1))
        XCTAssertFalse(keyboard.discardTranscriptOfADeadSession())
        XCTAssertNotNil(keyboard.transcript())
    }

    // MARK: Levels

    /// Per mille as an integer, because every bit pattern in a shared page has
    /// to be a value: a `Double` read mid-write can be a NaN.
    func testLevelSurvivesThePageAsAnInteger() {
        recorder.begin(seconds: 900, microphoneAuthorized: true)
        recorder.setLevel(0.4567)
        XCTAssertEqual(keyboard.state()?.level ?? 0, 0.457, accuracy: 0.001)

        recorder.setLevel(.nan)
        XCTAssertEqual(keyboard.state()?.level, 0)
        recorder.setLevel(50)
        XCTAssertEqual(keyboard.state()?.level, 1, "an out-of-range level was not clamped")
    }

    // MARK: Pages

    /// Both structs are memcpy'd through a fixed-size page, so a field added
    /// without widening the page is a `precondition` crash on a device rather
    /// than here. `SharedPage.init` asserts it; this is the cheaper alarm.
    func testBothStructsStillFitTheirPages() {
        XCTAssertLessThanOrEqual(
            MemoryLayout<DictationState>.size + 8, DictationChannel.statePageBytes)
        XCTAssertLessThanOrEqual(
            MemoryLayout<DictationRequest>.size + 8, DictationChannel.requestPageBytes)
    }
}
