import XCTest

/// The test that was missing when this keyboard shipped to a phone and typed
/// nothing.
///
/// **What it caught, in hindsight.** `KeyboardController.target` was `weak` and
/// `KeyboardViewController` built its `ProxyTextTarget` in argument position, so
/// nothing retained it past `viewDidLoad`. Every keystroke on a real device was
/// `target?.insertText(…)` against nil: keys drew, animated and clicked, and not
/// one character reached the host app. The suggestion bar sat on its hardcoded
/// no-context defaults — `I / The / We` — because a nil target reads as an empty
/// document, and an empty document is indistinguishable from a field the user has
/// not typed in yet.
///
/// **Why the rest of the suite was green through all of it.** Every unit test and
/// the in-app playground pass a `MockTextTarget` that something else holds — a
/// `@StateObject` in `KeyboardPreview`, a method-scoped local in an
/// `XCTestCase`. A local outlives the assertion that follows it, so a weak
/// reference stays valid for exactly as long as the test needs and the test
/// passes against a keyboard that cannot type. And the two existing cross-process
/// tests do stand the real extension over a real `UITextField`
/// (`KeyboardExtensionTestCase.openPersonalDictionaryAndFocusTextField`), but
/// they assert only that a key *exists*. Neither ever pressed one.
///
/// So this is deliberately the dumbest test in the repo: press a letter, read the
/// field. It is the only thing here that exercises the extension's own wiring
/// rather than the package's, and the only shape of test that could have failed.
///
///     xcodebuild test -project AIKeyboard.xcodeproj -scheme AIKeyboard \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:AIKeyboardUITests/KeyboardTypesIntoHostTests
final class KeyboardTypesIntoHostTests: KeyboardExtensionTestCase {

    /// Defect D1: "the keyboard typing is not working, its not sending the typed
    /// chars to the input".
    func testPressingALetterPutsItInTheHostTextField() throws {
        let field = try standExtensionOverARealTextField()
        let before = fieldText(field)

        let key = try someLetterKey()
        let letter = String(key.identifier.dropFirst("key-char-".count))
        key.tap()

        // The extension is a separate process, so the insert is asynchronous from
        // here. Poll rather than sleep-and-hope.
        waitUntil { self.fieldText(field).count > before.count }

        let after = fieldText(field)
        XCTAssertTrue(
            after.localizedCaseInsensitiveContains(letter),
            """
            Tapped "\(letter)" on the real keyboard extension and the host field \
            still reads "\(after)". The extension drew a keyboard that inserts \
            nothing — which is exactly what a dropped text target looks like from \
            the outside, and exactly what shipped.
            """
        )
    }

    /// Defect D2: "and not the auto complete".
    ///
    /// **Two things this asserts that the obvious spelling does not.**
    ///
    /// It ignores candidate zero. `SuggestionEngine` unconditionally offers the
    /// literal keystrokes back so the user can never be trapped in a word they
    /// did not type, which makes "a candidate starts with what I typed" true of
    /// any build that can read the document at all — including one whose
    /// `UITextChecker` lookup is broken and shows one chip reading `hel` and two
    /// blanks forever. Only a word the engine had to *generate* counts.
    ///
    /// And it does not skip when nothing was typed. An earlier draft bailed with
    /// `XCTSkip` if the field stayed empty, which turned D1's regression into a
    /// green skip on the one test that covers D2 end to end.
    func testTheSuggestionBarCompletesWhatIsInTheHostField() throws {
        let field = try standExtensionOverARealTextField()

        // Three letters of an unambiguous English word. Typed through the
        // extension, so this also fails if D1 comes back.
        let typed = "hel"
        for letter in typed {
            let key = app.descendants(matching: .any)
                .matching(identifier: "key-char-\(letter)").firstMatch
            guard key.waitForExistence(timeout: 5) else {
                throw XCTSkip("The keyboard is not on an English plane; nothing to type here")
            }
            key.tap()
        }

        XCTAssertTrue(
            waitUntil { self.fieldText(field).localizedCaseInsensitiveContains(typed) },
            """
            Typed "\(typed)" on the real extension and the field reads \
            "\(fieldText(field))". Autocomplete cannot be judged because the \
            keystrokes never arrived — that is D1 again.
            """
        )

        let candidates = (0..<3).map { slot in
            app.descendants(matching: .any).matching(identifier: "suggestion-\(slot)").firstMatch
        }
        XCTAssertTrue(
            candidates[0].waitForExistence(timeout: 5), "The suggestion bar showed nothing at all")

        let labels = candidates.filter(\.exists).map(\.label)
        XCTAssertTrue(
            labels.contains {
                let label = $0.lowercased()
                return label != typed && label.hasPrefix(typed)
            },
            """
            After typing "\(typed)" the bar offered \(labels). None of those is a \
            word the engine generated — candidate zero is always an echo of the \
            keystrokes, so this bar is either the no-context defaults or an echo \
            beside two blanks. The field held "\(fieldText(field))".
            """
        )
    }

