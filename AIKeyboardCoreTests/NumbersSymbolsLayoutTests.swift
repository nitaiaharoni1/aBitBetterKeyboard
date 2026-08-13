import XCTest

@testable import AIKeyboardCore

/// The numbers and symbols planes follow SwiftKey's four-row layout: digits,
/// brackets, the page-specific symbols, then the `#+=` / `123` punctuation row.
///
/// The three-row iOS layout this replaced is what every assertion below rejects.
/// A count of "at least four" or a scan for `[` anywhere on the plane would pass
/// that build — `[` already lived on symbols — so the tests name the row and the
/// exact string.
final class NumbersSymbolsLayoutTests: LanguageCatalogueTestFixture {

    /// SwiftKey's first symbols row, on both pages. The old numbers plane put
    /// `-/:;()$&@"` here instead.
    static let brackets = "[]{}#%^*+="

    func testEnglishNumbersRowsMatchSwiftKey() {
        let rows = KeyboardLayout.rows(for: .english, plane: .numbers)
        XCTAssertEqual(rows.count, 4, "the old numbers plane was three rows")
        XCTAssertEqual(characters(in: rows[0]), KeyboardLanguage.english.digits)
        XCTAssertEqual(characters(in: rows[1]), Self.brackets)
        XCTAssertEqual(characters(in: rows[2]), "-/:;()$&@\"")
        assertPunctuationRow(rows[3], planeLabel: "#+=", language: .english)
    }

    func testEnglishSymbolsRowsMatchSwiftKey() {
        let rows = KeyboardLayout.rows(for: .english, plane: .symbols)
        XCTAssertEqual(rows.count, 4, "the old symbols plane was three rows and had no digits")
        XCTAssertEqual(characters(in: rows[0]), KeyboardLanguage.english.digits)
        XCTAssertEqual(characters(in: rows[1]), Self.brackets)
        XCTAssertEqual(characters(in: rows[2]), "_\\|~<>$€£·")
        assertPunctuationRow(rows[3], planeLabel: "123", language: .english)
    }

    /// Both pages keep the same four-row shape so `#+=` does not move the
    /// punctuation row under the thumb.
    func testBothPlanesHaveTheSameRowCountInEveryLanguage() {
        for language in KeyboardLanguage.allCases {
            let numbers = KeyboardLayout.rows(for: language, plane: .numbers)
            let symbols = KeyboardLayout.rows(for: language, plane: .symbols)
            XCTAssertEqual(numbers.count, 4, "\(language.displayName) numbers")
            XCTAssertEqual(symbols.count, 4, "\(language.displayName) symbols")
            XCTAssertEqual(
                characters(in: numbers[1]), Self.brackets, "\(language.displayName) numbers")
            XCTAssertEqual(
                characters(in: symbols[1]), Self.brackets, "\(language.displayName) symbols")
            XCTAssertEqual(
                characters(in: numbers[0]), language.digits, "\(language.displayName) numbers")
            XCTAssertEqual(
                characters(in: symbols[0]), language.digits, "\(language.displayName) symbols")
        }
    }

    /// ¥ and • used to occupy the two slots SwiftKey gives to £ and ·. A layout
    /// that dropped them without a long press would make yen and the bullet
    /// untypeable. Welsh's currency *is* £, so the long press has to sit on
    /// that leading key, not only on the extras list.
    func testTheDisplacedMarksStayReachableAsLongPresses() {
        let english = KeyboardLayout.rows(for: .english, plane: .symbols).flatMap(\.keys)
        XCTAssertEqual(english.first { $0.cap == .character("£") }?.alternates, ["¥"])
        XCTAssertEqual(english.first { $0.cap == .character("·") }?.alternates, ["•"])
        XCTAssertNil(english.first { $0.cap == .character("¥") })
        XCTAssertNil(english.first { $0.cap == .character("•") })

        let welsh = KeyboardLayout.rows(for: .welsh, plane: .symbols).flatMap(\.keys)
        XCTAssertEqual(welsh.first { $0.cap == .character("£") }?.alternates, ["¥"])
        XCTAssertEqual(characters(in: KeyboardLayout.rows(for: .welsh, plane: .symbols)[2]), "_\\|~<>£$€·")
    }

