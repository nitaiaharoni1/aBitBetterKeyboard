import UIKit
import XCTest

@testable import AIKeyboardCore

/// Completing a word or inserting a space after a pause. Both switches ship off.
@MainActor
final class IdleTypingTests: XCTestCase {

    private var completeOnIdle = false
    private var spaceOnIdle = false
    private var idleDelayMs = 300
    private var autocorrectLevel = AutocorrectLevel.full
    private var predictions = true

    override func setUp() {
        super.setUp()
        let store = SharedStore.shared
        completeOnIdle = store.completeOnIdle
        spaceOnIdle = store.spaceOnIdle
        idleDelayMs = store.idleDelayMs
        autocorrectLevel = store.autocorrectLevel
        predictions = store.predictions
        store.completeOnIdle = false
        store.spaceOnIdle = false
        store.idleDelayMs = 300
        store.autocorrectLevel = .full
        store.predictions = true
    }

    override func tearDown() {
        let store = SharedStore.shared
        store.completeOnIdle = completeOnIdle
        store.spaceOnIdle = spaceOnIdle
        store.idleDelayMs = idleDelayMs
        store.autocorrectLevel = autocorrectLevel
        store.predictions = predictions
        super.tearDown()
    }

    /// Completing on pause rewrites the word and leaves no trailing space. A
    /// build that called `apply` here would add one.
    ///
    /// **The completion is slot 1, not the bold slot.** Mid-word the engine
    /// leaves what you typed as default. A build that only commits `isDefault`
    /// no-ops here and leaves `hel`.
    func testCompleteOnIdleReplacesTheWordWithoutASpace() {
        SharedStore.shared.completeOnIdle = true
        let target = MockTextTarget(text: "hel")
        let controller = KeyboardController(target: target, language: .english)
        controller.suggestions = [
            Suggestion(text: "hel", language: .english, isDefault: true),
            Suggestion(text: "hello", language: .english)
        ]

        controller.performIdleTyping()

        XCTAssertEqual(target.text, "hello")
    }

    /// Autocorrect-off remakes the bold slot to the typed word so space will
    /// not swap. Complete on pause is a different switch and still finishes
    /// the word.
    func testCompleteOnIdleWorksWhenAutocorrectIsOff() {
        SharedStore.shared.completeOnIdle = true
        SharedStore.shared.autocorrectLevel = .off
        let target = MockTextTarget(text: "hel")
        let controller = KeyboardController(target: target, language: .english)
        controller.suggestions = [
            Suggestion(text: "hel", language: .english, isDefault: true),
            Suggestion(text: "hello", language: .english)
        ]

        controller.performIdleTyping()

        XCTAssertEqual(target.text, "hello")
    }

    /// Space on pause is the space bar, so Autocorrect still decides whether
    /// the bold word is inserted with it.
    func testSpaceOnIdleInsertsASpace() {
        SharedStore.shared.spaceOnIdle = true
        SharedStore.shared.autocorrectLevel = .off
        let target = MockTextTarget(text: "hel")
        let controller = KeyboardController(target: target, language: .english)
        controller.suggestions = [
            Suggestion(text: "hel", language: .english, isDefault: true),
            Suggestion(text: "hello", language: .english)
        ]

        controller.performIdleTyping()

        XCTAssertEqual(target.text, "hel ")
    }

    /// Both switches on is the completion plus a space, even when the typed
    /// letters still hold the bold slot.
    func testCompleteAndSpaceOnIdleCommitTheCompletionAndASpace() {
        SharedStore.shared.completeOnIdle = true
        SharedStore.shared.spaceOnIdle = true
        let target = MockTextTarget(text: "hel")
        let controller = KeyboardController(target: target, language: .english)
        controller.suggestions = [
            Suggestion(text: "hel", language: .english, isDefault: true),
            Suggestion(text: "hello", language: .english)
        ]

        controller.performIdleTyping()

        XCTAssertEqual(target.text, "hello ")
    }

