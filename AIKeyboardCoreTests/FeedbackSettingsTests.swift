import XCTest

@testable import AIKeyboardCore

/// The Haptics and Key sounds switches, read at the press.
///
/// **Both switches shipped with the bug `storedAutocorrect` was written to fix.**
/// `Feedback` held two plain `Bool`s that `KeyboardViewController.viewDidLoad`
/// filled once, and `SharedStore`'s `didSet`s pushed new values into them — which
/// is the app's own process talking to itself. Nothing reached a keyboard
/// instance iOS had already built, so turning the sound off and returning to the
/// same host app left it clicking.
@MainActor
final class FeedbackSettingsTests: XCTestCase {

    private var haptics = true
    private var keySounds = true
    private var strength = HapticStrength.default

    override func setUp() {
        super.setUp()
        haptics = SharedStore.shared.haptics
        keySounds = SharedStore.shared.keySounds
        strength = SharedStore.shared.hapticStrength
        SharedStore.shared.haptics = true
        SharedStore.shared.keySounds = true
        SharedStore.shared.hapticStrength = .default
    }

    override func tearDown() {
        SharedStore.shared.haptics = haptics
        SharedStore.shared.keySounds = keySounds
        SharedStore.shared.hapticStrength = strength
        super.tearDown()
    }

    /// **Writes only into the suite, behind the published copy's back**, because
    /// that is the state the defect lives in: the app has written `false` and the
    /// keyboard's `@Published` copy, filled once by `load()` at launch, still says
    /// `true`. Assigning `keySounds = false` instead would update both readers and
    /// pass against the build that cached the value.
    func testKeyClicksSeeTheSoundTurnedOffInTheOtherProcess() {
        SharedStore.shared.userDefaults.set(false, forKey: SharedStore.Key.keySounds)
        XCTAssertTrue(
            SharedStore.shared.keySounds,
            "the published copy must stay stale, or this proves nothing")

        XCTAssertFalse(SharedStore.shared.storedKeySounds)
        XCTAssertFalse(
            Feedback.soundEnabled,
            "the keyboard is still clicking after the user turned Key sounds off")
    }

    /// Same defect, same file, one line above it.
    func testHapticsSeeTheSwitchTurnedOffInTheOtherProcess() {
        SharedStore.shared.userDefaults.set(false, forKey: SharedStore.Key.haptics)
        XCTAssertTrue(
            SharedStore.shared.haptics,
            "the published copy must stay stale, or this proves nothing")

        XCTAssertFalse(SharedStore.shared.storedHaptics)
        XCTAssertFalse(
            Feedback.hapticsEnabled,
            "the keyboard is still buzzing after the user turned Haptics off")
    }

    /// A switch nobody has ever touched has no key in the suite, and both readers
    /// have to answer the shipped default rather than `false`.
    func testAnUntouchedSwitchReadsAsOn() {
        SharedStore.shared.userDefaults.removeObject(forKey: SharedStore.Key.keySounds)
        SharedStore.shared.userDefaults.removeObject(forKey: SharedStore.Key.haptics)

        XCTAssertTrue(SharedStore.shared.storedKeySounds)
        XCTAssertTrue(SharedStore.shared.storedHaptics)
    }

    /// The dial nobody has moved has no key either, and `integer(forKey:)` answers
    /// 0 for it — which is why no case is numbered 0. An install that predates the
    /// dial has to keep the impact it has always played.
    func testAnUntouchedStrengthReadsAsTheShippedDefault() {
        SharedStore.shared.userDefaults.removeObject(forKey: SharedStore.Key.hapticStrength)

        XCTAssertNil(HapticStrength(rawValue: 0), "0 is what an absent key reads as")
        XCTAssertEqual(SharedStore.shared.storedHapticStrength, .strong)
        XCTAssertEqual(HapticStrength.default.style, .heavy)
    }

