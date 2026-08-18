import XCTest

@testable import AIKeyboardCore

// MARK: - Through the keyboard

@MainActor
final class SpaceBarLanguageSwitchTests: XCTestCase {

    private var saved = TypingSettings.snapshot()

    override func setUp() {
        super.setUp()
        saved = TypingSettings.snapshot()
        let store = SharedStore.shared
        store.enabledLanguages = [.english, .hebrew]
        store.autocorrectLevel = .full
        store.predictions = true
    }

    override func tearDown() {
        saved.restore()
        super.tearDown()
    }

    /// One whole touch on the space bar, in the order `KeyView` delivers it.
    private func slide(_ controller: KeyboardController, _ points: CGFloat) {
        controller.spaceBarTouch(.began)
        controller.spaceBarTouch(.moved(points))
        controller.spaceBarTouch(.ended(points))
    }

    /// The whole defect, end to end: a slide along the space bar changes the
    /// keyboard's language.
    func testASlideAlongTheSpaceBarSwitchesLanguage() {
        let controller = KeyboardController(target: MockTextTarget(), language: .english)

        slide(controller, 60)

        XCTAssertEqual(controller.language, .hebrew)
    }

    /// And back the other way, which is what makes the direction worth having.
    func testSlidingBackReturnsToTheLanguageBefore() {
        SharedStore.shared.enabledLanguages = [.english, .hebrew, .russian]
        let controller = KeyboardController(target: MockTextTarget(), language: .hebrew)

        slide(controller, -60)

        XCTAssertEqual(controller.language, .english)
    }

    /// **The tap the swipe must not eat, and the correction it must not commit.**
    /// The space bar is the one key that commits the highlighted candidate, so a
    /// swipe that inserted a space on finger-down and deleted it afterwards would
    /// leave `sched` silently rewritten as `schedule`. The first half of this test
    /// proves the correction was armed; without it the second half would pass
    /// against a keyboard with no autocorrect at all.
    func testASlideCommitsNeitherASpaceNorTheAutocorrectCandidate() {
        let tapped = MockTextTarget(text: "sched")
        let tapping = KeyboardController(target: tapped, language: .english)
        guard let correction = tapping.suggestions.first(where: \.isDefault)?.text,
            correction.lowercased() != "sched"
        else {
            return XCTFail(
                "Nothing was armed to replace \"sched\", so nothing below is a test of anything")
        }

        slide(tapping, 3)
        XCTAssertEqual(
            tapped.text, correction + " ", "A tap on the space bar stopped correcting")

        let slid = MockTextTarget(text: "sched")
        let sliding = KeyboardController(target: slid, language: .english)
        slide(sliding, 60)

        XCTAssertEqual(
            slid.text, "sched",
            "The swipe left \"\(slid.text)\" in the document — a space, a correction, or both")
        XCTAssertEqual(sliding.language, .hebrew)
    }

    /// A touch that goes away without lifting — a banner, a Control Centre pull,
    /// the keyboard being dismissed — types nothing and switches nothing.
    func testACancelledTouchDoesNeither() {
        let target = MockTextTarget(text: "sched")
        let controller = KeyboardController(target: target, language: .english)

        controller.spaceBarTouch(.began)
        controller.spaceBarTouch(.moved(60))
        controller.spaceBarTouch(.cancelled)

        XCTAssertEqual(target.text, "sched")
        XCTAssertEqual(controller.language, .english)
        XCTAssertNil(controller.languageSwitchIndication)
    }

    /// **The ordering hazard, pinned.** SwiftUI resets a `@GestureState` when a
    /// gesture ends *or* is cancelled and does not promise which of that reset and
    /// `onEnded` runs first, so `KeyView` can report a cancellation immediately
    /// before the lift it belongs to. A cancellation that threw the touch away
    /// would turn every completed swipe back into a space — silently, and on
    /// every swipe.
    func testACancellationArrivingJustBeforeTheLiftStillSwitches() {
        let target = MockTextTarget(text: "sched")
        let controller = KeyboardController(target: target, language: .english)

        controller.spaceBarTouch(.began)
        controller.spaceBarTouch(.moved(60))
        controller.spaceBarTouch(.cancelled)
        controller.spaceBarTouch(.ended(60))

        XCTAssertEqual(controller.language, .hebrew)
        XCTAssertEqual(target.text, "sched", "The swipe typed \"\(target.text)\" instead of switching")
    }

    /// And the state does not survive into the next touch: a tap after an
    /// abandoned slide is an ordinary space.
    func testATapAfterAnAbandonedSlideIsStillASpace() {
        let target = MockTextTarget(text: "hi")
        let controller = KeyboardController(target: target, language: .english)

        controller.spaceBarTouch(.began)
        controller.spaceBarTouch(.moved(60))
        controller.spaceBarTouch(.cancelled)

        slide(controller, 2)

        XCTAssertEqual(target.text, "hi ", "The abandoned slide swallowed the next space")
        XCTAssertEqual(controller.language, .english)
    }