    /// An empty prefix is not a word in progress. Firing here would keep adding
    /// spaces after every committed word.
    func testIdleTypingDoesNothingWhenNoWordIsInProgress() {
        SharedStore.shared.completeOnIdle = true
        SharedStore.shared.spaceOnIdle = true
        let target = MockTextTarget(text: "hello ")
        let controller = KeyboardController(target: target, language: .english)
        controller.suggestions = [
            Suggestion(text: "there", language: .english, isDefault: true)
        ]

        controller.performIdleTyping()

        XCTAssertEqual(target.text, "hello ")
    }

    /// Space still only inserts the bold word when Autocorrect is on. That
    /// switch is the one the user asked to keep in their hands.
    func testSpaceOnIdleRespectsAutocorrectOff() {
        SharedStore.shared.spaceOnIdle = true
        SharedStore.shared.autocorrectLevel = .off
        let target = MockTextTarget(text: "hel")
        let controller = KeyboardController(target: target, language: .english)
        controller.suggestions = [
            Suggestion(text: "hel", language: .english),
            Suggestion(text: "hello", language: .english, isDefault: true)
        ]

        controller.performIdleTyping()

        XCTAssertEqual(
            target.text, "hel ",
            "space on pause committed the bold word while Autocorrect was off")
    }

    /// The keyboard must read the suite, not the published copy filled at launch.
    func testIdleSwitchesAreReadFromTheOtherProcess() {
        SharedStore.shared.completeOnIdle = true
        SharedStore.shared.spaceOnIdle = true
        SharedStore.shared.userDefaults.set(false, forKey: SharedStore.Key.completeOnIdle)
        SharedStore.shared.userDefaults.set(false, forKey: SharedStore.Key.spaceOnIdle)
        XCTAssertTrue(SharedStore.shared.completeOnIdle)
        XCTAssertFalse(SharedStore.shared.storedCompleteOnIdle)
        XCTAssertFalse(SharedStore.shared.storedSpaceOnIdle)
    }

    /// A junk value in the suite must not become a zero-millisecond pause.
    func testAnUnknownPauseLengthFallsBackToThreeHundred() {
        SharedStore.shared.idleDelayMs = 300
        SharedStore.shared.userDefaults.set(12, forKey: SharedStore.Key.idleDelayMs)
        XCTAssertEqual(SharedStore.shared.storedIdleDelayMs, 300)
    }

    /// The picker is 100 ms jumps from 200 to 600. The old list (150, 300, 500,
    /// 800, 1200) is what this rejects.
    func testPauseLengthStepsFromTwoHundredToSixHundred() {
        XCTAssertEqual(SharedStore.idleDelayChoices, [200, 300, 400, 500, 600])
    }

    /// A password field must not be rewritten or spaced by a pause.
    func testIdleTypingDoesNothingInASecureField() {
        SharedStore.shared.completeOnIdle = true
        SharedStore.shared.spaceOnIdle = true
        let target = SecureTypingTarget(text: "hel")
        let controller = KeyboardController(target: target, language: .english)
        controller.suggestions = [
            Suggestion(text: "hel", language: .english, isDefault: true),
            Suggestion(text: "hello", language: .english)
        ]

        controller.performIdleTyping()

        XCTAssertEqual(target.text, "hel")
    }

    /// The emoji panel is not a pause in ordinary typing.
    func testIdleTypingDoesNothingWhileTheEmojiPanelIsOpen() {
        SharedStore.shared.completeOnIdle = true
        SharedStore.shared.spaceOnIdle = true
        let target = MockTextTarget(text: "hel")
        let controller = KeyboardController(target: target, language: .english)
        controller.overlay = .emoji
        controller.suggestions = [
            Suggestion(text: "hel", language: .english, isDefault: true),
            Suggestion(text: "hello", language: .english)
        ]

        controller.performIdleTyping()

        XCTAssertEqual(target.text, "hel")
    }