    /// **The one thing only a real `UITextDocumentProxy` can answer.**
    ///
    /// Committing a candidate deletes the partial word and types the whole one,
    /// and `deleteBackward(utf16Units:)` sizes that deletion by *measuring* — it
    /// reads `documentContextBeforeInput`, presses backspace, reads again, and
    /// subtracts. It has to, because one press is not one of anything fixed: on a
    /// real `UITextView` an emoji, a flag and a ZWJ sequence each go in a single
    /// press while `שָׁ` takes three, so any fixed count is wrong for one script or
    /// the other.
    ///
    /// What that buys is correctness and what it costs is an assumption: that the
    /// proxy's context reflects a deletion by the time the next line runs.
    /// `UITextDocumentProxy` documents its context as a snapshot and gives no
    /// acknowledgement, and no double can answer for it — `AIKeyboardCoreTests`
    /// drives a `UITextView`, which is synchronous by construction. If the real
    /// proxy lagged by one mutation the loop would read zero, stop after the first
    /// press, and the field would read `helhello ` — the whole word appended to the
    /// fragment instead of replacing it. That is the assertion below, and it is
    /// the reason this case is in the UI suite rather than the unit one.
    ///
    /// It does not measure `adjustTextPosition`'s unit, which is the other half of
    /// the same story. Nothing a user can reach calls it without a model answer
    /// first — it runs only when an AI result is applied — and no simulator can
    /// produce one, because the on-device model has no assets there and no backend
    /// URL ships. That claim is still asserted by a double and not by a host.
    func testCommittingACandidateReplacesTheFragmentRatherThanAppendingToIt() throws {
        let field = try standExtensionOverARealTextField()

        let typed = "hel"
        for letter in typed {
            let key = app.descendants(matching: .any)
                .matching(identifier: "key-char-\(letter)").firstMatch
            guard key.waitForExistence(timeout: 5) else {
                throw XCTSkip("The keyboard is not on an English plane; nothing to type here")
            }
            key.tap()
        }
        XCTAssertTrue(
            waitUntil { self.fieldText(field).localizedCaseInsensitiveContains(typed) },
            "Typed \"\(typed)\" and the field reads \"\(fieldText(field))\" — that is D1 again")

        // Candidate zero is the keystrokes echoed back, so committing it would
        // prove nothing: it replaces a fragment with itself. Take a word the
        // engine had to generate.
        let candidates = (0..<3).map { slot in
            app.descendants(matching: .any).matching(identifier: "suggestion-\(slot)").firstMatch
        }
        XCTAssertTrue(
            candidates[0].waitForExistence(timeout: 5), "The suggestion bar showed nothing at all")
        guard
            let chip = candidates.first(where: {
                $0.exists && $0.label.lowercased() != typed && $0.label.lowercased().hasPrefix(typed)
            })
        else {
            throw XCTSkip("The bar offered no generated completion to commit; that is D2, not this")
        }

        let word = chip.label
        chip.tap()

        XCTAssertTrue(
            waitUntil { self.fieldText(field).count > typed.count },
            "Tapping the candidate changed nothing in the field")
        XCTAssertEqual(
            fieldText(field), word + " ",
            """
            Committed "\(word)" over "\(typed)" and the field reads \
            "\(fieldText(field))". Anything longer than the word and a space means \
            the fragment was not deleted: against a real proxy the per-press \
            measurement in `deleteBackward(utf16Units:)` read zero and gave up, \
            which is the one thing a UITextView cannot tell us.
            """
        )
    }

