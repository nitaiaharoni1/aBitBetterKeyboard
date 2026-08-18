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