    /// **The wait starts at the last key, not at a suggestion refresh.** Opening
    /// the keyboard over a half-typed word, a caret tap, and the host's own
    /// `textDidChange` all call `refreshSuggestions`, and the old pause treated
    /// every one of those as "the user stopped typing". Space then landed 300 ms
    /// later in a word nobody had just keyed.
    func testIdleSpaceDoesNotFireFromARefreshAlone() async {
        SharedStore.shared.spaceOnIdle = true
        SharedStore.shared.idleDelayMs = 200
        SharedStore.shared.autocorrectLevel = .off
        let target = MockTextTarget(text: "hel")
        let controller = KeyboardController(target: target, language: .english)

        controller.refreshSuggestions()
        try? await Task.sleep(for: .milliseconds(350))

        XCTAssertEqual(
            target.text, "hel",
            "space on pause fired without a keystroke: \(target.text)")
    }

    /// A second letter has to restart the wait. Firing from the first letter
    /// would insert a space in the gap between keys.
    func testIdleSpaceDebouncesFromTheLastKeystroke() async {
        SharedStore.shared.spaceOnIdle = true
        SharedStore.shared.idleDelayMs = 200
        SharedStore.shared.autocorrectLevel = .off
        let target = MockTextTarget(text: "")
        let controller = KeyboardController(target: target, language: .english)

        controller.press(.character("h"))
        try? await Task.sleep(for: .milliseconds(80))
        controller.press(.character("e"))
        try? await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(
            target.text, "He",
            "space on pause fired from the first letter: \(target.text)")

        try? await Task.sleep(for: .milliseconds(350))

        XCTAssertEqual(
            target.text, "He ",
            "space on pause never fired after the last letter: \(target.text)")
    }

    /// A tap onto a different word is not a pause in typing this one.
    func testIdleSpaceDoesNotFireAfterTheCaretMovesToAnotherWord() async {
        SharedStore.shared.spaceOnIdle = true
        SharedStore.shared.idleDelayMs = 200
        SharedStore.shared.autocorrectLevel = .off
        let target = MockTextTarget(text: "")
        let controller = KeyboardController(target: target, language: .english)

        controller.press(.character("h"))
        controller.press(.character("i"))
        target.text = "other"
        controller.refreshSuggestions()
        try? await Task.sleep(for: .milliseconds(350))

        XCTAssertEqual(
            target.text, "other",
            "space on pause followed the caret onto a word that was not typed: \(target.text)")
    }

    func testRefinementCannotPublishIntoASecureField() {
        let target = SecureTypingTarget(text: "hel")
        let controller = KeyboardController(target: target, language: .english)
        let original = [Suggestion(text: "hel", language: .english, isDefault: true)]
        controller.suggestions = original
        controller.applyRefinement(["hello"], for: "hel")
        XCTAssertEqual(controller.suggestions, original)
    }

    func testIdlePauseBelongsToTheExactCaretAndDocument() async {
        SharedStore.shared.spaceOnIdle = true
        SharedStore.shared.autocorrectLevel = .off
        for change in ["none", "before", "after", "document", "prepare"] {
            let target = CursorTextTarget(before: "first hel", after: " last")
            let controller = KeyboardController(target: target, language: .english)
            controller.noteTypedInput()
            switch change {
            case "before": target.placeCaret(before: "other hel", after: " last")
            case "after": target.placeCaret(before: "first hel", after: " elsewhere")
            case "document": target.documentIdentifier = UUID()
            case "prepare": controller.prepareForNewDocument()
            default: break
            }
            controller.refreshSuggestions()
            let unchanged = target.document
            try? await Task.sleep(for: .milliseconds(500))
            XCTAssertEqual(
                target.document, change == "none" ? "first hel  last" : unchanged, change)
            controller.cancelRefinement()
        }
    }

