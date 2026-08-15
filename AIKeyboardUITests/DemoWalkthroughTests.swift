import XCTest

/// Drives the whole mock and writes a PNG per screen.
///
/// This exists because the alternative — synthesising mouse clicks at the host
/// window — depends on the Simulator's zoom level, steals the pointer, and taps
/// coordinates rather than controls. Here every tap addresses an accessibility
/// identifier, so the walkthrough survives layout changes.
///
/// Run it with:
///
///     TEST_RUNNER_SHOT_DIR=/path/to/output xcodebuild test \
///       -project AIKeyboard.xcodeproj -scheme AIKeyboard \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
///
/// `AIKeyboard` is the only shared scheme, and it is the one that carries the
/// test action. `xcodebuild` strips the `TEST_RUNNER_` prefix when forwarding
/// the variable to the runner, which is why the test reads plain `SHOT_DIR`.
final class DemoWalkthroughTests: XCTestCase {

    private var app: XCUIApplication!
    private var shotDirectory: URL!
    private var shotIndex = 0

    override func setUpWithError() throws {
        continueAfterFailure = true

        let path =
            ProcessInfo.processInfo.environment["SHOT_DIR"]
            ?? NSTemporaryDirectory().appending("aikeyboard-shots")
        shotDirectory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: shotDirectory, withIntermediateDirectories: true)

