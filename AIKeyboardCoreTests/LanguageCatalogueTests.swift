import UIKit
import XCTest

@testable import AIKeyboardCore

#if canImport(FoundationModels)
import FoundationModels
#endif

/// The sixty-four keyboards this build draws, and the Apple tables the catalogue
/// claims things about.
///
/// Every layout row was extracted from Apple's own keyboard layout data
/// (`TISCreateInputSourceList` + `UCKeyTranslate` over the macOS input source of
/// the same name), so what these tests protect is not the arrangement — that is
/// Apple's — but the properties a keyboard with three rows and no shift plane has
/// to keep anyway: every letter of the alphabet reachable, no two keys with the
/// same identity, and no row wider than the screen.
final class LanguageCatalogueTests: LanguageCatalogueTestFixture {

    // MARK: Identity and persistence
    // Identity and persistence tests live in KeyboardLanguageIdentityTests.swift.

    // MARK: Layouts

    func testEveryLanguageHasThreeLetterRows() {
        for language in KeyboardLanguage.allCases {
            let rows = KeyboardLayout.rows(for: language, plane: .letters)
            XCTAssertEqual(rows.count, 3, "\(language.displayName) has \(rows.count) letter rows")
            XCTAssertFalse(rows.contains { $0.keys.isEmpty }, "\(language.displayName) has an empty row")
        }
    }

    /// Two keys with one identity is a `ForEach` with duplicate identity, which is
    /// undefined behaviour rather than a cosmetic clash. It happened for real:
    /// Greek writes its question mark as `;`, which collided with the `;` in the
    /// numbers plane's `-/:;()` run until that became an ano teleia.
    func testNoPlaneHasTwoKeysWithTheSameIdentity() {
        for language in KeyboardLanguage.allCases {
            for plane in [KeyboardPlane.letters, .numbers, .symbols] {
                let identifiers = allKeys(language, plane).map(\.id)
                XCTAssertEqual(
                    Set(identifiers).count, identifiers.count,
                    "\(language.displayName) \(plane) repeats a key: "
                        + Dictionary(grouping: identifiers, by: { $0 })
                        .filter { $0.value.count > 1 }.keys.joined(separator: ", "))
            }
        }
    }

    /// Every row has to fit the screen, and there is no tolerance left to hide in.
    ///
    /// **This used to allow one key gap of overspill, and one row was using it.**
    /// Hebrew's bottom row ran 5.1pt over: nine letters plus delete divide out at
    /// exactly one unit each, and `widths` floored the delete key to 1.15 units on
    /// the way past. That floor is now asked only where the even share is *under*
    /// a letter key — see `KeyboardLayout.widths` — so nothing needs the slack and
    /// the assertion is the real one: a row is at most as wide as the keyboard.
    ///
    /// Two widths, because a floor only bites on the narrow one: an iPhone 17 Pro
    /// at 402pt, and 320pt, which is what Display Zoom gives a modern iPhone. The
    /// narrow case caught a second floor of the same shape — `unitWidth` asked for
    /// 20pt keys where Bulgarian's thirteen columns had room for 18.6, and its top
    /// two rows ran 18pt off the side. The bottom row is included by `allRows`, so
    /// the letters plane's punctuation key is measured with the rest.
    ///
    /// The epsilon is floating-point dust, not slack: a row of ten keys that
    /// divides evenly comes back as 396.0000000000001 against an available 396.
    func testNoRowOverflowsTheKeyboard() {
        let sideInset = Theme.Metrics.sideInset
        let spacing = Theme.Metrics.keySpacing

        for width in [CGFloat(402), 320] {
            let available = width - sideInset * 2
            for language in KeyboardLanguage.allCases {
                for plane in [KeyboardPlane.letters, .numbers, .symbols] {
                    let columns = KeyboardLayout.columns(for: language, plane: plane)
                    let unit = KeyboardLayout.unitWidth(
                        totalWidth: width, spacing: spacing, sideInset: sideInset, columns: columns)
                    for row in allRows(language, plane) {
                        let widths = KeyboardLayout.widths(
                            for: row, totalWidth: available, unitWidth: unit, spacing: spacing)
                        let total =
                            widths.reduce(0, +) + spacing * CGFloat(row.keys.count - 1)
                            + row.sideInsetUnits * (unit + spacing) * 2
                        XCTAssertLessThanOrEqual(
                            total, available + 0.001,
                            "\(language.displayName) \(plane) row \(row.id) is "
                                + "\(total - available)pt too wide at \(width)pt")
                    }
                }
            }
        }
    }

