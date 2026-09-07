import XCTest

@testable import AIKeyboardCore

@MainActor
final class WordBoundaryTests: XCTestCase {
    func testAdjacentPunctuationStartsANewWordWithoutLosingEdgeMarks() {
        XCTAssertEqual(WordBoundary.prefix(in: "שלום,מה"), "מה")
        XCTAssertEqual(WordBoundary.prefix(in: "hello,world!"), "world!")
        XCTAssertEqual(WordBoundary.prefix(in: "say (hel"), "(hel")
        XCTAssertEqual(WordBoundary.prefix(in: ",usv"), ",usv")
        XCTAssertEqual(WordBoundary.prefix(in: "hello🎉"), "")
    }

    func testContextHandlesQuotesAndScriptSpecificSentenceMarks() {
        XCTAssertEqual(WordBoundary.words(in: "שלום,מה 'hello' don't"), ["שלום", "מה", "hello", "don't"])
        XCTAssertEqual(WordBoundary.sentenceWords(in: "old。'new' word", limit: 4), ["new", "word"])
        XCTAssertEqual(WordBoundary.sentenceWords(in: "قديم؟ كلمة", limit: 4), ["كلمة"])
        XCTAssertEqual(WordBoundary.sentenceWords(in: "old\nnew word", limit: 1), ["word"])
    }

    func testEmailAndURLRemainWholeTokens() {
        XCTAssertEqual(WordBoundary.words(in: "contact me@example.com"), ["contact", "me@example.com"])
        XCTAssertEqual(WordBoundary.prefix(in: "open https://example.com/path"), "https://example.com/path")
    }

    func testTappedMidwordCorrectionPreservesFollowingPunctuationAndEmoji() {
        for (before, after, replacement, expected) in [
            ("say he", "llo🎉next", "hello", "say hello🎉next"),
            ("say te", "h,world", "the", "say the,world"),
            ("שלום,של", "ומ!מה", "שלום", "שלום,שלום!מה")
        ] {
            let target = CursorTextTarget(before: before, after: after)
            let controller = KeyboardController(target: target, language: .english)
            controller.apply(Suggestion(text: replacement, language: .english))
            XCTAssertEqual(target.document, expected)
        }
    }

    func testSelectionRecognizesPunctuationBoundariesButRejectsMultipleWords() {
        let target = CursorTextTarget(before: "hello,", selecting: "recieve", after: ".next")
        let controller = KeyboardController(target: target, language: .english)
        XCTAssertEqual(controller.selectedWord, "recieve")
        controller.apply(Suggestion(text: "receive", language: .english))
        XCTAssertEqual(target.document, "hello,receive.next")

        let multiword = CursorTextTarget(before: "", selecting: "hello,world", after: "")
        let other = KeyboardController(target: multiword, language: .english)
        XCTAssertNil(other.selectedWord)
    }
}
