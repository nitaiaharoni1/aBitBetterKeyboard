import XCTest

@testable import AIKeyboardCore

/// **Which of six things the banner says when more than one of them is true.**
///
/// The strip above the suggestion bar is driven by six published properties that
/// different code paths set and clear — `isWorking`, `aiError`, `variants`,
/// `replies`, `aiResultText`, `isDictating` — and a view that branched on them in
/// sequence would render whichever it happened to test first. `BannerState.resolve`
/// is the one ordered place that decides, so this is where the order is pinned.
///
/// Every case here is written to reject a plausible wrong ordering rather than to
/// restate the implementation.
final class BannerStateTests: XCTestCase {

    private let reply = BannerOption(label: "AGREE", text: "sure", language: .english)

    private func resolve(
        isDictating: Bool = false,
        dictationIsLive: Bool = false,
        dictationTranscript: String = "",
        dictationFailure: String = "",
        isWorking: Bool = false,
        runningAction: AIAction? = nil,
        error: AIEngineError? = nil,
        block: BannerState.Block? = nil,
        options: [BannerOption] = [],
        index: Int = 0,
        screenContext: ScreenContext? = nil,
        idleHint: String = BannerState.defaultHint
    ) -> BannerState {
        BannerState.resolve(
            isDictating: isDictating,
            dictationIsLive: dictationIsLive,
            dictationTranscript: dictationTranscript,
            dictationFailure: dictationFailure,
            isWorking: isWorking,
            runningAction: runningAction,
            error: error,
            block: block,
            options: options,
            index: index,
            screenContext: screenContext,
            idleHint: idleHint)
    }

    // MARK: Ordering

    /// **A recording outranks a model call**, because it is running in another
    /// process and stopping it is the time-critical thing on screen. A version that
    /// tested `isWorking` first would hide the Stop button behind a shimmer.
    func testARecordingOutranksAModelCall() {
        let state = resolve(
            isDictating: true, isWorking: true, runningAction: .rewrite)
        XCTAssertEqual(state, .dictating(transcript: "", isListening: true))
    }

    /// **A failed recording is reported even though `isDictating` is already
    /// false.** `stopDictation` clears the flag before the reason arrives, so a
    /// failure tested after the live check is a failure never shown — the waveform
    /// vanishes and the user gets no text and no explanation.
    func testAFailedRecordingIsReportedAfterTheFlagIsCleared() {
        let state = resolve(
            isDictating: false, dictationIsLive: true, dictationFailure: "No speech")
        XCTAssertEqual(state, .dictationFailed("No speech"))
    }

    /// A transcript that landed is not a failure, whatever is left in the reason.
    func testATranscriptWinsOverAStaleFailure() {
        let state = resolve(
            isDictating: false, dictationIsLive: true, dictationTranscript: "hello",
            dictationFailure: "No speech")
        XCTAssertEqual(state, .dictating(transcript: "hello", isListening: false))
    }

    /// **Work outranks both a result and a failure**, because `beginWork` sets
    /// `isWorking` and clears `aiError` in the same breath: a retry must not flash
    /// the previous attempt's error, and must not show the previous action's
    /// answers under the new action's name.
    func testWorkOutranksAStaleResultAndAStaleFailure() {
        let state = resolve(
            isWorking: true, runningAction: .fix, error: .refused, options: [reply])
        XCTAssertEqual(state, .working(.fix))
    }

    /// A failure outranks options, because a failed call can leave the previous
    /// action's answers in place.
    func testAFailureOutranksOptions() {
        guard
            case .failed(let action, _, _) = resolve(
                runningAction: .reply, error: .refused, options: [reply])
        else { return XCTFail("a failure was not reported") }
        XCTAssertEqual(action, .reply)
    }

    // MARK: A refusal

    private let noSession = BannerState.Block(
        action: .reply,
        title: "Screen context is off",
        detail: "Tap to pick AI Keyboard, then Start Broadcast.",
        remedy: .broadcastPicker)

    /// **A recording outranks a refusal**, for the reason it outranks everything else
    /// here: it is running in another process and stopping it is the time-critical
    /// thing on screen. A refusal is a sentence about a tap that did nothing, and it
    /// can wait.
    func testARecordingOutranksARefusal() {
        let state = resolve(isDictating: true, block: noSession)
        XCTAssertEqual(state, .dictating(transcript: "", isListening: true))
    }

    /// **A refusal outranks the idle hint**, which is the ordering the whole case
    /// exists for. Resolved the other way, the user taps Reply with no session and the
    /// strip goes on reading "Type, or pick an action below" — which is exactly what
    /// the build before this one did, under a panel that covered the keys.
    func testARefusalOutranksTheIdleHint() {
        XCTAssertEqual(resolve(block: noSession), .blocked(noSession))
    }

    /// **A refusal outranks a live screen-context reading.** The idle branch prefers
    /// the reading over the hint, so without this a refusal about Reply would be drawn
    /// as the very message it just refused to answer — the one wrong answer here that
    /// looks like a right one.
    func testARefusalOutranksAScreenContextReading() {
        let context = ScreenContext(
            appName: "WhatsApp", appIcon: "message", sender: "Dana", message: "מה קורה",
            language: .hebrew)
        XCTAssertEqual(resolve(block: noSession, screenContext: context), .blocked(noSession))
    }

