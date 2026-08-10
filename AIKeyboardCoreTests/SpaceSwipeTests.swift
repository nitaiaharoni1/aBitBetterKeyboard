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

// MARK: - Distance to language

final class SpaceSwipeDistanceTests: XCTestCase {

    private let two: [KeyboardLanguage] = [.english, .hebrew]
    private let three: [KeyboardLanguage] = [.english, .hebrew, .arabic]
    /// A long enabled list, and deliberately not the whole catalogue any more.
    /// `KeyboardLanguage.allCases` is sixty-four keyboards and nobody turns on
    /// sixty-four; this is the shape of a list a heavy user builds, which is what
    /// the gesture is measured against.
    private let many = Array(KeyboardLanguage.allCases.prefix(14))

    func testATapMovesNothing() {
        XCTAssertEqual(SpaceSwipe.places(translation: 6, languageCount: 2), 0)
        XCTAssertNil(SpaceSwipe.destination(from: .english, in: two, translation: 6))
    }

    /// Direction is the whole point of a directional gesture: right is forwards
    /// through the user's own order, left is backwards.
    func testRightIsForwardsAndLeftIsBackwards() {
        XCTAssertEqual(SpaceSwipe.destination(from: .hebrew, in: three, translation: 40), .arabic)
        XCTAssertEqual(SpaceSwipe.destination(from: .hebrew, in: three, translation: -40), .english)
    }

    /// **The right-to-left decision, stated as the property that decides it.**
    /// Hebrew, Arabic and Persian mirror the letters plane, and it is tempting to
    /// mirror this gesture with them. Doing so would make one right swipe move
    /// forwards from English and *backwards* from Hebrew, so two identical swipes
    /// would go English → Hebrew → English and the rest of the list could never be
    /// reached by repeating the gesture. The enabled list has one order and does
    /// not flip; neither does the swipe.
    func testTheSameSwipeKeepsMovingForwardsOnARightToLeftKeyboard() {
        let first = SpaceSwipe.destination(from: .english, in: three, translation: 40)
        XCTAssertEqual(first, .hebrew)

        let second = SpaceSwipe.destination(from: .hebrew, in: three, translation: 40)
        XCTAssertEqual(
            second, .arabic,
            """
            The second identical swipe went back to \(second?.displayName ?? "nowhere") — a mirrored \
            gesture oscillates between two languages and leaves the rest of the list unreachable.
            """)
    }

    // MARK: Two languages

    func testTwoLanguagesSwitchOnTheShortestSlideThereIs() {
        XCTAssertEqual(
            SpaceSwipe.destination(
                from: .english, in: two, translation: SpaceSwipe.activation),
            .hebrew)
    }

    /// With two languages every slide, however enthusiastic, means the other one.
    func testALongSlideAcrossTwoLanguagesStillMeansTheOtherOne() {
        XCTAssertEqual(SpaceSwipe.destination(from: .english, in: two, translation: 400), .hebrew)
        XCTAssertEqual(SpaceSwipe.destination(from: .hebrew, in: two, translation: 400), .english)
    }

    func testOneLanguageHasNowhereToGo() {
        XCTAssertEqual(SpaceSwipe.places(translation: 300, languageCount: 1), 0)
        XCTAssertNil(SpaceSwipe.destination(from: .english, in: [.english], translation: 300))
        XCTAssertNil(SpaceSwipe.destination(from: .english, in: [], translation: 300))
    }

    // MARK: Fourteen languages

    /// The reason the slide is scrubbed rather than stepped. One step per swipe is
    /// fine for two keyboards and unusable for fourteen — the seventh language
    /// would be six separate swipes, each of them redrawing the layout under the
    /// thumb on the way past. Distance carries the count instead.
    func testOneSlideCrossesMostOfAFourteenLanguageList() {
        XCTAssertEqual(
            SpaceSwipe.places(translation: SpaceSwipe.activation, languageCount: 14), 1,
            "The shortest slide that counts has to be worth exactly one language")

        let sweep = SpaceSwipe.places(translation: 200, languageCount: 14)
        XCTAssertGreaterThan(
            sweep, 5,
            "A thumb's sweep moved \(sweep) of fourteen languages, so the far end needs a dozen swipes")
        XCTAssertLessThan(sweep, 14)
    }

