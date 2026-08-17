import XCTest

@testable import AIKeyboardCore

/// `דוגמטןת` for `דוגמאות` ("examples") is the case this whole file exists
/// for: two adjacent-key substitutions that every distance-1 correction
/// source in this engine — `SeedLanguageModel.neighbours`,
/// `UITextChecker.guesses` — was structurally unable to reach.
final class TypoChannelTests: XCTestCase {

    // MARK: The motivating case

    func testTwoAdjacentSlipsCostOneHundredAndTen() {
        let cost = TypoChannel.cost(
            typed: Array("דוגמטןת"), candidate: Array("דוגמאות"), language: .hebrew, budget: 130)
        XCTAssertEqual(cost, 110, "two adjacent-key substitutions, 55 apiece")
    }

    func testTheSameTwoSlipsDoNotFitTheShorterWordsBudget() {
        // A pre-fix build with no budget gate at all would happily return 110
        // here too. What has to fail is the budget check itself: 110 must not
        // fit inside the 100 a four- or five-letter word is allowed to spend.
        let cost = TypoChannel.cost(
            typed: Array("דוגמטןת"), candidate: Array("דוגמאות"), language: .hebrew, budget: 100)
        XCTAssertNil(cost, "110 must not fit a 100 budget, or the length gate is not doing anything")
    }

    func testTheLengthGateHandsOutTheRightBudgets() {
        XCTAssertNil(TypoChannel.budget(forTypedLength: 3))
        XCTAssertEqual(TypoChannel.budget(forTypedLength: 4), 100)
        XCTAssertEqual(TypoChannel.budget(forTypedLength: 5), 100)
        XCTAssertEqual(TypoChannel.budget(forTypedLength: 6), 130)
        XCTAssertEqual(TypoChannel.budget(forTypedLength: 12), 130)
    }

    // MARK: Two unrelated substitutions are not a typo

    func testTwoUnrelatedSubstitutionsAreOutOfReachAtEveryBudget() {
        // `z`/`q` are two rows apart on QWERTY and in no confusion class;
        // `a`/`r` are three columns apart and likewise unrelated. Each
        // substitution alone is a plain, unweighted edit — 100 — so the pair
        // is 200, which the most generous budget this file ever hands out
        // (130, for a six-letter-or-longer word) cannot afford.
        let cost = TypoChannel.cost(
            typed: Array("qebrr"), candidate: Array("zebra"), language: .english, budget: 130)
        XCTAssertNil(cost, "two unrelated substitutions must stay out of reach even at the top budget")
    }

    // MARK: Transposition

    func testAdjacentTranspositionCostsSixtyNotTwoSubstitutions() {
        // תדוה / תודה: the same slip `SeedLanguageModel.isTransposition`
        // already treats as one edit rather than two, priced here instead of
        // merely detected.
        let transposed = TypoChannel.cost(
            typed: Array("תדוה"), candidate: Array("תודה"), language: .hebrew, budget: 100)
        XCTAssertEqual(transposed, 60)

        let english = TypoChannel.cost(
            typed: Array("teh"), candidate: Array("the"), language: .english, budget: 100)
        XCTAssertEqual(english, 60, "teh/the is the same adjacent swap in the other script")

        // A build that only knew plain substitution would price this as two
        // changed letters. ת/ד and ו/ד are not a final-form pair, not in a
        // confusion class, and not adjacent on the Hebrew layout, so two
        // substitutions would cost 200 — nowhere near 60.
        XCTAssertNotEqual(
            transposed, 200, "a broken build pricing this as two substitutions would not reach 60")
    }

    // MARK: Transposition across Hebrew's final-form boundary

    func testTranspositionOutOfFinalPositionCostsTranspositionPlusTwenty() {
        // Corpus `typo-11`: שלמו for שלום. A reader sees one transposition
        // of ו and ם, but the mem loses its final shape the moment it
        // leaves the last position — candidate ends in ם, typed has מ one
        // letter earlier — so the raw swap check never fires and this has
        // to fall through to the shape-folded one. Before this fix `cost`
        // fell back to two unrelated substitutions (100 apiece, 200 total)
        // and returned nil against this budget.
        let cost = TypoChannel.cost(
            typed: Array("שלמו"), candidate: Array("שלום"), language: .hebrew, budget: 100)
        XCTAssertEqual(
            cost, 80, "60 for the swap, 20 for the shape change, still inside the length-4 budget of 100"
        )
    }