    /// **The dial changes the collision, not the `intensity:` argument.** A build
    /// that stored the setting, read it at the press and went on playing `.heavy`
    /// would pass every assertion above: `UIImpactFeedbackGenerator` fixes its
    /// style at init, so the only proof the setting reaches the motor is that the
    /// generator was rebuilt. Written through the suite alone, behind the
    /// published copy's back, for the reason the two tests above are.
    func testMovingTheDialRebuildsTheGeneratorAtTheNextPress() {
        // Seeded rather than assumed: `builtStyle` is process-wide, and a test
        // that ran earlier and left it on `.light` would make the assertion
        // below true of a build that never rebuilds anything.
        Feedback.keyPress()
        XCTAssertEqual(Feedback.builtStyle, .heavy, "setUp put the dial back on the default")

        SharedStore.shared.userDefaults.set(
            HapticStrength.light.rawValue, forKey: SharedStore.Key.hapticStrength)
        XCTAssertEqual(
            SharedStore.shared.hapticStrength, .strong,
            "the published copy must stay stale, or this proves nothing")

        Feedback.keyPress()
        XCTAssertEqual(
            Feedback.builtStyle, .light,
            "the keyboard is still hitting at full strength after the user turned the dial down")

        SharedStore.shared.userDefaults.set(
            HapticStrength.medium.rawValue, forKey: SharedStore.Key.hapticStrength)
        Feedback.keyPress()
        XCTAssertEqual(Feedback.builtStyle, .medium)
    }

    /// **The dial is moved while the keyboard is off screen, so the warm-up is
    /// where it has to land.** `prepare()` runs from `KeyboardView.onAppear`; a
    /// version that warmed the generator the user had just replaced would leave
    /// the rebuild to the first press, and a generator built at the press is
    /// cold — the late first tap `attach` and `prepare` exist to stop.
    func testWarmingUpPicksUpADialMovedWhileTheKeyboardWasAway() {
        Feedback.prepare()
        XCTAssertEqual(Feedback.builtStyle, .heavy, "setUp put the dial back on the default")

        SharedStore.shared.userDefaults.set(
            HapticStrength.light.rawValue, forKey: SharedStore.Key.hapticStrength)
        Feedback.prepare()
        XCTAssertEqual(
            Feedback.builtStyle, .light,
            "the burst was warmed on the generator the user had already replaced")
    }

    /// Every stop is a different collision at full intensity. Two stops sharing a
    /// style is a dial with a dead position.
    func testEachStopIsADistinctCollision() {
        let styles = HapticStrength.allCases.map(\.style)
        XCTAssertEqual(Set(styles).count, HapticStrength.allCases.count)
        XCTAssertEqual(HapticStrength.light.style, .light)
        XCTAssertEqual(HapticStrength.medium.style, .medium)
    }

    /// The mock damped every letter to 0.6 of `.light`. `.rigid` at 1.0 was the
    /// next stop and still read as a miss. Asking only "is there a generator"
    /// would pass against both; these two numbers are what changed.
    ///
    /// Still pinned now the Strength dial exists, because the dial moves the
    /// style and leaves the intensity at 1.0: a stop that damped its waveform
    /// instead would put the mock's feel back under a new name.
    func testEveryPressIsFullHeavyByDefault() {
        XCTAssertNotEqual(
            Feedback.impactStyle, .light,
            "light at 0.6 was the mock; a letter has to land as a thud")
        XCTAssertNotEqual(
            Feedback.impactStyle, .rigid,
            "rigid at 1.0 was the previous click and still read as a miss")
        XCTAssertEqual(Feedback.impactStyle, .heavy)
        XCTAssertEqual(Feedback.impactIntensity, 1.0)
        XCTAssertEqual(Feedback.keyPressStyle, Feedback.impactStyle)
        XCTAssertEqual(Feedback.modifierPressStyle, Feedback.impactStyle)
        XCTAssertEqual(Feedback.actionPressStyle, Feedback.impactStyle)
        XCTAssertEqual(Feedback.keyPressIntensity, Feedback.impactIntensity)
        XCTAssertEqual(Feedback.actionPressIntensity, Feedback.impactIntensity)
    }

    /// The aliases above would still pass if `modifierPress` went back to
    /// `selectionChanged()`. This count is what `playImpact` produces and
    /// a picker tick does not.
    func testModifierPressIsAnImpactNotASelectionTick() {
        let before = Feedback.impactCount
        Feedback.modifierPress()
        XCTAssertEqual(
            Feedback.impactCount, before + 1,
            "modifierPress went back to a selection tick")
    }
}
