# Emoji search: can the ranker be changed at all?

`EmojiSearch` has three known-wrong answers that have sat open for months, and
the reason they sat open is not that nobody knew what was wrong. The mechanism
was written down exactly. **Nothing could score a fix.** Two repairs were tried
against an ad-hoc 60-query run, both made the product worse, and the only record
of that was prose.

This is the instrument. 99 frozen queries in Hebrew and English, a scorer that
reports **where** the right answer landed rather than whether it appeared, and a
check that compiles the shipping Swift and refuses to let the two disagree.

```bash
Bar/emoji/harness/run.sh              # selftest, then score; ~1s → results.json
Bar/emoji/harness/run.sh /tmp/after.json
python3 Bar/emoji/harness/score.py before.json after.json   # diff two runs
python3 Bar/emoji/harness/variants.py # candidate ranker changes, headline each
Bar/emoji/harness/swift-check.sh      # the port against the shipping engine; needs Xcode
```

**No simulator, no network, Python 3 standard library only.** That is the whole
design, and it is `Bar/grouped/`'s trade rather than `Bar/typing`'s: `Bar/typing`
must build for the iOS Simulator because `UITextChecker` is UIKit and takes
minutes a run, and a ranker cannot be swept at that price. `EmojiSearch` and
`EmojiCatalog` import Foundation and nothing else, so there is no platform
behaviour to preserve and no device to boot.

## Read this before quoting any number

**This scores a port, and `swift-check.sh` is what makes it a score of the
keyboard.** `harness/rank.py` is ~60 lines of Python re-implementing
`EmojiSearch.swift` over the shipping `EmojiCatalog.json`. Every number in
`results.json` is a number about that Python until the check is green. It
compares 147 result lists — all 99 corpus queries plus every single letter of
both alphabets, which are the widest result sets the engine ever produces —
rank by rank, and 15 raw `Match` records on top. Today: **147/147 identical.**

**The port was wrong once and the check is why anybody knows.** The first
version used Python's `len` and `str.startswith`, which are code points, where
Swift's `count` and `hasPrefix` are grapheme clusters. CLDR's Hebrew carries
niqqud in four places — 🐏 is `אַיִל`, 🛷 is `מִזְחֶלֶת`, 👩‍🏫 is `מוֹרָה`, 🩺
has `מַסְכֵּת` among its keywords — and `"אַיִל".hasPrefix("א")` is **false** in
Swift and true in Python, because the first `Character` is alef *with* its
patah. That put 🐏 in the results for `א` on one side and not the other and
shifted every rank below it. `EmojiSearch`'s doc comment used to say CLDR's
Hebrew carries no niqqud to strip; it now names the four strings that carry it.

**Folding the niqqud away was then measured, and it is not worth doing.** Three
of the four are already reachable unpointed, because CLDR carries the bare
spelling as a *keyword* even where it points the *name*: `איל` answers 🐏 first,
`מזחלת` answers 🛷 first, `מורה` answers 👩‍🏫 second. Only 🩺's `מַסְכֵּת` has no
unpointed route. Folding both sides — the query in `normalise` and the
catalogue, which has to be both, since stripping the query alone leaves the
catalogue string pointed and the two still never meet — leaves this corpus
byte-identical at 56/76, 69/76, 0.819 under the ranker of the day. The whole
gain is `מסכת` reaching 🩺; the price is folding 1,870 strings per keystroke
unless `EmojiCatalog` folds them once at load. Not taken.

**The window is five, and the strip shows about nine.** Five is used because it
is stricter and because a thumb goes to the first two or three; a number quoted
against a nine-wide window would be higher and would mean less. `EmojiSearch`'s
doc comment used to carry its own reading against nine cells and 29 queries; it
now quotes this corpus, so there is one set of numbers rather than two.

**One run is one run, but not in the way the other corpora mean it.** There is
no model and no judge here: the ranker is deterministic, so two runs of
identical code are byte-identical, and any delta is a real delta. What *is*
sampled is the corpus — 99 queries out of every word two languages have — so a
one- or two-entry move is not a finding, and the per-entry verdicts matter more
than the total. Read the diff, not the headline.