    /// Every language the user enabled is reachable in one gesture, and each one by
    /// its own distance.
    ///
    /// **Fourteen, not the whole catalogue, and the difference is a real limit.**
    /// `step` bottoms out at `narrowestStep`, so a slide only carries so many
    /// languages however long the list gets; the test below measures where that
    /// stops, and this one measures the list it comfortably covers.
    func testEveryEnabledLanguageIsReachableInOneSlide() {
        var landed: Set<KeyboardLanguage> = []
        for points in stride(from: 0.0, through: 500.0, by: 1.0) {
            if let destination = SpaceSwipe.destination(
                from: .english, in: many, translation: CGFloat(points))
            {
                landed.insert(destination)
            }
        }

        XCTAssertEqual(
            landed, Set(many).subtracting([.english]),
            "A rightward slide could not reach \(Set(many).subtracting(landed).map(\.displayName))")
    }

    /// **Where one slide stops being enough, measured rather than assumed.**
    /// `step(languageCount:)` clamps at `narrowestStep`, so past a certain count
    /// the far end of the list needs a second swipe — a slide is bounded by the
    /// screen it happens on. Twenty-three enabled languages is the last count a
    /// slide the width of an iPhone 17 Pro carries end to end, and the globe key
    /// is what covers the rest, one language at a time, exactly as it does on
    /// Gboard.
    ///
    /// The point of pinning it is that the number moves if anyone retunes
    /// `activation`, `sweep` or the clamp, and a gesture that silently stops
    /// reaching half a list is the kind of regression nobody notices with two
    /// keyboards on.
    func testOneSlideCarriesTwentyThreeLanguagesAndNoMore() {
        let screenWidth: CGFloat = 402

        XCTAssertEqual(SpaceSwipe.step(languageCount: 23), SpaceSwipe.narrowestStep)
        XCTAssertEqual(
            SpaceSwipe.places(translation: screenWidth, languageCount: 23), 22,
            "the far end of a 23-language list is one slide away")
        XCTAssertLessThan(
            SpaceSwipe.places(translation: screenWidth, languageCount: 24), 23,
            "24 would mean the clamp had moved")

        // The whole catalogue does not fit, and the honest consequence is that
        // the gesture still moves a long way rather than doing nothing.
        let across = SpaceSwipe.places(
            translation: screenWidth, languageCount: KeyboardLanguage.allCases.count)
        XCTAssertGreaterThan(across, 20)
        XCTAssertLessThan(across, KeyboardLanguage.allCases.count - 1)
    }

    /// **Over-travel stops one short of a full lap rather than wrapping.** A
    /// modulo would let an enthusiastic swipe land back on the language it started
    /// from, which the user reads as the gesture not working at all — and it is
    /// exactly what a long swipe produces: 5000 points is 270 raw steps, and 270
    /// wraps to 4 of 14 and to 0 of 3.
    func testALongSlideNeverLandsBackWhereItStarted() {
        XCTAssertEqual(SpaceSwipe.places(translation: 5000, languageCount: 14), 13)
        XCTAssertEqual(SpaceSwipe.places(translation: -5000, languageCount: 14), -13)

        for points in stride(from: 0.0, through: 2000.0, by: 1.0) {
            for enabled in [three, many, KeyboardLanguage.allCases] {
                let destination = SpaceSwipe.destination(
                    from: .english, in: enabled, translation: CGFloat(points))
                XCTAssertNotEqual(
                    destination, .english,
                    "A \(Int(points))-point slide across \(enabled.count) languages wrapped back to English")
            }
        }
    }

    /// Distance in, places out: it never skips a language on the way, so the
    /// callout the finger is watching never jumps.
    func testTheCountRisesOneAtATimeAsTheFingerTravels() {
        var seen = 0
        for points in stride(from: 0.0, through: 400.0, by: 1.0) {
            let places = SpaceSwipe.places(translation: CGFloat(points), languageCount: 14)
            XCTAssertTrue(
                places == seen || places == seen + 1,
                "The count jumped from \(seen) to \(places) at \(Int(points)) points")
            seen = places
        }
        XCTAssertEqual(seen, 13)
    }
}

// MARK: - Saying the gesture is there

/// **A gesture nobody can find is a gesture nobody has.** The swipe worked from
/// the day it shipped and the owner of the first phone it went on had to be told
/// it existed: the space bar was captioned "space" — "רווח" in Hebrew — and
/// nothing else on the keyboard mentioned it. `announceLanguage` names the
/// language for 1.4s *after* a switch and `LanguageCallout` names it *during* a
/// slide, and both of those are feedback for somebody who already knows.
final class SpaceBarAffordanceTests: XCTestCase {

