import XCTest

@testable import AIKeyboardCore

/// Two costs `refreshSuggestions` and `applyRefinement` used to spend on
/// nothing: a model call armed on every keyboard construction (NIT-191), and a
/// full republish of the bar whenever a refiner cache hit reproduced exactly
/// what was already on screen.
@MainActor
final class RefreshPerformanceTests: XCTestCase {

    private var predictions = true

    override func setUp() {
        super.setUp()
        predictions = SharedStore.shared.predictions
        SharedStore.shared.predictions = true
    }

    override func tearDown() {
        SharedStore.shared.predictions = predictions
        super.tearDown()
    }

    // MARK: Fix 7 — real extension construction must stay inert

    /// Activation performs one local, non-refining refresh. A refiner injected
    /// before that boundary must survive, and must remain idle until a later
    /// ordinary refresh.
    func testSchedulingRefinementFalseNeverReachesTheRefiner() {
        let target = CursorTextTarget(before: "hello there")
        let controller = KeyboardController(
            target: target, language: .english, isSystemKeyboard: true)
        let spy = CanPredictSpy()
        controller.refiner = PredictiveRefiner(onDevice: spy, apply: { _, _ in })

        controller.activateSuggestionWorkAfterPresentation()

        XCTAssertEqual(
            spy.canPredictCallCount, 0,
            "schedulingRefinement: false must never reach the refiner")

        controller.refreshSuggestions()

        XCTAssertGreaterThan(
            spy.canPredictCallCount, 0,
            "the default must still ask, or the guard above proves nothing")
    }

    /// App previews remain eager because they are not under the extension's
    /// launch deadline.
    func testNonSystemConstructionStillPopulatesTheBar() {
        let target = MockTextTarget(text: "hel")
        let controller = KeyboardController(target: target, language: .english)

        XCTAssertFalse(
            controller.suggestions.isEmpty,
            "a freshly built controller over a non-empty document must still "
                + "have scored it")
    }

    /// The real extension must draw before any local dictionary or model work.
    /// Activation is the explicit boundary that fills the bar afterwards.
    func testSystemConstructionWaitsForPresentationBeforeScoring() {
        let target = MockTextTarget(text: "hel")
        let controller = KeyboardController(
            target: target, language: .english, isSystemKeyboard: true)

        XCTAssertTrue(
            controller.suggestions.isEmpty,
            "a real keyboard must not score its document during construction")

        controller.activateSuggestionWorkAfterPresentation()

        XCTAssertFalse(
            controller.suggestions.isEmpty,
            "post-presentation activation must fill the local suggestion bar")
    }

    func testSystemSuggestionsStayInertWhileSuspendedAndReactivate() {
        let target = MockTextTarget(text: "hel")
        let controller = KeyboardController(
            target: target, language: .english, isSystemKeyboard: true)
        controller.activateSuggestionWorkAfterPresentation()
        XCTAssertFalse(controller.suggestions.isEmpty)

        controller.suspendSuggestionWork()
        XCTAssertTrue(controller.suggestions.isEmpty)
        controller.refreshSuggestions()
        XCTAssertTrue(controller.suggestions.isEmpty)

        controller.activateSuggestionWorkAfterPresentation()
        XCTAssertFalse(controller.suggestions.isEmpty)
    }

    // MARK: Fix 8 — applyRefinement must not republish when nothing changed

    /// **Guarded the same way `refreshSuggestions` already guards its own
    /// publish.** A refiner cache hit answers synchronously, so a single
    /// keystroke's 2-3 refreshes could each re-arm and re-answer the same
    /// question, and without this guard every one of them republished
    /// `suggestions` — a rebuild of every key — even when the merge reproduced
    /// exactly what was already on screen.
    func testApplyRefinementDoesNotRepublishWhenNothingChanged() {
        let controller = KeyboardController(target: CursorTextTarget(before: "hel"))
        // Slot 0 is the typed keystrokes and already not default; the model's
        // own answer ("hello") is already the bar's default, in slot 1 — so a
        // correctly-processed refinement reproduces this exact array.
        let seeded = [
            Suggestion(text: "hel", language: .english),
            Suggestion(text: "hello", language: .english, isDefault: true)
        ]
        controller.suggestions = seeded

        var publishCount = 0
        let cancellable = controller.$suggestions
            .dropFirst()
            .sink { _ in publishCount += 1 }
        defer { cancellable.cancel() }

        controller.applyRefinement(["hello"], for: "hel")

        XCTAssertEqual(
            controller.suggestions, seeded,
            "the merge should reproduce what was already on screen: "
                + "\(controller.suggestions.map(\.text))")
        XCTAssertEqual(
            publishCount, 0,
            "a refinement that changes nothing must not republish the bar")
    }
}

/// A `TextPrediction` that counts every synchronous `canPredict` call, which
/// is what `PredictiveRefiner.shouldRefine` asks before it ever schedules the
/// 300ms wait — a call this spy can observe without waiting on the wait
/// itself.
private final class CanPredictSpy: TextPrediction, @unchecked Sendable {
    private(set) var canPredictCallCount = 0

    func canPredict(in language: KeyboardLanguage) -> Bool {
        canPredictCallCount += 1
        return true
    }

    func continuations(
        after text: String, replyingTo context: ScreenContext?, language: KeyboardLanguage
    ) async throws -> [String] {
        []
    }
}
