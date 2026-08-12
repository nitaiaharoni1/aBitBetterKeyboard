import XCTest

/// Setup shared by every test that needs the keyboard extension running in its
/// own process.
///
/// Getting there is most of the work and none of the point: iOS only offers the
/// keyboard under "Add New Keyboard" once the containing app has launched,
/// `xcodebuild` reinstalls the app on every run and that drops the extension out
/// of the enabled list, and iOS denies a keyboard extension the App Group
/// container until the user grants Full Access. All of that is here so the tests
/// that follow are about their own subject.
///
/// Steps that cannot be completed `throw XCTSkip` rather than failing: a
/// simulator that will not cooperate should not break the shared suite. What
/// each test exists to catch is asserted after setup has genuinely succeeded.
class KeyboardExtensionTestCase: XCTestCase {

    var app: XCUIApplication!

    /// A letter that exists only on the Hebrew plane, and one that exists only on
    /// the English plane. Which of the two the extension draws is an observable
    /// of what the extension process read.
    let hebrewOnlyKey = "key-char-ק"
    let englishOnlyKey = "key-char-q"

    /// The system globe key sits in the keyboard dock, which belongs to the
    /// input system rather than to the app, so it has no identifier to address.
    /// This is the one place the suite taps a coordinate instead.
    let globeOffset = CGVector(dx: 0.104, dy: 0.954)

    /// Extra launch arguments a subclass needs on top of the standard two.
    var extraLaunchArguments: [String] { [] }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-uiTestSkipOnboarding"] + extraLaunchArguments
    }

    // MARK: Setup

    /// Adds the keyboard in Settings and grants Full Access. Idempotent: both
    /// steps are skipped if iOS is already in that state.
    func enableKeyboardWithFullAccess() throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()

        // Settings restores whatever screen it was left on, which after a
        // previous run is somewhere inside Keyboards. Walk back to the root
        // before navigating down.
        let general = settings.cells.staticTexts["General"]
        for _ in 0..<8 {
            if general.waitForExistence(timeout: 3) { break }
            let back = settings.navigationBars.buttons.element(boundBy: 0)
            guard back.exists else { break }
            back.tap()
        }
        guard general.waitForExistence(timeout: 10) else {
            throw XCTSkip("Could not reach the Settings root; cannot enable the keyboard")
        }
        general.tap()
        try tapCell(settings, "Keyboard")
        try tapCell(settings, "Keyboards")

        if !settings.cells.staticTexts["AI Keyboard"].waitForExistence(timeout: 3) {
            settings.cells["AddNewKeyboard"].tap()
            let offered = settings.cells.staticTexts["AI Keyboard"]
            guard offered.waitForExistence(timeout: 10) else {
                throw XCTSkip("iOS is not offering AI Keyboard; the extension is not installed")
            }
            offered.tap()
        }

        let row = settings.cells.staticTexts["AI Keyboard"]
        guard row.waitForExistence(timeout: 10) else {
            throw XCTSkip("AI Keyboard is not in the keyboards list")
        }
        row.tap()

        let fullAccess = settings.switches["Allow Full Access"]
        guard fullAccess.waitForExistence(timeout: 10) else {
            throw XCTSkip("No Allow Full Access switch")
        }
        if (fullAccess.value as? String) == "0" {
            // The switch's accessibility frame spans the whole row, so a centre
            // tap lands on the label and does nothing. Aim at the control.
            fullAccess.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()

            let allow = settings.alerts.buttons["Allow"].firstMatch
            if allow.waitForExistence(timeout: 10) { allow.tap() }
            Thread.sleep(forTimeInterval: 2.0)
        }
        guard (settings.switches["Allow Full Access"].value as? String) == "1" else {
            throw XCTSkip(
                "Full Access was not granted, so iOS keeps the shared container from the keyboard")
        }
        settings.terminate()
    }

    func tapCell(_ app: XCUIApplication, _ label: String) throws {
        let cell = app.cells.staticTexts[label].firstMatch
        guard cell.waitForExistence(timeout: 10) else {
            throw XCTSkip("Settings row '\(label)' never appeared")
        }
        cell.tap()
    }

    // MARK: Steps

    /// Focuses a real text field, which is what makes iOS spawn the keyboard
    /// extension. The in-app playground renders the keyboard in-process and
    /// would prove nothing.
    func openPersonalDictionaryAndFocusTextField() {
        app.tabBars.buttons["Settings"].tap()

        let row = app.descendants(matching: .any)
            .matching(identifier: "row-Personal dictionary").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Personal dictionary row never appeared")
        row.tap()

        let field = app.textFields["Add a word or name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "The dictionary text field never appeared")
        field.tap()
        Thread.sleep(forTimeInterval: 3.0)
    }

    /// Long-presses the globe and picks our keyboard by name, which is
    /// deterministic in a way that cycling through the installed keyboards is
    /// not.
    func switchToAIKeyboard() throws {
        // iOS restores the keyboard last used on this simulator, which after a
        // previous run is already ours.
        if app.descendants(matching: .any).matching(identifier: hebrewOnlyKey).firstMatch.exists
            || app.descendants(matching: .any).matching(identifier: englishOnlyKey).firstMatch.exists
        {
            return
        }

        let globe = app.coordinate(withNormalizedOffset: globeOffset)
        globe.press(forDuration: 1.4)

        let entry = app.staticTexts["AI Keyboard"]
        guard entry.waitForExistence(timeout: 8) else {
            throw XCTSkip("iOS did not offer AI Keyboard in the keyboard switcher")
        }
        entry.tap()
        Thread.sleep(forTimeInterval: 4.0)
    }

    func skipOnboardingIfPresent() {
        let start = app.buttons["Start typing"]
        let cont = app.buttons["Continue"]
        // Ten onboarding steps, so the bound clears ten taps rather than equalling them.
        for _ in 0..<14 {
            Thread.sleep(forTimeInterval: 0.5)
            if start.exists {
                start.tap()
                Thread.sleep(forTimeInterval: 1.0)
                return
            }
            guard cont.exists else { return }
            cont.tap()
        }
    }
}