    /// The state the owner was in: two languages, finger nowhere near the key. The
    /// strip has to name the language that is on **and** the one that is not, which
    /// is the half the first fix missed — a caption reading "עברית" says where you
    /// are and nothing about where the chevrons go.
    func testAtTwoLanguagesTheSpaceBarNamesBothAndSaysItSlides() {
        let strip = SpaceSwipe.codeStrip(active: .hebrew, in: [.english, .hebrew])
        XCTAssertEqual(strip, [.english, .hebrew])
        XCTAssertEqual(strip.map { $0.shortName }, ["EN", "עב"])
        XCTAssertTrue(SpaceSwipe.showsSlideAffordance(languageCount: 2))
        XCTAssertFalse(SpaceSwipe.slideHint(languageCount: 2).isEmpty)
    }

    /// With one language there is nowhere to slide, so the strip and the chevrons
    /// both go and the key is a plain space bar. An affordance for a gesture that
    /// cannot move is worse than none.
    func testWithOneLanguageItIsAnOrdinarySpaceBar() {
        for language in [KeyboardLanguage.hebrew, .english] {
            XCTAssertEqual(SpaceSwipe.codeStrip(active: language, in: [language]), [])
        }
        XCTAssertEqual(SpaceSwipe.codeStrip(active: .english, in: []), [])
        XCTAssertFalse(SpaceSwipe.showsSlideAffordance(languageCount: 1))
        XCTAssertEqual(SpaceSwipe.slideHint(languageCount: 1), "")
    }

    /// Two and three fit whole, so nothing is hidden and the order is the order a
    /// slide moves through.
    func testUpToThreeLanguagesAreAllPrinted() {
        let three: [KeyboardLanguage] = [.english, .hebrew, .french]
        for active in three {
            XCTAssertEqual(
                SpaceSwipe.codeStrip(active: active, in: three), three,
                "at three languages the strip should be the whole list")
        }
    }

    /// **Past three the strip is a window, and the property that matters is that it
    /// is the window the gesture actually moves to** — asked of `language`, which
    /// is the code that moves it, rather than of a second copy of the arithmetic.
    /// A strip that named a neighbour a swipe does not reach would be a worse lie
    /// than no strip at all.
    func testPastThreeTheStripIsTheNeighboursTheGestureReaches() {
        let enabled: [KeyboardLanguage] = [.english, .hebrew, .french, .german, .greek]
        for active in enabled {
            let strip = SpaceSwipe.codeStrip(active: active, in: enabled)
            XCTAssertEqual(strip.count, 3, "\(active) got a strip of \(strip.count)")
            XCTAssertEqual(
                strip[0], SpaceSwipe.language(from: active, in: enabled, places: -1),
                "the left code is not where a left swipe from \(active) lands")
            XCTAssertEqual(
                strip[1], active, "the lit code is not the language in use at \(active)")
            XCTAssertEqual(
                strip[2], SpaceSwipe.language(from: active, in: enabled, places: 1),
                "the right code is not where a right swipe from \(active) lands")
        }
    }

    /// Every language ships a code short enough to sit two or three abreast on a
    /// key that is a little over half the keyboard wide. Nothing enforces this in
    /// the catalogue, and one long entry would push the strip into
    /// `minimumScaleFactor` and shrink the whole row.
    func testEveryLanguageCodeIsShortEnoughToPrintThreeAbreast() {
        for language in KeyboardLanguage.allCases {
            XCTAssertFalse(language.shortName.isEmpty, "\(language.rawValue) has no short name")
            XCTAssertLessThanOrEqual(
                language.shortName.count, 3,
                "\(language.rawValue) prints \(language.shortName) on the space bar")
        }
    }

    /// **The chevrons and the gesture have to agree at every list length**, or the
    /// keyboard is either promising a slide that does nothing or hiding one that
    /// works. `places` is the code that actually moves the language, asked with a
    /// travel far past `activation`, so this is the affordance checked against the
    /// behaviour rather than against itself.
    func testTheAffordanceAppearsExactlyWhenTheGestureCanMove() {
        for count in 0...KeyboardLanguage.allCases.count {
            let moves =
                SpaceSwipe.places(translation: SpaceSwipe.activation + 300, languageCount: count) != 0
            XCTAssertEqual(
                SpaceSwipe.showsSlideAffordance(languageCount: count), moves,
                "\(count) enabled languages: the space bar and the gesture disagree")
        }
    }
}

// MARK: - Through the keyboard

/// `SharedStore.init` is private and the singleton is the App Group plist, so
/// there is no scratch instance to build. Every test that writes a setting puts it
/// back.
private struct TypingSettings {
    let languages: [KeyboardLanguage]
    let autocorrect: Bool
    let predictions: Bool

    static func snapshot() -> TypingSettings {
        let store = SharedStore.shared
        return TypingSettings(
            languages: store.enabledLanguages,
            autocorrect: store.autocorrect,
            predictions: store.predictions)
    }