**The corpus is authored, not observed.** Nobody's real emoji searches are in
it. Every `intended` and `acceptable` value is a human judgement about what a
person typing that word means, written before any of it was run — with the four
exceptions the corpus marks `priorKnowledge` and the one entry it marks
`revised`. See "How the corpus was written" below.

## What is measured

The printed label and the `results.json` key are not always the same word, so
both are given. Nothing here is self-explanatory and none of it should be quoted
without its denominator.

| Printed | In `results.json` | Meaning |
|---|---|---|
| **first** | `first` | Rank 1 is a right answer. The only number a user would recognise: it is the leftmost cell of the results strip, which is where a thumb goes without reading. |
| **strip** | `strip` | A right answer inside the first five. Separates "the ranker is wrong" from "the candidate was never generated" — the split `Bar/typing` keeps between commit and offered. |
| **MRR** | `mrr`, `mrrOver` | Mean reciprocal rank of the judged target: 1.0 if it is first, 0.5 if second, 0 if it never appears. One number for "how far down is it", where `first` only sees rank 1. `mrrOver` is how many entries it averages. |
| **clean** | `clean` | Denominator is **only the entries carrying a `mustNotRank` list**, not all 99. An entry passes when no forbidden emoji is inside the five. See below — this number is small on purpose and reads worse than it is. |
| **empty** | `negative` | Queries that must return nothing: `""`, `"   "`, `zzzzzz`, `קקקקקק`. |
| **open** | `open` | Entries whose `acceptable` list is a sample rather than a whitelist. **Outside every count above.** `firstFromTheSample` and `stripFromTheSample` are how many were answered from the sample, reported as the floor they are. |
| **gaps** | `knownGaps` | Entries expected to fail today for a reason already understood and written into `corpus.json`. **Counted as failures anyway** — they are inside `first` and `strip`, not excused from them. Two: `he-bechi` and `he-yom-huledet`. |

An **open** list cannot fail. That is not leniency, it is arithmetic: if an
entry can only ever pass, leaving it in the denominator lets it raise the
headline and never lower it. Nineteen entries are open and all nineteen are
counted separately.

**`clean` has ten entries in it, not ninety-nine, and that is why it looks like
the weakest column.** `mustNotRank` is deliberately narrow: it names an emoji of
a *different concept* — a carrot for `car`, a moon cake for `moon`, a kiss for
`heart` — and never the less-wanted member of the right concept, which `first`
already judges. Only ten entries have anything that qualifies, so a single
failure is ten points. The four that fail are **three distinct facts**: 💏 is in
the strip for both `heart` and `לב` (one cause, counted twice, because the kiss
carries `heart` and `לב` as keywords) and 🥮 is in it for both `moon` and `cake`
(one cause, counted twice, because the moon cake carries both words). So `6/10`
is two real defects seen from four angles, not four independent ones. Read it as
a tripwire on a short list, never as a rate.

`intended` and `acceptable` never appear on the same entry. Near answers to an
`intended` are written as `alsoFine`, printed and never counted, so `targetRank`
always means the rank of the thing the columns are about. An earlier version
mixed them and produced entries that read as a pass and a fail at once.

## Today's reading

**2026-08-16, working tree over `9ec51c2c`**, catalogue `8a9748c8cbdea345`,
corpus `94b02ff5ead39007`. Numbers move when any of those move; `results.json`
carries all four so a stale reading is tellable from a current one. This reading
is **after** the NIT-112 change below; the one before it was 56/76, 69/76,
0.819, 6/10, and `keyword-covers-everything` in `variants.py` reproduces it.

| | |
|---|---|
| **first** | **58 / 76** |
| **strip** | **70 / 76** |
| **MRR** | **0.837** over 76 entries with a definite target |
| **clean** | **6 / 10** entries carrying a `mustNotRank` list |
| **empty** | **4 / 4** |
| open | 19 entries; 4 answered from the sample at rank 1, 17 inside five |
| known gaps | 2, red on purpose |

