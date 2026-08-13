import XCTest

@testable import AIKeyboardCore

/// Held backspace deletes a word, not a character.
///
/// **The assertion that rejects the old build is the one after a tap.** Finger-down
/// still eats one letter, so `"hello world"` becomes `"hello worl"`. A hold that
/// still called `press(.backspace)` would then leave `"hello wor"`. Word-delete
/// leaves `"hello "`.
@MainActor
final class WordDeleteTests: XCTestCase {

    func testPreviousWordSuffix() {
        let cases: [(String, String)] = [
            ("hello world", "world"),
            ("hello ", "hello "),
            ("hello   ", "hello   "),
            ("hello world!", "world!"),
            ("", ""),
            ("   ", "   "),
            ("שלום עולם", "עולם"),
            ("hello worl", "worl")
        ]
        for (before, expected) in cases {
            XCTAssertEqual(
                KeyboardController.previousWordSuffix(in: before), expected,
                "suffix of \(before.debugDescription)")
        }
    }

    func testTapStillDeletesOneCharacter() {
        check(before: "hello world") { controller, document, name in
            controller.press(.backspace)
            XCTAssertEqual(document(), "hello worl", "tap against \(name)")
        }
    }

    /// Load-bearing: character-repeat after the tap would leave `"hello wor"`.
    func testHeldTickDeletesTheRestOfTheWord() {
        check(before: "hello world") { controller, document, name in
            controller.press(.backspace)
            controller.deletePreviousWord()
            XCTAssertEqual(
                document(), "hello ",
                "hold against \(name); character-repeat would leave \"hello wor\"")
        }
    }

    func testAWordDeleteFromTrailingSpaceTakesTheWordToo() {
        check(before: "hello ") { controller, document, name in
            controller.deletePreviousWord()
            XCTAssertEqual(document(), "", "hold against \(name)")
        }
    }

    func testEmojiSearchDropsAWordFromTheQueryAndLeavesTheDocument() {
        check(before: "hello") { controller, document, name in
            controller.show(.emojiSearch)
            controller.setEmojiQuery("red heart")

            controller.deletePreviousWord()
            XCTAssertEqual(controller.emojiQuery, "red ", "after heart against \(name)")
            XCTAssertEqual(document(), "hello", "document changed against \(name)")

            controller.deletePreviousWord()
            // `"red "` word-deletes as one suffix, matching `"hello "`.
            XCTAssertEqual(controller.emojiQuery, "", "after red against \(name)")
            XCTAssertEqual(document(), "hello", "document changed against \(name)")

            controller.deletePreviousWord()
            XCTAssertEqual(controller.overlay, .emoji, "empty query against \(name)")
            XCTAssertEqual(document(), "hello", "closing search deleted text against \(name)")
        }
    }

    func testDeletedWordPrefixIsEmptyStringAfterTheLastWordNotNil() {
        check(before: "hello") { controller, document, name in
            controller.deletePreviousWord()
            XCTAssertEqual(document(), "", "last word against \(name)")
            XCTAssertEqual(
                controller.deletedWordPrefix, "",
                "nil against \(name) looks like nobody has deleted")
        }
    }

    /// One case, twice: against the model and against a real `UITextView`.
    private func check(
        before: String,
        body: (KeyboardController, () -> String, String) -> Void
    ) {
        let mock = CursorTextTarget(before: before)
        let live = LiveTextViewTarget(before: before)
        for (target, document, name) in [
            (mock as TextTarget, { mock.document }, "the model"),
            (live as TextTarget, { live.document }, "a real UITextView")
        ] {
            body(KeyboardController(target: target), document, name)
        }
    }
}