    /// A slide with nowhere to go still must not type. The user asked for a
    /// language, not for a space.
    func testASlideWithOnlyOneLanguageEnabledTypesNothing() {
        SharedStore.shared.enabledLanguages = [.english]
        let target = MockTextTarget(text: "hi")
        let controller = KeyboardController(target: target, language: .english)
        var handedOver = false
        controller.onAdvanceToNextKeyboard = { handedOver = true }

        slide(controller, 200)

        XCTAssertEqual(target.text, "hi")
        XCTAssertFalse(
            handedOver,
            "A swipe threw the user out to another keyboard, which no swipe can be undone from")
    }

    /// A long list is walked by repeating the gesture, and the length of any one
    /// slide is not part of the answer. A sweep right across the whole space bar
    /// is still the next language, so three slides are still the third one along.
    func testALongListIsWalkedOneLanguagePerSlideHoweverLongTheSlide() {
        let enabled = KeyboardLanguage.allCases
        SharedStore.shared.enabledLanguages = enabled
        let controller = KeyboardController(target: MockTextTarget(), language: .english)

        slide(controller, 300)
        XCTAssertEqual(
            enabled.firstIndex(of: controller.language), 1,
            "A 300-point sweep landed on \(controller.language.displayName) rather than the next language")

        slide(controller, 40)
        slide(controller, 900)
        XCTAssertEqual(
            enabled.firstIndex(of: controller.language), 3,
            "Three slides of three different lengths did not move three places")
    }

    // MARK: What the user sees

    /// The indication the user needs *before* they commit: which language they are
    /// about to land on, while the finger is still down.
    func testTheCandidateIsNamedWhileTheFingerIsStillDown() {
        SharedStore.shared.enabledLanguages = [.english, .hebrew, .russian]
        let controller = KeyboardController(target: MockTextTarget(), language: .english)

        controller.spaceBarTouch(.began)
        controller.spaceBarTouch(.moved(60))

        XCTAssertEqual(controller.languageSwitchIndication?.language, .hebrew)
        XCTAssertEqual(controller.languageSwitchIndication?.isPending, true)
        XCTAssertEqual(controller.languageSwitchIndication?.count, 3)
        XCTAssertEqual(controller.languageSwitchIndication?.position, 1)
        XCTAssertEqual(
            controller.languageSwitchIndication?.step, 1,
            "A right swipe did not tell the keys which edge to enter from")
        XCTAssertEqual(controller.language, .english, "The slide switched before the finger lifted")
    }

    /// It follows the finger's *direction* rather than latching on the first
    /// candidate, so a thumb that has gone the wrong way can turn round under the
    /// name it is reading instead of lifting on a language it did not want.
    func testTheCandidateTurnsRoundWhenTheFingerDoes() {
        SharedStore.shared.enabledLanguages = [.english, .hebrew, .russian]
        let controller = KeyboardController(target: MockTextTarget(), language: .english)

        controller.spaceBarTouch(.began)
        controller.spaceBarTouch(.moved(30))
        XCTAssertEqual(controller.languageSwitchIndication?.language, .hebrew)

        // Further the same way is the same language: distance is a threshold, not
        // a count. See `SpaceSwipe.places`.
        controller.spaceBarTouch(.moved(120))
        XCTAssertEqual(
            controller.languageSwitchIndication?.language, .hebrew,
            "Travelling further right skipped past the next language")

        controller.spaceBarTouch(.moved(-120))
        XCTAssertEqual(
            controller.languageSwitchIndication?.language, .russian,
            "Turning the finger round did not move the candidate back the other way")
    }

    /// And the indication the user needs *after* it lands: the space bar naming
    /// the language it just moved to, the way Gboard does.
    func testTheSpaceBarNamesTheLanguageItLandedOn() {
        let controller = KeyboardController(target: MockTextTarget(), language: .english)

        slide(controller, 60)

        XCTAssertEqual(controller.languageSwitchIndication?.language, .hebrew)
        XCTAssertEqual(
            controller.languageSwitchIndication?.isPending, false,
            "The space bar is still showing a candidate for a slide that has already landed")
        XCTAssertEqual(controller.languageSlideStep, 1)
        XCTAssertEqual(controller.languageSwitchIndication?.step, 1)
    }

    /// A left swipe has to carry the opposite step, or the keys slide in from the
    /// wrong side and fight the codes the space bar just highlighted.
    func testALeftSwipeTellsTheKeysToEnterFromTheLeft() {
        SharedStore.shared.enabledLanguages = [.english, .hebrew, .russian]
        let controller = KeyboardController(target: MockTextTarget(), language: .hebrew)

        slide(controller, -60)

        XCTAssertEqual(controller.language, .english)
        XCTAssertEqual(controller.languageSlideStep, -1)
        XCTAssertEqual(controller.languageSwitchIndication?.step, -1)
    }

    /// A confirmation that never leaves is not a confirmation, it is a caption:
    /// the space bar has to go back to saying what it is.
    func testTheNameGivesTheSpaceBarBack() async {
        let controller = KeyboardController(target: MockTextTarget(), language: .english)

        slide(controller, 60)
        XCTAssertNotNil(controller.languageSwitchIndication)

        try? await Task.sleep(for: .milliseconds(1900))

        XCTAssertNil(
            controller.languageSwitchIndication,
            "The space bar is permanently captioned with a language instead of \"space\"")
    }

    // Globe and gesture-order tests live in SpaceBarGestureOrderTests.swift.
}
