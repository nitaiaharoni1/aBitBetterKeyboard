import Foundation

/// Why the space bar is allowed to replace what was typed, and how sure of it
/// the engine is.
///
/// **The confidence is a property of the rule that fired, not a score computed
/// beside it, and that is the whole design.** `SuggestionEngine.commitReason`
/// is a cascade of about a dozen questions, each written for a defect somebody
/// reported and each carrying the measurement that justified it. A separate
/// scorer over the candidate — source tier, frequency rank, edit distance —
/// would be a second opinion that knows none of that, and it would have to be
/// tuned against the same corpora the cascade is already tuned against. Naming
/// the rule and pricing it is the smaller change and the honest one: every
/// number below answers "how often is *this rule* right", which is a question
/// `Bar/typing/typos/` can actually be asked.
///
/// **Every number below is measured, and two of them were wrong when they were
/// reasoned.** `Bar/typing/typos/reasons.sh` runs this cascade over the 128 pairs
/// next door and reports which rule fired on each, so "how often is this rule
/// right" is a question with an answer rather than an ordering of intuitions. The
/// first pass at this file put `frequency` above 60 over the floor and the
/// four-letter fallback under it; the probe found that band is the worst tier in
/// the file (1 right, 3 wrong) and the fallback among the better ones (5 right, 1
/// wrong). Re-run it before moving any constant here, and read
/// `AutocorrectLevel.confidenceFloor` for where the line currently falls.
enum CommitReason: Equatable, Sendable {

    /// An apostrophe left out of an English contraction: `dont` → `don't`.
    ///
    /// A closed hand-authored table, so a word is in it or it is not and there
    /// is no guess anywhere in the rule. The only cost ever recorded against it
    /// is the two words deliberately kept *out* — `id` and `were` — and both
    /// are controls in `Bar/typing/typos/` rather than misses.
    case contraction

    /// A finished Hebrew word ending in the ordinary form of ‎כ מ נ פ צ‎:
    /// `שלומ` → `שלום`.
    ///
    /// Orthographic law rather than a guess, and gated on the keystrokes
    /// continuing to nothing so it cannot fire on `אפ` — how Hebrew writes
    /// "app" — on its way to `אפשר`.
    case hebrewFinalForm

    /// Two adjacent letters swapped: `teh` → `the`, `תדוה` → `תודה`.
    ///
    /// Both dictionaries disown what was typed, and the two keys pressed
    /// closest together in time arrived out of order. The most mechanically
    /// identifiable slip there is: every letter is correct and only the order
    /// is not.
    case transposition

    /// The keys were right and the plane was wrong: `akuo` → `שלום`. A whole
    /// word of gibberish in the alphabet it was keyed in.
    ///
    /// **Below the two orthography rules because it has already been wrong in
    /// production.** It fired on deliberate code-switching — `scr` committed
    /// `דבר` three letters into `screenshot` — and needed a gate adding for
    /// the sentence this product exists for. A rule caught overreaching does
    /// not get to price itself as law.
    case wrongLayout

    /// A common word one keystroke away from something no dictionary has heard
    /// of, where the edit is not a transposition: `probaly` → `probably`,
    /// `definately` → `definitely`.
    ///
    /// **Only just above the floor, and `wich` → `with` is why.** Both are one
    /// edit from what was typed, `with` is far commoner, and the engine has no
    /// way to know the user meant `which`. NIT-154 calls that commit
    /// defensible and it is. It is also the clearest example of this tier
    /// being a good bet rather than a certainty.
    case singleEdit