    /// **Delete is the same rect in all sixty-four languages and on all three
    /// planes**, which is the whole point of `KeyWidth.pinned`.
    ///
    /// Three things together are what make the rendered frame identical, so all
    /// three are asserted: the resolved width is `pinnedWidth`, delete closes its
    /// row, and that row carries no side inset. `KeyboardView.rowView` draws a
    /// trailing pinned key hard against the end of the row, so a key that is last,
    /// uninset and of a fixed width is at a fixed place.
    ///
    /// **Written to reject the build it was named after.** On the old one delete
    /// took whatever the letters left over, so on a 402pt screen English's was
    /// 54.3pt, Hebrew's 34.2pt and the numbers plane's 94.5pt — three different
    /// keys. Asserting merely that a delete key *exists*, or that it is the last
    /// key in its row, passed against every one of those.
    func testDeleteIsTheSameKeyInEveryLanguageAndOnEveryPlane() {
        let sideInset = Theme.Metrics.sideInset
        let spacing = Theme.Metrics.keySpacing

        for width in [CGFloat(402), 320] {
            let available = width - sideInset * 2
            let pinned = KeyboardLayout.pinnedWidth(totalWidth: available, spacing: spacing)

            for language in KeyboardLanguage.allCases {
                for plane in [KeyboardPlane.letters, .numbers, .symbols] {
                    let columns = KeyboardLayout.columns(for: language, plane: plane)
                    let unit = KeyboardLayout.unitWidth(
                        totalWidth: width, spacing: spacing, sideInset: sideInset,
                        columns: columns)
                    let rows = allRows(language, plane)
                    let place = "\(language.displayName) \(plane) at \(width)pt"
                    guard
                        let row = rows.first(where: { $0.keys.contains { $0.cap == .backspace } })
                    else {
                        XCTFail("\(place) has no delete key")
                        continue
                    }

                    XCTAssertEqual(row.keys.last?.cap, .backspace, "delete does not close \(place)")
                    XCTAssertEqual(row.sideInsetUnits, 0, "the delete row is inset on \(place)")

                    let widths = KeyboardLayout.widths(
                        for: row, totalWidth: available, unitWidth: unit, spacing: spacing)
                    XCTAssertEqual(
                        widths.last ?? 0, pinned, accuracy: 0.001,
                        "delete is \(widths.last ?? 0)pt rather than \(pinned)pt on \(place)")
                }
            }
        }
    }

    /// **The space row is the same proportions in every language**, which is the
    /// whole point of solving it against `referenceColumns` rather than the
    /// letter grid.
    ///
    /// **Written to reject the build it was named after.** `KeyboardView` used to
    /// feed every row the language's own `unitWidth`, so Arabic's twelve-column
    /// unit made `123` / punctuation / return shrink and the flexible space bar
    /// grow, while English's ten-column unit kept the stock proportions. Passing
    /// each language its own unit and still getting identical widths is what
    /// proves the solver no longer listens. Asserting only that a space key
    /// *exists*, or that it is `.flexible`, passed against the broken build.
    func testTheSpaceRowWidthsAreIdenticalInEveryLanguage() {
        let sideInset = Theme.Metrics.sideInset
        let spacing = Theme.Metrics.keySpacing
        let available = CGFloat(402) - sideInset * 2

        let englishColumns = KeyboardLayout.columns(for: .english, plane: .letters)
        let englishUnit = KeyboardLayout.unitWidth(
            totalWidth: 402, spacing: spacing, sideInset: sideInset, columns: englishColumns)
        let englishRow = KeyboardLayout.bottomRow(
            for: .english, plane: .letters, showsGlobe: false)
        let expected = KeyboardLayout.widths(
            for: englishRow, totalWidth: available, unitWidth: englishUnit, spacing: spacing)

        // The pair that exposed it: ten-column English against twelve-column Arabic.
        XCTAssertNotEqual(
            englishColumns, KeyboardLayout.columns(for: .arabic, plane: .letters),
            "fixture assumes Arabic is wider than English; otherwise the assertion is soft")

        for language in KeyboardLanguage.allCases {
            for plane in [KeyboardPlane.letters, .numbers, .symbols] {
                let columns = KeyboardLayout.columns(for: language, plane: plane)
                let unit = KeyboardLayout.unitWidth(
                    totalWidth: 402, spacing: spacing, sideInset: sideInset, columns: columns)
                let row = KeyboardLayout.bottomRow(
                    for: language, plane: plane, showsGlobe: false)
                let widths = KeyboardLayout.widths(
                    for: row, totalWidth: available, unitWidth: unit, spacing: spacing)
                let place = "\(language.displayName) \(plane)"
                XCTAssertEqual(
                    widths.count, expected.count,
                    "\(place) has a different key count on the space row")
                for (index, width) in widths.enumerated() {
                    XCTAssertEqual(
                        width, expected[index], accuracy: 0.001,
                        "\(place) key \(index) is \(width)pt rather than \(expected[index])pt")
                }
            }
        }
    }

