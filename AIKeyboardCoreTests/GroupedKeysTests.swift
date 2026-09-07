import XCTest

@testable import AIKeyboardCore

/// Grouped keys, pinned against `Bar/grouped/` — the harness that measured this
/// feature before it was built. `Bar/grouped/harness/grouping.py` is the reference
/// the Swift was ported from, and every group, key count and decode asserted here
/// is what that harness produces for the shipped rows.
///
/// **Every assertion was tried against a plausible wrong implementation before it
/// was written**, per the standing rule, and the ones where that is not obvious
/// carry a line naming the build they reject. Two weak shapes are deliberately
/// absent: a key count alone cannot see where a group boundary fell, so the splits
/// are asserted as splits; and `XCTAssertFalse(_.isEmpty)` on a decoder's
/// candidates is true of a decoder that answers the same three words to
/// everything, so the candidates are asserted as exact lists.
///
/// **The `keepingApart:` and `words:` forms are used wherever they exist.** The
/// language-based overloads read `KeyboardLayout.letterLayouts` and the bundled
/// lexicon, and a decoder built where either is missing codes no word, indexes
/// nothing and answers `[]` to everything — which reads as a broken decoder rather
/// than a broken test. `testTheRowsFormAndTheLanguageFormAgree` is what holds the
/// two forms together, since the rest of the file trusts the explicit one.
final class GroupedKeysTests: XCTestCase {

    /// The rows this feature transforms, read from the shipped layout rather than
    /// restated — `Bar/grouped/make-rows.py` extracts the same strings from
    /// `LetterLayouts.swift`, so a row edited there moves the harness and this test
    /// together.
    internal func letterRows(_ language: KeyboardLanguage) throws -> [[String]] {
        try letterLayout(language).rows
    }

    internal func letterLayout(_ language: KeyboardLanguage) throws -> KeyboardLayout.LetterLayout {
        try XCTUnwrap(KeyboardLayout.letterLayouts[language])
    }

    /// Hebrew is the only language with anything to keep apart, so the two arguments
    /// the `keepingApart:` form ever takes are these.
    internal let noAvoid: Set<String> = []

    internal var savedCompleteOnIdle = false
    internal var savedIdleDelayMs = 0

    override func setUp() {
        super.setUp()
        savedCompleteOnIdle = SharedStore.shared.completeOnIdle
        savedIdleDelayMs = SharedStore.shared.idleDelayMs
        SharedStore.shared.completeOnIdle = false
    }

    override func tearDown() {
        SharedStore.shared.completeOnIdle = savedCompleteOnIdle
        SharedStore.shared.idleDelayMs = savedIdleDelayMs
        super.tearDown()
    }

    // MARK: - How many keys a row becomes

    /// **Half-up, not banker's.** Foundation's plain `rounded()` is
    /// `.toNearestOrEven`, so ten letters at four per key is 2.5 → 2 and the top row
    /// becomes two keys instead of three. That is a different keyboard, not a
    /// rounding detail. Both sides of the fence are here: 10@4 is the tie the two
    /// rules disagree about, 9@4 rounds down under either.
    func testKeyCountRoundsHalfUp() {
        XCTAssertEqual(GroupedKeys.keyCount(rowLength: 10, level: .l2), 3)
        XCTAssertEqual(GroupedKeys.keyCount(rowLength: 9, level: .l2), 2)
        XCTAssertEqual(GroupedKeys.keyCount(rowLength: 7, level: .l3), 1)
    }

    /// A row can never vanish, and the floor is load-bearing rather than tidy:
    /// `split` divides the row by the key count, so a zero would trap.
    func testARowNeverBecomesZeroKeys() {
        XCTAssertEqual(GroupedKeys.keyCount(rowLength: 2, level: .l3), 1)
        XCTAssertEqual(GroupedKeys.keyCount(rowLength: 1, level: .l3), 1)
        XCTAssertEqual(GroupedKeys.keyCount(rowLength: 0, level: .l3), 1)
    }

    // MARK: - Where the boundaries fall