    /// `TypoLexicon` and `TypoChannel` agreeing that the keystrokes are absent
    /// from 50,000 forms of real text and the winner is not, an explainable
    /// distance away.
    ///
    /// **The cost, the transposition flag and the edit count are all measured
    /// splits, not reasoned ones.** Over the 107 corrections in
    /// `Bar/typing/typos/` this rule fires 43 times: at a cost of 60 or under
    /// it is right 30 times out of 31, and above 60 — before the count split
    /// below — it was right 5 times out of 11. A near certainty and a coin
    /// flip priced as one rule is what the middle setting exists to separate.
    ///
    /// **The transposition flag rescues the one entry the cost bound gets
    /// wrong.** `שלמו` → `שלום` costs 80 — a transposition at 60 plus a final
    /// form at 20, two explainable edits — and it is `typo-11`, one of the two
    /// entries NIT-153 shipped the frequency corrector to close. None of the
    /// rows below is a transposition and `שלמו` is, so the flag keeps this
    /// measured win out of the coin-flip band entirely.
    ///
    /// **`count` is `TypoChannel.EditCost.count`, carried alongside `cost`
    /// rather than folded into it, and it is what splits the coin flip in
    /// two.** Cost alone cannot tell `דוגמטןת` → `דוגמאות` and `thsnkd` →
    /// `thanks` (both cost 110, two adjacent-key slips apiece) from `נזעדה`
    /// → `נועדה` (cost 100, one plain substitution onto a commoner word) —
    /// they sit a single cost quantum apart. Count can: the two-slip rows are
    /// `count: 2`, the wild guesses are `count: 1`. Measured over
    /// `Bar/typing/typos/reasons.sh`'s extended output, two runs,
    /// byte-identical: `(cost: 110, count: 2)` is 3 right, 0 wrong —
    /// `דוגמטןת` → `דוגמאות`, `thsnkd` → `thanks`, `wprkinh` → `working` —
    /// and every measured wrong row in the coin-flip band lands outside it:
    /// `מצטעד` → `מצעד` (70, count 1), `בברדה` → `הורדה` (95 = 40 + 55, count
    /// 2 but not 110), `נזעדה` → `נועדה` and `מעומית` → `מקומית` (100, count
    /// 1 each). The residual band — everything above 60, not a transposition,
    /// not `(110, 2)` — is now 2 right, 6 wrong: `משפה` → `משפחה` and `בבקה`
    /// → `בבקשה` (both cost 100) are the wild guesses that still land right;
    /// the six wrong rows are `מצטעד` → `מצעד` and `עכדין` → `עדין` (70),
    /// `בברדה` → `הורדה` (95), and `נזעדה` → `נועדה`, `מעומית` → `מקומית`,
    /// `אמתי` → `אמרתי` (100). See
    /// `frequencyConfidence(cost:transposition:count:)`.
    case frequency(cost: Int, transposition: Bool, count: Int)

    /// The previous words are known to be followed by the winner, and what was
    /// keyed is absent from the common core: `בעוד רבה` → `בעוד רבע`.
    ///
    /// **Deliberately under the floor.** This is the one rule in the engine
    /// where the sentence overrules a spelling verdict, it rests on a 353-word
    /// bigram table, and it replaces a string that is usually a real Hebrew
    /// word. Somebody who asked for high-confidence corrections has asked for
    /// exactly this rule to stop taking the space bar. The candidate is still
    /// offered; only the bold slot moves.
    case sentenceFollower

    /// Four letters or more that no dictionary knows, replaced by whatever
    /// ranked first. The fallback at the bottom of the cascade.
    ///
    /// **The weakest claim in the file, and the reason the setting has a middle
    /// position at all.** Every rule above names something it recognises. This
    /// one names only an absence — nobody has heard of what you typed — and
    /// then trusts the ranker. It is why `qwt` became `qwtxyz` the moment that
    /// entry was in the personal dictionary, the defect that put the length
    /// gate at four instead of three.
    ///
    /// **`explainable` is the distance test the gate itself does not have, asked
    /// with the channel the rest of this file already uses.** Measured over
    /// `Bar/typing/typos/`, the gate commits six words: five are one or two
    /// slips `TypoChannel` can price — `צריכ` → `צריך` and `חשבונ` → `חשבון`
    /// are final forms the seed-continuation gate on `hebrewFinalForm`
    /// deliberately declined, `מצטערר` → `מצטער` is a doubled key, `מהמשרג` →
    /// `מהמשרד` is one letter, `להתראו` → `להתראות` is one more — and the sixth
    /// is `yjis` → `egos`, three substitutions in a four-letter word, which
    /// shares one letter with what was typed and nothing else. Five right and
    /// none wrong against none right and one wrong. The gate has no idea those
    /// are different; `TypoChannel.budget` has known since NIT-153.
    ///
    /// The frozen 90 charges one entry for the same line: `restaraunt` →
    /// `restaurant` is a rotation rather than a swap, costs more than a
    /// ten-letter budget of 130 allows, and is held at `.confident`. That is the
    /// rule doing what it says rather than a defect in it.
    ///
    /// It changes nothing at `.full`, where both prices commit. It is only the
    /// line the middle position cuts on.
    case unknownWord(explainable: Bool)

