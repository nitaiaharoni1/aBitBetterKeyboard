import XCTest

@testable import AIKeyboardCore

/// Gesture-order tests extracted from `SpaceBarLanguageSwitchTests`.
@MainActor
final class SpaceBarGestureOrderTests: XCTestCase {

    private var saved = TypingSettings.snapshot()

    override func setUp() {
        super.setUp()
        saved = TypingSettings.snapshot()
        let store = SharedStore.shared
        store.enabledLanguages = [.english, .hebrew]
        store.autocorrect = true
        store.predictions = true
    }

    override func tearDown() {
        saved.restore()
        super.tearDown()
    }

    private func slide(_ controller: KeyboardController, _ points: CGFloat) {
        controller.spaceBarTouch(.began)
        controller.spaceBarTouch(.moved(points))
        controller.spaceBarTouch(.ended(points))
    }

    // MARK: Globe key

    /// One tap on the globe, one language enabled — the keyboard has nowhere of
    /// its own to go, so it hands the user over to iOS without changing the
    /// language or typing anything.
    func testGlobeWithOneLanguageHandsOver() {
        SharedStore.shared.enabledLanguages = [.english]
        let controller = KeyboardController(target: MockTextTarget(), language: .english)
        var handedOver = false
        controller.onAdvanceToNextKeyboard = { handedOver = true }

        controller.press(.globe)

        XCTAssertTrue(handedOver, "globe did not call onAdvanceToNextKeyboard with one language")
        XCTAssertEqual(
            controller.language, .english,
            "globe changed the language instead of handing over")
    }

    /// Multiple languages enabled — the globe cycles one step, the same step a
    /// slide makes, and never calls `onAdvanceToNextKeyboard`.
    func testGlobeWithMultipleLanguagesCycles() {
        let controller = KeyboardController(target: MockTextTarget(), language: .english)
        var handedOver = false
        controller.onAdvanceToNextKeyboard = { handedOver = true }

        controller.press(.globe)

        XCTAssertFalse(handedOver, "globe handed over instead of cycling with two languages")
        XCTAssertEqual(controller.language, .hebrew, "globe did not advance to the next language")
    }

    /// After the globe lands the space bar names the destination, the same way
    /// a completed swipe does — the only confirmation a user who pressed the
    /// globe key gets that the layout changed.
    func testGlobeNamesDestinationOnSpaceBar() {
        let controller = KeyboardController(target: MockTextTarget(), language: .english)

        controller.press(.globe)

        XCTAssertEqual(
            controller.languageSwitchIndication?.language, .hebrew,
            "globe tap did not name the destination on the space bar")
        XCTAssertEqual(
            controller.languageSwitchIndication?.isPending, false,
            "the space bar still shows a pending indication after the globe already landed")
    }

    // MARK: Orders a gesture recogniser is free to deliver

    func testALetterRollingOverAnOpenSpaceTouchLandsAfterTheSpace() {
        let target = MockTextTarget(text: "sched")
        let controller = KeyboardController(target: target, language: .english)
        controller.shift = .off
        guard let correction = controller.suggestions.first(where: \.isDefault)?.text,
            correction.lowercased() != "sched"
        else {
            return XCTFail(
                "Nothing was armed to replace \"sched\", so this proves nothing about the correction")
        }

        controller.spaceBarTouch(.began)
        controller.press(.character("t"))
        controller.spaceBarTouch(.ended(0))

        XCTAssertEqual(
            target.text, correction + " t",
            "The rolled-over letter landed before the space and took the correction with it")
    }

    func testADeleteRollingOverAnOpenSpaceTouchLandsAfterTheSpace() {
        let target = MockTextTarget(text: "sched")
        let controller = KeyboardController(target: target, language: .english)
        guard let correction = controller.suggestions.first(where: \.isDefault)?.text,
            correction.lowercased() != "sched"
        else { return XCTFail("Nothing was armed to replace \"sched\"") }

        controller.spaceBarTouch(.began)
        controller.press(.backspace)
        controller.spaceBarTouch(.ended(0))

        // **The answer is the original word, and that is the ordering working
        // rather than failing.** The space commits the swap and arms
        // `pendingAutocorrectUndo`; the delete that lands after it is therefore
        // the delete that takes the swap back, which is the documented rule at
        // `insertSpace` ("only this swap, if there was one, can be taken back by
        // the next delete") and the same thing a user gets by tapping space then
        // backspace deliberately.
        //
        // This asserted `correction` instead, which is what a delete that only
        // removed the trailing space would leave, and it predates the undo. It
        // had been failing on committed `main` against correct behaviour.
        //
        // The value still rejects both orderings this test exists to catch. A
        // delete that ran *before* the space would cut the word to `sche` and
        // commit whatever that suggests, and a delete that was dropped entirely
        // would leave `schedule ` with its trailing space. Only space-then-delete
        // lands back on the word the user actually typed.
        XCTAssertEqual(
            target.text, "sched",
            "the delete did not land after the space, so it did not take back the swap the space made")
        XCTAssertNotEqual(
            target.text, correction,
            "the delete removed only the space, so the swap it should have undone is still standing")
    }

    func testASecondTouchBeginningBeforeTheFirstEndsTypesOneSpace() {
        let target = MockTextTarget(text: "hi")
        let controller = KeyboardController(target: target, language: .english)

        controller.spaceBarTouch(.began)
        controller.spaceBarTouch(.began)
        controller.spaceBarTouch(.ended(0))

        XCTAssertEqual(target.text, "hi ", "Two overlapping touches typed \"\(target.text)\"")
    }

    func testALiftWithNoTouchBehindItTypesNothing() {
        let target = MockTextTarget(text: "hi")
        let controller = KeyboardController(target: target, language: .english)

        controller.spaceBarTouch(.ended(0))

        XCTAssertEqual(target.text, "hi")
    }

    func testALetterAfterACancelledSpaceTouchGetsNoSpace() {
        let target = MockTextTarget(text: "sched")
        let controller = KeyboardController(target: target, language: .english)
        controller.shift = .off

        controller.spaceBarTouch(.began)
        controller.spaceBarTouch(.cancelled)
        controller.press(.character("t"))

        XCTAssertEqual(
            target.text, "schedt",
            "A space touch iOS took away still typed a space in front of the next letter")
    }

    func testACancellationJustBeforeAPlainLiftStillTypesTheSpace() {
        let target = MockTextTarget(text: "hi")
        let controller = KeyboardController(target: target, language: .english)

        controller.spaceBarTouch(.began)
        controller.spaceBarTouch(.cancelled)
        controller.spaceBarTouch(.ended(0))

        XCTAssertEqual(
            target.text, "hi ",
            "An ordinary space tap typed nothing, because the cancellation landed before the lift")
    }

    func testASwipeReportedOnlyByItsLiftStillSwitches() {
        let target = MockTextTarget(text: "hi")
        let controller = KeyboardController(target: target, language: .english)

        controller.spaceBarTouch(.began)
        controller.spaceBarTouch(.ended(60))

        XCTAssertEqual(controller.language, .hebrew)
        XCTAssertEqual(
            target.text, "hi",
            "The swipe typed a space because no movement had been reported separately")
    }
}
