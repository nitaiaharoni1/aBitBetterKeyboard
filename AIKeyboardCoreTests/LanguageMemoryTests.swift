import UIKit
import XCTest

@testable import AIKeyboardCore

/// The keyboard opens on the language the user left it on.
///
/// **Every assertion here rejects the same shipped build, and it is simple to
/// state: the extension opened on `enabledLanguages.first`.** For the shipped
/// pair that is English, every single time, and iOS rebuilds a keyboard
/// extension whenever it likes — so a Hebrew speaker slid the space bar back by
/// hand several times a day and nothing in the product noticed.
///
/// The interesting half is what must *not* be remembered. `adoptFieldKeyboardType`
/// moves a Hebrew keyboard to English for a field that can only hold ASCII and
/// puts it back on the way out; if that imposition were remembered it would
/// outlive the process that knows how to undo it, and one email address would
/// leave a Hebrew user in English in every app on the phone.
@MainActor
final class LanguageMemoryTests: XCTestCase {

    private var saved = TypingSettings.snapshot()

    override func setUp() {
        super.setUp()
        saved = TypingSettings.snapshot()
        SharedStore.shared.enabledLanguages = [.english, .hebrew]
        SharedStore.shared.userDefaults.removeObject(forKey: SharedStore.Key.lastLanguage)
    }

    override func tearDown() {
        saved.restore()
        super.tearDown()
    }

    /// The real keyboard, which is the only controller allowed to remember
    /// anything.
    ///
    /// Every document here is empty on purpose. The flag selects the shared
    /// `PersonalLanguageModel`, but both it and the refiner stay lazy while
    /// suggestion work is suspended. Nothing here activates suggestions or types,
    /// so the suite neither learns fixtures nor starts a model call.
    private func keyboard(language: KeyboardLanguage) -> KeyboardController {
        KeyboardController(target: MockTextTarget(), language: language, isSystemKeyboard: true)
    }

    private func slide(_ controller: KeyboardController, _ points: CGFloat) {
        controller.spaceBarTouch(.began)
        controller.spaceBarTouch(.moved(points))
        controller.spaceBarTouch(.ended(points))
    }

    /// The whole feature in one case. The build before this answers `.english`.
    func testTheLanguageSlidToIsWhatTheNextLaunchOpensOn() {
        slide(keyboard(language: .english), 60)

        XCTAssertEqual(
            SharedStore.shared.storedOpeningLanguage, .hebrew,
            "the next launch would have opened on English again")
    }

    /// The globe key is the same choice made with a tap, and it walks the same
    /// list. A fix that only caught the slide leaves every globe user where they
    /// were.
    func testTheGlobeKeyIsRememberedToo() {
        keyboard(language: .english).advanceLanguage()

        XCTAssertEqual(SharedStore.shared.storedOpeningLanguage, .hebrew)
    }

    /// **The imposition the keyboard makes for itself is not a choice the user
    /// made.** An email box moves a Hebrew keyboard to English and
    /// `adoptFieldKeyboardType` puts it back when the user leaves. Remembering it
    /// would outlast the process holding that undo, so the one email address a
    /// person types would leave them in English everywhere, tomorrow.
    func testTheLatinAnAsciiFieldImposesIsNotRemembered() {
        let target = MockTextTarget()
        let controller = KeyboardController(
            target: target, language: .english, isSystemKeyboard: true)
        slide(controller, 60)
        XCTAssertEqual(controller.language, .hebrew, "the slide did not land on Hebrew")

        target.keyboardType = .emailAddress
        controller.prepareForNewDocument()

        XCTAssertEqual(controller.language, .english, "the email box did not reshape the keys")
        XCTAssertEqual(
            SharedStore.shared.storedOpeningLanguage, .hebrew,
            "one email address moved this user to English for good")
    }

    /// The playground and the layout editor drive a real controller and have real
    /// space bars. A scripted demo deciding what tomorrow's keyboard opens on is
    /// the defect `KeyboardController.personal` already records, one setting over.
    func testTheAppsPlaygroundDoesNotDecideWhatTheKeyboardOpensOn() {
        slide(KeyboardController(target: MockTextTarget(), language: .english), 60)

        XCTAssertEqual(
            SharedStore.shared.storedOpeningLanguage, .english,
            "a playground swipe wrote the real keyboard's opening language")
    }

    /// A language the user has since turned off in the app cannot come back by
    /// the side door. The remembered value is validated rather than trusted, so
    /// this falls through to the head of the list.
    func testALanguageNoLongerEnabledIsNotRestored() {
        slide(keyboard(language: .english), 60)
        SharedStore.shared.enabledLanguages = [.english, .russian]

        XCTAssertEqual(
            SharedStore.shared.storedOpeningLanguage, .english,
            "a keyboard opened on a language its owner had switched off")
    }

    /// A fresh install has nothing remembered, and answers exactly what the line
    /// this replaced answered.
    func testAFreshInstallOpensOnTheFirstEnabledLanguage() {
        SharedStore.shared.enabledLanguages = [.hebrew, .english]

        XCTAssertEqual(SharedStore.shared.storedOpeningLanguage, .hebrew)
    }

    // MARK: The instance that did not relaunch

    /// **iOS keeps one extension instance alive across any number of trips to
    /// Settings.** Validating the remembered language on the launch path is only
    /// half the rule: a user who switches Hebrew off in the app and comes back to
    /// WhatsApp was met by the Hebrew keyboard they had just removed, for as long
    /// as iOS chose not to rebuild the process.
    func testTurningOffTheCurrentLanguageMovesTheKeysOnTheNextAppearance() {
        let controller = keyboard(language: .english)
        slide(controller, 60)
        XCTAssertEqual(controller.language, .hebrew)

        SharedStore.shared.enabledLanguages = [.english]
        controller.settleLanguage()

        XCTAssertEqual(
            controller.language, .english,
            "the keyboard went on drawing a language its owner had deleted")
    }

    /// The control, and the one that matters: an appearance must not move a
    /// keyboard that is standing somewhere legitimate. This runs on every single
    /// appearance, so a version that reset to the head of the list would undo
    /// every swipe the moment the user switched apps.
    func testAnAppearanceLeavesAnEnabledLanguageAlone() {
        let controller = keyboard(language: .english)
        slide(controller, 60)

        controller.settleLanguage()

        XCTAssertEqual(
            controller.language, .hebrew, "an ordinary appearance undid the user's own swipe")
    }
}