    /// How sure the engine is, out of 100. Compared only with
    /// `AutocorrectLevel.confidenceFloor`.
    var confidence: Int {
        switch self {
        case .contraction: return 98
        case .hebrewFinalForm: return 96
        case .transposition: return 92
        case .wrongLayout: return 88
        case .singleEdit: return 87
        case .frequency(let cost, let transposition, let count):
            return Self.frequencyConfidence(cost: cost, transposition: transposition, count: count)
        case .sentenceFollower: return 78
        // A slip the channel can price is the same claim `singleEdit` makes, and
        // it is measured at five right and none wrong. An unpriceable one is the
        // fallback doing what only it does.
        case .unknownWord(let explainable): return explainable ? 87 : 68
        }
    }

    /// One line on `TypoChannel`'s own price list, and it is where the corpus
    /// puts it rather than where the budget does.
    ///
    /// **60 or under is exactly one slip the channel can explain**, because
    /// nothing costs less than `TypoChannel.minimumIndelCost` (55) and so no two
    /// edits can sum this low: a final form at 20, a homophone letter at 40, an
    /// adjacent key or a dropped mater at 55, a transposition at 60. Measured at
    /// 30 right and 1 wrong.
    ///
    /// **Above 60 the rule used to be one coin flip**, measured at 6 right and
    /// 6 wrong before the transposition exemption and 5 and 6 after it, and
    /// `cost` alone could not improve on that: `נזעדה` → `נועדה` and `משפה` →
    /// `משפחה` both cost exactly 100, one a replacement nobody wanted and one
    /// the right repair, with nothing in `cost` to tell them apart.
    ///
    /// **A transposition is exempt at any cost**, because it is the one slip
    /// above 60 the corpus vouches for and because it is already the strongest
    /// evidence in this enum for the same reason `case transposition` is: every
    /// letter is right and only the order is not.
    ///
    /// **`count` splits what was left into a second near-certainty and a
    /// smaller coin flip.** `TypoChannel.EditCost.count` is how many of
    /// `TypoChannel`'s edits the cheapest path actually took, and at
    /// `(cost: 110, count: 2)` — two adjacent-key slips, the shape this
    /// corrector was built for (`דוגמטןת` → `דוגמאות`, NIT-153's report) — it
    /// is 3 right and 0 wrong, measured over `Bar/typing/typos/reasons.sh`'s
    /// extended output, two runs, byte-identical. Every wrong row elsewhere in
    /// the coin-flip band sits outside that exact shape: a wild single
    /// substitution at `count: 1` (`נזעדה` → `נועדה`, `מעומית` → `מקומית`, both
    /// 100; `מצטעד` → `מצעד`, `עכדין` → `עדין`, both 70), or two edits that do
    /// not sum to 110 (`בברדה` → `הורדה`, 95 = a homophone substitution at 40
    /// plus an adjacent-key one at 55). **87, matching `singleEdit` and an
    /// explainable `unknownWord`** rather than the 92 a transposition or a
    /// cost-60 slip earns: those two tiers are priced on a similar-sized,
    /// similarly clean sample (`singleEdit` 28/2, `unknownWord(explainable:
    /// true)` 5/0), and 3 of 3 here is that same class of evidence rather
    /// than the larger, near-unanimous samples behind 92 — three rows is the
    /// smallest sample priced anywhere in this file, and the probe corpus in
    /// `Bar/typing/typos/probes-motor2/` is what widens it. The residual band
    /// — everything else above 60 — is now 2 right, 6 wrong, worse than
    /// before the split pulled its 3 best rows out, and stays at 72.
    static func frequencyConfidence(cost: Int, transposition: Bool, count: Int) -> Int {
        if transposition { return 92 }
        if cost <= 60 { return 92 }
        if cost == 110, count == 2 { return 87 }
        return 72
    }
}

