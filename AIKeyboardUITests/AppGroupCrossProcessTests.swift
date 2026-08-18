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
/// `store.storedOpeningLanguage`, so turning English off in the app must leave
/// the extension rendering Hebrew. If the two processes are not sharing state
/// the extension reads an empty store, falls back to the shipped default of
/// `[.english, .hebrew]`, and draws QWERTY — which fails this test.
///
/// That property remembers the language the user last chose, and it cannot
/// weaken this test in either direction: `-uiTestReset` clears the remembered
/// value before the app launches, and a value that survived anyway is validated
/// against the enabled list, so an English one would be refused by the very
/// write this test is checking crossed the process boundary.
///
///     xcodebuild test -project AIKeyboard.xcodeproj -scheme AIKeyboard \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:AIKeyboardUITests/AppGroupCrossProcessTests
///
/// Installing and enabling the keyboard is `KeyboardExtensionTestCase`'s job.
final class AppGroupCrossProcessTests: KeyboardExtensionTestCase {

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
}