99 entries: 58 English, 41 Hebrew.

`heart` is fixed and answers ❤️. The two that remain, with the rank of the right
answer:

| query | answer | should be | rank of the right one |
|---|---|---|---|
| `לב` | 🫀 💏 💗 🤎 🤍 | ❤️ | **9** |
| `car` | 🚕 🚙 🛻 🛞 🚚 | 🚗 | **6** |

**🏠 second for `heart` was not in the record before this corpus existed**, and
it is what the change below removed. CLDR lists `heart` among 🏠's keywords (as
in "the heart of the home"), the keyword rung outscored every name rung, and a
house outranked eight actual hearts. `music` is worse and was also unrecorded:
🥁 🪈 🎸 🎻 🪕, with 🎵 at **rank 10** and `מוזיקה` at **12**, and it did not
move. The same shape runs through a dozen entries — a related *object* wins
because its name is shorter, and nothing in the data says which emoji a concept
is actually spelled with.

### The two entries that are red on purpose

- `he-bechi` — `בכי` finds nothing useful where `בוכה` finds 😭. Same root, a
  different form. `EmojiSearch`'s own doc comment names this pair: matching is
  whole-word and prefix, and fixing it needs a stemmer the package does not
  have.
- `he-yom-huledet` — `יום הולדת` returns nothing at all. A multi-word query can
  only reach rung 0, which needs a CLDR name equal to the whole query.
  `thumbs up` gets there because 👍 is named exactly that; two Hebrew words
  never do, because keywords are split on spaces and 🎂 is `עוגת יום הולדת`.
  Hebrew is the language this keyboard exists for and it loses a whole query
  shape that English keeps.

Both are counted as failures. Neither is excused.

## The `לב` decision

`EmojiModeTests` contradicts itself about `לב` today and one of the two
assertions has to go.

- `testHebrewFindsWhatEnglishFinds` wants ❤️.
- `testRecentsWinACloseCallAndLoseToAName` pins 🫀 with an empty recents list,
  and says so in a comment.

**This corpus encodes ❤️.** `he-lev` and `rec-lev` both name it. Three reasons,
in the order they should be weighed:

**1. The Hebrew annotation is missing a word the English one has.** 🫀's English
name is `anatomical heart` and its Hebrew name is the bare noun `לב`. CLDR
marked the organ explicitly in one locale and not in the other. That is a
shortcoming of the annotation, not a difference in what the two languages mean:
nobody typing `לב` into a chat field wants a cardiology diagram, exactly as
nobody typing `heart` does. Bundling CLDR so Hebrew reaches what English reaches
is the stated reason the search box exists at all.

**2. The second test uses today's defect as its control.** Its `לב` half only
works as a recents probe *because* 🫀 wins with recents empty — which is the bug
under discussion. That is the shape this repo has already been bitten by three
times: an assertion that passes because of the defect it sits next to. And the
test's own purpose survives without it. Its `pizza` / `פיצה` halves already
prove that recents lose to a name, and a genuine close call is easy to build:
🐈 is named `cat`, 🐱 is `cat face`, and the corpus carries **both** directions
(`rec-cat`, `rec-cat-face`) so one of them must be doing real work whichever way
an empty-recents ranker leans. Both pass today.

**3. Nothing is lost.** 🫀 is still reachable — it is rank 1 for `לב` today and
would be rank 2 under any repair that puts ❤️ first, still inside the strip. A
user who wants the organ can see it without typing another letter.

So `testHebrewFindsWhatEnglishFinds` is the one that is right, and the `לב` pair
inside `testRecentsWinACloseCallAndLoseToAName` is what should be replaced — by
the cat pair, which tests the boost without depending on a ranking anybody
disputes.