    /// Everything below is a claim about *these* rows, and the measured percentages
    /// in `GroupedKeys.Level.measuredAccuracy` are too. A row edited upstream has to
    /// fail here first, loudly, rather than quietly changing what every other
    /// assertion in this file means.
    func testTheShippedRowsAreTheOnesTheHarnessMeasured() throws {
        XCTAssertEqual(
            try letterRows(.english).map { $0.joined() }, ["qwertyuiop", "asdfghjkl", "zxcvbnm"])
        XCTAssertEqual(
            try letterRows(.hebrew).map { $0.joined() }, ["קראטוןםפ", "שדגכעיחלךף", "זסבהנמצתץ"])
    }

    /// **The extra letter goes to the leading groups.** `qwe|rty|uiop` is the same
    /// three keys as `qwer|tyu|iop`, so nothing that counts keys can tell the two
    /// apart — and they are different keyboards: `r` moves off the first key onto
    /// the second, which changes the code of every word that contains it.
    ///
    /// The rule outlived the row-at-a-time layout: the band splits *columns* by it,
    /// and the row that keeps shift and delete still splits its letters by it.
    func testTheExtraLetterGoesToTheLeadingGroups() throws {
        let top = try letterRows(.english)[0]

        XCTAssertEqual(
            GroupedKeys.split(top, level: .l1).map { $0.joined() }, ["qwer", "tyu", "iop"])
    }

    /// Order is the whole promise here: the letters stay where a thumb already
    /// knows them and only the boundaries move. Hebrew is in this loop because its
    /// rows are stored **left to right on screen**, so a split that read them as
    /// logical order and reversed them would be the defect that shipped all six
    /// right-to-left keyboards mirrored.
    ///
    /// **Asserted per source row rather than per drawn row**, because banding
    /// merges two source rows into one drawn one: `[qwas]` is `q` and `w` over `a`
    /// and `s`, so the flattened keys of that row are not `qwertyuiop`. Reading one
    /// source row's letters back out of the keys in order is the claim that
    /// survives banding, and it is the one that matters — it is what says a thumb
    /// still finds its letters where it left them. It rejects a reversal, a
    /// duplicate and a dropped letter exactly as the flat form did.
    func testEveryLetterSurvivesInOrderAtEveryLevel() throws {
        for (language, avoid) in [(KeyboardLanguage.english, noAvoid), (.hebrew, GroupedKeys.hebrewClitics)] {
            let rows = try letterRows(language)
            for level in GroupedKeys.Level.allCases {
                let keys = GroupedKeys.groups(for: rows, keepingApart: avoid, level: level)
                    .flatMap { $0 }
                for (index, row) in rows.enumerated() {
                    let seen = keys.flatMap { $0 }.filter(Set(row).contains)
                    XCTAssertEqual(
                        seen, row,
                        "\(language.rawValue) row \(index) at \(level.rawValue) per key is not the row it was given"
                    )
                }
                XCTAssertEqual(
                    keys.flatMap { $0 }.count, rows.flatMap { $0 }.count,
                    "\(language.rawValue) at \(level.rawValue) per key lost or duplicated a letter")
            }
        }
    }

    /// **The letter underneath is on the same key, and that is the whole of what
    /// this feature changed.** Against the row-at-a-time version — which grouped
    /// `qwer|tyu|iop` and left `a` two rows away in its own key — every key count
    /// in this file is identical and every other assertion still passes, so this is
    /// the one that rejects it.
    ///
    /// The second half is what stops it being vacuous: a build that put the whole
    /// keyboard on one key would satisfy the first line.
    func testAKeyCarriesTheLettersAboveAndBelowEachOther() throws {
        let rows = try letterRows(.english)
        let keys = GroupedKeys.groups(for: rows, keepingApart: noAvoid, level: .pairs)
            .flatMap { $0 }

        XCTAssertEqual(keys.first, ["q", "a"])
        XCTAssertTrue(keys.contains(["o", "p", "l"]))
        // The row that keeps shift and delete groups sideways, because a pinned
        // key cannot stand in a double-height row without being one.
        XCTAssertTrue(keys.contains(["z", "x"]))
        XCTAssertFalse(
            keys.contains { $0.count > 3 },
            "two letters per key means two, plus a leftover column folded in, not a band that swallowed a whole row"
        )
    }

