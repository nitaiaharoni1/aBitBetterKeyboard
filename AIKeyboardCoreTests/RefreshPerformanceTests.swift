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

    // MARK: Fix 7 — construction must not arm the refiner

    /// **`KeyboardController.init` calls `refreshSuggestions(schedulingRefinement:
    /// false)` rather than the plain call**, precisely so a controller built
    /// over a non-empty document does not start `PredictiveRefiner`'s 300ms
    /// clock before the first frame has even drawn. This is not reachable as a
    /// black-box "does construction avoid it" test, because `init` always
    /// builds its own refiner internally with no injection seam — a refiner
    /// swapped in afterwards cannot observe what happened during the call that
    /// already returned. What is tested instead is the mechanism `init` relies
    /// on: the parameter genuinely gates whether the refiner is ever asked.
    func testSchedulingRefinementFalseNeverReachesTheRefiner() {
        let target = CursorTextTarget(before: "hello there")
        let controller = KeyboardController(
            target: target, language: .english, isSystemKeyboard: true)
        let spy = CanPredictSpy()
        controller.refiner = PredictiveRefiner(onDevice: spy, apply: { _, _ in })

        controller.refreshSuggestions(schedulingRefinement: false)

        XCTAssertEqual(
            spy.canPredictCallCount, 0,
            "schedulingRefinement: false must never reach the refiner")

        controller.refreshSuggestions()

        XCTAssertGreaterThan(
            spy.canPredictCallCount, 0,
            "the default must still ask, or the guard above proves nothing")
    }

    /// The first frame still needs a populated bar: the playground and
    /// onboarding (`MockTextTarget`) read `controller.suggestions` off a
    /// freshly built controller with no explicit refresh of their own, and the
    /// production extension's own `viewDidLoad` does the same before
    /// `viewWillAppear` ever runs. `schedulingRefinement: false` only withholds
    /// the async tier; the local tier still scores the document.
    func testConstructionStillPopulatesTheBarWithoutTheRefiner() {
        let target = MockTextTarget(text: "hel")
        let controller = KeyboardController(target: target, language: .english)

        XCTAssertFalse(
            controller.suggestions.isEmpty,
            "a freshly built controller over a non-empty document must still "
                + "have scored it")
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