    /// The pinned width answers to the screen and to nothing else. If it ever
    /// takes a language or a column count, delete starts moving again and the test
    /// above is the only thing that would say so — this one says why.
    func testThePinnedWidthIsIndependentOfTheColumnCount() {
        let spacing = Theme.Metrics.keySpacing
        let available = CGFloat(402) - Theme.Metrics.sideInset * 2
        let pinned = KeyboardLayout.pinnedWidth(totalWidth: available, spacing: spacing)

        // A twelve-column language's own unit is smaller than a ten-column one's,
        // so 1.5 of *its* units is not this number. That difference is exactly what
        // used to move the key between English and Russian.
        let twelve = KeyboardLayout.unitWidth(
            totalWidth: 402, spacing: spacing, sideInset: Theme.Metrics.sideInset, columns: 12)
        XCTAssertNotEqual(pinned, twelve * 1.5, accuracy: 0.001)
        XCTAssertEqual(KeyboardLayout.referenceColumns, Int(LayoutValidator.widthBudget))
    }

    /// Ten for Latin and Hebrew; twelve for the layouts Apple itself draws twelve
    /// keys wide. Never fewer than ten, so nine-key Greek rows keep English's key
    /// size and centre rather than growing.
    func testColumnsFollowTheWidestRow() {
        XCTAssertEqual(KeyboardLayout.columns(for: .english, plane: .letters), 10)
        XCTAssertEqual(KeyboardLayout.columns(for: .hebrew, plane: .letters), 10)
        XCTAssertEqual(KeyboardLayout.columns(for: .greek, plane: .letters), 10)
        XCTAssertEqual(KeyboardLayout.columns(for: .german, plane: .letters), 11)
        XCTAssertEqual(KeyboardLayout.columns(for: .hindi, plane: .letters), 11)
        for language in [KeyboardLanguage.arabic, .persian, .russian, .ukrainian, .turkish] {
            XCTAssertEqual(
                KeyboardLayout.columns(for: language, plane: .letters), 12,
                "\(language.displayName)")
        }
        // The numbers and symbols planes are ten keys wide in every language.
        for language in KeyboardLanguage.allCases {
            XCTAssertEqual(KeyboardLayout.columns(for: language, plane: .numbers), 10)
            XCTAssertEqual(KeyboardLayout.columns(for: language, plane: .symbols), 10)
        }
    }

    /// **Shift and delete are keys, and the column budget used to pretend they
    /// were not.** Apple's Bulgarian puts ten letters on the bottom row and
    /// eleven on the middle one, so the widest row said eleven columns while the
    /// bottom row needed thirteen, and it ran 45pt — a key and a half — off the
    /// side of an iPhone 17 Pro. `testNoRowOverflowsTheKeyboard` is what fails
    /// when this rule goes; this one says which rule.
    ///
    /// The three numbers below are the only ones that move, and the fourth
    /// assertion is why the rule is safe: English's bottom row is seven letters,
    /// 7 + 3 = 10, which is the ten columns it already had.
    func testTheBottomRowsFunctionKeysCountAgainstTheColumnBudget() {
        XCTAssertEqual(KeyboardLayout.columns(for: .bulgarian, plane: .letters), 13)
        XCTAssertEqual(KeyboardLayout.columns(for: .belarusian, plane: .letters), 12)
        XCTAssertEqual(KeyboardLayout.columns(for: .tongan, plane: .letters), 11)

        // Widest row alone would give these three 11, 11 and 10.
        for language in [KeyboardLanguage.bulgarian, .belarusian, .tongan] {
            let widest =
                KeyboardLayout.rows(for: language, plane: .letters).map(\.keys.count).max() ?? 0
            XCTAssertLessThan(
                widest, KeyboardLayout.columns(for: language, plane: .letters),
                "\(language.displayName) would fit its widest row and still overflow")
        }
        XCTAssertEqual(KeyboardLayout.columns(for: .english, plane: .letters), 10)
    }

