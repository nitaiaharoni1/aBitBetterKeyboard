import XCTest

@testable import AIKeyboardCore

/// D3: "it doesnt have capeability to change language within it, we need a swipe
/// on space to make it switch lang (also ui indication somehow)".
///
/// The gesture itself needs a finger, so everything a finger cannot be asked
/// about afterwards lives in `SpaceSwipe` and is driven directly here: whether a
/// touch that wandered is still a space, how many places a slide of a given length
/// moves, and which language that lands on. `KeyView` only forwards translations
/// into it.
final class SpaceSwipeTouchTests: XCTestCase {

    /// The failure this dead zone exists to stop: a keyboard that changes language
    /// on the few points of wobble every thumb puts into an ordinary space tap.
    func testAnOrdinaryTapIsNeverASlide() {
        var touch = SpaceSwipe.Touch()
        touch.began()

        XCTAssertFalse(touch.moved(to: 0))
        XCTAssertFalse(touch.moved(to: 3))
        XCTAssertFalse(touch.moved(to: -7))
        XCTAssertFalse(touch.moved(to: 9))

        XCTAssertEqual(
            touch.lifted(after: 9), .space,
            "A tap that wandered nine points was read as a language slide, so it typed no space")
    }

    func testADeliberateSlideIsASlide() {
        var touch = SpaceSwipe.Touch()
        touch.began()
        XCTAssertTrue(touch.moved(to: 60))
        XCTAssertEqual(touch.lifted(after: 60), .slide(60))
    }

    /// **The lift carries the distance because it may be the only event that
    /// does.** A touch delivered as one `onChanged` and then `onEnded` never
    /// reports its travel any other way, and a version that classified the touch
    /// purely from the movements it had already seen typed a space over a
    /// sixty-point swipe.
    func testALiftThatIsTheFirstNewsOfTheTravelIsStillASlide() {
        var touch = SpaceSwipe.Touch()
        touch.began()

        XCTAssertEqual(
            touch.lifted(after: 60), .slide(60),
            "The swipe typed a space because no movement had been reported separately")
    }

    /// **Sticky on purpose.** A finger that slides out, changes its mind and comes
    /// back to where it started has stopped asking for a language — and it never
    /// asked for a space either. Letting the touch turn back into a tap would type
    /// a space nobody wanted, and worse, commit the highlighted autocorrect
    /// candidate along with it.
    func testASlideThatComesBackIsStillASlideAndNotASpace() {
        var touch = SpaceSwipe.Touch()
        touch.began()
        XCTAssertTrue(touch.moved(to: 60))
        XCTAssertTrue(touch.moved(to: 12))
        XCTAssertTrue(touch.moved(to: 0))

        XCTAssertEqual(
            touch.lifted(after: 0), .slide(0),
            "The touch became a tap again on the way back, which types a space the user cancelled")
    }

    /// One touch does not leak into the next.
    func testLiftingResetsTheTouch() {
        var touch = SpaceSwipe.Touch()
        touch.began()
        touch.moved(to: 60)
        _ = touch.lifted(after: 60)

        XCTAssertFalse(touch.isSliding)
        touch.began()
        XCTAssertFalse(touch.moved(to: 4), "The next tap inherited the last slide")
        XCTAssertEqual(touch.lifted(after: 4), .space)
    }

    /// A lift nobody began owes nothing. A phantom space is worse than a lost one.
    func testALiftWithNoTouchBehindItOwesNothing() {
        var touch = SpaceSwipe.Touch()
        XCTAssertEqual(touch.lifted(after: 0), .nothing)
    }

    // MARK: Interruption

    /// **The rollover case.** Two thumbs overlap on a phone keyboard: a finger
    /// lands on space, the other thumb taps a letter, and only then does the first
    /// lift. The space is owed at the moment the letter arrives and has to be paid
    /// then — not on the lift, by which time the letter has already changed both
    /// the word being corrected and the candidates it would be corrected to.
    func testAKeyPressedDuringTheTouchTakesTheSpaceWithIt() {
        var touch = SpaceSwipe.Touch()
        touch.began()

        XCTAssertTrue(touch.interrupted(), "The rolled-over key did not collect the owed space")
        XCTAssertEqual(
            touch.lifted(after: 0), .nothing,
            "The lift typed a second space for a debt that was already paid")
    }

    /// Only once, however many keys roll over it.
    func testASecondKeyCollectsNothing() {
        var touch = SpaceSwipe.Touch()
        touch.began()

        XCTAssertTrue(touch.interrupted())
        XCTAssertFalse(touch.interrupted(), "Two rolled-over keys typed two spaces")
    }

    /// A touch that has already become a slide owes nothing, so a key pressed
    /// during it takes nothing.
    func testAKeyPressedDuringASlideCollectsNothing() {
        var touch = SpaceSwipe.Touch()
        touch.began()
        touch.moved(to: 60)

        XCTAssertFalse(touch.interrupted())
        XCTAssertEqual(touch.lifted(after: 60), .slide(60))
    }

    /// And an abandoned touch owes nothing to a key pressed afterwards, because it
    /// may never lift at all. A banner that swallows a half-pressed space bar must
    /// not put a space in front of the next thing the user types.
    func testAKeyPressedAfterAnAbandonedTouchCollectsNothing() {
        var touch = SpaceSwipe.Touch()
        touch.began()
        touch.cancelled()

        XCTAssertFalse(touch.interrupted())
    }

    /// **But the abandonment does not cancel the debt**, because a cancellation can
    /// arrive immediately before the lift it belongs to rather than instead of it.
    /// SwiftUI resets a `@GestureState` when a gesture ends *or* is cancelled and
    /// does not promise which of that reset and `onEnded` runs first; a tap whose
    /// debt was written off half a millisecond early would type nothing at all.
    func testACancellationArrivingJustBeforeALiftStillOwesItsSpace() {
        var touch = SpaceSwipe.Touch()
        touch.began()
        touch.cancelled()

        XCTAssertEqual(touch.lifted(after: 0), .space)
    }

    func testACancellationArrivingJustBeforeALiftStillOwesItsSlide() {
        var touch = SpaceSwipe.Touch()
        touch.began()
        touch.moved(to: 60)
        touch.cancelled()

        XCTAssertEqual(touch.lifted(after: 60), .slide(60))
    }

    /// The threshold as a band rather than as a number, so it can be tuned without
    /// rewriting this file and cannot be tuned into either failure. Below
    /// SwiftUI's own 10-point drag minimum a tap starts switching languages; above
    /// half a space bar the gesture stops being reachable with a thumb.
    func testTheDeadZoneClearsThumbDriftAndFitsInsideASpaceBar() {
        XCTAssertGreaterThan(SpaceSwipe.activation, 12)
        XCTAssertLessThan(SpaceSwipe.activation, 70)
    }
}