    /// The table in `Bar/grouped/README.md`, which is the keyboard
    /// `GroupedKeys.Level.measuredAccuracy` reports percentages for. A key count
    /// that drifts means those percentages describe a keyboard this is not.
    func testTheKeyCountsAreTheOnesThatWereMeasured() throws {
        let measured: [(KeyboardLanguage, Set<String>, GroupedKeys.Level, Int)] = [
            (.english, noAvoid, .off, 26), (.english, noAvoid, .pairs, 12),
            (.english, noAvoid, .l1, 7), (.english, noAvoid, .l2, 7), (.english, noAvoid, .l3, 5),
            (.hebrew, GroupedKeys.hebrewClitics, .off, 27),
            (.hebrew, GroupedKeys.hebrewClitics, .pairs, 13),
            (.hebrew, GroupedKeys.hebrewClitics, .l1, 8),
            (.hebrew, GroupedKeys.hebrewClitics, .l2, 7),
            (.hebrew, GroupedKeys.hebrewClitics, .l3, 6)
        ]

        for (language, avoid, level, keys) in measured {
            let grouped = GroupedKeys.groups(
                for: try letterRows(language), keepingApart: avoid, level: level)
            XCTAssertEqual(
                grouped.reduce(0) { $0 + $1.count }, keys,
                "\(language.rawValue) at \(level.rawValue) letters per key")
        }
    }

    /// The English groups exactly as the harness produced them, written out rather
    /// than derived — a derivation would only be the implementation a second time.
    /// Two drawn rows, not three: the band first, then the row that keeps shift and
    /// delete. Letters inside a banded cap read top row first.
    func testTheEnglishGroupsAreTheOnesThatWereMeasured() throws {
        let expected: [GroupedKeys.Level: [[String]]] = [
            .pairs: [
                ["qa", "ws", "ed", "rf", "tg", "yh", "uj", "ik", "opl"],
                ["zx", "cv", "bnm"]
            ],
            .l1: [["qwas", "erdf", "tygh", "uijk", "opl"], ["zxcv", "bnm"]],
            .l2: [["qwas", "erdf", "tygh", "uijk", "opl"], ["zxcv", "bnm"]],
            .l3: [["qweasd", "rtyfgh", "uijk", "opl"], ["zxcvbnm"]]
        ]

        let rows = try letterRows(.english)
        for (level, groups) in expected {
            let grouped = GroupedKeys.groups(for: rows, keepingApart: noAvoid, level: level)
            XCTAssertEqual(
                grouped.map { row in row.map { $0.joined() } }, groups,
                "english at \(level.rawValue) letters per key")
        }
    }

    /// Hebrew, written out the same way. The leftover columns `ך` and `ף` share a
    /// key rather than sitting alone, and `ז` folds into the group beside it.
    func testTheHebrewGroupsFoldLeftoverLettersRatherThanLeavingThemAlone() throws {
        let expected: [GroupedKeys.Level: [[String]]] = [
            .pairs: [
                ["קש", "רד", "אג", "טכ", "וע", "ןי", "םח", "פל", "ךף"],
                ["זסב", "הנ", "מצ", "תץ"]
            ],
            .l1: [["קרשד", "אטגכ", "וע", "ןםיח", "פלךף"], ["זסב", "הנ", "מצתץ"]],
            .l2: [["קרשד", "אטגכ", "וןעי", "םפחל", "ךף"], ["זסבהנ", "מצתץ"]],
            .l3: [["קרשד", "אטגכ", "וןםעיח", "פלךף"], ["זסבהנ", "מצתץ"]]
        ]

        let rows = try letterRows(.hebrew)
        for (level, groups) in expected {
            let grouped = GroupedKeys.groups(
                for: rows, keepingApart: GroupedKeys.hebrewClitics, level: level)
            XCTAssertEqual(
                grouped.map { row in row.map { $0.joined() } }, groups,
                "hebrew at \(level.rawValue) letters per key")
        }
    }

