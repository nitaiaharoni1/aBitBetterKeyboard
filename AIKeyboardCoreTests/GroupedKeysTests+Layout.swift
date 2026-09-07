import XCTest

@testable import AIKeyboardCore

extension GroupedKeysTests {
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

        XCTAssertEqual(grouped[1].map(\.count), [3, 2, 2, 2])
        // The splitter itself still prefers the singleton-leading partition; the
        // plan folds that leftover in rather than drawing a one-letter key.
        XCTAssertEqual(
            GroupedKeys.split(
                try letterRows(.hebrew)[2], level: .pairs,
                avoiding: GroupedKeys.hebrewClitics
            )?.map(\.count),
            [1, 2, 2, 2, 2])
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

        // The cap carries the line break between the two rows it merged, and the
        // popup lists the letters top row first.
        XCTAssertEqual(grouped.rows[0], ["qw\nas", "er\ndf", "ty\ngh", "ui\njk", "op\nl"])
        XCTAssertEqual(grouped.alternates["qw\nas"], ["q", "w", "a", "s"])
        XCTAssertEqual(grouped.alternates["bnm"], ["b", "n", "m"])
    }

    /// **The line break in a cap is layout, never a letter.** `letters(inCap:)` is
    /// the only route from a cap back to what it types, so a version that kept the
    /// newline types one — and the decoder codes a keystroke nothing is on.
    func testTheLineBreakInACapIsNotALetter() throws {
        let grouped = GroupedKeys.layout(try letterLayout(.english), language: .english, level: .l2)
        let cap = try XCTUnwrap(grouped.rows[0].first)

        XCTAssertTrue(cap.contains("\n"), "a banded cap has to be drawn on two lines")
        XCTAssertEqual(GroupedKeys.letters(inCap: cap), ["q", "w", "a", "s"])
        // And it never reaches an accessibility identifier, which a UI test types.
        XCTAssertEqual(KeySpec(.character(cap)).id, "char-qw-as")
    }

    /// A band key with nothing in the row above still occupies both lines, so its
    /// letters sit on the lower half rather than floating in the middle of a
    /// double-height key. The blank line is layout: `letters(inCap:)` drops it.
    func testALeftoverBottomColumnStillOccupiesBothLinesOfTheBand() throws {
        let rows = KeyboardLayout.rows(for: .hebrew, plane: .letters, grouping: .pairs)
        let last = try XCTUnwrap(rows.first?.keys.last)

        XCTAssertEqual(last.groupedLines.count, 2, "the blank top line is how it stays on the lower half")
        XCTAssertTrue(last.groupedLines[0].isEmpty)
        XCTAssertEqual(last.groupedLines[1], ["ך", "ף"])
        XCTAssertEqual(last.groupedLetters, ["ך", "ף"])
        XCTAssertEqual(last.id, "char--ךף")
        if case .character(let cap) = last.cap {
            XCTAssertTrue(cap.hasPrefix("\n"), "the leading break is the empty top line")
            XCTAssertEqual(GroupedKeys.letters(inCap: cap), ["ך", "ף"])
            // `letters(inCap:)` is the only safe first-character, because the
            // cap itself starts with a newline.
            XCTAssertEqual(GroupedDecoder.literal(for: [cap]), "ך")
        } else {
            XCTFail("the leftover column has to be a character key")
        }
    }

    /// A tap clearly on one letter of the group names that letter; a tap in the
    /// middle of the key names nothing, so the decoder still has to guess. The
    /// broken version that always answers the first letter of the cap would pin
    /// every press to `q` on `qw/as`.
    func testATapOnACornerOfAGroupedKeyNamesThatLetterAndTheMiddleNamesNothing() {
        let qwas = [["q", "w"], ["a", "s"]]
        XCTAssertEqual(GroupedKeys.letter(atX: 0.2, y: 0.2, in: qwas), "q")
        XCTAssertEqual(GroupedKeys.letter(atX: 0.8, y: 0.2, in: qwas), "w")
        XCTAssertEqual(GroupedKeys.letter(atX: 0.2, y: 0.8, in: qwas), "a")
        XCTAssertEqual(GroupedKeys.letter(atX: 0.8, y: 0.8, in: qwas), "s")
        XCTAssertNil(GroupedKeys.letter(atX: 0.5, y: 0.5, in: qwas))
        XCTAssertNil(GroupedKeys.letter(atX: 0.5, y: 0.2, in: qwas), "on the line between q and w")
    }

    /// The blank top of a leftover band key is not a letter. A tap there must
    /// not invent one, and a tap on the lower half still names ך or ף.
    func testATapOnTheEmptyTopOfALeftoverKeyNamesNothing() throws {
        let rows = KeyboardLayout.rows(for: .hebrew, plane: .letters, grouping: .pairs)
        let last = try XCTUnwrap(rows.first?.keys.last)
        let lines = last.groupedLines
        XCTAssertNil(GroupedKeys.letter(atX: 0.5, y: 0.2, in: lines))
        XCTAssertEqual(GroupedKeys.letter(atX: 0.2, y: 0.8, in: lines), "ך")
        XCTAssertEqual(GroupedKeys.letter(atX: 0.8, y: 0.8, in: lines), "ף")
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

    /// **A leftover column is never a key of its own.** English `p` and Hebrew `ז`
    /// used to sit alone, which is a skinny one-character button on a feature
    /// whose point is size. Accents on those letters stay reachable with grouping
    /// off — the same rule every other grouped letter already followed.
    func testAGroupedKeyNeverCarriesASingleLetter() throws {
        for language in [KeyboardLanguage.english, .hebrew] {
            let avoid: Set<String> = language == .hebrew ? GroupedKeys.hebrewClitics : noAvoid
            for level in [GroupedKeys.Level.pairs, .l1, .l2, .l3] {
                let grouped = GroupedKeys.groups(
                    for: try letterRows(language), keepingApart: avoid, level: level)
                for group in grouped.flatMap({ $0 }) {
                    XCTAssertGreaterThanOrEqual(
                        group.count, 2,
                        "\(group.joined()) is a singleton at \(language.rawValue) \(level.rawValue) per key")
                }
                let layout = GroupedKeys.layout(try letterLayout(language), language: language, level: level)
                for cap in layout.rows.flatMap({ $0 }) {
                    XCTAssertGreaterThanOrEqual(
                        GroupedKeys.letters(inCap: cap).count, 2,
                        "cap \(cap.debugDescription) is a singleton at \(language.rawValue) \(level.rawValue)"
                    )
                }
            }
        }
        XCTAssertEqual(try letterLayout(.english).alternates["l"], ["ł"])
        let zayin = try letterRows(.hebrew)[2][0]
        XCTAssertEqual(
            try letterLayout(.hebrew).alternates[zayin],
            [zayin + "\u{05F3}", zayin + "\u{05F4}"])
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

    /// **The invariant `supports(_:)` exists to guarantee, said over every language
    /// it lets through, at every level.** A cap is the only route back to "which
    /// letters is this key", so a layout this feature accepts has to split its caps
    /// into exactly the letters they were built from — across a band as well as
    /// along a row, since a band joins a letter to the one *underneath* it and no
    /// per-row check can see that pair.
    ///
    /// Written as a sweep rather than a list of language names, because a list goes
    /// stale the next time a layout is added and this cannot: a new language either
    /// satisfies the invariant or is refused by the same rule.
    func testEveryGroupableLanguageSplitsItsCapsBackIntoItsLetters() {
        var groupable: [KeyboardLanguage] = []
        for language in KeyboardLanguage.allCases where GroupedKeys.supports(language) {
            groupable.append(language)
            guard let base = KeyboardLayout.letterLayouts[language] else {
                XCTFail("\(language.rawValue) is groupable and has no layout")
                continue
            }
            for level in GroupedKeys.Level.allCases {
                for row in GroupedKeys.plan(for: base.rows, language: language, level: level) {
                    for group in row.groups {
                        XCTAssertEqual(
                            GroupedKeys.letters(inCap: group.cap), group.letters,
                            "\(language.rawValue) at \(level.rawValue) fused a cap")
                    }
                }
            }
        }

        // Not an empty sweep agreeing with itself.
        XCTAssertTrue(groupable.contains(.english))
        XCTAssertTrue(groupable.contains(.hebrew))
        XCTAssertFalse(groupable.contains(.hindi))
    }

    /// **This test used to fail on purpose, and the fix it prescribed is now in
    /// `supports(_:)`.**
    ///
    /// The old rule asked whether each *key* was a single `Character`. Every
    /// Devanagari key is — `ौ` is one combining mark, one scalar, one grapheme — so
    /// it answered `true` and InScript got grouped. The question it had to ask is
    /// whether *joined* letters split back into the letters they were built from,
    /// and that is where Devanagari fails: a run of combining marks with no base is
    /// one grapheme cluster, so the three keys `ौ` `ै` `ा` join into a cap that
    /// `letters(inCap:)` splits into **one** letter that no key ever carried. The
    /// long press then offers a fused mark instead of the three letters, which is
    /// exactly the escape hatch failing in the one way that traps the user.
    ///
    /// The evidence is asserted first, so the refusal below is a consequence rather
    /// than a matter of taste. Banding made the old rule worse rather than better —
    /// a band joins a letter to the one *underneath* it, so a per-row check would
    /// not have been enough either.
    func testDevanagariMayNotBeGrouped() throws {
        let top = try letterRows(.hindi)[0]
        let cap = top.prefix(3).joined()

        // Swift's own grapheme breaking, not this repo's code: three keys in, one
        // "letter" out, and it is not any of the three.
        XCTAssertEqual(GroupedKeys.letters(inCap: cap).count, 1)
        XCTAssertNotEqual(GroupedKeys.letters(inCap: cap), Array(top.prefix(3)))

        // And the rule that catches it, said over one key rather than a whole row:
        // doubling a base character gives two, doubling a combining mark gives one.
        XCTAssertEqual((top[0] + top[0]).count, 1)
        XCTAssertEqual(("q" + "q").count, 2)

        XCTAssertFalse(
            GroupedKeys.supports(.hindi),
            "a layout whose letters fuse when joined must never see this feature")

        // The consequence, and the reason the refusal is not fussiness.
        let base = try letterLayout(.hindi)
        XCTAssertEqual(
            GroupedKeys.layout(base, language: .hindi, level: .l1).rows, base.rows,
            "an unsupported language must never see this feature")
    }

    // MARK: - The keystroke code

    /// Keys are numbered across the whole keyboard rather than per drawn row: the
    /// band's five keys are 0…4 and the row under it carries on at 5. A per-row
    /// numbering compiles, draws identically, and silently makes `q` and `z` the
    /// same keystroke.
    ///
    /// `a` under `q` sharing key 0 is the feature rather than the bug the earlier
    /// version of this test guarded — which is why the pair that must *not* share
    /// is asserted as well.
    func testLettersAreNumberedAcrossTheWholeKeyboard() throws {
        let letterKeys = GroupedDecoder.letterToKey(
            rows: try letterRows(.english), keepingApart: noAvoid, level: .l1)

        XCTAssertEqual(letterKeys.count, 26)
        XCTAssertEqual(Set(letterKeys.values).count, 7)
        XCTAssertEqual(letterKeys["q"], 0)
        XCTAssertEqual(letterKeys["a"], 0)
        XCTAssertEqual(letterKeys["r"], 1)
        XCTAssertEqual(letterKeys["t"], 2)
        XCTAssertEqual(letterKeys["z"], 5)
        XCTAssertEqual(letterKeys["m"], 6)
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
        XCTAssertEqual(GroupedDecoder.code(for: "qt", map: letterKeys), "\u{E000}\u{E002}")
        // t, h, e are keys 2, 2, 1 — the code the Python harness answers for `the`.
        XCTAssertEqual(
            GroupedDecoder.code(for: "the", map: letterKeys), "\u{E002}\u{E002}\u{E001}")
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

        // d, o, n, t are keys 1, 4, 6, 2; the apostrophe is itself.
        XCTAssertEqual(
            GroupedDecoder.code(for: "don't", map: letterKeys), "\u{E001}\u{E004}\u{E006}'\u{E002}")
        XCTAssertNil(GroupedDecoder.code(for: "ā", map: letterKeys))
        XCTAssertNil(GroupedDecoder.code(for: "שלום", map: letterKeys))
    }

    // MARK: - Decoding

    /// The vocabulary the Swift and the Python were cross-checked on, in frequency
    /// order — a lower index is commoner. Passed to the decoder explicitly, because
    /// a test that leaned on `GroupedLexiconResource` would be asserting about a
    /// generated file rather than the ranking rule.
    private static let vocabulary = [
        "the", "to", "and", "of", "a", "in", "is", "it", "that", "for",
        "cat", "car", "cab", "bat"
    ]

    func referenceDecoder() -> GroupedDecoder {
        GroupedDecoder(
            language: .english, level: .l1, words: GroupedKeysTests.vocabulary, source: .bundled)
    }

    func referenceKeys() throws -> [String: Int] {
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

    /// Exact-length field, not a prefix completion. One key of `the` still
    /// prefix-matches `["the","to","that"]`; the field must not take `"the"`.
    func testDecodeWritesExactLengthNotALongerPrefix() throws {
        let decoder = referenceDecoder()
        let code = try XCTUnwrap(GroupedDecoder.code(for: "the", map: try referenceKeys()))
        let one = String(code.prefix(1))

        XCTAssertEqual(decoder.candidates(startingWith: one), ["the", "to", "that"])

        let none = decoder.decode(matching: one, completions: .none)
        XCTAssertNotEqual(none.fieldWord, "the")
        if let field = none.fieldWord {
            XCTAssertEqual(
                try XCTUnwrap(GroupedDecoder.code(for: field, map: try referenceKeys())), one)
        }
        XCTAssertFalse(none.barWords.contains { $0 == none.fieldWord })
        XCTAssertNil(none.idleCompletion)

        let after = decoder.decode(matching: one, completions: .afterExact)
        XCTAssertEqual(after.fieldWord, none.fieldWord)
        XCTAssertFalse(after.barWords.contains { $0 == after.fieldWord })
        XCTAssertEqual(after.idleCompletion, "the")

        let toCode = try XCTUnwrap(GroupedDecoder.code(for: "to", map: try referenceKeys()))
        let toDecode = decoder.decode(matching: toCode, completions: .afterExact)
        XCTAssertEqual(toDecode.fieldWord, "to")
        XCTAssertFalse(toDecode.barWords.contains("to"))
    }

    func testAnEmptyCodeDecodesToNothing() {
        let empty = referenceDecoder().decode(matching: "", completions: .afterExact)
        XCTAssertNil(empty.fieldWord)
        XCTAssertEqual(empty.barWords, [])
        XCTAssertNil(empty.idleCompletion)
    }

    /// **Commonest first, and code order is deliberately not the answer.** Three
    /// words begin on key 3 — `in`, `is`, `it` — and their codes sort `is, it, in`,
    /// so a decoder that returns what it meets walking its index answers `is, it,
    /// in`: three real words in the wrong order, for a keyboard whose whole claim is
    /// that the ranking recovers what the keys threw away.
    func testCandidatesComeBackCommonestFirstRatherThanInCodeOrder() throws {
        let decoder = referenceDecoder()
        let code = try XCTUnwrap(GroupedDecoder.code(for: "i", map: try referenceKeys()))

        XCTAssertEqual(decoder.candidates(startingWith: code), ["in", "is", "it"])
    }

    /// Nothing typed is not a prefix of everything. An empty code has to answer
    /// nothing, or the bar fills with words before a key has been pressed — which is
    /// what the ungrouped bar's hardcoded openers did, and what made
    /// `XCTAssertFalse(_.isEmpty)` pass against a keyboard whose document was
    /// unreadable.

}
