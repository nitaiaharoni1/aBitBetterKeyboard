import XCTest

@testable import AIKeyboardCore

/// **Which of several things the banner says when more than one of them is
/// true.**
///
/// The strip above the suggestion bar is driven by published properties that
/// different code paths set and clear — `isWorking`, `aiError`, `variants`,
/// `replies`, `aiResultText`, `isDictating` — and a view that branched on them in
/// sequence would render whichever it happened to test first. `BannerState.resolve`
/// is the one ordered place that decides, so this is where the order is pinned.
///
/// **Two of those states no longer draw anything, and the order still matters for
/// them.** A running call is `WorkingProgressBar` and a live recording is the
/// microphone key; both resolve to the idle state here, and both have to keep
/// their place ahead of the branches below, or a recording started after a Fix
/// would put that Fix's leftover answer back on screen.
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

    /// **A recording draws no strip, and it still has to outrank everything under
    /// it.**
    ///
    /// Neither a recording nor a model call earns a row any more — one is on the
    /// microphone key, the other is `WorkingProgressBar` — so the interesting
    /// question is no longer which of the two is drawn. It is that a recording
    /// started while the previous action's answers are still in `options` must not
    /// let those answers back onto the screen: `resolve` reaches the option branch
    /// by falling through, and a recording that fell through with it would put a
    /// Use button over three replies from before the user started speaking.
    ///
    /// Asserting `!isPresented` is what rejects that build. Asserting `.hint`
    /// alone would not, because `.hint` is also what a *correct* fall-through to
    /// the idle branch produces.
    func testARecordingKeepsThePreviousAnswersOffTheScreen() {
        let state = resolve(
            isDictating: true, isWorking: true, runningAction: .rewrite, options: [reply])
        XCTAssertFalse(state.isPresented)
        XCTAssertEqual(state, .hint(BannerState.defaultHint))
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
    ///
    /// The words are in the field by the time this is asked — they were streamed
    /// there as they were spoken — so what this rejects is a "Nothing to insert"
    /// strip appearing over a sentence the user can see.
    func testATranscriptWinsOverAStaleFailure() {
        let state = resolve(
            isDictating: false, dictationIsLive: true, dictationTranscript: "hello",
            dictationFailure: "No speech")
        XCTAssertFalse(state.isPresented)
    }

    /// **Work outranks both a result and a failure**, because `beginWork` sets
    /// `isWorking` and clears `aiError` in the same breath: a retry must not flash
    /// the previous attempt's error, and must not show the previous action's
    /// answers under the new action's name.
    ///
    /// The shimmer that used to prove this is gone, so the assertion is that
    /// nothing at all is drawn — which the wrong ordering fails twice over, once
    /// with `.failed` and once with `.options`.
    func testWorkOutranksAStaleResultAndAStaleFailure() {
        let state = resolve(
            isWorking: true, runningAction: .fix, error: .refused, options: [reply])
        XCTAssertFalse(state.isPresented)
        XCTAssertEqual(state, .hint(BannerState.defaultHint))
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
    /// here: it is running in another process. A refusal is a sentence about a tap
    /// that did nothing, and it can wait — the alternative is a 69pt strip opening
    /// underneath somebody who has already started speaking.
    func testARecordingOutranksARefusal() {
        XCTAssertFalse(resolve(isDictating: true, block: noSession).isPresented)
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

    /// **A refusal outranks a call in flight, and this test used to claim the
    /// opposite of what `resolve` does.**
    ///
    /// It asserted `.working(.fix)` while `resolve` has tested `block` above
    /// `isWorking` since the refusals were converted from panels — so it was red,
    /// and nobody saw it, because the suite is not run on every change here. The
    /// two can only disagree on a state that `beginWork` makes unreachable (it
    /// clears `block` in the same breath as it sets `isWorking`), which is why a
    /// wrong answer cost nothing and went unnoticed.
    ///
    /// `resolve`'s order is the one kept: a refusal is a sentence about the tap the
    /// user just made, and the call it would be hidden behind now draws a progress
    /// bar rather than a strip, so there is nothing for it to compete with.
    func testARefusalOutranksACallInFlight() {
        XCTAssertEqual(
            resolve(isWorking: true, runningAction: .fix, block: noSession), .blocked(noSession))
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

    /// **What earns a row and what does not**, which is the whole of what this
    /// strip costs the keyboard.
    ///
    /// Two entries here changed direction rather than being added: a model call
    /// and a live recording used to present, and now do not. They are the two most
    /// frequent states in the feature, and both were spending 69 points of a
    /// 368-point keyboard on a word that a three-point progress bar and a red key
    /// say without moving anything. What survives is the set of states with a
    /// *sentence* in them.
    func testOnlyTheStatesWithSomethingToSayEarnARow() {
        XCTAssertFalse(resolve().isPresented)
        XCTAssertFalse(resolve(isWorking: true, runningAction: .fix).isPresented)
        XCTAssertFalse(resolve(isDictating: true).isPresented)

        XCTAssertTrue(resolve(runningAction: .rewrite, options: [reply]).isPresented)
        XCTAssertTrue(resolve(runningAction: .fix, error: .refused).isPresented)
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
