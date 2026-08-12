import XCTest

/// **What the one-tap rewrite control does with nothing typed**, which is the
/// state a keyboard comes up in and spends most of its life in.
///
/// It shipped `.disabled(!canRun)` with a brand gradient behind an icon drawn at
/// full brand colour: only the background faded, so beside the fully-lit sparkle
/// it read as live. The owner of the first phone this went on tapped it on an
/// empty field, nothing happened, and nothing said why.
///
/// A unit test can hold the *decision* — `ToneButtonTapTests` does — and cannot
/// see a `.disabled()` modifier or a fill colour. This drives the real control and
/// asserts on what a tap actually reaches, which is the thing that was missing:
/// against the shipped build the tap lands on a disabled button and the AI menu
/// never opens.
///
/// **The control moved out of the suggestion bar and the defect did not.** It is
/// now a key in the action row under the keyboard, so this addresses
/// `key-quick-tone` rather than `bar-tone` — and it goes through
/// `KeyboardController.press(.quickTone)`, which asks `SuggestionBar.toneTap` the
/// same three-way question the bar button asked. That shared question is the whole
/// reason the key and the button could never disagree about an empty field; the
/// bar's own ends now ship empty, so this is the only place left that a user meets
/// it.
final class EmptyFieldBarTests: XCTestCase {

    private var app: XCUIApplication!
    private var shotDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = true
        let path =
            ProcessInfo.processInfo.environment["SHOT_DIR"]
            ?? NSTemporaryDirectory().appending("aikeyboard-bar")
        shotDirectory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: shotDirectory, withIntermediateDirectories: true)

        app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-uiTestSkipOnboarding"]
    }

    func testTheOneTapRewriteButtonAnswersATapOnAnEmptyField() throws {
        app.launch()
        skipOnboardingIfPresent()

        let card = element("home-playground")
        XCTAssertTrue(card.waitForExistence(timeout: 10), "playground card never appeared")
        card.tap()
        XCTAssertTrue(
            element("key-space").waitForExistence(timeout: 10), "the keyboard never appeared")

        // The playground is seeded on purpose, so the state under test has to be
        // made: hold delete until the field is empty. The key repeat accelerates
        // to 45ms and stops at 200, which is far more than the seed's 55
        // characters — and the placeholder appearing is how the field says it is
        // empty rather than how long the press was.
        element("key-backspace").press(forDuration: 8)
        let placeholder = app.staticTexts.containing(
            NSPredicate(format: "label BEGINSWITH 'Type in Hebrew or English'")
        ).firstMatch
        XCTAssertTrue(
            placeholder.waitForExistence(timeout: 5),
            "the field is not empty, so this is not the state the defect is about")
        capture("empty-field-bar")

        let tone = element("key-quick-tone")
        let fix = element("key-ai-fix")
        XCTAssertTrue(tone.exists, "the one-tap rewrite key is not in the action row")
        XCTAssertTrue(fix.exists, "the Fix key is not in the action row")

        // **The answer to an empty field is now the control itself, and this is
        // where that is measured.** Both keys are drawn dim and take no tap, which
        // is what `.disabled()` reports to the accessibility tree — the one thing
        // about a `.disabled()` modifier that *can* be read back, and the reason
        // this test exists rather than a unit test.
        XCTAssertFalse(tone.isEnabled, "the one-tap rewrite key is live on an empty field")
        XCTAssertFalse(fix.isEnabled, "the Fix key is live on an empty field")

        // And the tap reaches nothing. `KeyView` guards its own gesture rather than
        // trusting `.disabled()` to stop it — see `KeyView.acceptsTouches` — so this
        // is the assertion that rejects the build where the key is only *drawn*
        // disabled: there the tap still lands on `run(.rewrite)` and raises the
        // refusal this test used to wait for.
        tone.tap()
        XCTAssertFalse(
            element("banner-blocked").waitForExistence(timeout: 2),
            "the dimmed key answered the tap, which is the defect it is dim to prevent")
        XCTAssertTrue(tone.exists, "the action row was covered")
        capture("empty-field-tone-tapped")

        // **The other half of the contract, and the half a screenshot would never
        // show.** A key that never re-enables is a worse bug than one that never
        // disables, and every assertion above passes against it. A space first,
        // because whitespace is deliberately not text — `hasTextToWorkWith` trims —
        // so the keys have to still be dim after it and live only after the letter.
        element("key-space").tap()
        XCTAssertFalse(fix.isEnabled, "a space alone counted as something to fix")

        element("key-char-h").tap()
        let liveFix = NSPredicate(format: "isEnabled == true")
        expectation(for: liveFix, evaluatedWith: fix)
        expectation(for: liveFix, evaluatedWith: tone)
        waitForExpectations(timeout: 4) { error in
            XCTAssertNil(error, "Fix and Rewrite stayed disabled after something was typed")
        }
        capture("empty-field-typed-again")
    }

    // MARK: Helpers

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
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

    private func capture(_ name: String) {
        let url = shotDirectory.appendingPathComponent("\(name).png")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        print("SHOT \(url.path)")
    }
}
