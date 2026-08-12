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
///
/// **`testDevanagariMayNotBeGrouped` fails against the code as it stands**, and it
/// is meant to: `GroupedKeys.supports` asks whether each *key* is one `Character`
/// when the question it has to answer is whether a *joined group* splits back into
/// the keys it came from. See the comment on that test.
final class GroupedKeysTests: XCTestCase {

    /// The rows this feature transforms, read from the shipped layout rather than
    /// restated — `Bar/grouped/make-rows.py` extracts the same strings from
    /// `LetterLayouts.swift`, so a row edited there moves the harness and this test
    /// together.
    private func letterRows(_ language: KeyboardLanguage) throws -> [[String]] {
        try letterLayout(language).rows
    }

    private func letterLayout(_ language: KeyboardLanguage) throws -> KeyboardLayout.LetterLayout {
        try XCTUnwrap(KeyboardLayout.letterLayouts[language])
    }

    /// Hebrew is the only language with anything to keep apart, so the two arguments
    /// the `keepingApart:` form ever takes are these.
    private let noAvoid: Set<String> = []

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
    func testTheExtraLetterGoesToTheLeadingGroups() throws {
        let top = try letterRows(.english)[0]

        XCTAssertEqual(
            GroupedKeys.split(top, level: .l1).map { $0.joined() }, ["qwer", "tyu", "iop"])
    }

    /// Order and adjacency are the whole promise here: the letters stay where a
    /// thumb already knows them and only the boundaries move. Hebrew is in this loop
    /// because its rows are stored **left to right on screen**, so a split that read
    /// them as logical order and reversed them would be the defect that shipped all
    /// six right-to-left keyboards mirrored.
    func testEveryLetterSurvivesInOrderAtEveryLevel() throws {
        for (language, avoid) in [(KeyboardLanguage.english, noAvoid), (.hebrew, GroupedKeys.hebrewClitics)] {
            let rows = try letterRows(language)
            for level in GroupedKeys.Level.allCases {
                let grouped = GroupedKeys.groups(for: rows, keepingApart: avoid, level: level)
                XCTAssertEqual(
                    grouped.count, rows.count,
                    "\(language.rawValue) at \(level.rawValue) per key lost or merged a row")
                for (index, row) in rows.enumerated() {
                    XCTAssertEqual(
                        grouped[index].flatMap { $0 }, row,
                        "\(language.rawValue) row \(index) at \(level.rawValue) per key is not the row it was given"
                    )
                }
            }
        }
    }