    func testLeavingAndReturningToTheSameCaretDoesNotReviveThePause() async {
        SharedStore.shared.spaceOnIdle = true
        SharedStore.shared.autocorrectLevel = .off
        let target = CursorTextTarget(before: "say hel")
        let controller = KeyboardController(target: target, language: .english)
        controller.noteTypedInput()
        target.placeCaret(before: "other hel")
        controller.refreshSuggestions()
        target.placeCaret(before: "say hel")
        controller.refreshSuggestions()
        try? await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(target.document, "say hel")
    }

    func testIdleTypingDoesNotSplitAnExistingWordOrAssumeAnUnavailableTail() {
        SharedStore.shared.completeOnIdle = true
        SharedStore.shared.spaceOnIdle = true
        for after in ["lo", "'s", "7", ""] {
            let target = CursorTextTarget(before: "hel", after: after)
            target.afterContextIsAvailable = !after.isEmpty
            let controller = KeyboardController(target: target, language: .english)
            controller.suggestions = [
                Suggestion(text: "hel", language: .english, isDefault: true),
                Suggestion(text: "hello", language: .english)
            ]
            controller.performIdleTyping()
            XCTAssertEqual(target.document, "hel" + after)
        }
    }

    /// Backspace is a keystroke. The wait from the letters it removed is armed
    /// on a prefix that is gone, so a new wait has to start on what is left.
    func testIdleSpaceFiresAfterBackspace() async {
        SharedStore.shared.spaceOnIdle = true
        SharedStore.shared.idleDelayMs = 200
        SharedStore.shared.autocorrectLevel = .off
        let target = MockTextTarget(text: "hel")
        let controller = KeyboardController(target: target, language: .english)

        controller.press(.backspace)
        XCTAssertEqual(target.text, "he", "the state under test is the letters delete left")
        try? await Task.sleep(for: .milliseconds(350))

        XCTAssertEqual(
            target.text, "he ",
            "space on pause never fired after backspace: \(target.text)")
    }

    /// Deleting the last letter is not a pause in a word. A space here would
    /// appear in an empty field.
    func testIdleSpaceDoesNotFireWhenBackspaceClearsTheWord() async {
        SharedStore.shared.spaceOnIdle = true
        SharedStore.shared.idleDelayMs = 200
        SharedStore.shared.autocorrectLevel = .off
        let target = MockTextTarget(text: "h")
        let controller = KeyboardController(target: target, language: .english)

        controller.press(.backspace)
        try? await Task.sleep(for: .milliseconds(350))

        XCTAssertEqual(target.text, "", "space on pause landed in an empty field")
    }

    /// Complete on pause would undo the delete: `hel` to `he` must not become
    /// `hello`. Space on pause is the other switch and is tested above.
    func testCompleteOnIdleDoesNotRewriteAWordBeingDeleted() {
        SharedStore.shared.completeOnIdle = true
        let target = MockTextTarget(text: "hel")
        let controller = KeyboardController(target: target, language: .english)

        controller.press(.backspace)
        controller.suggestions = [
            Suggestion(text: "he", language: .english, isDefault: true),
            Suggestion(text: "hello", language: .english)
        ]
        controller.performIdleTyping()

        XCTAssertEqual(
            target.text, "he",
            "complete on pause rewrote a word delete was changing")
    }