    /// **The keyboard is the height it was, and the band is why.** Two rows merged
    /// into one drawn row that is two key-heights tall, so the letter area still
    /// adds up to three. A band declared one unit tall halves the keys it merged;
    /// a band declared three grows the keyboard past the 368pt screen-context
    /// cliff, which is the failure nothing on screen would report.
    func testTheBandIsTwoRowsTallAndTheKeyboardIsNot() throws {
        for language in [KeyboardLanguage.english, .hebrew] {
            let ungrouped = KeyboardLayout.rows(for: language, plane: .letters)
            XCTAssertEqual(ungrouped.map(\.heightUnits), [1, 1, 1])

            for level in [GroupedKeys.Level.pairs, .l1, .l2, .l3] {
                let rows = KeyboardLayout.rows(for: language, plane: .letters, grouping: level)
                XCTAssertEqual(
                    rows.map(\.heightUnits), [2, 1],
                    "\(language.rawValue) at \(level.rawValue) letters per key")
                XCTAssertEqual(
                    rows.reduce(0) { $0 + $1.heightUnits },
                    ungrouped.reduce(0) { $0 + $1.heightUnits },
                    "grouping changed the height of the \(language.rawValue) keyboard")
            }
        }
    }

    /// **Grouped letter keys in a row are the same width and fill it.** Weighting
    /// by the columns a key swallowed left leftover letters on a skinny button
    /// beside a fat one, which is the opposite of the feature. A slot is one of
    /// N equal parts of the whole row, gutters included. `.unit` cannot, because
    /// a unit is a key width and knows nothing about the spacing beside it.
    func testGroupedKeysInARowAreTheSameWidthAndFillIt() throws {
        let width: CGFloat = 402 - Theme.Metrics.sideInset * 2
        func drawn(_ row: KeyRow, columns: Int) -> [CGFloat] {
            let unit = KeyboardLayout.unitWidth(
                totalWidth: 402, spacing: Theme.Metrics.keySpacing,
                sideInset: Theme.Metrics.sideInset, columns: columns)
            return KeyboardLayout.widths(
                for: row, totalWidth: width, unitWidth: unit,
                spacing: Theme.Metrics.keySpacing)
        }
        func filledWidth(_ row: KeyRow, columns: Int) -> CGFloat {
            let widths = drawn(row, columns: columns)
            return widths.reduce(0, +) + Theme.Metrics.keySpacing * CGFloat(widths.count - 1)
        }

        for level in [GroupedKeys.Level.pairs, .l1, .l2, .l3] {
            for language in [KeyboardLanguage.english, .hebrew] {
                let rows = KeyboardLayout.rows(for: language, plane: .letters, grouping: level)
                let band = try XCTUnwrap(rows.first)
                XCTAssertTrue(
                    band.keys.allSatisfy {
                        if case .slot(of: band.keys.count) = $0.width { return true }
                        return false
                    },
                    "every band key is a slot of the band at \(language.rawValue) \(level.rawValue)")

                let bottom = rows[1]
                let firstBand = try assertEqualWidths(
                    drawn(band, columns: 10),
                    "band keys must be the same size at \(language.rawValue) \(level.rawValue)")
                let firstLetter = try assertEqualWidths(
                    slotWidths(in: bottom, columns: 10, drawn: drawn),
                    "grouped keys on the shift/delete row must be the same size at \(language.rawValue) \(level.rawValue)")
                XCTAssertEqual(
                    firstBand, firstLetter, accuracy: 0.5,
                    "band letter-key width must match third-row letter-key width at \(language.rawValue) \(level.rawValue)"
                )
            }

            let band = KeyboardLayout.rows(for: .english, plane: .letters, grouping: level)[0]
            let ungrouped = KeyboardLayout.rows(for: .english, plane: .letters)[0]
            XCTAssertEqual(
                filledWidth(band, columns: 10), filledWidth(ungrouped, columns: 10),
                accuracy: 0.5)
        }

        assertGroupedColumnCount()
    }