    /// The table in `Bar/grouped/README.md`, which is the keyboard
    /// `GroupedKeys.Level.measuredAccuracy` reports percentages for. A key count
    /// that drifts means those percentages describe a keyboard this is not.
    func testTheKeyCountsAreTheOnesThatWereMeasured() throws {
        let measured: [(KeyboardLanguage, Set<String>, GroupedKeys.Level, Int)] = [
            (.english, noAvoid, .off, 26), (.english, noAvoid, .pairs, 14),
            (.english, noAvoid, .l1, 8), (.english, noAvoid, .l2, 7), (.english, noAvoid, .l3, 5),
            (.hebrew, GroupedKeys.hebrewClitics, .off, 27),
            (.hebrew, GroupedKeys.hebrewClitics, .pairs, 14),
            (.hebrew, GroupedKeys.hebrewClitics, .l1, 9),
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
    func testTheEnglishGroupsAreTheOnesThatWereMeasured() throws {
        let expected: [GroupedKeys.Level: [[String]]] = [
            .pairs: [
                ["qw", "er", "ty", "ui", "op"], ["as", "df", "gh", "jk", "l"],
                ["zx", "cv", "bn", "m"]
            ],
            .l1: [["qwer", "tyu", "iop"], ["asd", "fgh", "jkl"], ["zxcv", "bnm"]],
            .l2: [["qwer", "tyu", "iop"], ["asdfg", "hjkl"], ["zxcv", "bnm"]],
            .l3: [["qwert", "yuiop"], ["asdfg", "hjkl"], ["zxcvbnm"]]
        ]

        let rows = try letterRows(.english)
        for (level, groups) in expected {
            let grouped = GroupedKeys.groups(for: rows, keepingApart: noAvoid, level: level)
            XCTAssertEqual(
                grouped.map { row in row.map { $0.joined() } }, groups,
                "english at \(level.rawValue) letters per key")
        }
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

    /// **Worth +4.9 points at 14 keys and +2.3 at nine, at no extra keys.** Plain
    /// adjacency puts ה and מ on one key at L1, so "the X" and "from X" become the
    /// same keystroke in a language where every sentence has one.
    ///
    /// This rejects the build that never keeps them apart, and it has to be asserted
    /// at both levels to do it: plain adjacency splits the bottom row into
    /// `זסב|הנמ|צתץ` at L1, landing ה with מ, and into `זס|בה|נמ|צת|ץ` at `.pairs`,
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
            XCTAssertEqual(
                grouped[2], GroupedKeys.split(bottom, level: level),
                "the unsatisfiable row must fall back to the plain split at \(level.rawValue) per key")
            XCTAssertEqual(grouped[2].flatMap { $0 }, bottom, "the fallback dropped letters")
        }
    }

    /// `nil` is a result and not a failure: it means separating those letters costs
    /// an extra key. Two clitics on a two-letter row that gets one key is the
    /// smallest case of it, and the control beside it is what stops the assertion
    /// passing against a solver that refuses any group holding a clitic at all —
    /// which would return `nil` for every Hebrew row at every level.
    func testTheConstrainedSplitReturnsNilOnlyWhenItIsImpossible() throws {
        let bottom = try letterRows(.hebrew)[2]
        let samekh = bottom[1]
        let bet = bottom[2]
        let he = bottom[3]
        XCTAssertTrue(GroupedKeys.hebrewClitics.contains(bet), "row order changed under this test")
        XCTAssertTrue(GroupedKeys.hebrewClitics.contains(he), "row order changed under this test")
        XCTAssertFalse(
            GroupedKeys.hebrewClitics.contains(samekh), "row order changed under this test")

        XCTAssertEqual(GroupedKeys.keyCount(rowLength: 2, level: .pairs), 1)
        XCTAssertNil(GroupedKeys.split([bet, he], level: .pairs, avoiding: GroupedKeys.hebrewClitics))
        XCTAssertEqual(
            GroupedKeys.split([bet, samekh], level: .pairs, avoiding: GroupedKeys.hebrewClitics)?
                .map { $0.joined() },
            [bet + samekh],
            "one clitic on a key is allowed; only a second one is not")
    }

    /// **Exhaustive over contiguous partitions rather than greedy, and the bottom row
    /// at `.pairs` is where the two disagree.** Greedy takes two letters, finds that
    /// ב and ה would collide, backs off to one, and produces sizes 2,1,2,2,2. The
    /// exhaustive walk reaches sizes 1,2,2,2,2 — the same squared-deviation cost, the
    /// same key count, the same constraint satisfied — and keeps the first minimum it
    /// finds, which is the one with the smallest leading group. Only the sizes can
    /// see the difference, so only the sizes are asserted.
    func testTheConstrainedSplitIsExhaustiveRatherThanGreedy() throws {
        let rows = try letterRows(.hebrew)
        let grouped = GroupedKeys.groups(
            for: rows, keepingApart: GroupedKeys.hebrewClitics, level: .pairs)

        XCTAssertEqual(grouped[2].map(\.count), [1, 2, 2, 2, 2])
    }

    // MARK: - The escape hatch

    /// **A grouped cap's long press is the only route to an exact letter**, so this
    /// is what stands between the feature and a keyboard nobody can get out of.
    /// `alternates[cap]` has to be the cap's own letters: the version that reads
    /// `base.alternates[cap] ?? []` compiles, answers `[]` for every grouped cap
    /// because no accent table has an entry for `qwer`, and leaves the whole alphabet
    /// untypeable while every key still draws.
    func testAGroupedCapOffersItsOwnLettersOnALongPress() throws {
        let grouped = GroupedKeys.layout(try letterLayout(.english), language: .english, level: .l1)

        XCTAssertEqual(grouped.rows[0], ["qwer", "tyu", "iop"])
        XCTAssertEqual(grouped.alternates["qwer"], ["q", "w", "e", "r"])
        XCTAssertEqual(grouped.alternates["bnm"], ["b", "n", "m"])
    }

    /// The same claim said over every letter of both languages at every level: after
    /// grouping, each letter is either a key of its own or an item in exactly one
    /// key's popup. `sorted()` rather than a `Set`, so a letter that arrives twice
    /// fails too.
    func testEveryLetterIsStillReachableAtEveryLevel() throws {
        for language in [KeyboardLanguage.english, .hebrew] {
            let base = try letterLayout(language)
            for level in [GroupedKeys.Level.pairs, .l1, .l2, .l3] {
                let grouped = GroupedKeys.layout(base, language: language, level: level)
                var reachable: [String] = []
                for cap in grouped.rows.flatMap({ $0 }) {
                    // A one-letter cap is reached by tapping it; anything wider is
                    // reached only through the popup.
                    let letters = GroupedKeys.letters(inCap: cap)
                    reachable += letters.count == 1 ? [cap] : (grouped.alternates[cap] ?? [])
                }
                XCTAssertEqual(
                    reachable.sorted(), base.rows.flatMap { $0 }.sorted(),
                    "\(language.rawValue) at \(level.rawValue) letters per key")
            }
        }
    }

    /// A group of one letter is an ordinary key and keeps its accents. English at
    /// `.pairs` is where that case is real: nine letters over five keys leaves `l`
    /// alone, and it still has to offer ł. The version that hands every cap its own
    /// letters answers `["l"]` — a one-item popup, and the accent gone.
    func testASingleLetterGroupKeepsItsOwnAlternates() throws {
        let base = try letterLayout(.english)
        let grouped = GroupedKeys.layout(base, language: .english, level: .pairs)

        XCTAssertEqual(grouped.rows[1], ["as", "df", "gh", "jk", "l"])
        XCTAssertEqual(grouped.alternates["l"], base.alternates["l"])
        XCTAssertEqual(grouped.alternates["l"], ["ł"])

        // `m` is alone on its key too and has no accents to keep, so it gets none
        // rather than being offered itself.
        XCTAssertEqual(grouped.rows[2], ["zx", "cv", "bn", "m"])
        XCTAssertEqual(grouped.alternates["m"], [String]())
    }

    /// The same case in Hebrew, where the alternates are marks rather than accents.
    /// ז comes out alone on the bottom row at `.pairs` — that is the singleton the
    /// clitic constraint produces — and it has to keep its geresh and gershayim,
    /// which are on no plane and reachable no other way.
    func testASingleLetterHebrewGroupKeepsItsGereshAndGershayim() throws {
        let base = try letterLayout(.hebrew)
        let zayin = try letterRows(.hebrew)[2][0]
        let grouped = GroupedKeys.layout(base, language: .hebrew, level: .pairs)

        XCTAssertEqual(grouped.rows[2].first, zayin)
        XCTAssertEqual(grouped.alternates[zayin], [zayin + "\u{05F3}", zayin + "\u{05F4}"])
    }

    /// **Grouping off is today's keyboard, and the accents are how you can tell.**
    /// The whole alternates table has to arrive intact rather than being rebuilt from
    /// the caps, which is what makes `off` "not a special case anywhere" true of the
    /// result as well as of the code.
    func testGroupingOffLeavesTheLayoutExactlyAsItWas() throws {
        let base = try letterLayout(.english)
        let off = GroupedKeys.layout(base, language: .english, level: .off)

        XCTAssertEqual(off.rows, base.rows)
        XCTAssertEqual(off.alternates, base.alternates)
        XCTAssertEqual(off.hasCase, base.hasCase)
        // Not an empty table agreeing with an empty table: à á â ä æ ã å ā.
        XCTAssertEqual(off.alternates["a"]?.count, 8)
    }

    // MARK: - Which languages may be grouped

    func testEnglishAndHebrewMayBeGrouped() {
        XCTAssertTrue(GroupedKeys.supports(.english))
        XCTAssertTrue(GroupedKeys.supports(.hebrew))
    }

    /// **This test fails against the code as it stands, and the failure is the
    /// finding.**
    ///
    /// `supports(_:)` asks whether each *key* is a single `Character`. Every
    /// Devanagari key is — `ौ` is one combining mark, one scalar, one grapheme — so
    /// it answers `true` and InScript gets grouped. The question it needed to ask is
    /// whether a *joined group* splits back into the keys it was built from, and that
    /// is where Devanagari fails: a run of combining marks with no base is one
    /// grapheme cluster, so the three keys `ौ` `ै` `ा` join into a cap that
    /// `letters(inCap:)` splits into **one** letter that no key ever carried. The
    /// long press then offers a fused mark instead of the three letters, which is
    /// exactly the escape hatch failing in the one way that traps the user.
    ///
    /// The evidence is asserted first so the failure below is not a matter of taste.
    /// The fix is to ask the real question — `row.joined().map(String.init) == row`
    /// per row — rather than to ask about a key in isolation.
    func testDevanagariMayNotBeGrouped() throws {
        let top = try letterRows(.hindi)[0]
        let cap = top.prefix(3).joined()

        // Swift's own grapheme breaking, not this repo's code: three keys in, one
        // "letter" out, and it is not any of the three.
        XCTAssertEqual(GroupedKeys.letters(inCap: cap).count, 1)
        XCTAssertNotEqual(GroupedKeys.letters(inCap: cap), Array(top.prefix(3)))

        XCTAssertFalse(
            GroupedKeys.supports(.hindi),
            "supports() checks that each key is one Character; every Devanagari key is, and the fusion happens when a group is joined"
        )

        // The consequence, and the reason the refusal is not fussiness.
        let base = try letterLayout(.hindi)
        XCTAssertEqual(
            GroupedKeys.layout(base, language: .hindi, level: .l1).rows, base.rows,
            "an unsupported language must never see this feature")
    }

    // MARK: - The keystroke code

    /// Keys are numbered across the whole keyboard rather than per row: `a` opens the
    /// second row and must not share a code with `q`, which opens the first. A
    /// per-row numbering compiles, draws identically, and silently makes those two
    /// letters the same keystroke.
    func testLettersAreNumberedAcrossTheWholeKeyboard() throws {
        let letterKeys = GroupedDecoder.letterToKey(
            rows: try letterRows(.english), keepingApart: noAvoid, level: .l1)

        XCTAssertEqual(letterKeys.count, 26)
        XCTAssertEqual(Set(letterKeys.values).count, 8)
        XCTAssertEqual(letterKeys["q"], 0)
        XCTAssertEqual(letterKeys["r"], 0)
        XCTAssertEqual(letterKeys["t"], 1)
        XCTAssertEqual(letterKeys["a"], 3)
        XCTAssertEqual(letterKeys["m"], 7)
    }

    /// **The rest of this file trusts the `rows:` form, and the keyboard ships the
    /// language one.** They have to answer identically or the tests are measuring
    /// something the phone does not run. The counts are asserted rather than
    /// `isEmpty`, because an empty map is precisely what the language form returns
    /// when `letterLayouts` has no entry — and a decoder built on an empty map codes
    /// no word, indexes nothing, and answers `[]` to every query, which reads as a
    /// broken decoder rather than a missing layout.
    func testTheRowsFormAndTheLanguageFormAgree() throws {
        XCTAssertEqual(
            GroupedDecoder.letterToKey(language: .english, level: .l1),
            GroupedDecoder.letterToKey(
                rows: try letterRows(.english), keepingApart: noAvoid, level: .l1))
        XCTAssertEqual(
            GroupedDecoder.letterToKey(language: .hebrew, level: .l1),
            GroupedDecoder.letterToKey(
                rows: try letterRows(.hebrew), keepingApart: GroupedKeys.hebrewClitics, level: .l1))

        XCTAssertEqual(GroupedDecoder.letterToKey(language: .english, level: .l1).count, 26)
        XCTAssertEqual(GroupedDecoder.letterToKey(language: .hebrew, level: .l1).count, 27)
    }

    /// Two letters on one key are one keystroke — that is the whole feature — and two
    /// letters on different keys are not. The first assertion rejects a decoder that
    /// codes each letter as itself, which is an ungrouped keyboard wearing grouped
    /// caps; the second rejects one that folds everything onto a single scalar, which
    /// would decode every word to the commonest word of its length.
    func testLettersOnOneKeyShareACodeAndLettersOnTwoDoNot() throws {
        let letterKeys = GroupedDecoder.letterToKey(
            rows: try letterRows(.english), keepingApart: noAvoid, level: .l1)

        XCTAssertEqual(
            GroupedDecoder.code(for: "q", map: letterKeys),
            GroupedDecoder.code(for: "w", map: letterKeys))
        XCTAssertNotEqual(
            GroupedDecoder.code(for: "q", map: letterKeys),
            GroupedDecoder.code(for: "t", map: letterKeys))
        // The Private Use Area, not 0x100: at 0x100 key 1 would be U+0101, which is
        // ā, so a character passing through could collide with a key index.
        XCTAssertEqual(GroupedDecoder.code(for: "qt", map: letterKeys), "\u{E000}\u{E001}")
        // t, h, e are keys 1, 4, 0 — the code the Python harness answers for `the`.
        XCTAssertEqual(
            GroupedDecoder.code(for: "the", map: letterKeys), "\u{E001}\u{E004}\u{E000}")
    }

    /// **A mark passes through and a foreign letter does not.** The apostrophe lives
    /// on the numbers plane, where nothing is grouped and so nothing is ambiguous, and
    /// coding it as itself is what keeps `don't` in the dictionary instead of dropping
    /// every contraction. A letter that is on no key of this layout has no keystroke
    /// at all, and coding it as itself would put a word in the list that cannot be
    /// typed.
    func testAMarkCodesAsItselfAndAnUntypeableLetterCodesAsNothing() throws {
        let letterKeys = GroupedDecoder.letterToKey(
            rows: try letterRows(.english), keepingApart: noAvoid, level: .l1)

        // d, o, n, t are keys 3, 2, 7, 1; the apostrophe is itself.
        XCTAssertEqual(
            GroupedDecoder.code(for: "don't", map: letterKeys), "\u{E003}\u{E002}\u{E007}'\u{E001}")
        XCTAssertNil(GroupedDecoder.code(for: "ā", map: letterKeys))
        XCTAssertNil(GroupedDecoder.code(for: "שלום", map: letterKeys))
    }

    // MARK: - Decoding

    /// The vocabulary the Swift and the Python were cross-checked on, in frequency
    /// order — a lower index is commoner. Passed to the decoder explicitly, because
    /// `GroupedLexiconResource` is generated and gitignored and a test that leaned on
    /// it would be asserting about a file that is usually absent.
    private static let vocabulary = [
        "the", "to", "and", "of", "a", "in", "is", "it", "that", "for",
        "cat", "car", "cab", "bat"
    ]

    private func referenceDecoder() -> GroupedDecoder {
        GroupedDecoder(
            language: .english, level: .l1, words: GroupedKeysTests.vocabulary, source: .bundled)
    }

    private func referenceKeys() throws -> [String: Int] {
        GroupedDecoder.letterToKey(
            rows: try letterRows(.english), keepingApart: noAvoid, level: .l1)
    }

    /// **The three answers the two implementations were checked against.** Typing
    /// `the` one key at a time: after `t` the bar can only narrow to the words on
    /// that key, after `h` to two, after `e` to one.
    ///
    /// The first line is the one that rejects most wrong builds. Inside that prefix
    /// the codes sort `to` before `the` before `that`, so a decoder that walks its
    /// sorted index and returns what it meets answers `to, the, that` — the right
    /// three words in the wrong order, with the wrong one bold.
    func testTypingAWordOneKeyAtATimeNarrowsAsItDidInPython() throws {
        let decoder = referenceDecoder()
        let code = try XCTUnwrap(GroupedDecoder.code(for: "the", map: try referenceKeys()))

        XCTAssertEqual(decoder.candidates(startingWith: String(code.prefix(1))), ["the", "to", "that"])
        XCTAssertEqual(decoder.candidates(startingWith: String(code.prefix(2))), ["the", "that"])
        XCTAssertEqual(decoder.candidates(startingWith: code), ["the"])

        XCTAssertEqual(
            decoder.candidates(startingWith: String(code.prefix(1)), limit: 2), ["the", "to"])
        // Reported rather than assumed, the rule `SharedStore.storage` follows.
        XCTAssertEqual(decoder.source, .bundled)
    }

    /// **Commonest first, and code order is deliberately not the answer.** Four words
    /// begin on key 2 — `of`, `in`, `is`, `it` — and their codes sort `it, is, of,
    /// in`, so a decoder that returns the first three it meets in its index answers
    /// `it, is, of`: three real words, none of them the commonest, for a keyboard
    /// whose whole claim is that the ranking recovers what the keys threw away.
    func testCandidatesComeBackCommonestFirstRatherThanInCodeOrder() throws {
        let decoder = referenceDecoder()
        let code = try XCTUnwrap(GroupedDecoder.code(for: "i", map: try referenceKeys()))

        XCTAssertEqual(decoder.candidates(startingWith: code), ["of", "in", "is"])
    }

    /// Nothing typed is not a prefix of everything. An empty code has to answer
    /// nothing, or the bar fills with words before a key has been pressed — which is
    /// what the ungrouped bar's hardcoded openers did, and what made
    /// `XCTAssertFalse(_.isEmpty)` pass against a keyboard whose document was
    /// unreadable.
    func testAnEmptyCodeAnswersNothing() {
        XCTAssertEqual(referenceDecoder().candidates(startingWith: ""), [])
    }

    /// **A pin is the user overruling the decoder, so it filters rather than
    /// nudges.** Long-pressing a key and choosing a letter out of it is the escape
    /// hatch being used; a candidate that disagrees with the letter somebody
    /// deliberately picked is not a worse answer, it is the wrong answer. Ranking it
    /// down instead would still leave `to` in the bar after the user said the second
    /// letter is `h`.
    func testAPinnedLetterFiltersTheCandidatesRatherThanRerankingThem() throws {
        let decoder = referenceDecoder()
        let code = String(try XCTUnwrap(GroupedDecoder.code(for: "the", map: try referenceKeys())).prefix(1))

        XCTAssertEqual(decoder.candidates(startingWith: code, pinnedTo: [:]), ["the", "to", "that"])
        XCTAssertEqual(decoder.candidates(startingWith: code, pinnedTo: [1: "h"]), ["the", "that"])
        XCTAssertEqual(decoder.candidates(startingWith: code, pinnedTo: [2: "a"]), ["that"])
        // Every candidate disagreeing with the pin is an empty bar, which is honest:
        // `literal(for:)` is what goes on screen then.
        XCTAssertEqual(decoder.candidates(startingWith: code, pinnedTo: [0: "z"]), [])
    }

    /// A pin can outlive the word it was set on — the user picks a letter at position
    /// 3 and the candidate is two letters long — so the bounds check is doing real
    /// work rather than guarding a theoretical crash. A word too short to hold the
    /// pin does not satisfy it.
    func testAPinPastTheEndOfAWordRejectsThatWord() throws {
        let decoder = referenceDecoder()
        let code = String(try XCTUnwrap(GroupedDecoder.code(for: "the", map: try referenceKeys())).prefix(1))

        XCTAssertEqual(decoder.candidates(startingWith: code, pinnedTo: [3: "t"]), ["that"])
        XCTAssertFalse(GroupedDecoder.honours([3: "t"], "the"))
        XCTAssertTrue(GroupedDecoder.honours([3: "t"], "that"))
    }

    /// **The keyboard must never go blank while somebody is typing.** With no
    /// candidate at all, what goes on screen is the first letter of each cap pressed:
    /// usually not a word, always something visible that can be deleted. Joining the
    /// caps instead answers `qwertyuiop` for three keystrokes, which is ten
    /// characters the user did not type.
    func testTheFallbackIsTheFirstLetterOfEachCap() throws {
        let grouped = GroupedKeys.layout(try letterLayout(.english), language: .english, level: .l1)

        XCTAssertEqual(GroupedDecoder.literal(for: grouped.rows[0]), "qti")
        // With grouping off every cap is one letter, so the fallback is exactly what
        // was keyed.
        XCTAssertEqual(GroupedDecoder.literal(for: ["h", "i"]), "hi")
        XCTAssertEqual(GroupedDecoder.literal(for: []), "")
    }

    // MARK: What ends a grouped word

    /// The broken version ends the word only on space, which leaves the strokes
    /// describing a word the cursor has since left — so the next grouped press
    /// rewrites whatever now sits behind it. Return, the globe and the cursor
    /// keys are the ones that used to slip through.
    func testEverythingExceptLettersDeleteAndShiftEndsTheWord() {
        for cap in [KeyCap.character("a"), .character("qwer"), .backspace, .shift] {
            XCTAssertFalse(
                GroupedInput.interrupts(cap), "\(cap) should let the word carry on")
        }
        for cap in [
            KeyCap.space, .ret, .globe, .emoji, .settings, .dictation, .cursorLeft,
            .cursorRight, .quickTone, .hideKeyboard, .plane(.numbers, label: "123")
        ] {
            XCTAssertTrue(GroupedInput.interrupts(cap), "\(cap) should end the word")
        }
    }

    /// A new `KeyCap` must end a grouped word by default rather than silently
    /// continuing one, so the switch has to be written as "which continue".
    func testAnUnknownCapEndsTheWord() {
        XCTAssertTrue(GroupedInput.interrupts(.aiFix))
        XCTAssertTrue(GroupedInput.interrupts(.aiReply))
    }

    // MARK: Case

    /// Shift is read once at the first key. The broken version read it per
    /// keystroke, and since a one-shot shift is consumed by the first press,
    /// `The` decoded as `The` and then immediately as `the`.
    func testShiftCapitalisesTheFirstLetterOnlyAndSurvivesLaterKeystrokes() {
        let input = GroupedInput()
        input.startedShifted = true
        // Not `THE`: shift on a word means a capital, not caps lock.
        XCTAssertEqual(input.cased("the", in: .english), "The")
        XCTAssertEqual(input.cased("hello", in: .english), "Hello")
        // Still capitalised however many times it is asked, because the flag is
        // the word's, not the keystroke's.
        XCTAssertEqual(input.cased("the", in: .english), "The")
        XCTAssertEqual(input.cased("", in: .english), "")

        input.startedShifted = false
        XCTAssertEqual(input.cased("the", in: .english), "the")
    }

    /// Hebrew has no case, so casing must be a no-op rather than something that
    /// mangles the word.
    func testCasingAHebrewWordChangesNothing() {
        let input = GroupedInput()
        input.startedShifted = true
        XCTAssertEqual(input.cased("שלום", in: .hebrew), "שלום")
    }

    /// `clear()` has to drop the case flag and the written text too. Leaving
    /// `lastWritten` behind makes the next press compare the field against a word
    /// that is no longer in it and conclude the cursor moved.
    func testClearingForgetsEverythingAboutTheWord() {
        let input = GroupedInput()
        input.startedShifted = true
        input.lastWritten = "The"
        input.append(cap: "qwer")
        input.clear()
        XCTAssertFalse(input.isTyping)
        XCTAssertFalse(input.startedShifted)
        XCTAssertEqual(input.lastWritten, "")
    }

    // MARK: The layout engine is a pure function of its arguments

    /// **The version this rejects read the dial out of `SharedStore` inside
    /// `KeyboardLayout`.** That made the whole layout engine depend on global
    /// mutable state: a dial left on in the simulator's App Group — which is
    /// exactly what happens on a machine where somebody has tried the feature —
    /// silently made `RenderedRowOrderTests` and `LanguageCatalogueTests` measure
    /// a grouped keyboard. The same shape as the `PersonalLanguageModel` trap,
    /// where the suite taught the store its own vocabulary and then tested
    /// against it.
    ///
    /// Asserting on the *default* argument is the whole point: it is what every
    /// existing caller and every existing test gets.
    func testTheLayoutIsUngroupedUnlessAskedRegardlessOfTheStore() {
        SharedStore.shared.groupedLevel = .l1
        defer { SharedStore.shared.groupedLevel = .off }

        for language in [KeyboardLanguage.english, .hebrew] {
            let rows = KeyboardLayout.rows(for: language, plane: .letters)
            let caps = rows.flatMap(\.keys).compactMap { spec -> String? in
                if case .character(let value) = spec.cap { return value }
                return nil
            }
            let expected = KeyboardLayout.letterLayouts[language]!.rows.flatMap { $0 }
            XCTAssertEqual(
                caps, expected,
                "\(language) drew a grouped keyboard from the store rather than its argument")
            // Every cap one letter: the grouped version merges them.
            XCTAssertTrue(caps.allSatisfy { $0.count == 1 })
        }

        XCTAssertEqual(KeyboardLayout.columns(for: .english, plane: .letters), 10)
        // And asking for grouping explicitly still works, so this is not just a
        // test that the feature is off.
        XCTAssertEqual(KeyboardLayout.columns(for: .english, plane: .letters, grouping: .l1), 5)
    }

    // MARK: Which fields may be grouped

    /// A password, email or URL field is typed exactly or not at all, and in a
    /// password field the user cannot even see what a decoder got wrong.
    func testCredentialAndExactFieldsAreNeverGrouped() {
        XCTAssertFalse(GroupedKeys.permitted(secure: true, contentType: nil))
        XCTAssertFalse(GroupedKeys.permitted(secure: nil, contentType: .some(.password)))
        XCTAssertFalse(GroupedKeys.permitted(secure: nil, contentType: .some(.emailAddress)))
        XCTAssertFalse(GroupedKeys.permitted(secure: nil, contentType: .some(.URL)))
        XCTAssertFalse(GroupedKeys.permitted(secure: nil, contentType: .some(.username)))
        // A field that says nothing is an ordinary field: silence is an
        // unimplemented optional protocol member, not a password box. Same rule
        // `SecureField.permitsRead` is built on.
        XCTAssertTrue(GroupedKeys.permitted(secure: nil, contentType: nil))
        XCTAssertTrue(GroupedKeys.permitted(secure: false, contentType: .some(nil)))
        XCTAssertTrue(GroupedKeys.permitted(secure: false, contentType: .some(.name)))
    }
}
