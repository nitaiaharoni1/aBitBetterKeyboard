import XCTest

@testable import AIKeyboardCore

/// Globe-key and gesture-order tests extracted from `SpaceBarLanguageSwitchTests`.
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

    // MARK: The globe, which the swipe is an addition to and not a replacement for

    func testTheGlobeStillHandsOverWhenOnlyOneLanguageIsEnabled() {
        SharedStore.shared.enabledLanguages = [.english]
        let controller = KeyboardController(target: MockTextTarget(), language: .english)
        var handedOver = false
        controller.onAdvanceToNextKeyboard = { handedOver = true }

        controller.press(.globe)

        XCTAssertTrue(handedOver)
        XCTAssertEqual(controller.language, .english)
    }

    func testTheGlobeStillCyclesTheEnabledLanguages() {
        SharedStore.shared.enabledLanguages = [.english, .hebrew, .russian]
        let controller = KeyboardController(target: MockTextTarget(), language: .english)

        controller.press(.globe)
        XCTAssertEqual(controller.language, .hebrew)
        controller.press(.globe)
        XCTAssertEqual(controller.language, .russian)
        controller.press(.globe)
        XCTAssertEqual(controller.language, .english)
    }

    func testTheGlobeAlsoNamesWhereItWent() {
        let controller = KeyboardController(target: MockTextTarget(), language: .english)

        controller.press(.globe)

        XCTAssertEqual(controller.languageSwitchIndication?.language, .hebrew)
        XCTAssertEqual(controller.languageSwitchIndication?.isPending, false)
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

        XCTAssertEqual(
            target.text, correction,
            "The delete ran before the space, so it took a letter out of the word instead of the space")
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
