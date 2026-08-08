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

        let names = ["welcome", "languages", "add-keyboard", "full-access", "microphone", "try-it"]
        for (index, name) in names.enumerated() {
            settle()
            capture("onboarding-\(name)")
            if index < names.count - 1 {
                tap(app.buttons["Continue"], "Continue on \(name)")
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
    }

    // MARK: The keyboard and its panels

    func testKeyboardPanels() throws {
        app.launchArguments.append("-uiTestSkipOnboarding")
        app.launch()
        skipOnboardingIfPresent()

        tap(element("home-playground"), "playground card")
        settle(1.2)
        capture("keyboard-letters")

        // Emoji
        tap(element("bar-emoji"), "emoji button")
        settle()
        capture("keyboard-emoji")
        tap(element("bar-emoji"), "emoji button (close)")
        settle(0.5)

        // AI menu, then each result panel
        tap(element("bar-sparkle"), "sparkle button")
        settle()
        capture("ai-menu")

        tap(element("ai-action-fix"), "Fix")
        settle(0.3)
        capture("ai-fix-loading")
        settle(1.2)
        capture("ai-fix-result")

        tap(app.buttons["Back"], "back to AI menu")
        settle(0.6)
        tap(element("ai-action-rewrite"), "Rewrite")
        settle(1.4)
        capture("ai-rewrite")

        tap(app.buttons["Professional"], "Professional tone chip", timeout: 3)
        settle(1.4)
        capture("ai-tone-professional")

        tap(app.buttons["Close and go back to the keyboard"], "close panel")
        settle(0.6)

        // Dictation
        tap(element("key-dictation"), "mic key")
        settle(2.2)
        capture("dictation")
        tap(app.buttons["Cancel"], "cancel dictation")
        settle(0.6)

        // Hebrew
        tap(element("key-globe"), "globe key")
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

        tap(element("home-screen-context"), "screen context card")
        settle(1.0)
        capture("screen-context-off")

        // The sample conversation, not a real session: starting one of those
        // needs `RPSystemBroadcastPickerView`, whose button is system-vended and
        // does nothing here — the simulator runtime ships no `replayd`, so no
        // broadcast can start on this destination at all.
        let sample = app.buttons["Play a sample conversation"]
        XCTAssertTrue(sample.waitForExistence(timeout: 6), "missing element: sample conversation")
        if !sample.isHittable { app.swipeUp() }
        tap(sample, "play the sample conversation")
        settle(3.2)
        capture("screen-context-live")

        // Back to home, then into the keyboard with the session running.
        tap(app.navigationBars.buttons.element(boundBy: 0), "back")
        settle(1.0)
        capture("home-context-live")

        tap(element("home-playground"), "playground card")
        settle(1.4)
        capture("keyboard-context-strip")

        tap(element("context-reply"), "Reply in strip")
        settle(0.3)
        capture("reply-loading")
        settle(1.4)
        capture("reply-results")
    }

    // MARK: The rest of the app

    func testCompanionScreens() throws {
        app.launchArguments.append("-uiTestSkipOnboarding")
        app.launch()
        skipOnboardingIfPresent()

        tap(app.tabBars.buttons["Languages"], "Languages tab")
        settle()
        capture("languages")

        tap(app.tabBars.buttons["Settings"], "Settings tab")
        settle()
        capture("settings")

        tap(element("row-Personal dictionary"), "dictionary row", timeout: 4)
        settle()
        capture("dictionary")
        tap(app.navigationBars.buttons.element(boundBy: 0), "back from dictionary")
        settle()

        tap(element("row-Upgrade to Pro"), "subscription row", timeout: 4)
        settle()
        capture("subscription")
    }

    // MARK: Helpers

    /// Onboarding is six taps; skip it when the screens under test come later.
    private func skipOnboardingIfPresent() {
        let start = app.buttons["Start typing"]
        let cont = app.buttons["Continue"]
        var guardCount = 0
        while guardCount < 10 {
            settle(0.5)
            if start.exists {
                start.tap()
                settle(1.0)
                return
            }
            guard cont.exists else { return }
            cont.tap()
            guardCount += 1
        }
    }
}
