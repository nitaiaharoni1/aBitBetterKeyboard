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

    override func setUp() {
        super.setUp()
        haptics = SharedStore.shared.haptics
        keySounds = SharedStore.shared.keySounds
        SharedStore.shared.haptics = true
        SharedStore.shared.keySounds = true
    }

    override func tearDown() {
        SharedStore.shared.haptics = haptics
        SharedStore.shared.keySounds = keySounds
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
}