**Done, and the replacement was checked for the same fault it was fixing.** The
test now asserts `results(for: "cat", recent: ["🐱", "🙏", "👍"]).first == "🐱"`
with `results(for: "cat").first == "🐈"` as the control. 🐈 is named `cat` and
scores `(rung 0, −1.0, 3)`; 🐱 is `cat face` and scores `(rung 1, −0.5, 8)`, so
the two rungs are what the boost has to close. Set `recentBoost` to 0 and the
first assertion answers **🐈** and fails, which is the proof it is not inert —
the `rec-cat` direction, 🐈 in recents, passes at either setting because 🐈 is
rank 1 for `cat` with recents empty anyway. The control is boost-independent on
purpose. `לב` is left to `testHebrewFindsWhatEnglishFinds`, which still fails,
and to `he-lev`, which still reads rank 9: no ordering of the signals in the
data fixes it, for the reason below.

## What the ranker change was

`variants.py` scores candidates in about a second each. Everything except the
one rule under test stays as it ships, so a delta is attributable. `shipping`
means *today's* engine, so the rule that was replaced is kept beside it under
its own name.

| variant | first | strip | MRR | clean | `car` | `heart` | `ירח` | `moon` |
|---|---|---|---|---|---|---|---|---|
| **shipping** (a keyword is worth half a name) | **58/76** | **70/76** | **0.837** | 6/10 | 🚕🚙🛻 | **❤️**🫀🏠 | **🌙**🎑🌑 | **🌙**🎑🌑 |
| keyword-covers-everything (what shipped before) | 56/76 | 69/76 | 0.819 | 6/10 | 🚕🚙🛻 | 🫀🏠💏 | 🌙🎑🌑 | 🌙🎑🌑 |
| keyword scored by its own length | 52/76 | 69/76 | 0.784 | 7/10 | 🚃🚞🚋 | 🥰😘😻 | 🎑🌑🌒 | 🥮🎑🌑 |
| keyword scored by the shortest name in the query's script | 51/76 | 71/76 | 0.786 | 6/10 | 🚕🛞🚋 | 💏🏠❤️ | 🌙🎑🌑 | 🌑🥮🌕 |
| a name word outranks an exact keyword (the plain split) | 60/76 | 69/76 | 0.852 | 8/10 | 🚋🚓🏎️ | ❤️🩷💙 | 🎑🌑🌕 | 🌑🥮🌕 |
| the same, plus giving 🫀 a Hebrew name of its own | 60/76 | 69/76 | 0.852 | 8/10 | 🚋🚓🏎️ | ❤️🩷💙 | 🎑🌑🌕 | 🌑🥮🌕 |
| a keyword is worth a third of a name | 59/76 | 70/76 | 0.845 | 7/10 | 🚋🚕🚙 | ❤️🩷💙 | 🎑🌑🌕 | 🌑🥮🌕 |
| a keyword is worth 0.48 of a name | 59/76 | 70/76 | 0.846 | 7/10 | 🚕🚙🛻 | ❤️🩷💙 | 🌙🎑🌑 | 🌑🌙🎑 |

**The two rejected repairs are confirmed rejected**, now against a frozen corpus
rather than a remembered run: −4 and −5 on `first`, and `heart` answers 🥰 and
💏. Nobody has to try them again.

**The plain rung split was rejected too, and that is the interesting one.**
`score` put "an exact keyword" and "a whole word of a name" on the same rung and
gave the keyword branch `coverage: -1`, which no name word can reach, so an
exact keyword *always* beat a name that merely contained the word. That single
value is what put 🏠 above eight hearts. Separating them into two rungs is worth
**+4 on `first`, +0.033 MRR and +2 on `clean`** and fixes `heart` outright — and
it costs `ירח` rank **1 → 13** and `car` **6 → 12**, because "ירח מלא" and
"police car" carry the word in a name where 🌙 and 🚗 only ever had it as a
keyword. Hebrew is the language this keyboard exists for. A headline that rises
while the priority language falls twelve places is what a corpus is supposed to
catch, not to license.

