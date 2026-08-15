import XCTest

@testable import AIKeyboardCore

/// Compiled-layout tests extracted from `CustomLayoutTests`.
final class CustomLayoutCompilerTests: XCTestCase {

    // MARK: Compiling

    /// **The letter rows are untouched by customization, in every language and on
    /// every plane.** This is the load-bearing test of the whole feature.
    ///
    /// It used to compare the *whole* compiled keyboard against the pre-feature
    /// one, which was the right check for as long as the default was a no-op. The
    /// default deliberately changed — dictation moved to the action row and the
    /// bar was emptied — so that comparison now pins a product decision rather
    /// than an invariant. What must never change is this: whatever the user does,
    /// the three rows that come out of `letterLayouts` come out unaltered.
    func testCustomizationNeverTouchesTheLetterRows() {
        var wild = KeyboardCustomization.default
        wild.showsNumberRow = true
        wild.bottomRow = [
            SlotSpec(action: .numbersPlane), SlotSpec(action: .globe),
            SlotSpec(action: .space, width: .fill), SlotSpec(action: .ret)
        ]
        wild.cursorRow = [SlotSpec(action: .text("x"), width: .fill)]

        for language in KeyboardLanguage.allCases {
            for plane in [KeyboardPlane.letters, .numbers, .symbols] {
                let stock = KeyboardLayout.rows(for: language, plane: plane)
                for layout in [KeyboardCustomization.default, wild] {
                    let compiled = KeyboardLayout.rows(
                        for: language, plane: plane, showsGlobe: true, customization: layout)
                    // The stock rows appear in order, unaltered, somewhere in the
                    // compiled set: after the number row when there is one.
                    let offset = (layout.showsNumberRow && plane == .letters) ? 1 : 0
                    for (index, row) in stock.enumerated() {
                        let mine = compiled[index + offset]
                        XCTAssertEqual(
                            row.keys.map(\.cap), mine.keys.map(\.cap), "\(language) \(plane)")
                        XCTAssertEqual(
                            row.keys.map(\.width), mine.keys.map(\.width), "\(language) \(plane)")
                        XCTAssertEqual(
                            row.sideInsetUnits, mine.sideInsetUnits, "\(language) \(plane)")
                    }
                }
            }
        }
    }

    /// The compiled bottom row is exactly what the model describes, in order.
    func testTheBottomRowCompilesToWhatTheModelSays() {
        let layout = KeyboardCustomization.default
        let row = KeyboardLayout.rows(
            for: .english, plane: .letters, showsGlobe: true,
            customization: layout)[KeyboardLayout.RowID.bottom]
        XCTAssertEqual(row.keys.count, layout.bottomRow.count)
        XCTAssertEqual(
            row.keys.map(\.width),
            layout.bottomRow.map { spec in
                switch spec.width {
                case .fill: return KeyWidth.flexible
                case .units(let value): return KeyWidth.unit(value)
                }
            })
    }

    func testEveryRowHasAUniqueID() {
        var layout = KeyboardCustomization.default
        layout.showsNumberRow = true
        layout.cursorRow = [SlotSpec(action: .cursorLeft), SlotSpec(action: .cursorRight)]
        let rows = KeyboardLayout.rows(
            for: .english, plane: .letters, showsGlobe: true, customization: layout)
        XCTAssertEqual(rows.count, 6)
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
    }