    /// The banner lives above a fixed-height suggestion bar and key area, so the
    /// extension host must grow when it appears. The in-app playground cannot
    /// prove that wiring: only `KeyboardViewController` owns the height
    /// constraint. Refuse Fix on an empty real field, require the real extension's
    /// banner to be fully on screen and hittable, then dismiss it.
    ///
    /// Height check: `app.keyboards.firstMatch` is the UIKit keyboard window the
    /// extension occupies. Appearing the banner adds `bannerHeight` (58 pt).
    /// Status no longer reserves a row, so there is no 24-for-3 swap. Assert
    /// that number with a few points of simulator rounding, not a lower bound:
    /// a missed idle keyboard reports height 0 and would pass any `> 30` check
    /// against a real after-height.
    func testARefusalGrowsTheRealExtensionToFitTheBanner() throws {
        _ = try standExtensionOverARealTextField()

        let fix = app.descendants(matching: .any).matching(identifier: "key-ai-fix").firstMatch
        guard fix.waitForExistence(timeout: 8) else {
            throw XCTSkip("The current layout has no Fix key")
        }

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(
            keyboard.waitForExistence(timeout: 5),
            "the extension keyboard window was not on screen before the refusal")
        let beforeHeight = keyboard.frame.height
        XCTAssertGreaterThan(
            beforeHeight, 200,
            "idle keyboard height \(beforeHeight) is too small to be the real extension")

        fix.tap()

        let banner = app.descendants(matching: .any).matching(identifier: "banner-blocked").firstMatch
        XCTAssertTrue(
            banner.waitForExistence(timeout: 5) && banner.isHittable,
            "the refusal banner was clipped because the extension kept its idle height")

        let afterHeight = keyboard.frame.height
        XCTAssertEqual(
            afterHeight - beforeHeight, CGFloat(58), accuracy: 8,
            """
            Extension grew \(afterHeight - beforeHeight) pt after the banner appeared; \
            expected ~58 pt. The height-constraint wiring in KeyboardViewController \
            may not be reaching the host.
            """)

        let dismiss = app.descendants(matching: .any)
            .matching(identifier: "banner-blocked-dismiss").firstMatch
        XCTAssertTrue(dismiss.waitForExistence(timeout: 3) && dismiss.isHittable)
        dismiss.tap()
        XCTAssertTrue(
            waitUntil { !banner.exists },
            "dismissing the refusal left the dynamic banner row on screen")
        XCTAssertEqual(
            keyboard.frame.height, beforeHeight, accuracy: 8,
            "dismissing the banner did not restore the idle host height")
    }

    // MARK: Steps

    /// Everything between a fresh simulator and a keyboard extension running in
    /// its own process over a focused field the test can read back.
    private func standExtensionOverARealTextField() throws -> XCUIElement {
        app.launch()
        skipOnboardingIfPresent()
        app.terminate()

        try enableKeyboardWithFullAccess()

        app.launch()
        skipOnboardingIfPresent()
        openPersonalDictionaryAndFocusTextField()
        try switchToAIKeyboard()

        let field = app.textFields["Add a word or name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "The host text field is gone")
        return field
    }

    /// Polls a condition without `XCTestExpectation`.
    ///
    /// `expectation(description:)` created from an `XCTestCase` sets
    /// `assertForOverFulfill`, so a repeating `Timer` that fires a second time
    /// while the assertions after it are still running raises. XCUITest queries
    /// are synchronous, so a plain loop is both simpler and safe.
    @discardableResult
    private func waitUntil(
        timeout: TimeInterval = 10, _ condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return condition()
    }

    /// `value` is the placeholder string when a `UITextField` is empty, which
    /// would otherwise read as text the user typed.
    private func fieldText(_ field: XCUIElement) -> String {
        let value = (field.value as? String) ?? ""
        return value == field.placeholderValue ? "" : value
    }

    /// Any single-character key currently on screen, whichever plane the
    /// extension started on. Asking for a specific letter would couple this test
    /// to the language set, which is not its subject.
    private func someLetterKey() throws -> XCUIElement {
        let keys = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "key-char-"))
        guard keys.firstMatch.waitForExistence(timeout: 10) else {
            throw XCTSkip("No character keys on screen; the extension is not the active keyboard")
        }
        for index in 0..<keys.count {
            let key = keys.element(boundBy: index)
            guard key.exists, key.isHittable else { continue }
            // Single scalar only: skip anything that is not one printable letter.
            if key.identifier.dropFirst("key-char-".count).count == 1 { return key }
        }
        throw XCTSkip("No hittable single-character key")
    }
}