/// How much evidence the space bar needs before it replaces what was typed.
///
/// **Three positions rather than a switch, because "autocorrect is wrong" and
/// "autocorrect is off" are different complaints with different remedies.**
/// `Bar/typing/typos/` grades 107 real misspellings and reports three columns:
/// the correction was right, the keyboard declined, or the keyboard inserted a
/// **third** word that was neither typed nor meant. That last column is the one
/// that makes people switch autocorrect off entirely, and switching it off also
/// gives up the 90 corrections that were right. The middle position is for
/// somebody who wants the repairs and not the guesses.
///
/// **A floor rather than a set of allowed rules**, so a rule added later is
/// priced once, in `CommitReason.confidence`, and lands on the right side of
/// this on its own.
public enum AutocorrectLevel: Int, CaseIterable, Sendable {

    /// Space types a space. Nothing is ever replaced, and the bar pins its bold
    /// slot to the literal keystrokes so it cannot advertise a swap that will
    /// not happen.
    ///
    /// **Not spelled `none`.** In any position where the expression's type is
    /// `AutocorrectLevel?`, Swift resolves `.none` to nil without a word of
    /// complaint, and this repo has been bitten by that four times. See
    /// `AGENTS.md`.
    case off = 0

    /// Only corrections the engine can explain: an orthography rule, a
    /// transposition, a single explainable slip, a wrong layout. The rules that
    /// guess — the sentence override, the frequency corrector at a cost it
    /// cannot account for, and the four-letter fallback — still put their
    /// candidate in the bar, and space stops taking it.
    case confident = 1

    /// Every rule in the cascade may commit. What shipped before this setting
    /// existed, and what every number in `README.md` was measured at.
    case full = 2

    /// The lowest `CommitReason.confidence` this level lets the space bar act
    /// on.
    ///
    /// **`.off` answers 101, which nothing can reach**, so all three positions
    /// come out of one comparison instead of a special case wrapped around two.
    /// The cut at 86 is the product decision: it keeps the contraction table
    /// (98), the Hebrew final form (96), transpositions (92), an explainable
    /// single slip through the frequency corrector (92 and 88), the wrong-layout
    /// rule (88) and the one-edit neighbour (87); it drops the sentence override
    /// (78), the four-letter fallback (68) and a frequency correction whose cost
    /// the channel cannot account for (72).
    public var confidenceFloor: Int {
        switch self {
        case .off: return 101
        case .confident: return 86
        case .full: return 0
        }
    }

    /// What a fresh install gets, and the one place it is written down.
    ///
    /// **`.confident` rather than `.full`, and the corpora are the argument.**
    /// Over the 107 corrections in `Bar/typing/typos/`, `.full` commits 90 and
    /// puts a word nobody typed or meant into the message 10 times; `.confident`
    /// commits 85 and does it 3 times. Both hold 21 of 21 controls intact, and
    /// both are stable over two runs with zero rows moving. The frozen 90 charges
    /// two more: 75 of 76 becomes 73, losing `restaraunt` → `restaurant` and
    /// `בעוד רבה` → `בעוד רבע`.
    ///
    /// So seven corrections buy seven fewer wrong words, and the wrong ones are
    /// what make people switch autocorrect off altogether — see
    /// `Bar/typing/typos/README.md` on why `WRONG` is the column that shouts.
    /// Every tier above `confidenceFloor` measures 93% right or better and every
    /// tier below it 45% or worse, so the cut sits in a real gap rather than in
    /// the middle of a slope.
    ///
    /// `SuggestionEngine.suggestions` deliberately does **not** default to this.
    /// Its default is `.full`, which means "ask every rule" — the cascade's own
    /// behaviour, which is what a unit test of the cascade wants and what every
    /// number recorded before this setting existed was read at. What ships is a
    /// product decision and lives here.
    public static let shippedDefault = AutocorrectLevel.confident

    /// What the settings row calls it.
    public var title: String {
        switch self {
        case .off: return "Off"
        case .confident: return "High confidence"
        case .full: return "Full"
        }
    }
}