    func restore() {
        let store = SharedStore.shared
        store.enabledLanguages = languages
        store.autocorrect = autocorrect
        store.predictions = predictions
    }
}

@MainActor
final class SpaceBarLanguageSwitchTests: XCTestCase {

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

    /// Fourteen enabled languages, one gesture, several places along the list.
    func testALongSlideAcrossFourteenLanguagesMovesSeveralPlaces() {
        let enabled = KeyboardLanguage.allCases
        SharedStore.shared.enabledLanguages = enabled
        let controller = KeyboardController(target: MockTextTarget(), language: .english)

        slide(controller, 200)

        let landed = enabled.firstIndex(of: controller.language) ?? 0
        XCTAssertGreaterThan(
            landed, 5,
            "One sweep moved to \(controller.language.displayName), \(landed) places along fourteen")
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
        XCTAssertEqual(controller.language, .english, "The slide switched before the finger lifted")
    }

    /// It follows the finger rather than latching on the first candidate, which is
    /// what makes a fourteen-language list choosable instead of a lottery.
    func testTheCandidateFollowsTheFingerFurtherAlongTheList() {
        SharedStore.shared.enabledLanguages = [.english, .hebrew, .russian]
        let controller = KeyboardController(target: MockTextTarget(), language: .english)

        controller.spaceBarTouch(.began)
        controller.spaceBarTouch(.moved(30))
        XCTAssertEqual(controller.languageSwitchIndication?.language, .hebrew)

        controller.spaceBarTouch(.moved(120))
        XCTAssertEqual(controller.languageSwitchIndication?.language, .russian)

        controller.spaceBarTouch(.moved(30))
        XCTAssertEqual(
            controller.languageSwitchIndication?.language, .hebrew,
            "Coming back down the list did not move the candidate back")
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

    // MARK: The globe, which the swipe is an addition to and not a replacement for

    /// The behaviour that already existed and must not be lost: with one of our
    /// languages enabled the globe hands the keyboard over to iOS.
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

    /// The globe was the other half of the same complaint: on the phone that
    /// reported D3 the layout changed with nothing saying to what. It says now.
    func testTheGlobeAlsoNamesWhereItWent() {
        let controller = KeyboardController(target: MockTextTarget(), language: .english)

        controller.press(.globe)

        XCTAssertEqual(controller.languageSwitchIndication?.language, .hebrew)
        XCTAssertEqual(controller.languageSwitchIndication?.isPending, false)
    }

    // MARK: Orders a gesture recogniser is free to deliver

    /// **The rollover the deferred space costs, and the guard that pays it.** Two
    /// thumbs overlap constantly on a phone keyboard: the right lands on space, the
    /// left taps a letter, and only then does the right lift. Without the flush in
    /// `press`, the letter goes in first, and `insertSpace` then reads
    /// `currentWordPrefix` and `suggestions` after that letter has re-scored both —
    /// so `sched` + space + `t` comes back as one word autocorrected from `schedt`.
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

    /// Delete is the other key a thumb rolls onto, and it is the one where landing
    /// out of order eats a character instead of moving one.
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

    /// A touch whose lift was never delivered costs its own space and nothing
    /// else. One space, never two, and never one belonging to a touch that may
    /// still be down.
    func testASecondTouchBeginningBeforeTheFirstEndsTypesOneSpace() {
        let target = MockTextTarget(text: "hi")
        let controller = KeyboardController(target: target, language: .english)

        controller.spaceBarTouch(.began)
        controller.spaceBarTouch(.began)
        controller.spaceBarTouch(.ended(0))

        XCTAssertEqual(target.text, "hi ", "Two overlapping touches typed \"\(target.text)\"")
    }

    /// A lift nobody began is a phantom, and a phantom space is worse than a lost
    /// one.
    func testALiftWithNoTouchBehindItTypesNothing() {
        let target = MockTextTarget(text: "hi")
        let controller = KeyboardController(target: target, language: .english)

        controller.spaceBarTouch(.ended(0))

        XCTAssertEqual(target.text, "hi")
    }

    /// A banner that swallows a half-pressed space bar must not put a space in
    /// front of the next thing the user types.
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

    /// And the other side of that: a cancellation arriving immediately before the
    /// lift it belongs to must not write the space off. SwiftUI does not promise
    /// whether a `@GestureState` reset runs before or after `onEnded`, and a
    /// keyboard that got this wrong would type no spaces at all.
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

    /// A touch delivered as one movement and then a lift reports its travel only
    /// on the lift, so the lift has to read it.
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