    /// **A refusal does not survive the next call.** `beginWork` clears it, so a state
    /// carrying both is unreachable — but `resolve` is the one place that decides, and
    /// a version testing `block` after `isWorking` would leave a stale refusal under a
    /// running shimmer the day that clearing regressed.
    func testWorkOutranksARefusal() {
        XCTAssertEqual(
            resolve(isWorking: true, runningAction: .fix, block: noSession), .working(.fix))
    }

    // MARK: The empty answer

    /// **An action that finished, threw nothing and produced nothing must say so.**
    /// The version that fell through to the idle hint left the user tapping Fix,
    /// watching a shimmer, and ending on a keyboard that looked untouched.
    func testAnActionThatProducedNothingIsReportedRatherThanIgnored() {
        guard case .failed(let action, let title, _) = resolve(runningAction: .fix)
        else { return XCTFail("an empty answer fell through to the idle hint") }
        XCTAssertEqual(action, .fix)
        XCTAssertFalse(title.isEmpty)
    }

    /// **And nothing silences it any more.** Two tests lived here about a panel
    /// owning the answer: `resolve` took a `resultsShownElsewhere` flag and stood
    /// down when `AIMenuPanel`'s Tone row ran a rewrite into `AIResultPanel`, and
    /// `ActionBanner.resultPanelIsOpen` decided when that was true. Both panels are
    /// deleted and the strip is the only place an answer can go, so the flag, the
    /// function and the two tests all went with them. The branch they guarded is
    /// what `testAnActionThatProducedNothingIsReportedRatherThanIgnored` above now
    /// reaches unconditionally.

    // MARK: Idle

    /// A live reading is the idle state that earns the banner its height. This is
    /// what `ScreenContextStrip` used to occupy a separate row to say.
    func testALiveReadingIsTheIdleState() {
        let context = ScreenContext(
            appName: "", appIcon: "", sender: "Dani", message: "when?", language: .hebrew)
        XCTAssertEqual(
            resolve(screenContext: context),
            .context(sender: "Dani", message: "when?", language: .hebrew))
    }

    /// With no action and no reading, whatever the caller wants said. Screen
    /// context's own sentence comes through here — see
    /// `KeyboardController.screenContextHint`.
    func testTheHintIsWhateverTheCallerPassed() {
        XCTAssertEqual(resolve(idleHint: "Screen context is paused"), .hint("Screen context is paused"))
    }

    /// **The idle instruction does not earn a row.** A version that kept the
    /// banner up for `.hint` would still spend 48 pt teaching the user what the
    /// action row already says by existing.
    func testTheIdleHintDoesNotPresentTheBanner() {
        XCTAssertFalse(resolve().isPresented)
        XCTAssertTrue(resolve(isWorking: true, runningAction: .fix).isPresented)
        XCTAssertTrue(resolve(runningAction: .rewrite, options: [reply]).isPresented)
        XCTAssertTrue(resolve(runningAction: .fix, error: .refused).isPresented)
        XCTAssertTrue(resolve(isDictating: true).isPresented)
        XCTAssertTrue(resolve(block: noSession).isPresented)
        XCTAssertTrue(
            resolve(
                dictationIsLive: true,
                dictationFailure: "No speech"
            ).isPresented)
        let context = ScreenContext(
            appName: "", appIcon: "", sender: "Dani", message: "when?", language: .hebrew)
        XCTAssertTrue(resolve(screenContext: context).isPresented)
    }

    /// The action-row highlight names the action the banner is reporting, and a
    /// live reading lights nothing — it is not something the user started.
    func testTheActiveActionKeyMatchesWhatTheBannerIsReporting() {
        XCTAssertEqual(
            resolve(isWorking: true, runningAction: .reply).activeActionKey, .ai(.reply))
        XCTAssertEqual(
            resolve(runningAction: .rewrite, options: [reply]).activeActionKey,
            .ai(.rewrite))
        XCTAssertEqual(
            resolve(runningAction: .fix, error: .refused).activeActionKey,
            .ai(.fix))
        XCTAssertEqual(
            resolve(isWorking: true, runningAction: .tone).activeActionKey,
            .ai(.tone))
        XCTAssertEqual(
            resolve(isDictating: true).activeActionKey, .dictation)
        XCTAssertEqual(
            resolve(block: noSession).activeActionKey, .ai(.reply))
        let noDictationSession = BannerState.Block(
            action: nil,
            title: "Dictation is not ready",
            detail: "Start a session in the app.",
            remedy: .none)
        XCTAssertEqual(
            resolve(block: noDictationSession).activeActionKey, .dictation)
        XCTAssertEqual(
            resolve(
                dictationIsLive: true,
                dictationFailure: "No speech"
            ).activeActionKey,
            .dictation)
        XCTAssertNil(resolve().activeActionKey)
        let context = ScreenContext(
            appName: "", appIcon: "", sender: "Dani", message: "when?", language: .hebrew)
        XCTAssertNil(resolve(screenContext: context).activeActionKey)
    }

    /// An index left over from an action with more answers must not read past the
    /// end of a shorter one.
    func testTheIndexIsClampedToTheOptionsItHas() {
        guard
            case .options(_, _, let index) = resolve(
                runningAction: .reply, options: [reply], index: 7)
        else { return XCTFail("options were not reported") }
        XCTAssertEqual(index, 0)
    }
}
