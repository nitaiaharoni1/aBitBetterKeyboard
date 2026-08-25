# Motor-slip probe, authored 2026-08-25

**Probe, not exam.** `Bar/typing/typos/typos.json` is the frozen corpus this repo
grades pricing decisions against; this directory is not that. It exists to widen
the evidence behind one specific split — `CommitReason.frequency`'s
`(cost: 110, count: 2)` price, added because three rows in the real corpus
(`דוגמטןת` → `דוגמאות`, `thsnkd` → `thanks`, `wprkinh` → `working`) were 3 right,
0 wrong at that exact shape and every measured wrong row landed elsewhere. Three
rows is real evidence but a small sample, and this corpus is 25 more, none of
which fed the decision. Its job is **pricing width**, not a headline: nobody
should read `Bar/drift/` and see this file's numbers, because it was never meant
to be re-run unattended the way the frozen exams are.

```bash
Bar/typing/typos/probes-motor2/run.sh                 # two runs, needs a booted simulator
Bar/typing/typos/probes-motor2/run.sh --verbose
PROBE_OUT=/tmp/probe Bar/typing/typos/probes-motor2/run.sh
```

It reuses `expand.py` and `judge.py` unchanged, pointed at `pairs.json` via
`TYPOS_PAIRS`, the same seam `Bar/typing/typos/run.sh` already uses for
`typos.json`. Two classes here exist only in this file: `mater-drop-double` and
`homophone-final`, added to `expand.py`'s own `SLUGS` and `check()` — extending
shared, validated infrastructure rather than forking it, and confirmed not to
change one byte of what `expand.py` generates from `typos.json` (`typos/README.md`'s
own baseline table is unmoved).

## The pairs

25 rows: 11 `adjacent-2` (6 Hebrew, 5 English, every typed string 6+ letters —
`TypoChannel.budget` only allows a 110-cost repair at that length, so a shorter
pair could never even reach the shape being measured), 5 `mater-drop-double`
(two matres lectionis dropped from one word), 5 `homophone-final` (a homophone
substitution stacked with a final-form one), 4 `must-not-correct` controls. Every
row's `note` names its two slips, the same rule `typos.json`'s own README states
for itself.

## What it measured, 2026-08-25

iPhone 17 Pro, iOS 26.2 Simulator. Two runs, stable 25/25, and `reasons.sh` run
twice against the generated corpus, byte-identical both times.

```
HEADLINE  typos 2 run(s) | stable 25/25 | corrections 21: 11 committed (52%),
          7 held, 3 WRONG | offered 12 | controls 4: 4 intact, 0 WRONG
```

| | n | committed | held | WRONG | offered |
|---|---|---|---|---|---|
| he `adjacent-2` | 6 | 5 | 1 | 0 | 5 |
| he `mater-drop-double` | 5 | 0 | 2 | 3 | 0 |
| he `homophone-final` | 5 | 3 | 2 | 0 | 3 |
| he `must-not-correct` | 2 | — | 2 intact | 0 | — |
| en `adjacent-2` | 5 | 3 | 2 | 0 | 4 |
| en `must-not-correct` | 2 | — | 2 intact | 0 | — |

**The `(cost: 110, count: 2)` signature reads 8 right, 0 wrong on this corpus** —
every `adjacent-2` row that reached that exact shape did, in both languages:

```
   cost  count  right  WRONG
     55      1      0      3
     70      1      0      1
     95      2      1      1
    110      2      8      0
```

Combined with the 3 corpus rows the price was set from, that is **11 right, 0
wrong at `(110, 2)` across two independent corpora**, which is the widening this
probe exists to do. One `adjacent-2` row (`חשבונחץ` → `חשבונית`) generated no
candidate at all — `חשבונית` sits outside `TypoLexicon`'s depth window or is
otherwise unreached — and is held rather than wrong; not evidence either way.

**`bedire` → `before` is the sharpest negative control the probe produced, and
it lands exactly where the split says it should.** Both slips are genuine
adjacent-key substitutions (`f`/`d`, `o`/`i`), the same shape as every row in the
table above, but the cheapest path the DP actually finds costs 95, not 110 — the
identical `40 + 55` shape the real corpus's own WRONG row (`בברדה` → `הורדה`, 95)
already carries. It is held, at 72, exactly as `בברדה` is, and the 87-tier does
not reach for it. The split is a price on an exact number, not on "roughly two
adjacent slips," and this is the row that tests whether that precision matters:
it does, since **95 is not owed the same trust as 110** — two rows this probe did
not design to fail (`bedire`, and `finmer` → `dinner` below) confirm the residual
band's low price rather than undermine it.

**Two `adjacent-2` rows found a cheaper real word first, which is a fact about
the dictionary, not about the split.** `finmer` (meant `dinner`) is one
adjacent-key insertion from the common word `finer` at cost 70, so the corrector
never reaches for `dinner` at all — `finer` is genuinely cheaper and the ranking
is doing its job. This lands in the residual (72) band, not the 87-tier, and
widens its already-poor evidence (2 right / 6 wrong in the real corpus) rather
than contradicting anything the split claims.

**`mater-drop-double` did not test what it was built to, and that is worth
recording rather than quietly reworking.** All five rows were designed to reach
`(cost: 110, count: 2)` through two mater-lectionis drops. Three of the five
instead found a *cheaper*, single-insertion path to a different word already in
`TypoLexicon`'s frequency list (`פשריות` → `אפשריות`, 55; `הזדמנית` →
`הזדמנות`, 55; `התנהגית` → `התנהגות`, 55) — landing in the pre-existing,
already-shipped `cost ≤ 60` tier (92) rather than the new one, and wrong there
(0 right, 3 wrong). **This is not a finding about the split this file exists to
measure** — that tier's price, `TypoLexicon`'s depth, and its budget are all out
of scope here and untouched — but it is a real, if narrow, gap the frequency
list itself has on long abstract-noun plurals, worth a second look on its own
ticket rather than folded into this one. The fourth (`התחיבת` → `התחנות`, not
`התחייבות`) lands in the residual 72 band at cost 95, another `40 + 55`
coincidence. The fifth (`משמעית` → `משמעויות`) is held with no rule firing at
all.

**`homophone-final` mostly committed through a different rule than the one it
was built to probe.** Three of five (`משמכ` → `מסמך`, `חסבונ` → `חשבון`,
`פטרונ` → `פתרון`) commit via `singleEdit`, not `.frequency` — short enough,
and close enough to a seed or checker neighbour, that the earlier neighbour
rule already closes the case before the frequency guard is ever asked. The
other two (`קספימ`, `זחרונ`) generate no candidate at all. None of the five
touches the `(110, 2)` price this probe exists to widen; they were included for
the taxonomy's own sake; and the finding is that the theoretical `40 + 60`
composite this class was written to probe never actually reaches the frequency
rule at the lengths tested.

## What this does not do

- **Not registered with `Bar/drift`.** A probe corpus is disposable by
  construction — edit `pairs.json` and regenerate — and this repo's drift
  tooling is for corpora meant to be re-read unattended over time.
- **Not a regression guard.** Nothing here fails a build. Re-run it by hand
  before moving `frequencyConfidence`'s `(110, 2)` price again, the same way
  `Bar/typing/typos/reasons.sh` is re-run before moving any other constant in
  `AutocorrectConfidence.swift`.