        app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        print("SHOT-DIR \(shotDirectory.path)")
    }

    /// Looks an element up by identifier regardless of the element type SwiftUI
    /// decided to expose it as. Keys land as `.key`, cards as `.button`, and the
    /// difference is not worth encoding at every call site.
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    // MARK: Capture

    private func capture(_ name: String) {
        shotIndex += 1
        let filename = String(format: "%02d-%@.png", shotIndex, name)
        let data = XCUIScreen.main.screenshot().pngRepresentation
        let url = shotDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url)
        } catch {
            // Fall back to the runner's own container, which is always writable.
            let fallback = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
            try? data.write(to: fallback)
            print("SHOT-FALLBACK \(fallback.path)")
        }
    }

    /// Taps an element once it exists, and says which one failed if it does not.
    @discardableResult
    private func tap(_ element: XCUIElement, _ label: String, timeout: TimeInterval = 6) -> Bool {
        guard element.waitForExistence(timeout: timeout) else {
            XCTFail("missing element: \(label)")
            return false
        }
        element.tap()
        return true
    }

    private func settle(_ seconds: TimeInterval = 0.7) {
        Thread.sleep(forTimeInterval: seconds)
    }

    // MARK: Onboarding

    func testOnboarding() throws {
        app.launch()

        // **`full-access` is deliberately absent.** NIT-15 removed the dedicated
        // Full Access step: it was the one blocking, alarming ask standing before
        // the user had seen the keyboard do anything, and the permission is now
        // raised where it buys something instead. The mention did not vanish with
        // it, so this list shrinking is the whole change and not a coverage loss:
        // `add-keyboard` still carries the Allow Full Access row and its one-tap
        // route to Settings, and `languages` still says the list is unreadable
        // until the permission is on. Nine steps now, six setup plus three
        // practice.
        let names = [
            "welcome", "palette", "languages", "add-keyboard", "switch",
            "microphone",
            "practice-writing", "practice-everyday", "practice-smart-tools"
        ]
        for (index, name) in names.enumerated() {
            settle()
            capture("onboarding-\(name)")
            if index < names.count - 1 {
                // On the switch step the primary action is the confirmation it
                // exists to collect; the walkthrough takes it, so the shot after
                // this one is a wizard whose globe row has ticked.
                let primary = name == "switch" ? "I've switched to it" : "Continue"
                tap(app.buttons[primary], "\(primary) on \(name)")
            }
        }

        // The last step embeds a live keyboard; exercise it before leaving.
        settle()
        tap(element("key-char-t"), "T key in onboarding preview", timeout: 3)
        settle(0.4)
        capture("onboarding-typing")

        tap(app.buttons["Start typing"], "Start typing")
        settle(1.2)
        capture("home")

        let globeConfirmation = element("setup-globe-switch")
        XCTAssertTrue(
            globeConfirmation.waitForExistence(timeout: 3)
                && globeConfirmation.label.localizedCaseInsensitiveContains("confirmed"),
            "the globe acknowledgement did not reach the Home setup card")

        // A published value surviving one navigation proves only the in-memory
        // path. Relaunch without `-uiTestReset` and require the same row to stay
        // confirmed, so dropping either the defaults write or the load bridge
        // fails here.
        app.terminate()
        app.launchArguments = []
        app.launch()
        let persistedConfirmation = element("setup-globe-switch")
        XCTAssertTrue(
            persistedConfirmation.waitForExistence(timeout: 5)
                && persistedConfirmation.label.localizedCaseInsensitiveContains("confirmed"),
            "the globe acknowledgement was lost when the app relaunched")
    }

    // MARK: The keyboard and its panels

    func testKeyboardPanels() throws {
        app.launchArguments.append("-uiTestSkipOnboarding")
        app.launch()
        skipOnboardingIfPresent()

        tap(element("home-playground"), "playground card")
        settle(1.2)
        capture("keyboard-letters")

        // **The walkthrough follows the action row now, because that is where
        // these controls are.** Emoji, the sparkle and the one-tap rewrite used to
        // sit at the ends of the suggestion bar and the three text actions were
        // rows inside a panel that covered the keys; they are keys in the action
        // row above the keys, and their answers arrive in the banner above that.
        // `bar-emoji` and `bar-sparkle` still exist as identifiers — a user can put
        // either back through the layout editor — but neither is in the shipped
        // default, so a walkthrough that addresses them is walking a keyboard
        // nobody has.

        // Emoji replaces the letter keys only. The action row stays put, so the
        // same Emoji key that opened the grid can close it — a panel that covered
        // the row would leave `key-emoji` unhittable while the grid was up.
        tap(element("key-emoji"), "emoji key")
        settle()
        let emojiKey = element("key-emoji")
        XCTAssertTrue(
            emojiKey.waitForExistence(timeout: 2) && emojiKey.isHittable,
            "emoji panel covered the action row; Emoji / Reply / Fix must stay reachable")
        capture("keyboard-emoji")
        tap(emojiKey, "emoji key (close)")
        settle(0.5)

        // Fix, straight from the row. No menu to open and no panel to close: the
        // keys stay visible for the whole call, which is the point of the redesign
        // — the user can see the sentence being corrected.
        tap(element("key-ai-fix"), "Fix key")
        settle(0.3)
        capture("ai-fix-working")
        settle(1.6)
        capture("ai-fix-result")
        // Either the answer is already in the field — Fix applies itself now, and
        // `bar-revert` is the way back it leaves in the suggestion row — or the
        // banner is holding a reason it failed. Both are terminal, and asserting on
        // the *answer* would make this a test of whether a model is reachable from a
        // simulator, which it is not: no backend token ships and the on-device model
        // has no assets here.
        XCTAssertTrue(
            element("bar-revert").exists || element("banner-dismiss").exists,
            "Fix left neither an applied answer nor a reason")

        // Rewrite in the default tone, which is the same three-way tap the bar
        // button used to make. Three versions come back and the first is written
        // straight into the field — the strip only pages through the other two on
        // the fallback path, where the field moved while the model was thinking.
        // See `KeyboardController.applyDirectly`.
        tap(element("key-quick-tone"), "one-tap rewrite key")
        settle(1.8)
        capture("ai-rewrite")

        if element("banner-dismiss").exists {
            tap(element("banner-dismiss"), "dismiss the banner")
            settle(0.5)
        }

        // Dictation. In the playground there is no recording session — the
        // microphone lives in the app and is opened deliberately, never by
        // walking a demo — so what this captures is the explanation, which is the
        // state a stock install is genuinely in. It used to capture a scripted
        // transcript mid-stream, which is the screenshot that made this feature
        // look finished for the whole of development.
        //
        // **The explanation is a banner now, not a panel.** `DictationPanel` is
        // deleted, so `dictation-explanation` and the ✕ in its header are gone with
        // it; the strip says the same two sentences with every key still visible,
        // which is the whole point of the screenshot this takes.
        tap(element("key-dictation"), "mic key")
        settle(0.6)
        XCTAssertTrue(
            element("banner-blocked").waitForExistence(timeout: 3),
            "the banner showed neither a session nor an explanation")
        XCTAssertTrue(
            element("key-a").exists || element("key-q").exists,
            "the keys were covered, which is the thing this change removed")
        capture("dictation")
        tap(element("banner-blocked-dismiss"), "dismiss the explanation")
        settle(0.6)

        // Hebrew
        let space = element("key-space")
        space.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
            .press(
                forDuration: 0.1,
                thenDragTo: space.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)))
        settle(0.8)
        capture("keyboard-hebrew")
        tap(element("key-plane-123"), "numbers plane", timeout: 3)
        settle(0.6)
        capture("keyboard-hebrew-numbers")
    }

    // MARK: Screen context

    func testScreenContext() throws {
        app.launchArguments.append("-uiTestSkipOnboarding")
        app.launch()
        skipOnboardingIfPresent()

        capture("home-context-off")

        XCTAssertTrue(
            element("screen-context-start-broadcast").waitForExistence(timeout: 6),
            "missing element: screen context start")

        tap(element("home-playground"), "playground card")
        settle(1.4)
        capture("keyboard-context-banner")

        // And Reply is a key in the action row rather than a button inside the
        // strip, which is what makes it reachable when there is no session at all —
        // the state the strip could not render, because it was not drawn.
        tap(element("key-ai-reply"), "Reply key")
        settle(0.3)
        capture("reply-working")
        settle(1.6)
        capture("reply-results")
    }

    // MARK: The rest of the app

    func testCompanionScreens() throws {
        app.launchArguments.append("-uiTestSkipOnboarding")
        app.launch()
        skipOnboardingIfPresent()

        XCTAssertTrue(
            element("dictation-start").waitForExistence(timeout: 6),
            "missing element: dictation start")
        capture("home-dictation")

        tap(app.tabBars.buttons["Languages"], "Languages tab")
        settle()
        capture("languages")

        tap(element("row-Personal dictionary"), "dictionary row", timeout: 4)
        settle()
        capture("dictionary")
        tap(app.navigationBars.buttons.element(boundBy: 0), "back from dictionary")
        settle()

        tap(app.tabBars.buttons["Keys"], "Keys tab")
        settle()
        capture("keys")

        tap(app.tabBars.buttons["Settings"], "Settings tab")
        settle()
        capture("settings")

        tap(element("row-Upgrade to Pro"), "subscription row", timeout: 4)
        settle()
        capture("subscription")
    }

    // MARK: Helpers

    /// Onboarding fits inside this guard; skip it when the screens under test come later.
    /// Nine steps today, so the bound has to clear nine taps, not equal them.
    /// It was ten until NIT-15 removed the dedicated Full Access step. The bound
    /// is deliberately loose rather than exact, which is why that change did not
    /// break this the way it broke `testOnboarding`'s hardcoded list.
    private func skipOnboardingIfPresent() {
        let start = app.buttons["Start typing"]
        let cont = app.buttons["Continue"]
        let switched = app.buttons["I've switched to it"]
        var guardCount = 0
        while guardCount < 14 {
            settle(0.5)
            if start.exists {
                start.tap()
                settle(1.0)
                return
            }
            // The switch step's primary action is its confirmation; tapping it
            // both collects the answer and advances, exactly like Continue does
            // everywhere else.
            if switched.exists {
                switched.tap()
                guardCount += 1
                continue
            }
            guard cont.exists else { return }
            cont.tap()
            guardCount += 1
        }
    }
}