    func testTheNumberRowSitsAboveTheLetters() {
        var layout = KeyboardCustomization.default
        layout.showsNumberRow = true
        let rows = KeyboardLayout.rows(
            for: .english, plane: .letters, showsGlobe: true, customization: layout)
        XCTAssertEqual(
            rows.first?.keys.compactMap(\.characterValue),
            ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"])
    }

    /// Arabic and Persian do not write their digits with the same glyphs, and
    /// `KeyboardLanguage.digits` already knows.
    func testTheNumberRowUsesTheLanguagesOwnDigits() {
        var layout = KeyboardCustomization.default
        layout.showsNumberRow = true
        let rows = KeyboardLayout.rows(
            for: .arabic, plane: .letters, showsGlobe: true, customization: layout)
        XCTAssertEqual(
            rows.first?.keys.compactMap(\.characterValue).joined(), KeyboardLanguage.arabic.digits)
    }

    /// The digits are already the top row of the numbers and symbols planes;
    /// drawing them twice is not a feature.
    func testTheNumberRowIsNotDrawnOnTheNumbersOrSymbolsPlane() {
        for plane in [KeyboardPlane.numbers, .symbols] {
            var layout = KeyboardCustomization.default
            layout.showsNumberRow = false
            let without = KeyboardLayout.rows(
                for: .english, plane: plane, showsGlobe: true, customization: layout
            ).count
            layout.showsNumberRow = true
            let with = KeyboardLayout.rows(
                for: .english, plane: plane, showsGlobe: true, customization: layout
            ).count
            // The digits are already the top row here; drawing them twice is not a
            // feature. Compared rather than counted, because the default also ships
            // an action row and an absolute count pins two decisions at once.
            XCTAssertEqual(with, without, "\(plane)")
        }
    }

    /// The compiler still appends this row last. `KeyboardView` draws it first,
    /// above the letters — `CustomLayoutRenderingTests.testTheOptionalRowsAreWhereTheySay`
    /// is the measurement of that.
    func testTheCursorRowCompilesAfterTheBottomRow() {
        var layout = KeyboardCustomization.default
        layout.cursorRow = [SlotSpec(action: .cursorLeft), SlotSpec(action: .cursorRight)]
        let rows = KeyboardLayout.rows(
            for: .english, plane: .letters, showsGlobe: true, customization: layout)
        XCTAssertEqual(rows.last?.keys.map(\.cap), [.cursorLeft, .cursorRight])
    }

    /// The layout stores the globe; iOS decides whether it is drawn.
    func testTheGlobeKeyDropsOutWhenTheSystemDoesNotWantIt() {
        let rows = KeyboardLayout.rows(
            for: .english, plane: .letters, showsGlobe: false, customization: .default)
        XCTAssertFalse(rows.flatMap(\.keys).contains { $0.cap == .globe })
    }

    /// The plane key is resolved at draw time, so it says where it goes *back* to.
    ///
    /// **`rows[RowID.bottom]` was not addressing by id, and the comment saying it
    /// was is how it survived.** `RowID.bottom` is the literal `3`, `rows` is a
    /// plain `[KeyRow]`, and nothing in the package gives it a by-id subscript —
    /// so this read *position* 3, which was the bottom row only for as long as
    /// the numbers plane drew three rows above it. `RowID.extraSymbols` added a
    /// fourth (see `NumbersSymbolsLayoutTests`), position 3 became that row, and
    /// this has been reading the `#+= . , ? ! '` strip and failing ever since.
    /// Look it up.
    func testTheBottomRowSwitchesBackFromTheNumbersPlane() throws {
        let rows = KeyboardLayout.rows(
            for: .hebrew, plane: .numbers, showsGlobe: true, customization: .default)
        let bottom = try XCTUnwrap(
            rows.first { $0.id == KeyboardLayout.RowID.bottom },
            "no row carries the bottom row's id")
        XCTAssertTrue(
            bottom.keys.map(\.cap)
                .contains(.plane(.letters, label: KeyboardLanguage.hebrew.lettersPlaneLabel)),
            "the 123 key on the numbers plane does not offer a way back to the letters")
    }

    /// **A plane key must go somewhere it is not, on every plane it is drawn on.**
    /// `.symbolsPlane` used to resolve to the letters plane from letters and to
    /// the symbols plane from symbols, so a symbols key the user placed themselves
    /// drew, pressed and switched to the plane already showing on two planes out
    /// of three.
    func testAPlaneKeyNeverTargetsThePlaneItIsStandingOn() {
        for action in [SlotAction.numbersPlane, .symbolsPlane] {
            for plane in [KeyboardPlane.letters, .numbers, .symbols] {
                var layout = KeyboardCustomization.default
                layout.bottomRow = [
                    SlotSpec(action: action), SlotSpec(action: .numbersPlane),
                    SlotSpec(action: .globe), SlotSpec(action: .space, width: .fill),
                    SlotSpec(action: .ret)
                ]
                let rows = KeyboardLayout.rows(
                    for: .english, plane: plane, showsGlobe: true, customization: layout)
                guard case .plane(let destination, _) = rows[3].keys[0].cap else {
                    return XCTFail("\(action) on \(plane) is not a plane key")
                }
                XCTAssertNotEqual(
                    destination, plane,
                    "\(action) on the \(plane) plane switches to the plane it is already on")
            }
        }
    }

    func testTheSymbolsKeyReachesTheSymbolsPlaneFromLetters() {
        var layout = KeyboardCustomization.default
        layout.bottomRow[0] = SlotSpec(action: .symbolsPlane, width: .units(1.3))
        let rows = KeyboardLayout.rows(
            for: .english, plane: .letters, showsGlobe: true, customization: layout)
        XCTAssertTrue(
            rows[KeyboardLayout.RowID.bottom].keys.map(\.cap)
                .contains(.plane(.symbols, label: "#+=")))
    }

    /// A key has to stay addressable by a test and a screen reader *and* be unique
    /// on its row. Both halves, in one assertion.
    func testCompiledKeysKeepAnAddressableIDAndAUniqueOne() {
        var layout = KeyboardCustomization.default
        layout.bottomRow.append(SlotSpec(action: .text(",")))
        layout.bottomRow.append(SlotSpec(action: .text(",")))
        let row = KeyboardLayout.rows(
            for: .english, plane: .letters, showsGlobe: true, customization: layout)[3]

        let commas = row.keys.filter { $0.cap == .character(",") }
        XCTAssertEqual(commas.count, 2)
        XCTAssertNotEqual(commas[0].id, commas[1].id, "two keys with one ForEach identity")
        XCTAssertTrue(commas.allSatisfy { $0.addressableID == "char-," })
    }

    func testTheDefaultBottomRowKeepsItsShippedIdentifiers() throws {
        // By id, for the reason `testTheBottomRowSwitchesBackFromTheNumbersPlane`
        // records: position 3 is the bottom row only while the letters plane
        // draws exactly three rows above it, so switching the default's number
        // row on would quietly point this at the digits instead.
        let rows = KeyboardLayout.rows(
            for: .english, plane: .letters, showsGlobe: true, customization: .default)
        let row = try XCTUnwrap(rows.first { $0.id == KeyboardLayout.RowID.bottom })
        XCTAssertEqual(
            row.keys.map(\.addressableID),
            // `.emoji` stands where the globe used to. Nothing compiles a globe
            // into a custom row — `KeyboardController.apply(_:)` inserts one into
            // the layout beforehand when the device needs it, which is why this row
            // has none even at `showsGlobe: true`.
            ["plane-123", "emoji", "space", KeyboardLayout.punctuationKeyID, "return"])
    }

    /// A key that was never compiled from a slot has no suffix to strip.
    func testAnOrdinaryKeysAddressableIDIsItsID() {
        XCTAssertEqual(KeySpec(.space).addressableID, "space")
        XCTAssertEqual(KeySpec(.character("a")).addressableID, "char-a")
    }

}

extension KeySpec {
    fileprivate var characterValue: String? {
        if case .character(let value) = cap { return value }
        return nil
    }
}