**What shipped is the same idea with a price on it instead of an absolute.** The
keyword branch's coverage is `EmojiSearch.exactKeywordCoverage`, −0.5: an exact
keyword ranks as a name word filling exactly half of its name. A name word
beats it when the query is more than half the name and loses when it is less.
"red heart" is 5 of 9 and clears it, so `heart` goes rank 10 → 1; "new moon" is
4 of 8 and does not, so `moon` still answers 🌙. **Exactly three entries move
and all three move forwards** — `heart`, `money` and `apple`, each to rank 1 —
for +2 on `first`, +1 on `strip` and +0.018 MRR. Nothing that answered at rank 1
stops answering at rank 1. `clean` does not move: 💏 carries `heart` and `לב` as
keywords, and half a name is not enough to push it past rank 5.

**Half is a statement; 0.48 is a fitted number.** The two rows below the split
are the near misses. A third of a name scores best of anything tried (+4, +0.036
MRR, +2 `clean`) and still moves 21 entries, `ירח` and `moon` from 1 to 4 and
`קשת` from 1 to 2 — and it drops `flower` and `פרח` out of the strip entirely,
which **no column here can see**, because both carry an open `acceptable` list
and an open list cannot fail. 0.48 costs only `moon`, 1 → 2, and buys one more
on `first` and one more on `clean`; the entire difference between it and 0.5 is
whether a name word filling *exactly* half its name wins, and there is no
sentence for 0.48 that is not "the number that let `new moon` through".
Everything in [0.5, 0.555] scores identically, so 0.5 is the middle of a
plateau rather than a peak on a curve.

**`heart` was a ranking bug and is fixed. `לב` is not one, and `car` is not.**
That is the finding worth keeping out of all of this:

- `לב` cannot be fixed by any ordering of the signals in the data. 🫀's Hebrew
  name *is* the query, so it takes rung 0 outright. Even with the data fix
  applied — the one that was tried and reverted — ❤️ still does not win, because
  its Hebrew name `לב אדום` is seven characters against `לב גדל`, `לב חום` and
  `לב לבן` at six, and coverage prefers the shorter. Length is not centrality
  and no rearrangement of it will become centrality.
- `car` is the same. 🚗 is `automobile`; the query reaches it only as a keyword,
  so it sits behind five short-named vehicles that carry `car` as a keyword too,
  and no rung change tested here moved it up. The shipped change leaves it at 6;
  every variant that beats it on the headline moves it to 7 or 12.

So the honest read is unchanged and now measured: **what is missing is a
frequency signal, the gap `SeedLanguageModel` fills for words, and CLDR has
none.** The +2 that shipped is real and does not close those two, and neither
would the +4 that did not. Closing them needs a per-emoji centrality list,
bundled the way
`GroupedLexicon-{en,he}.txt` is bundled with its own `NOTICE`, and picking a
source for it with a licence this repo can carry is its own piece of work. The
corpus is ready to score it the day it exists.

## How the corpus was written

99 entries, 58 English and 41 Hebrew, across nine categories:

| Category | n | What it is for |
|---|---|---|
| `ambiguous` | 45 | Several emoji are all a fine answer |
| `single-concept` | 21 | One obvious answer, close to its name |
| `name-vs-keyword` | 13 | The `car` / `automobile` shape: the query is not the target's name |
| `recents` | 5 | The boost should win a close call and lose to a name |
| `prefix` | 4 | What the box actually sees on every keystroke but the last |
| `multiword` | 4 | Two words, which can only ever reach rung 0 |
| `negative` | 4 | Must return nothing |
| `normalisation` | 2 | Case and padding |
| `morphology` | 1 | A Hebrew form CLDR does not carry |

**The query list and the answers were written before anything was run**, so the
corpus is not a description of what the ranker already does. Three exceptions,
all stamped in the file itself:

- Four entries carry `priorKnowledge`. `heart`, `car`, `לב` and `moon` were
  already named in `.claude/docs/test-suite-state.md` with the engine's current
  answer, so they could not be authored blind. Their judgements match the prose
  that was already in the repo; discount them accordingly.
