import UIKit
import XCTest

@testable import AIKeyboardCore

/// RTL delete and cursor glyphs must point the way the action moves. The broken
/// build always drew `delete.left` / `arrow.left`, which on Hebrew point away
/// from the caret.
final class DeleteSymbolTests: XCTestCase {

    func testEnglishKeepsLeftPointingBackspace() {
        assertLTRArrows(KeyboardLanguage.english)
    }

    func testGeorgianStaysUnflipped() {
        assertLTRArrows(KeyboardLanguage.georgian)
    }

    /// Not a hardcoded Hebrew/Arabic pair: Persian, Urdu, Pashto and Dhivehi
    /// get the flip from the script, the same way `isRightToLeft` does.
    func testEveryRightToLeftLanguageFlipsDeleteAndCursorArrows() {
        let rtl = KeyboardLanguage.allCases.filter(\.isRightToLeft)
        XCTAssertFalse(rtl.isEmpty)
        for language in rtl {
            XCTAssertEqual(
                KeyCap.backspaceSymbol(isRightToLeft: language.isRightToLeft),
                "delete.right",
                "\(language.rawValue) backspace still points left")
            XCTAssertEqual(
                KeyCap.deleteForwardSymbol(isRightToLeft: language.isRightToLeft),
                "delete.left",
                "\(language.rawValue) forward delete still points right")
            XCTAssertEqual(
                KeyCap.cursorLeftSymbol(isRightToLeft: language.isRightToLeft),
                "arrow.right",
                "\(language.rawValue) cursor left still points left")
            XCTAssertEqual(
                KeyCap.cursorRightSymbol(isRightToLeft: language.isRightToLeft),
                "arrow.left",
                "\(language.rawValue) cursor right still points right")
        }
    }

    /// The layout editor chrome is English. A missing `isRightToLeft:` default
    /// would flip the drawer whenever the phone locale is Hebrew.
    func testTheEditorDrawerStaysLTR() {
        XCTAssertEqual(SlotAction.backspace.glyph(), "delete.left")
        XCTAssertEqual(SlotAction.deleteForward.glyph(), "delete.right")
        XCTAssertEqual(SlotAction.cursorLeft.glyph(), "arrow.left")
        XCTAssertEqual(SlotAction.cursorRight.glyph(), "arrow.right")
    }

    func testTheBarCanAskForRTLGlyphs() {
        XCTAssertEqual(SlotAction.backspace.glyph(isRightToLeft: true), "delete.right")
        XCTAssertEqual(SlotAction.cursorLeft.glyph(isRightToLeft: true), "arrow.right")
    }

    func testHelperNamesAreRealSFSymbols() {
        for rtl in [false, true] {
            XCTAssertNotNil(UIImage(systemName: KeyCap.backspaceSymbol(isRightToLeft: rtl)))
            XCTAssertNotNil(UIImage(systemName: KeyCap.deleteForwardSymbol(isRightToLeft: rtl)))
            XCTAssertNotNil(UIImage(systemName: KeyCap.cursorLeftSymbol(isRightToLeft: rtl)))
            XCTAssertNotNil(UIImage(systemName: KeyCap.cursorRightSymbol(isRightToLeft: rtl)))
        }
    }

    func testHebrewCursorLeftSpeaksCursorRight() {
        XCTAssertEqual(
            KeyCap.cursorLeft.accessibilityLabel(isRightToLeft: true),
            "Cursor right")
        XCTAssertEqual(
            KeyCap.cursorRight.accessibilityLabel(isRightToLeft: true),
            "Cursor left")
        XCTAssertEqual(
            KeyCap.cursorLeft.accessibilityLabel(isRightToLeft: false),
            "Cursor left")
    }

    private func assertLTRArrows(_ language: KeyboardLanguage) {
        XCTAssertFalse(language.isRightToLeft, language.rawValue)
        XCTAssertEqual(
            KeyCap.backspaceSymbol(isRightToLeft: language.isRightToLeft),
            "delete.left")
        XCTAssertEqual(
            KeyCap.deleteForwardSymbol(isRightToLeft: language.isRightToLeft),
            "delete.right")
        XCTAssertEqual(
            KeyCap.cursorLeftSymbol(isRightToLeft: language.isRightToLeft),
            "arrow.left")
        XCTAssertEqual(
            KeyCap.cursorRightSymbol(isRightToLeft: language.isRightToLeft),
            "arrow.right")
    }
}
