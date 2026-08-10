import XCTest

@testable import AIKeyboardCore

/// Shift, in the keyboard's own language.
@MainActor
final class UppercasingTests: XCTestCase {

    private func typed(_ character: String, under language: KeyboardLanguage) -> String {
        let target = MockTextTarget()
        let controller = KeyboardController(target: target, language: language)
        controller.shift = .on
        controller.press(.character(character))
        return target.text
    }

    /// **Turkish has two i's and `uppercased()` only knows one.** A locale-less
    /// uppercase turns `i` into `I`, which in Turkish is the capital of the
    /// *dotless* ı — a different letter, and a spelling mistake in every word the
    /// shift key touches. `İstanbul` is the test everyone uses because `Istanbul`
    /// is wrong there in the same way `english` is wrong for `English`.
    func testTurkishShiftProducesTheDottedCapital() {
        XCTAssertEqual(typed("i", under: .turkish), "İ")
        XCTAssertEqual(typed("ı", under: .turkish), "I", "the dotless i capitalises without a dot")
    }

    /// And every other keyboard is byte for byte what it was, because that is the
    /// half a locale-aware uppercase could quietly change.
    func testEveryOtherLanguageIsUnchanged() {
        XCTAssertEqual(typed("i", under: .english), "I")
        XCTAssertEqual(typed("i", under: .german), "I")
        XCTAssertEqual(typed("é", under: .french), "É")
        XCTAssertEqual(typed("α", under: .greek), "Α")
        XCTAssertEqual(typed("б", under: .russian), "Б")
        // Scripts with no case at all come through untouched.
        XCTAssertEqual(typed("א", under: .hebrew), "א")
        XCTAssertEqual(typed("م", under: .arabic), "م")
    }
}