    private func assertGroupedColumnCount() {
        XCTAssertEqual(KeyboardLayout.columns(for: .english, plane: .letters, grouping: .l2), 10)
    }

    private func slotWidths(
        in row: KeyRow, columns: Int, drawn: (KeyRow, Int) -> [CGFloat]
    ) -> [CGFloat] {
        zip(row.keys, drawn(row, columns)).compactMap { spec, width in
            guard case .slot = spec.width else { return nil }
            return width
        }
    }

    private func assertEqualWidths(_ widths: [CGFloat], _ message: String) throws -> CGFloat {
        let first = try XCTUnwrap(widths.first)
        for width in widths { XCTAssertEqual(width, first, accuracy: 0.5, message) }
        return first
    }

    /// **Hebrew L1 is the screenshot this exists for.** `ו` over `ע` is one
    /// letter per line; `פ` over `לךף` is one over three; the shift row's `הנ`
    /// sits beside `מצתץ`. Weighting by span — or by how many letters a cap
    /// carries — is what made those look like skinny buttons beside fat ones.
    /// Equal slots keep the caps the same size; the drawing has to fill each
    /// cap with equal cells or the glyphs still read as different-sized buttons.
    func testHebrewL1CapsAreEqualEvenWhenLetterCountsDiffer() throws {
        let rows = KeyboardLayout.rows(for: .hebrew, plane: .letters, grouping: .l1)
        let band = try XCTUnwrap(rows.first)
        let vavAyin = try XCTUnwrap(
            band.keys.first { $0.groupedLetters == ["ו", "ע"] },
            "the one-letter-per-line band key")
        let peLeftovers = try XCTUnwrap(
            band.keys.first { $0.groupedLetters == ["פ", "ל", "ך", "ף"] },
            "the one-over-three band key")
        guard case .slot(let vavCount) = vavAyin.width,
            case .slot(let peCount) = peLeftovers.width
        else {
            return XCTFail("both band caps must be a slot, not leftover-share or span-weighted")
        }
        XCTAssertEqual(vavCount, peCount)

        let bottom = rows[1]
        let heNun = try XCTUnwrap(bottom.keys.first { $0.groupedLetters == ["ה", "נ"] })
        let memTsadi = try XCTUnwrap(
            bottom.keys.first { $0.groupedLetters == ["מ", "צ", "ת", "ץ"] })
        guard case .slot(let two) = heNun.width, case .slot(let four) = memTsadi.width else {
            return XCTFail("both shift-row caps must be a slot")
        }
        XCTAssertEqual(two, four)
        XCTAssertEqual(vavCount, two)
    }

    // MARK: - Hebrew's clitics

    /// The bridge between the two forms: the language-based one has to hand Hebrew
    /// its clitics and hand every other language nothing. It is one line and it is
    /// the only place that mapping lives, so a `!=` in it would switch the whole
    /// Hebrew win off while every test that passes the set explicitly kept passing.
    ///
    /// The last assertion is what stops this being vacuous — if the constraint made
    /// no difference at L1, agreeing about it would prove nothing.
    func testTheLanguageFormHandsHebrewItsCliticsAndEnglishNothing() throws {
        let hebrew = try letterRows(.hebrew)
        let english = try letterRows(.english)

        for level in GroupedKeys.Level.allCases {
            XCTAssertEqual(
                GroupedKeys.groups(for: hebrew, language: .hebrew, level: level),
                GroupedKeys.groups(
                    for: hebrew, keepingApart: GroupedKeys.hebrewClitics, level: level),
                "hebrew at \(level.rawValue) per key")
            XCTAssertEqual(
                GroupedKeys.groups(for: english, language: .english, level: level),
                GroupedKeys.groups(for: english, keepingApart: noAvoid, level: level),
                "english at \(level.rawValue) per key")
        }

        XCTAssertNotEqual(
            GroupedKeys.groups(for: hebrew, keepingApart: GroupedKeys.hebrewClitics, level: .l1),
            GroupedKeys.groups(for: hebrew, keepingApart: noAvoid, level: .l1),
            "the constraint has to change the split, or agreeing about it proves nothing")
    }

