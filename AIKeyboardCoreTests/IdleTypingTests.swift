import UIKit
import XCTest

@testable import AIKeyboardCore

/// Completing a word or inserting a space after a pause. Both switches ship off.
@MainActor
final class IdleTypingTests: XCTestCase {

    private var completeOnIdle = false
    private var spaceOnIdle = false
    private var idleDelayMs = 300
    private var autocorrect = true
    private var predictions = true

    override func setUp() {
        super.setUp()
        let store = SharedStore.shared
        completeOnIdle = store.completeOnIdle
        spaceOnIdle = store.spaceOnIdle
        idleDelayMs = store.idleDelayMs
        autocorrect = store.autocorrect
        predictions = store.predictions
        store.completeOnIdle = false
        store.spaceOnIdle = false
        store.idleDelayMs = 300
        store.autocorrect = true
        store.predictions = true
    }

    override func tearDown() {
        let store = SharedStore.shared
        store.completeOnIdle = completeOnIdle
        store.spaceOnIdle = spaceOnIdle
        store.idleDelayMs = idleDelayMs
        store.autocorrect = autocorrect
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
        SharedStore.shared.autocorrect = false
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
        SharedStore.shared.autocorrect = false
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
        SharedStore.shared.autocorrect = false
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

    func insertText(_ newText: String) { text.append(newText) }
    func deleteBackward() { if !text.isEmpty { text.removeLast() } }
    func adjustTextPosition(byCharacterOffset offset: Int) {}
}
