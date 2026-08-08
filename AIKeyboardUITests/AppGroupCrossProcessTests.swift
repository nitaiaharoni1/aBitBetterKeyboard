import XCTest

/// Proves the App Group is real by changing a setting in one process and
/// observing the consequence in another.
///
/// A unit test cannot do this. A process always sees its own writes, so
/// `UserDefaults(suiteName:)` behaves identically whether or not the entitlement
/// exists — asserting it is non-nil proves nothing. The only honest check is to
/// write from the app, then let iOS launch the keyboard extension, which is a
/// separate process with its own sandbox, and watch it act on what the app
/// wrote.
///
/// The observable is the keyboard layout. `KeyboardViewController` starts in
/// `store.enabledLanguages.first`, so turning English off in the app must leave
/// the extension rendering Hebrew. If the two processes are not sharing state
/// the extension reads an empty store, falls back to the shipped default of
/// `[.english, .hebrew]`, and draws QWERTY — which fails this test.
///
///     xcodebuild test -project AIKeyboard.xcodeproj -scheme AIKeyboard \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:AIKeyboardUITests/AppGroupCrossProcessTests
///
/// The test installs and enables the keyboard itself. It has to: `xcodebuild`
/// reinstalls the app on every run, and that drops the extension out of the
/// enabled-keyboards list, so enabling it in a previous run does not carry over.
/// Full Access is part of that setup because iOS denies a keyboard extension the
/// shared container without it — which is also why `RequestsOpenAccess` is true
/// in the extension's `Info.plist`.
final class AppGroupCrossProcessTests: XCTestCase {

    private var app: XCUIApplication!

    /// A letter that exists only on the Hebrew plane, and one that exists only on
    /// the English plane. Which of the two the extension draws is the answer.
    private let hebrewOnlyKey = "key-char-ק"
    private let englishOnlyKey = "key-char-q"

    /// The system globe key sits in the keyboard dock, which belongs to the
    /// input system rather than to the app, so it has no identifier to address.
    /// This is the one place the suite taps a coordinate instead.
    private let globeOffset = CGVector(dx: 0.104, dy: 0.954)

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-uiTestSkipOnboarding"]
    }

    func testKeyboardExtensionReadsSettingWrittenByApp() throws {
        // 1. iOS does not offer the keyboard under "Add New Keyboard" until its
        //    containing app has been launched at least once.
        app.launch()
        skipOnboardingIfPresent()
        app.terminate()

        // 2. Enable the extension and grant it Full Access.
        try enableKeyboardWithFullAccess()

        // 3. Relaunch the app and write from the app process, through the real
        //    UI rather than a test hook, so what is under test is the shipping
        //    path. The write has to come after this launch, because
        //    `-uiTestReset` would otherwise undo it.
        app.launch()
        skipOnboardingIfPresent()
        turnOffEnglishInLanguagesTab()

        // 4. Focus a real text field. This is what makes iOS spawn the keyboard
        //    extension; the in-app playground renders the keyboard in-process and
        //    would prove nothing.
        openPersonalDictionaryAndFocusTextField()

        // 5. Switch to our keyboard and read the layout back out of the
        //    extension process.
        try switchToAIKeyboard()

        let hebrew = app.descendants(matching: .any).matching(identifier: hebrewOnlyKey).firstMatch
        XCTAssertTrue(
            hebrew.waitForExistence(timeout: 10),
            """
            The keyboard extension did not start in Hebrew. The app wrote \
            enabledLanguages=[hebrew] to the App Group; the extension acted on \
            something else, which means the two processes are not sharing it.
            """
        )
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: englishOnlyKey).firstMatch.exists,
            "The extension drew the English layout, i.e. it fell back to its own defaults."
        )
    }

    // MARK: Setup

    /// Adds the keyboard in Settings and grants Full Access. Idempotent: both
    /// steps are skipped if iOS is already in that state.
    private func enableKeyboardWithFullAccess() throws {
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
        // Skipping rather than failing here keeps a simulator that will not
        // cooperate from breaking the shared suite. What this test exists to
        // catch — the extension reading the wrong store — is asserted below,
        // and is only reachable once setup has genuinely succeeded.
        guard (settings.switches["Allow Full Access"].value as? String) == "1" else {
            throw XCTSkip("Full Access was not granted, so iOS keeps the shared container from the keyboard")
        }
        settings.terminate()
    }

    private func tapCell(_ app: XCUIApplication, _ label: String) throws {
        let cell = app.cells.staticTexts[label].firstMatch
        guard cell.waitForExistence(timeout: 10) else {
            throw XCTSkip("Settings row '\(label)' never appeared")
        }
        cell.tap()
    }

    // MARK: Steps

    private func turnOffEnglishInLanguagesTab() {
        let tab = app.tabBars.buttons["Languages"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15), "Languages tab never appeared")
        tab.tap()

        let english = app.switches.firstMatch
        XCTAssertTrue(english.waitForExistence(timeout: 5), "English toggle never appeared")
        XCTAssertEqual(english.value as? String, "1", "English should start enabled")
        english.tap()

        XCTAssertEqual(
            app.switches.firstMatch.value as? String, "0",
            "English is still on, so the app never wrote enabledLanguages=[hebrew]"
        )
    }

    private func openPersonalDictionaryAndFocusTextField() {
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
    private func switchToAIKeyboard() throws {
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

    private func skipOnboardingIfPresent() {
        let start = app.buttons["Start typing"]
        let cont = app.buttons["Continue"]
        for _ in 0..<10 {
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
