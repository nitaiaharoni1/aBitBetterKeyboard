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

    /// **Delete keeps the same width and trailing edge in all sixty-four
    /// languages and on all three planes**, which is the point of
    /// `KeyWidth.pinned`.
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
    func testDeleteKeepsTheSameWidthAndTrailingEdgeInEveryLanguageAndOnEveryPlane() {
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

    /// Delete closes exactly one row. A strictly shortest top row carries it;
    /// otherwise the bottom row does. Hebrew's 8 / 10 / 9 layout is currently the
    /// only top-row case, matching `Bar/layouts/stock-rendered-rows.json`.
    ///
    /// The wrong implementations this rejects are both real shapes: delete on
    /// every row (a `map` that appends it unconditionally), and delete on no row
    /// at all (an index the row builder never reaches).
    func testDeleteClosesAStrictlyShortestTopRowOtherwiseTheBottomRow() {
        for language in KeyboardLanguage.allCases {
            let rows = KeyboardLayout.rows(for: language, plane: .letters)
            let carrying = rows.filter { row in row.keys.contains { $0.cap == .backspace } }
            XCTAssertEqual(
                carrying.count, 1,
                "\(language.displayName) has delete on \(carrying.count) letter rows")
            guard let row = carrying.first else { continue }
            let counts = KeyboardLayout.letterLayouts[language]?.rows.map(\.count) ?? []
            let expectedRow =
                counts.count == 3 && counts[0] < counts[1] && counts[0] < counts[2] ? 0 : 2
            XCTAssertEqual(
                row.id, expectedRow,
                "\(language.displayName) puts delete on row \(row.id)")
            XCTAssertEqual(
                row.keys.last?.cap, .backspace,
                "\(language.displayName) does not end that row with delete")
        }

        XCTAssertEqual(
            KeyboardLayout.rows(for: .hebrew, plane: .letters)
                .first { $0.keys.contains { $0.cap == .backspace } }?.id,
            0)
        XCTAssertEqual(
            KeyboardLayout.rows(for: .arabic, plane: .letters)
                .first { $0.keys.contains { $0.cap == .backspace } }?.id,
            2)
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

    /// Holding any Hebrew letter offers that letter with a geresh and with a
    /// gershayim, on all twenty-seven keys.
    ///
    /// **Two builds this rejects, and asserting the exact pair is what rejects
    /// the second.** Before `hebrewMarks` existed every Hebrew letter carried no
    /// alternates, and `KeyView.startAlternatesIfNeeded` opens nothing for a key
    /// with fewer than two items, so the hold was dead. Writing the table through
    /// `KeyboardLayout.alternates(_:)` instead splits `"צ׳"` into two entries —
    /// U+05F3 and U+05F4 are spacing punctuation, not combining marks, so each
    /// string is two `Character`s — and the popup then offers the letter again
    /// beside a naked mark. A test that only asked whether the list was non-empty
    /// passes on that.
    func testEveryHebrewLetterOffersItsGereshAndGershayimOnALongPress() {
        let letters = KeyboardLayout.rows(for: .hebrew, plane: .letters)
            .flatMap(\.keys)
            .compactMap { key -> (String, [String])? in
                guard case .character(let value) = key.cap else { return nil }
                return (value, key.alternates)
            }
        XCTAssertEqual(letters.count, 27, "Hebrew's rows are no longer 8 / 10 / 9")
        for (letter, alternates) in letters {
            XCTAssertEqual(
                alternates, [letter + "\u{05F3}", letter + "\u{05F4}"],
                "holding \(letter) offers \(alternates)")
        }
        XCTAssertEqual(KeyboardLayout.hebrewMarks["צ"], ["צ׳", "צ״"])
        // The acronyms and loanwords the two marks exist for.
        XCTAssertTrue(reachableLetters(.hebrew).contains("ה״"), "צה״ל needs ה״")
        XCTAssertTrue(reachableLetters(.hebrew).contains("צ׳"), "צ׳יפס needs צ׳")
        XCTAssertEqual("צ׳".count, 2, "the mark fused with its letter; the table is one key")
        XCTAssertEqual("צ״".count, 2, "the mark fused with its letter; the table is one key")
    }

    /// Every Persian letter offers the half-space, and the hamza forms Apple
    /// hides behind shift are still in front of it.
    ///
    /// U+200C is what separates a prefix or a suffix from its stem without
    /// breaking the word — `می‌روم`, `کتاب‌ها` — and `InputMode_fa.plist` names
    /// it as the one mark that appears inside a Persian word. Written `میروم` it
    /// is a spelling mistake, and no plane here could type it.
    ///
    /// **Asserting `last` rather than the whole list is deliberate**: six letters
    /// carry hamza forms as well, and a rule that replaced them instead of
    /// appending to them would take ا's أ إ آ ء away — which is a regression no
    /// assertion about the half-space alone can see. The second half of this test
    /// is that one.
    func testEveryPersianLetterOffersTheHalfSpaceWithoutLosingItsHamzaForms() {
        let letters = KeyboardLayout.rows(for: .persian, plane: .letters)
            .flatMap(\.keys)
            .compactMap { key -> (String, [String])? in
                guard case .character(let value) = key.cap else { return nil }
                return (value, key.alternates)
            }
        XCTAssertEqual(letters.count, 31, "Persian's rows are no longer 12 / 11 / 8")
        for (letter, alternates) in letters {
            XCTAssertEqual(
                alternates.last, letter + "\u{200C}",
                "holding \(letter) offers \(alternates)")
        }

        let alef = letters.first { $0.0 == "ا" }?.1
        XCTAssertEqual(alef, ["آ", "أ", "إ", "ء", "ا\u{200C}"])
        for form in ["ة", "ى", "ء", "أ", "إ", "آ", "ؤ", "ژ"] {
            XCTAssertTrue(reachableLetters(.persian).contains(form), "Persian lost \(form)")
        }
    }

    /// The straight quotes carry the curved ones, which were on no plane.
    ///
    /// `UIKeyboardNonstopPunctuationCharacters` lists U+2019 as a mark that
    /// appears *inside* a word in ten of the languages this keyboard ships, so a
    /// word spelled with it could not be typed. The guillemets ride on `"`
    /// because they are the primary quotation marks of Russian, Persian, Greek
    /// and French.
    func testTheStraightQuotesOfferTheCurvedOnes() {
        for language in KeyboardLanguage.allCases {
            let keys = KeyboardLayout.rows(for: language, plane: .numbers).flatMap(\.keys)
            let name = language.displayName
            XCTAssertEqual(
                keys.first { $0.cap == .character("\"") }?.alternates, ["“", "”", "«", "»"],
                "\(name) cannot reach the curved double quotes")
            XCTAssertEqual(
                keys.first { $0.cap == .character("'") }?.alternates, ["’", "‘"],
                "\(name) cannot reach the typographic apostrophe")
        }

        // The script's own marks are still on the same row, in front of them.
        let arabic = KeyboardLayout.rows(for: .arabic, plane: .numbers).flatMap(\.keys)
        XCTAssertEqual(arabic.first { $0.cap == .character("،") }?.alternates, [","])
        XCTAssertEqual(arabic.first { $0.cap == .character("؟") }?.alternates, ["?"])
        let spanish = KeyboardLayout.rows(for: .spanish, plane: .numbers).flatMap(\.keys)
        XCTAssertEqual(spanish.first { $0.cap == .character("?") }?.alternates, ["¿"])
        XCTAssertEqual(spanish.first { $0.cap == .character("!") }?.alternates, ["¡"])
    }

    /// Catalan's `l` carries the punt volat, which is a letter's mark the same
    /// way the geresh is.
    ///
    /// `l·l` is a different sound from `ll` — `col·legi`, `paral·lel` — so
    /// spelling it `ll` is an error rather than a shortcut. It arrives attached
    /// to its letter, because picking an alternate *replaces* the character the
    /// key already typed: a bare `·` *alternate* would eat the `l` in front of
    /// it. SwiftKey's symbols page now offers a bare `·` as its own key, which
    /// is a second tap and does not replace that rule.
    func testCatalanCanTypeThePuntVolat() {
        let l = KeyboardLayout.rows(for: .catalan, plane: .letters)
            .flatMap(\.keys)
            .first { $0.cap == .character("l") }
        XCTAssertEqual(l?.alternates, ["ł", "l·"])
        XCTAssertFalse(
            l?.alternates.contains("·") ?? true,
            "a bare interpunt would replace the l it belongs to")
        // SwiftKey puts a bare · on the symbols page. That is a second tap,
        // not an alternate: a bare · *alternate* would still eat the l.
        XCTAssertTrue(
            reachablePunctuation(.catalan).contains("·"),
            "SwiftKey's symbols page lost the interpunt")
        XCTAssertTrue(reachablePunctuation(.greek).contains("·"), "Greek's is its ano teleia")
    }

    // Reachability tests live in LanguageReachabilityTests.swift.
    // Digit, script-detection, and on-device-model tests live in LanguageScriptTests.swift.
    // Field tests live in LanguageCatalogueFieldTests.swift.
}