    /// **Worth +7.0 points at thirteen keys and +6.6 at eight, at no extra keys.**
    /// Plain adjacency puts ה and מ on one key at L1, so "the X" and "from X"
    /// become the same keystroke in a language where every sentence has one.
    ///
    /// This rejects the build that never keeps them apart, and it has to be asserted
    /// at both levels to do it: plain adjacency splits the bottom row into
    /// `זסב|הנמ|צתץ` at L1, landing ה with מ, and into `זס|בה|נמ|צתץ` at `.pairs`,
    /// landing ב with ה. Neither is visible to a key count — the constrained and
    /// unconstrained splits produce the same number of keys, which is the entire
    /// point of the constraint — so the second half asserts that the wrong build
    /// really does collide, or the first half is asserting about nothing.
    func testHebrewKeepsTheCliticsApartWhileTheArithmeticAllows() throws {
        let rows = try letterRows(.hebrew)

        for level in [GroupedKeys.Level.pairs, .l1] {
            let grouped = GroupedKeys.groups(
                for: rows, keepingApart: GroupedKeys.hebrewClitics, level: level)
            for group in grouped.flatMap({ $0 }) {
                XCTAssertLessThanOrEqual(
                    group.filter(GroupedKeys.hebrewClitics.contains).count, 1,
                    "\(group.joined()) holds two prefixes at \(level.rawValue) letters per key")
            }

            let plain = GroupedKeys.groups(for: rows, keepingApart: noAvoid, level: level)
            XCTAssertTrue(
                plain.flatMap { $0 }.contains { $0.filter(GroupedKeys.hebrewClitics.contains).count > 1 },
                "plain adjacency has to collide at \(level.rawValue) per key, or the check above is empty")
        }
    }

    /// **It runs out rather than snapping, and L1 is the last stop where it is fully
    /// satisfiable.** The bottom row holds three clitics and gets two keys from L2
    /// down, so one key must take two of them: the constraint is genuinely
    /// unsatisfiable and the solver says so.
    ///
    /// What must not happen is the row falling back to *nothing*. The plain split is
    /// what it falls back to, asserted as that split rather than as "some split" — an
    /// implementation that propagated the `nil` would give an empty row, and one that
    /// quietly bought an extra key would give a keyboard whose key count is not the
    /// one that was measured.
    func testWhereSeparationIsImpossibleTheRowStillSplitsCompletely() throws {
        let rows = try letterRows(.hebrew)
        let bottom = rows[2]

        for level in [GroupedKeys.Level.l2, .l3] {
            XCTAssertNil(
                GroupedKeys.split(bottom, level: level, avoiding: GroupedKeys.hebrewClitics),
                "three clitics cannot be separated into \(GroupedKeys.keyCount(rowLength: bottom.count, level: level)) keys"
            )

            let grouped = GroupedKeys.groups(
                for: rows, keepingApart: GroupedKeys.hebrewClitics, level: level)
            // Drawn row 1, not source row 2: the top two rows band into one.
            XCTAssertEqual(
                grouped[1], GroupedKeys.split(bottom, level: level),
                "the unsatisfiable row must fall back to the plain split at \(level.rawValue) per key")
            XCTAssertEqual(grouped[1].flatMap { $0 }, bottom, "the fallback dropped letters")
        }
    }

    /// `nil` is a result and not a failure: it means separating those letters costs
    /// an extra key. Two clitics on a two-letter row that gets one key is the
    /// smallest case of it, and the control beside it is what stops the assertion
    /// passing against a solver that refuses any group holding a clitic at all —
    /// which would return `nil` for every Hebrew row at every level.

}
