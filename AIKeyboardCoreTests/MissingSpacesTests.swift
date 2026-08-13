import XCTest

@testable import AIKeyboardCore

/// Local recovery for Fix when the model echoes jammed text unchanged.
///
/// Every assertion names a build it rejects. A test that the prompt *asks* for
/// a split is true of a keyboard that still writes `מהאופישלומהקורה` into
/// WhatsApp — that was the previous change, and the screenshots.
final class MissingSpacesTests: XCTestCase {

    /// The WhatsApp screenshot. The model returned this string unchanged.
    func testJammedHebrewFromTheScreenshotIsSplit() {
        XCTAssertEqual(
            MissingSpaces.restored("מהאופישלומהקורה"),
            "מה אופי שלו מה קורה")
    }

    func testJammedEnglishIsSplit() {
        XCTAssertEqual(MissingSpaces.restored("hellothere"), "hello there")
    }

    /// `therapist` is in the list. Splitting it is `the rapist`.
    func testAKnownWordIsNotSplit() {
        XCTAssertEqual(MissingSpaces.restored("therapist"), "therapist")
        XCTAssertEqual(MissingSpaces.restored("לעבודה"), "לעבודה")
        XCTAssertEqual(MissingSpaces.restored("anyway"), "anyway")
    }

    /// Slang the list does not know, and cannot cover with real pieces.
    func testSlangTheListDoesNotKnowIsLeftAlone() {
        XCTAssertEqual(MissingSpaces.restored("יאללה"), "יאללה")
    }

    /// `מהגן` is four letters of real Hebrew (from the garden). Splitting it is
    /// `מה גן`. The floor is six, which is `מהקורה`.
    func testAShortCliticCompoundIsNotSplit() {
        XCTAssertEqual(MissingSpaces.restored("מהגן"), "מהגן")
        XCTAssertEqual(MissingSpaces.restored("מהקורה"), "מה קורה")
    }

    func testAnAlreadySpacedMessageIsUnchanged() {
        XCTAssertEqual(
            MissingSpaces.restored("יאללה סבבה, נדבר אח\"כ"),
            "יאללה סבבה, נדבר אח\"כ")
        XCTAssertEqual(MissingSpaces.restored("Already right."), "Already right.")
    }

    func testAJammedWordInASpacedMessageIsSplit() {
        XCTAssertEqual(
            MissingSpaces.restored("היי מהאופישלומהקורה"),
            "היי מה אופי שלו מה קורה")
    }

    /// `המקורן` as the whole field is a word with its prefix glued on, not two
    /// words. The same letters inside a longer jammed run can still be a piece.
    func testAPrefixedStemAloneIsNotSplitOffItsPrefix() {
        XCTAssertEqual(MissingSpaces.restored("המקורן"), "המקורן")
        XCTAssertEqual(
            MissingSpaces.restored("מהמושלהמקורן"),
            "מה מושל המקורן")
    }
}