    /// Hebrew still earns ₪ on the connectors row. Replacing that row with the
    /// brackets row — the other way to "add SwiftKey's characters" without a
    /// fourth row — is what this rejects.
    func testHebrewKeepsItsCurrencyOnTheConnectorsRow() {
        let rows = KeyboardLayout.rows(for: .hebrew, plane: .numbers)
        XCTAssertEqual(characters(in: rows[2]), "-/:;()₪&@\"")
    }

    /// Four sliding rows have to occupy the same height as three letter rows.
    /// Growing the keyboard to fit them crosses the 368 pt fingerprint cliff;
    /// leaving them at 41 pt each is that growth.
    func testFourSymbolRowsFitInThreeLetterRowsOfHeight() {
        let keyHeight = Theme.Metrics.keyHeight
        let spacing = Theme.Metrics.rowSpacing
        let fitted = Theme.Metrics.fittedKeyHeight(
            slidingRows: 4, referenceRows: 3, keyHeight: keyHeight, rowSpacing: spacing)

        XCTAssertEqual(fitted, 28, accuracy: 0.001)
        XCTAssertEqual(
            4 * fitted + 3 * spacing,
            3 * keyHeight + 2 * spacing,
            accuracy: 0.001)

        XCTAssertEqual(
            Theme.Metrics.fittedKeyHeight(
                slidingRows: 3, referenceRows: 3, keyHeight: keyHeight, rowSpacing: spacing),
            keyHeight,
            "three rows must keep the shipped key height")
        XCTAssertEqual(
            Theme.Metrics.fittedKeyHeight(
                slidingRows: 4, referenceRows: 4, keyHeight: keyHeight, rowSpacing: spacing),
            keyHeight,
            "a layout that already paid for a number row must not shrink again")
    }

    /// The host height is still the letters-plane count. A `rowCount` that
    /// followed the numbers plane would make every default keyboard 52 pt taller
    /// and retire screen context.
    func testTheDefaultRowCountDoesNotGrowForTheExtraSymbolsRow() {
        XCTAssertEqual(KeyboardCustomization.default.rowCount, 5)
        XCTAssertEqual(
            Theme.Metrics.totalHeight(for: .default),
            368,
            accuracy: 0.001)
    }

    /// `extraSymbols` is 5 because 3 is the space row. Two rows with one id is
    /// a `ForEach` with duplicate identity, and using 3 for the new row is the
    /// collision that would do it.
    func testTheExtraSymbolsRowDoesNotReuseTheSpaceRowID() {
        for plane in [KeyboardPlane.numbers, .symbols] {
            var layout = KeyboardCustomization.default
            layout.showsNumberRow = true
            let rows = KeyboardLayout.rows(
                for: .english, plane: plane, showsGlobe: true, customization: layout)
            XCTAssertEqual(
                Set(rows.map(\.id)).count, rows.count, "\(plane) repeats a row id")
            XCTAssertEqual(
                rows.filter { $0.id == KeyboardLayout.RowID.extraSymbols }.count, 1,
                "\(plane) is missing the fourth symbols row")
            XCTAssertEqual(
                rows.filter { $0.id == KeyboardLayout.RowID.bottom }.count, 1,
                "\(plane) lost the space row")
        }
    }

    // MARK: Helpers

    private func characters(in row: KeyRow) -> String {
        row.keys.compactMap { key -> String? in
            if case .character(let value) = key.cap { return value }
            return nil
        }.joined()
    }

    private func assertPunctuationRow(
        _ row: KeyRow, planeLabel: String, language: KeyboardLanguage
    ) {
        let destination: KeyboardPlane = planeLabel == "123" ? .numbers : .symbols
        XCTAssertEqual(row.keys.first?.cap, .plane(destination, label: planeLabel))
        XCTAssertEqual(row.keys.last?.cap, .backspace)
        XCTAssertEqual(
            characters(in: row),
            KeyboardLayout.punctuationMarks(for: language))
    }
}