    func testTranspositionWithNoShapeChangeStaysAtSixty() {
        // The control for the fix above: neither swapped letter in
        // תדוה/תודה is ever a final form, so a build that charged the extra
        // 20 unconditionally rather than only when the raw swap fails would
        // fail this pair instead of the one the fix was written for.
        let cost = TypoChannel.cost(
            typed: Array("תדוה"), candidate: Array("תודה"), language: .hebrew, budget: 100)
        XCTAssertEqual(cost, 60)
    }

    func testTranspositionIntoFinalPositionCostsTheSameTwenty() {
        // The reverse of the control case above and a different real word
        // pair: candidate שלמו ("they paid") against typed שלום ("hello")
        // moves the same mem the other way, into final position, so it must
        // take its final shape (מ → ם) rather than lose it. Same mechanism,
        // same price — this is what confirms the fix is not one-directional.
        let cost = TypoChannel.cost(
            typed: Array("שלום"), candidate: Array("שלמו"), language: .hebrew, budget: 100)
        XCTAssertEqual(cost, 80)
    }

    // MARK: Final-form substitution

    func testFinalFormPairIsTwentyNotAPlainSubstitution() {
        let cost = TypoChannel.cost(
            typed: Array("שלומ"), candidate: Array("שלום"), language: .hebrew, budget: 100)
        XCTAssertEqual(cost, 20, "מ/ם is an orthography slip, not a fat finger")
        // A build with no final-form rule at all would still find this
        // substitution, just at the plain unweighted price.
        XCTAssertNotEqual(cost, TypoChannel.plainEdit)
    }

    // MARK: Deletion — mater lectionis beats an unrelated deletion

    func testDroppingAMaterLectionisIsCheaperThanAnUnrelatedDeletion() {
        // דוגמות is what a person writes when they drop the א from דוגמאות —
        // ktiv haser instead of ktiv male, the commonest Hebrew misspelling
        // there is.
        let materLectionis = TypoChannel.cost(
            typed: Array("דוגמות"), candidate: Array("דוגמאות"), language: .hebrew, budget: 130)
        XCTAssertEqual(materLectionis, 55)

        // Same shape — a candidate one letter longer than what was typed —
        // but the missing letter (נ) is not a mater lectionis, is not
        // doubled, and has nothing else cheap to say about it.
        let unrelated = TypoChannel.cost(
            typed: Array("דוגמות"), candidate: Array("דוגמנות"), language: .hebrew, budget: 130)
        XCTAssertEqual(unrelated, 100)

        XCTAssertLessThan(materLectionis!, unrelated!)
    }

    // MARK: Deletion — a doubled letter typed once

    func testADoubledLetterTypedOnceIsCheap() {
        let cost = TypoChannel.cost(
            typed: Array("acommodate"), candidate: Array("accommodate"), language: .english,
            budget: 130)
        XCTAssertEqual(cost, 55, "the second c is a doubled letter dropped, not a wild guess")
    }

    // MARK: Substitution — vowel confusion

    func testVowelConfusionIsCheaperThanAPlainSubstitution() {
        let cost = TypoChannel.cost(
            typed: Array("seperate"), candidate: Array("separate"), language: .english, budget: 130)
        XCTAssertEqual(cost, 40, "e for a is the English vowel-confusion class")
        XCTAssertNotEqual(cost, TypoChannel.plainEdit)
    }

    // MARK: Symmetry

    func testSubstitutionOnlyCostsAreSymmetric() {
        // A pure substitution difference (no length change) has to cost the
        // same regardless of which spelling is "the candidate" and which is
        // "what was typed" — every rule substitutionCost checks (equality, a
        // final-form pair, a confusion class, keyboard adjacency) reads the
        // same both ways. Insertion and deletion do not share that property,
        // which is why this test is scoped to a same-length pair.
        let forward = TypoChannel.cost(
            typed: Array("שלומ"), candidate: Array("שלום"), language: .hebrew, budget: 100)
        let backward = TypoChannel.cost(
            typed: Array("שלום"), candidate: Array("שלומ"), language: .hebrew, budget: 100)
        XCTAssertEqual(forward, backward)
        XCTAssertEqual(forward, 20)
    }