    /// **Complete on pause is a completion switch, and it was applying
    /// corrections the commit cascade had explicitly declined.**
    ///
    /// The engine order is `[typed, best, ...]` and "best" is not always a
    /// completion: `restaraunt` offers `restaurant`, which the space bar refuses
    /// at `AutocorrectLevel.confident` because `TypoChannel` cannot price a
    /// rotation inside a ten-letter budget. `idleCompletion` took the first offer
    /// that was not the typed word, so a 300ms pause wrote in the very correction
    /// the autocorrect setting had just held — and it reads no level of its own,
    /// so the Autocorrect-off case is worse: the bold slot is pinned back to slot
    /// 0 there and this path ignores `isDefault`, which is how `תדוה` became
    /// `תודה` for somebody who had turned autocorrect off altogether.
    ///
    /// The suggestions are set by hand, as everywhere else in this file, so the
    /// assertion is about the rule rather than about whichever word Apple's
    /// checker ranks first today. Both arrays are the engine's own shape: the
    /// literal keystrokes at slot 0, a correction that disagrees with a key that
    /// was pressed at slot 1.
    func testCompleteOnPauseDoesNotApplyACorrectionThatDisagreesWithTheKeystrokes() {
        SharedStore.shared.completeOnIdle = true
        SharedStore.shared.autocorrectLevel = .confident
        let held = MockTextTarget(text: "restaraunt")
        let heldController = KeyboardController(target: held, language: .english)
        heldController.suggestions = [
            Suggestion(text: "restaraunt", language: .english, isDefault: true),
            Suggestion(text: "restaurant", language: .english)
        ]

        heldController.performIdleTyping()

        XCTAssertEqual(
            held.text, "restaraunt",
            "the pause pasted in a correction the space bar refuses at .confident")

        SharedStore.shared.autocorrectLevel = .off
        let hebrew = MockTextTarget(text: "תדוה")
        let hebrewController = KeyboardController(target: hebrew, language: .hebrew)
        hebrewController.suggestions = [
            Suggestion(text: "תדוה", language: .hebrew, isDefault: true),
            Suggestion(text: "תודה", language: .hebrew)
        ]

        hebrewController.performIdleTyping()

        XCTAssertEqual(
            hebrew.text, "תדוה",
            "and it rewrote a word for somebody who had switched autocorrect off")
    }

    /// The other half: a genuine completion still lands, and it lands through a
    /// trailing mark.
    ///
    /// `hel,` is the control that rejects a fix written as `hasPrefix` on the raw
    /// keystrokes — a comma is not a letter of the word, `hello` does not begin
    /// with `hel,`, and the whole switch would go silent the moment anybody typed
    /// a mark. `SuggestionEngine.comparable` is what both sides are compared on,
    /// the same reduction the bar already uses to decide whether to draw the echo.
    func testCompleteOnPauseStillFinishesAWordThroughATrailingMark() {
        SharedStore.shared.completeOnIdle = true
        let plain = MockTextTarget(text: "hel")
        let plainController = KeyboardController(target: plain, language: .english)
        plainController.suggestions = [
            Suggestion(text: "hel", language: .english, isDefault: true),
            Suggestion(text: "hello", language: .english)
        ]

        plainController.performIdleTyping()

        XCTAssertEqual(plain.text, "hello", "the ordinary completion stopped firing")

        let marked = MockTextTarget(text: "hel,")
        let markedController = KeyboardController(target: marked, language: .english)
        markedController.suggestions = [
            Suggestion(text: "hel,", language: .english, isDefault: true),
            Suggestion(text: "hello", language: .english)
        ]

        markedController.performIdleTyping()

        XCTAssertEqual(
            marked.text, "hello,",
            "a comma turned the completion off, which means the prefix test is reading "
                + "the keystrokes instead of the word")
    }
}

/// A field that says it is a password. Local to this file: `MockTextTarget`
/// answers `false` on purpose so the playground stays readable.
@MainActor
private final class SecureTypingTarget: TextTarget {
    var text: String

    init(text: String) { self.text = text }

    var documentContextBeforeInput: String? { text }
    var documentContextAfterInput: String? { "" }
    var selectedText: String? { nil }
    var isSecureTextEntry: Bool? { true }
    var textContentType: UITextContentType?? { .some(.password) }
    var keyboardType: UIKeyboardType? { .default }

    func insertText(_ newText: String) { text.append(newText) }
    func deleteBackward() { if !text.isEmpty { text.removeLast() } }
    func adjustTextPosition(byCharacterOffset offset: Int) {}
}