    /// **Delete closes exactly one row, and it is the bottom row in all
    /// sixty-four.** Apple's Hebrew keyboard is the one measured layout that puts
    /// it elsewhere — at the end of the short *top* row, beside eight letters, per
    /// `Bar/layouts/stock-rendered-rows.json` — and this keyboard deliberately
    /// does not follow it there. A swipe along the space bar changes language
    /// mid-sentence, so a delete key that follows Apple moves rows under a thumb
    /// already reaching for it; that is the trade `KeyboardLayout.letters(for:)`
    /// names.
    ///
    /// The wrong implementations this rejects are both real shapes: delete on
    /// every row (a `map` that appends it unconditionally), and delete on no row
    /// at all (an index the row builder never reaches).
    func testDeleteClosesTheBottomRowInEveryLanguage() {
        for language in KeyboardLanguage.allCases {
            let rows = KeyboardLayout.rows(for: language, plane: .letters)
            let carrying = rows.filter { row in row.keys.contains { $0.cap == .backspace } }
            XCTAssertEqual(
                carrying.count, 1,
                "\(language.displayName) has delete on \(carrying.count) letter rows")
            guard let row = carrying.first else { continue }
            XCTAssertEqual(
                row.id, 2,
                "\(language.displayName) puts delete on row \(row.id)")
            XCTAssertEqual(
                row.keys.last?.cap, .backspace,
                "\(language.displayName) does not end that row with delete")
        }
    }

    /// The bottom row's punctuation key types the script's own marks, on every
    /// plane, exactly once per plane.
    ///
    /// **The two failures worth naming.** A key hardcoded to `.,?!` would type a
    /// Latin question mark on an Arabic keyboard, which is why the marks are read
    /// from the same `punctuationMarks` the numbers plane prints. And this key on
    /// the numbers plane sits one row under the `.` that row already carries, so
    /// without the explicit `punctuationKeyID` both would answer to `char-.` and
    /// the plane would have two keys with one identity — undefined `ForEach`
    /// behaviour, not a cosmetic clash. That is what let the key move onto all
    /// three planes at all; `testNoPlaneHasTwoKeysWithTheSameIdentity` is what
    /// keeps measuring it.
    func testThePunctuationKeyIsOnEveryPlaneAndTypesTheScriptsOwnMarks() {
        for language in KeyboardLanguage.allCases {
            for plane in [KeyboardPlane.letters, .numbers, .symbols] {
                let found = bottomKeys(language, plane).filter {
                    $0.id == KeyboardLayout.punctuationKeyID
                }
                XCTAssertEqual(
                    found.count, 1,
                    "\(language.displayName) has \(found.count) punctuation keys on \(plane)")

                guard let key = found.first else { continue }
                let marks = KeyboardLayout.punctuationMarks(for: language).map(String.init)
                XCTAssertEqual(key.cap, .character(marks[0]))
                XCTAssertEqual(key.alternates, Array(marks.dropFirst()))
            }
        }

        // The scripts that write these marks differently, spelled out rather than
        // derived, so a change to `punctuationMarks` has to be deliberate.
        XCTAssertEqual(KeyboardLayout.punctuationMarks(for: .arabic), ".،؟!'")
        XCTAssertEqual(KeyboardLayout.punctuationMarks(for: .persian), ".،؟!'")
        XCTAssertEqual(KeyboardLayout.punctuationMarks(for: .greek), ".,;!'")
        XCTAssertEqual(KeyboardLayout.punctuationMarks(for: .hebrew), ".,?!'")
    }

    // Reachability tests live in LanguageReachabilityTests.swift.
    // Digit, script-detection, and on-device-model tests live in LanguageScriptTests.swift.
    // Field tests live in LanguageCatalogueFieldTests.swift.
}
