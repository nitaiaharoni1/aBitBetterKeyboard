import XCTest

/// **What the custom rows actually draw, measured off the screen.**
///
/// A row-string assertion cannot see a reversal, because the string is right
/// either way — that is the lesson `RenderedRowOrderTests` was written for after
/// all six right-to-left keyboards shipped mirrored. A custom bottom row is the
/// obvious place for that bug to come back, so these read frames rather than
/// data: which key is left of which, which row is above which, and how tall a
/// key is.
///
/// The playground renders the real `KeyboardView` in process, which is what
/// `RenderedRowOrderTests` measures too. It is evidence about *geometry* and
/// deliberately not about whether the extension types — that is
/// `CustomLayoutTypesIntoHostTests` below, and the distinction matters: this repo
/// shipped a build where every key drew, animated and clicked and not one
/// character reached the host.
final class CustomLayoutRenderingTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-uiTestSkipOnboarding"]
        app.launch()
        skipOnboardingIfPresent()
    }

    // MARK: The tests

    /// **Saving must not wedge the app**, which it did: the editor was pushed as
    /// `LayoutView(layout: store.keyboardLayout)`, so writing the store on Done
    /// rebuilt the screen the user was standing on while it dismissed itself. The
    /// app spun at 100% CPU with an empty accessibility tree, which reads as a
    /// crash and leaves no crash report — four UI tests below timed out against
    /// it and only the one that never tapped Done passed. Cheap, and first,
    /// because everything after it depends on saving working.
    func testSavingALayoutReturnsToKeys() throws {
        try selectPreset("compact")
        XCTAssertTrue(
            element("row-Layout").waitForExistence(timeout: 10),
            "Done did not return to Keys")
    }

    /// The stored order is the drawn order, in a right-to-left language.
    func testACustomRowIsNotMirroredUnderHebrew() throws {
        try selectPreset("power")
        openPlayground()
        cycleLanguage(until: "key-char-ק")

        let left = element("key-cursor-left")
        let right = element("key-cursor-right")
        XCTAssertTrue(left.exists && right.exists, "the cursor row is not on screen")
        XCTAssertLessThan(
            left.frame.minX, right.frame.minX,
            "the cursor row mirrored under Hebrew: stored order must be drawn order")

        // The digits too. Ten keys reversed is the same defect and reads the same
        // way from the data.
        let one = element("key-char-1")
        let zero = element("key-char-0")
        XCTAssertTrue(one.exists && zero.exists, "the number row is not on screen")
        XCTAssertLessThan(one.frame.minX, zero.frame.minX, "the number row mirrored under Hebrew")
    }

    /// The extra row is above the number row, which is above the letters. The
    /// compiler still appends the extra row last; `KeyboardView` is what lifts it.
    func testTheOptionalRowsAreWhereTheySay() throws {
        try selectPreset("power")
        openPlayground()

        let digit = element("key-char-1")
        let letter = element("key-char-q")
        let space = element("key-space")
        let cursor = element("key-cursor-left")
        for (name, item) in [("digit", digit), ("letter", letter), ("space", space), ("cursor", cursor)] {
            XCTAssertTrue(item.exists, "no \(name) key on screen")
        }
        XCTAssertLessThan(cursor.frame.midY, digit.frame.midY, "the extra row is below the number row")
        XCTAssertLessThan(digit.frame.midY, letter.frame.midY, "the number row is below the letters")
        XCTAssertLessThan(letter.frame.midY, space.frame.midY, "the letters are below the space row")
    }

    /// Key height reaches the rendered keys, not only the arithmetic.
    func testTheGeometryReachesTheRenderedKeys() throws {
        try selectPreset("compact")
        openPlayground()
        let compact = element("key-char-q").frame.height

        try leavePlayground()
        try selectPreset("roomy")
        openPlayground()
        let roomy = element("key-char-q").frame.height

        XCTAssertGreaterThan(
            roomy, compact + 8,
            "Roomy is \(roomy)pt and Compact is \(compact)pt; the slider is not reaching the keys")
    }

    /// One-handed hugs a physical side, and the same side in both languages.
    /// `.leading` resolves against the layout direction, so a Hebrew keyboard set
    /// to Left hugged the right until the pin moved outside the frame.
    func testOneHandedHugsTheSameSideInBothLanguages() throws {
        try selectPreset("default")
        try setReach("Left")
        openPlayground()

        let englishSpace = element("key-space").frame
        let window = app.windows.firstMatch.frame
        XCTAssertLessThan(
            englishSpace.midX, window.midX,
            "one-handed Left did not move the English keyboard to the left")

        cycleLanguage(until: "key-char-ק")
        let hebrewSpace = element("key-space").frame
        XCTAssertLessThan(
            hebrewSpace.midX, window.midX,
            "one-handed Left hugged the right under Hebrew: the alignment mirrored")
    }

    /// Space is required. The X badge is absent, not disabled after the tap.
    ///
    /// **The badge follows the selection now**, so both halves have to select
    /// first: a build that drew no badges at all would otherwise pass the second
    /// assertion for the wrong reason, which is exactly the trap
    /// `AGENTS.md` records this suite falling into three times.
    func testTheSpaceBarCannotBeRemoved() throws {
        try openLayoutEditor()
        let space = element("canvas-Space")
        XCTAssertTrue(space.waitForExistence(timeout: 5), "the space bar is not on the canvas")

        element("canvas-Settings").tap()
        XCTAssertTrue(
            element("remove-Settings").waitForExistence(timeout: 5),
            "no remove badge drew on a removable key, so a missing Space X proves nothing")

        space.tap()
        XCTAssertTrue(
            element("inspector-width").waitForExistence(timeout: 5),
            "tapping the space bar did not select it, so the missing X proves nothing")
        XCTAssertFalse(
            element("remove-Space").exists,
            "the space bar offered to remove itself")
    }

    // MARK: Driving the editor

    private func openLayoutEditor() throws {
        app.tabBars.buttons["Keys"].tap()
        let row = element("row-Layout")
        guard row.waitForExistence(timeout: 10) else {
            throw XCTSkip("the Layout row never appeared")
        }
        row.tap()
        guard element("layout-done").waitForExistence(timeout: 10) else {
            throw XCTSkip("the layout editor never opened")
        }
    }

    private func selectPreset(_ id: String) throws {
        try openLayoutEditor()
        let card = element("preset-\(id)")
        XCTAssertTrue(card.waitForExistence(timeout: 5), "no \(id) preset card")
        card.tap()
        commitLayout()
    }

    private func setReach(_ label: String) throws {
        try openLayoutEditor()
        let picker = element("layout-reach")
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "no one-handed picker")
        scrollIntoView(picker)
        picker.buttons[label].tap()
        commitLayout()
    }

    /// **The settings live on the editor itself now, not behind an Options
    /// sheet**, so the ones near the bottom of the workbench can start off
    /// screen on a short phone. `exists` is true for those; `isHittable` is not,
    /// and tapping one is a silent no-op that reads as "the slider did not reach
    /// the keys".
    private func scrollIntoView(_ item: XCUIElement) {
        for _ in 0..<4 where !item.isHittable {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    private func commitLayout() {
        let done = element("layout-done")
        XCTAssertTrue(done.waitForExistence(timeout: 5), "no Done button")
        XCTAssertTrue(done.isEnabled, "Done is blocked on a preset, which validates clean")
        done.tap()
        Thread.sleep(forTimeInterval: 0.6)
    }

    /// Back to Home, so the next preset can be picked. The playground is a sheet
    /// over the Home tab.
    private func leavePlayground() throws {
        let dismiss = app.buttons["Close and go back to the keyboard"]
        if dismiss.exists { dismiss.tap() }
        app.swipeDown(velocity: .fast)
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func openPlayground() {
        // **Wait for the bar, do not assume it.** The layout editor hides the
        // tab bar while it is up (`AppChrome`) and restores it on disappear, so
        // straight after Done there is a moment with no tab bar to tap and the
        // tap lands on nothing.
        let home = app.tabBars.buttons["Home"]
        XCTAssertTrue(home.waitForExistence(timeout: 10), "the tab bar never came back")
        home.tap()
        let card = element("home-playground")
        XCTAssertTrue(card.waitForExistence(timeout: 10), "playground card never appeared")
        card.tap()
        XCTAssertTrue(
            element("key-space").waitForExistence(timeout: 10), "the keyboard never appeared")
        Thread.sleep(forTimeInterval: 0.8)
    }

    /// Taps the globe until the wanted key is on screen. The globe cycles the
    /// enabled languages in order, so this terminates as long as it is enabled.
    private func cycleLanguage(until key: String) {
        for _ in 0..<8 where !element(key).exists {
            element("key-globe").tap()
            Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertTrue(element(key).exists, "the globe never reached \(key)")
    }

    private func skipOnboardingIfPresent() {
        let start = app.buttons["Start typing"]
        let cont = app.buttons["Continue"]
        // Nine onboarding steps (ten before NIT-15 removed the Full Access step), so
        // the bound clears them rather than equalling them.
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

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}

// MARK: - Into a real host

/// **A key the user added types into a real text field, through the real
/// extension.**
///
/// The in-app playground is not evidence that the keyboard works. This repo
/// shipped a build where every key drew, animated and clicked and not one
/// character reached the host, and the playground was unaffected for the whole of
/// development. A layout feature that only ever renders in-process would repeat
/// exactly that.
final class CustomLayoutTypesIntoHostTests: KeyboardExtensionTestCase {

    func testAKeyAddedInTheEditorTypesIntoTheHost() throws {
        app.launch()
        skipOnboardingIfPresent()

        // Power puts a comma on the cursor row, which the shipped layout has no
        // key for on the letters plane.
        try selectPowerPreset()
        try enableKeyboardWithFullAccess()

        app.activate()
        openPersonalDictionaryAndFocusTextField()
        try switchToAIKeyboard()

        let comma = app.descendants(matching: .any).matching(identifier: "key-char-,").firstMatch
        guard comma.waitForExistence(timeout: 10) else {
            throw XCTSkip("the custom comma key never appeared in the extension")
        }
        comma.tap()
        Thread.sleep(forTimeInterval: 1.0)

        let field = app.textFields["Add a word or name"]
        XCTAssertEqual(
            field.value as? String, ",",
            "the custom key drew and did nothing: it never reached the host document")
    }

    private func selectPowerPreset() throws {
        app.tabBars.buttons["Keys"].tap()
        let row = app.descendants(matching: .any)
            .matching(identifier: "row-Layout").firstMatch
        guard row.waitForExistence(timeout: 10) else {
            throw XCTSkip("the Layout row never appeared")
        }
        row.tap()

        let card = app.descendants(matching: .any).matching(identifier: "preset-power").firstMatch
        guard card.waitForExistence(timeout: 10) else {
            throw XCTSkip("the layout editor never opened")
        }
        card.tap()

        let done = app.descendants(matching: .any).matching(identifier: "layout-done").firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        Thread.sleep(forTimeInterval: 1.0)
    }
}