    // MARK: Budget is a ceiling, never a floor

    func testAReturnedCostNeverExceedsItsBudget() {
        let cases: [(typed: String, candidate: String, language: KeyboardLanguage, budget: Int)] = [
            ("דוגמטןת", "דוגמאות", .hebrew, 130),
            ("תדוה", "תודה", .hebrew, 100),
            ("teh", "the", .english, 100),
            ("seperate", "separate", .english, 130),
            ("acommodate", "accommodate", .english, 130),
            ("דוגמות", "דוגמאות", .hebrew, 130)
        ]
        for entry in cases {
            guard
                let cost = TypoChannel.cost(
                    typed: Array(entry.typed), candidate: Array(entry.candidate),
                    language: entry.language, budget: entry.budget)
            else {
                XCTFail("\(entry.typed) → \(entry.candidate) was expected to fit budget \(entry.budget)")
                continue
            }
            XCTAssertLessThanOrEqual(
                cost, entry.budget, "\(entry.typed) → \(entry.candidate) reported a cost above its budget")
        }
    }
}

/// `TypoLexicon`'s own behaviour: the frequency-ranked list `TypoChannel`
/// scores against.
final class TypoLexiconTests: XCTestCase {

    func testCorrectionsPutsTheIntendedWordFirst() {
        let results = TypoLexicon.corrections(of: "דוגמטןת", in: .hebrew, limit: 3)
        XCTAssertEqual(
            results.first?.word, "דוגמאות",
            "the whole reason this file exists: \(results.map(\.word))")
        XCTAssertEqual(results.first?.cost, 110)
    }

    func testRankAnswersInsideDepthAndNilPastIt() {
        XCTAssertEqual(TypoLexicon.rank(of: "the", in: .english), 0)
        XCTAssertNotNil(TypoLexicon.rank(of: "accommodate", in: .english))
        XCTAssertTrue(TypoLexicon.isWord("the", in: .english))

        // "truancy" sits at rank 37,999 in the bundled frequency list, well
        // past `depth(for: .english)` (12,000), so `rank` — bounded to the
        // commonest `depth` forms — must not answer it. `isWord` asks a different
        // question over the full 50,000 forms and must still say yes: a word
        // rare enough that rewriting keystrokes into it is not worth
        // proposing is not thereby a typo, and a build that answered both
        // questions off the same bounded list would wrongly treat this as
        // free to correct away.
        XCTAssertNil(TypoLexicon.rank(of: "truancy", in: .english))
        XCTAssertTrue(
            TypoLexicon.isWord("truancy", in: .english),
            "a word past `depth` is still a word; rank and isWord must not agree here")
    }

    func testIsWordReadsTheWholeListNotOnlyTheCorrectionDepth() {
        // `cat`, `car`, `bus` and `but` are all ordinary, correctly spelled
        // English inside `depth` too, which is the point: before this file,
        // nothing but the 353-word hand-authored seed list stood between a
        // real word and a rewrite (`.claude/rules/suggestion-bar.md`'s "two
        // dictionaries have to disown a word before it is replaced" rule),
        // and `cat` is not in that list. `isWord` is what a caller checks
        // before ever proposing to replace one of these.
        for word in ["cat", "car", "bus", "but"] {
            XCTAssertTrue(TypoLexicon.isWord(word, in: .english), "\(word) is real English")
        }

        // None of this file's own motivating typos are real words in either
        // language's bundled list — confirmed directly against the shipped
        // resource, not assumed — which is exactly what makes them safe to
        // rewrite in the first place.
        for typo in ["תדוה", "שלמו"] { XCTAssertFalse(TypoLexicon.isWord(typo, in: .hebrew)) }
        for typo in ["teh", "recieve"] { XCTAssertFalse(TypoLexicon.isWord(typo, in: .english)) }
    }

    func testTheCorrectorRefusesAThreeLetterWord() {
        // "teh" is one adjacent transposition from "the" — the commonest
        // word in the English list — so a build missing the length gate
        // would very likely return it. The gate has to make this empty
        // regardless.
        let results = TypoLexicon.corrections(of: "teh", in: .english, limit: 3)
        XCTAssertTrue(
            results.isEmpty,
            "a three-letter word must be refused outright, even one edit from the commonest word in the list: \(results.map(\.word))"
        )
    }
}