- One entry carries `revised`. `en-run` was written as `intended: 🏃` and
  widened to accept 🏃‍♀️ and 🏃‍♂️ after the first run answered with the
  gendered variant. That was an authoring mistake — this keyboard has no gender
  picker any more than it has a skin-tone one, so all three are the same answer
  — but it was corrected with the output in front of me and it is the only entry
  in the file that changed after being scored.
- `rec-cat` turned out to be inert: 🐈 is rank 1 for `cat` with recents empty
  too, so the entry passes without exercising the boost. `rec-cat-face` was
  added for that reason and is the half doing the work. Adding the mirror image
  is completing a probe, not fitting one — "whichever of the two is in recents
  should be first" is a claim in both directions. `EmojiModeTests` takes the
  `rec-cat-face` direction for exactly this reason.

`selftest.py` runs before every score and rejects a corpus that cannot do its
job: an entry carrying no judgement at all (which `score.py` would bucket as
`unjudged` and never count again — `Bar/typing/async/validate.py` exists for the
same reason), a duplicate query, an emoji named in a judgement that is not in
the shipping catalogue, or a `mustNotRank` that names something the same entry
calls a good answer.

## The port is checked against the shipping Swift

```bash
Bar/emoji/harness/swift-check.sh    # seconds; needs Xcode, no simulator
```

It compiles the real `EmojiSearch.swift` and `EmojiCatalog.swift` against a
one-accessor shim and the real `Resources/EmojiCatalog.json`, then diffs 147
result lists and 15 `Match` records structurally — not as text, because the two
JSON writers disagree about key order and about how a Double is spelled, and a
`diff` over that reports formatting as a defect.

Three things it does deliberately:

- **It builds for the host.** `Bar/typing/harness/run.sh` must target the
  simulator because `UITextChecker` is UIKit; there is no platform behaviour in
  a string comparison.
- **It refuses to run on an empty catalogue.** If the resource bundle did not
  assemble, both sides would rank nothing and every list would match — a green
  check over a harness that measured neither implementation. `main.swift` reads
  `EmojiCatalog.loadFailure` and exits first.
- **It guards the Foundation-only rule**, the same guard
  `Bar/grouped/harness/swift-check.sh` carries. An `import UIKit` in either file
  is easy, reasonable and fatal here, and without the guard the failure reads as
  a broken toolchain.

It prints the three argued-about queries from both sides every run, agreement or
not. A check whose only output is the word "ok" cannot be told from a check that
ran on nothing.

## Files

| | |
|---|---|
| `corpus.json` | The exam. 99 frozen queries and what a good answer would be. Does not change once a judgement has been made against it. |
| `results.json` | The reading, with its date, its commit and the hashes of the corpus and the catalogue it was taken against. |
| `harness/rank.py` | `EmojiSearch` in Python, faithfully, bug included. |
| `harness/score.py` | Grades a run; diffs two runs. |
| `harness/selftest.py` | What must be true before a score means anything. |
| `harness/variants.py` | Candidate ranker changes. Nothing here ships. |
| `harness/run.sh` | Selftest, then score. |
| `harness/swift-check.sh` | The port against the shipping engine. |

## What this harness cannot see

- **Taste, past a point.** `party` leading with 🪅 before 🎉 is a preference and
  the corpus says so by putting both in one closed list. Nineteen entries are
  open for the same reason. Tuning past what these can distinguish is fitting
  one person's judgement to 1,870 rows.
- **The grid.** Every number here is about the search results strip. Nothing
  about the categories, the seams, the tab row or the recents list is measured;
  `EmojiModeTests` holds those and they pass.
- **Typing into the box.** The shift state, the layout and the caret belong to
  `EmojiSearchTypingTests`. This corpus starts from a finished query string.
- **Whether anybody searches at all.** No usage data exists for this keyboard,
  which is the same hole that makes the centrality signal unavailable.
