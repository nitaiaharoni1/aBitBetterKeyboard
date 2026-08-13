import XCTest

@testable import AIKeyboardCore

/// A downward slide over the chrome dismisses the keyboard. Everything a finger
/// cannot be asked about afterwards lives in `DrawerDismiss` and is driven
/// directly here: whether a touch that wandered is still a tap, whether a
/// diagonal was vertical enough, and whether the same translation asked twice
/// is still the same answer. The view only forwards translations into it.
final class DrawerDismissTests: XCTestCase {

    /// A pull has to be taller than the suggestion bar, or a tap on a candidate
    /// that wandered a little is also a dismiss. `minTouchTarget` is 44 and the
    /// bar is 36; a version that reused `SpaceSwipe.activation` (24) or sat at 32
    /// would still be inside the chip.
    func testAPullIsTallerThanTheSuggestionBar() {
        XCTAssertGreaterThan(
            DrawerDismiss.Policy.standard.minimumTravel,
            Theme.Metrics.suggestionBarHeight,
            "A \(DrawerDismiss.Policy.standard.minimumTravel)pt pull still fits inside the \(Theme.Metrics.suggestionBarHeight)pt bar"
        )
        XCTAssertEqual(DrawerDismiss.Policy.standard.minimumTravel, Theme.Metrics.minTouchTarget)
    }

    func testJustShyOfTheThresholdIsIgnored() {
        let shy = DrawerDismiss.Policy.standard.minimumTravel - 1
        XCTAssertEqual(
            DrawerDismiss.outcome(for: CGSize(width: 0, height: shy)),
            .ignored,
            "A \(shy)-point downward wander dismissed the keyboard")
    }

    func testTheThresholdDownDismisses() {
        let travel = DrawerDismiss.Policy.standard.minimumTravel
        XCTAssertEqual(
            DrawerDismiss.outcome(for: CGSize(width: 0, height: travel)),
            .dismiss,
            "A \(travel)-point downward slide was ignored, so the keyboard could not be swiped away")
    }

    /// Upward is never dismiss. A version that classified `abs(height)` would
    /// hide the keyboard on a flick toward the field, which is the opposite of
    /// putting it away.
    func testUpwardIsIgnored() {
        XCTAssertEqual(
            DrawerDismiss.outcome(for: CGSize(width: 0, height: -Theme.Metrics.minTouchTarget)),
            .ignored,
            "An upward flick of the dismiss distance hid the keyboard")
        XCTAssertEqual(
            DrawerDismiss.outcome(for: CGSize(width: 0, height: -80)),
            .ignored,
            "A long upward swipe dismissed the keyboard")
    }

    func testHorizontalIsIgnored() {
        XCTAssertEqual(
            DrawerDismiss.outcome(for: CGSize(width: 80, height: 0)),
            .ignored,
            "A sideways slide dismissed the keyboard")
        XCTAssertEqual(
            DrawerDismiss.outcome(for: CGSize(width: -80, height: 10)),
            .ignored,
            "A mostly-horizontal slide dismissed the keyboard")
    }

    /// 50 down and 40 across is exactly 1.25, and 50 clears the 44-point floor.
    /// A version that asked only `height > abs(width)` would still dismiss here,
    /// but so would a shallower diagonal that was aiming at Rewrite.
    func testAxisDominanceAtTheThresholdDismisses() {
        XCTAssertEqual(
            DrawerDismiss.outcome(for: CGSize(width: 40, height: 50)),
            .dismiss,
            "A 1.25-dominant downward slide was ignored")
        XCTAssertEqual(
            DrawerDismiss.outcome(for: CGSize(width: -40, height: 50)),
            .dismiss,
            "Leftward travel flipped a vertically-dominant dismiss into a no-op")
    }

    func testAxisDominanceJustOutsideTheThresholdIsIgnored() {
        XCTAssertEqual(
            DrawerDismiss.outcome(for: CGSize(width: 41, height: 50)),
            .ignored,
            "A diagonal shallower than 1.25 dismissed the keyboard")
    }

    /// The classifier is a function of the translation, not of how many times
    /// it has been asked. A version that counted calls would dismiss once and
    /// then start ignoring the same slide.
    func testTheSameTranslationAskedTwiceIsTheSameOutcome() {
        let dismiss = CGSize(width: 0, height: 50)
        XCTAssertEqual(
            DrawerDismiss.outcome(for: dismiss),
            DrawerDismiss.outcome(for: dismiss))
        XCTAssertEqual(DrawerDismiss.outcome(for: dismiss), .dismiss)

        let ignore = CGSize(width: 80, height: 10)
        XCTAssertEqual(
            DrawerDismiss.outcome(for: ignore),
            DrawerDismiss.outcome(for: ignore))
        XCTAssertEqual(DrawerDismiss.outcome(for: ignore), .ignored)
    }
}
