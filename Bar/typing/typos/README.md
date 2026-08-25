# Typos: does the bar offer the word they meant, and does space take it?

One question, asked 128 times.

```bash
Bar/typing/typos/run.sh                 # two runs, a couple of minutes, needs a booted simulator
Bar/typing/typos/run.sh --runs=3
Bar/typing/typos/run.sh --verbose       # every stable row, not just the findings
TYPOS_OUT=/tmp/typos Bar/typing/typos/run.sh
SIMULATOR_DEVICE=<udid> Bar/typing/typos/run.sh
AUTOCORRECT_LEVEL=full Bar/typing/typos/run.sh   # every rule allowed to fire
```

**A bare run measures the shipping keyboard, which is not the same as measuring
the cascade.** `AutocorrectLevel.shippedDefault` is a floor on
`CommitReason.confidence`, so some rules generate a candidate and are not allowed
to commit it; `AUTOCORRECT_LEVEL=full` lifts the floor and asks every rule. Both
are worth reading and they answer different questions. As of 2026-08-18, two runs
per side, zero rows moving on either:

| | committed | held | WRONG | controls |
|---|---|---|---|---|
| `confident` (ships) | 85 | 19 | **3** | 21/21 intact |
| `full` | 90 | 7 | **10** | 21/21 intact |

Seven corrections buy seven fewer wrong words. The three that survive the floor
are `wich` → `with` (NIT-154 calls it defensible and it is), `לכשוב` → `לכתוב`
for `לחשוב`, and `מהעבדה` → `מהעובדה` for `מהעבודה`; the last two are genuinely
ambiguous, one explainable edit in either direction. `Bar/typing/` charges two
more entries for the same floor, which is recorded there.

**Updated 2026-08-25: `confident` reads 88 / 16 / 3, WRONG unchanged.** The
motor-slip split below rescued exactly the three rows it was measured to rescue
— `דוגמטןת` → `דוגמאות`, `thsnkd` → `thanks`, `wprkinh` → `working`, all three
previously held — and moved nothing else: `full` is still 90 / 7 / 10, controls
still 21/21 both sides, two runs per side.

It is the same invigilator as the frozen exam and the sweep next door: `expand.py`
turns `typos.json` into `Bar/typing/corpus.json`'s own shape, `harness/run.sh`
runs the shipping `SuggestionEngine` over it on the iOS Simulator, and `judge.py`
grades the bold slot. Nothing here re-implements the engine, and the corpus it
generates is disposable by design: edit `typos.json` and regenerate.

## What it measures

**A person typed the wrong letters and knows which word they meant.** That is the
whole premise, and it is the one thing neither instrument next door has. The
frozen 90 hold a prefix and a list of answers a human called acceptable, so they
grade plausibility. The sweep types correctly spelled words and asks whether the
keyboard hijacks one on the way to its last letter. Neither asks the question
everybody actually has about autocorrect, which is what it does with a mistake.

Four things are reported per row, and the first three are a partition of the bold
slot — what `KeyboardController.insertSpace` would insert:

| | meaning |
|---|---|
| `committed` | The bold slot holds the intended word. The keyboard fixed it. |
| `held` | The bold slot holds what was typed. The keyboard declined. Conservative, never a defect on its own. |
| `WRONG` | The bold slot holds a **third** word: not typed, not meant. |
| `offered` | The intended word is in a slot, whether or not space takes it. Asked alongside the three, not instead of one. |

`WRONG` is the column that matters most and the reason for the shouting. A
keyboard that declines to help is inert and a user works around it in a second; a
keyboard that replaces `נזעדה` with `נועדה` has put a word in the message that
nobody was reaching for, and that is what makes people switch autocorrect off.
Every one of them is printed individually, always, and none is ever summarised
into a total.

## `reasons.sh` — which rule decided it

```bash
Bar/typing/typos/reasons.sh                          # the 128 pairs
Bar/typing/typos/reasons.sh Bar/typing/corpus.json   # the frozen 90
```

**The judge grades the word; this grades the rule that chose it, and the
difference is not academic.** `SuggestionEngine.commitReason` is a dozen rules
resting on wildly different evidence, and `AutocorrectLevel` cuts them at a
confidence floor — so "is this correction right" and "is *this rule* right" are
separate questions, and only the second one can price a rule. It prints a row per
entry (`id, typed, intended, winner, reason, confidence`) and joins them into a
per-rule table.

The prices in `AutocorrectConfidence.swift` came from this, and it earned its
place immediately: reasoning about the shape of each rule had put the frequency
corrector above 60 *over* the floor and the four-letter fallback *under* it, and
the measurement is the other way round. Reading at 2026-08-18:

| rule | price | right | WRONG |
|---|---|---|---|
| `contraction` | 98 | 7 | 0 |
| `hebrewFinalForm` | 96 | 5 | 0 |
| `frequency` (≤60 or a transposition) | 92 | 31 | 1 |
| `transposition` | 92 | 9 | 0 |
| `singleEdit` | 87 | 28 | 2 |
| `unknownWord` (channel can price it) | 87 | 5 | 0 |
| `frequency` (>60) | 72 | 5 | 6 |
| `unknownWord` (it cannot) | 68 | 0 | 1 |

Everything above the floor of 86 is 93% right or better and everything below it
45% or worse, which is what makes 86 a line rather than a guess. **Re-run this
before moving any of those constants**, and note that it calls `commitReason`
directly, so it reports what every rule claims regardless of the level in force.

**The `frequency (>60)` row split again on 2026-08-25, once `TypoChannel.cost`
started returning an edit count alongside its cost.** `reasons.sh`'s output
grew two columns, `channelCost` and `editCount` — extra columns, the six this
table has always sourced from are unchanged — and grouping the `frequency (>60)`
rows by `(cost, count)` found `(110, 2)`, the two-adjacent-slip shape
`דוגמטןת` → `דוגמאות` was reported for, at 3 right and 0 wrong, with every
measured wrong row in the band landing at some other `(cost, count)`:

| rule | price | right | WRONG |
|---|---|---|---|
| `frequency` (cost 110, two edits) | 87 | 3 | 0 |
| `frequency` (>60, everything else) | 72 | 2 | 6 |

`Bar/typing/typos/probes-motor2/` is 25 rows built to widen exactly this: 8
more `(110, 2)` rows, all right, none wrong — 11 of 11 across the two corpora —
plus a negative control (`bedire` → `before`, both slips genuinely adjacent-key
but summing to 95, not 110) that stays held at 72 as designed. That probe is
disposable and not re-run automatically; its own README has the rest.

`offered` is the split between two different bugs with two different fixes: **the
ranker put it second** and **no source ever generated it**. The judge prints both
lists in full — `offered but not committed` and `never offered` — because a class
scoring 0 committed means opposite things in the two cases, and the baseline
below has one class of each.

**`must-not-correct` rows are the control, and they are why the headline cannot
be gamed.** 21 of the 128 are correctly spelled real words where `typed` and
`intended` are the same string. A build that simply corrects everything scores
badly on those instead of perfectly on the rest. They are counted apart from the
corrections, verdicts `intact` or `WRONG`, and there is no third state.

## What it does not measure

- **What the user sees.** `main.swift` records the engine's array, and mid-word
  that array holds `SuggestionEngine.barSlots + 1` candidates while the bar draws
  three: `SuggestionBar.centeredSlots` puts the default in the middle, the next
  two either side, and drops the rest. A word recorded at slot 3 was generated and
  ranked and would still not have been on screen. The judge prints the slot index
  with every offered-not-committed row rather than modelling `centeredSlots` in
  Python, because a second spelling of it would drift from the one that draws the
  keyboard.
- **Anything in `KeyboardController` or `SuggestionBar`.** `harness/run.sh`
  compiles `SuggestionEngine*.swift` and the models, no controller and no view. So
  the undo after a swap, the personal-dictionary path through `storedPersonalDictionary`,
  the edge-mark restoration and the drawn bar are all invisible here. A correction
  this instrument calls `committed` is one the space bar would insert; what the
  field ends up holding around it is `CandidateCommitTests`'s question.
- **The async tier.** Local tier only, exactly like the sweep. `Bar/typing/async/`
  is the other exam.
- **Frequency.** Every pair is worth one row. The corpus says nothing about how
  often each mistake happens, so `61 committed` is 61 rows and not 57% of anybody's
  typing.
- **Whether a correction is *welcome*.** `held` is not a failure and this file
  will not call it one. Two dictionaries have to disown a word before this engine
  replaces it, on purpose, and the whole `held` column is that trade being paid
  for. What the numbers are for is seeing the size of the bill.

## How to add a pair

```json
{ "typed": "בסגר", "intended": "בסדר", "language": "he", "class": "adjacent-1",
  "context": "", "note": "why a person plausibly types this" }
```

`context` is text already committed before the word and defaults to empty, which
is the cleanest control because no sentence signal is in play; fill it only where
the mistake needs a sentence to make sense (`קניתי כרוב`, `that's a good id`).
`note` is required and is not decoration: a reader has to be able to tell a pair
somebody found from a pair somebody invented, and the rule while writing this file
was that a mistake you are not sure Israelis make stays out.

**`expand.py` validates before it expands, and a mislabelled row fails the run
before a simulator is touched.** Every class with a mechanical shape is checked:
`adjacent-1` really is one substitution between two keys that touch on the rows
this keyboard draws, `transpose` really is a swap (compared with final forms
folded, because swapping the last two letters of `שלום` also un-finals the mem),
`final-form` really is the last letter in the wrong shape, `omit` and `double` are
told apart by whether the missing letter sits beside its own twin. The classes
with no shape say so in the code rather than pretending to a check they cannot
make. A taxonomy nobody checks is a set of labels somebody typed once, and the
report then says the keyboard is bad at fat fingers when it was never asked about
one.

Ids are numbered per language and per class (`he-adj1-05`, `en-apos-03`), so
adding a pair renumbers only its own class and the next run stays a readable diff.

The adjacency the validator uses is `KeyProximity`'s raw-index rule: same row at
one column apart, neighbouring row within one column, diagonal included. That
rule was being replaced by a geometry one while this corpus was written — rows of
8, 10 and 9 keys are each centred inside the same reference width, so equal
indexes in two rows are not above each other — and **every pair here is adjacent
under both**, which was checked rather than assumed: all but two substitutions
stay inside one row, where the two rules are identical, and the two that cross a
row clear the new threshold by a distance (ר/ד at 0.34 of a key width, ו/י at
0.84, against a floor of 1). The looser rule is kept on purpose: this file is
asking about fingers, not about the engine's opinion of them.

## The taxonomy

107 misspelling pairs and 21 controls. Hebrew-weighted, because this is a
Hebrew-first keyboard: 72 Hebrew pairs against 35 English.

| class | n | one real example | why it happens |
|---|---|---|---|
| `adjacent-1` | 13 he / 7 en | `בסגר` → `בסדר`, `tje` → `the` | One key over. ד/ג and h/j are neighbours, and both target words are among the most typed in their language. |
| `adjacent-2` | 5 he / 3 en | `דוגמטןת` → `דוגמאות`, `yjis` → `this` | The whole hand one key over: both slips go the same direction. The Hebrew one is the report that started this work. |
| `transpose` | 8 he / 5 en | `תדוה` → `תודה`, `recieve` → `receive` | The two keys pressed closest together in time arrive out of order. Hebrew swaps the last two letters constantly. |
| `final-form` | 8 he | `שלומ` → `שלום` | The ordinary and final shapes are different keys, and a word finished in a hurry finishes on the wrong one. |
| `final-form-wrong` | 4 he | `דרךים` → `דרכים` | You know the word as `דרך`, you add the plural, and the kaf keeps the shape you know it in. A knowledge slip, not a finger slip. |
| `mater-drop` | 6 he | `בנתיים` → `בינתיים` | Hebrew is written both with and without its silent י, ו and א, so the full spelling is the one that gets lost. The commonest Hebrew misspelling there is. |
| `mater-add` | 3 he | `פרוייקט` → `פרויקט` | The same rule over-applied, almost always a second yod. |
| `homophone` | 8 he | `מסכורת` → `משכורת` | א/ה/ע, ח/כ, ט/ת, כ/ק and ס/ש are one sound each in modern Israeli Hebrew, so a word spelled from its sound can be spelled several ways. A spelling error, not a typing error. |
| `omit` | 5 he / 4 en | `בבקה` → `בבקשה`, `probaly` → `probably` | A key that did not register, or a letter nobody pronounces. |
| `double` | 4 he / 4 en | `תוודה` → `תודה`, `acommodate` → `accommodate` | Key bounce in Hebrew; the English doubling rule in English, in both directions. |
| `clitic` | 8 he | `מהעבדה` → `מהעבודה` | A typo behind one of Hebrew's glued prefixes ה ב ל מ ו ש כ, so the corrector is tested **through** the morphology layer rather than beside it. |
| `phonetic` | 5 en | `definately` → `definitely` | An unstressed vowel is a schwa, so the spelling has to be remembered rather than heard. |
| `apostrophe` | 7 en | `dont` → `don't` | The apostrophe is on the numbers plane, so on a phone leaving it out is two saved taps rather than laziness. |
| `must-not-correct` | 12 he / 9 en | `קליפ`, `כרוב`, `id`, `Nitai` | Correctly spelled real words. Committing anything else is the failure. |

The controls are chosen to be the words a corrector is most likely to eat:
Hebrew's shortest and commonest (`כן`, `לא`, `אני`), the loanwords Hebrew writes
with an ordinary final letter on purpose (`אפ` for app, `קליפ` for clip, both
recorded in this repo as having been destroyed by an over-eager final-form rule),
real words one edit from a much commoner word (`כרוב` cabbage against `קרוב`,
`מכר` acquaintance against `מחר`, `עובדה` fact as a transposition of `עבודה`,
`bus`/`but`, `cat`/`car`, `form`/`from`), the two English words this repo
deliberately kept out of the contraction table (`id`, `were`, each with the
context that makes the ordinary reading the right one), and four entries from
`SharedStore.shippedPersonalDictionary` (`Nitai`, `Handi`, `KeyboardKit`, `סאפא`,
`בלי-פרופ` typed with the ASCII hyphen its owner can actually reach).

### What was deliberately left out

- **`ב`/`ו` homophones.** Real in speech, and every written example anybody could
  defend turned out to be a different phenomenon (`טלוויזיה` written with one vav
  is the doubling rule, and it is filed under `mater-drop` where it belongs). The
  class is thin rather than padded, so it is absent.
- **Spellings where both forms are in real use.** `תכנית`/`תוכנית`,
  `דוגמא`/`דוגמה`, `אשה`/`אישה`, `עכשו`/`עכשיו`. These look like the richest seam
  in Hebrew and are not usable here: "the word they meant" is not defined when
  both spellings are things people write on purpose, and grading a keyboard for
  preferring one would be grading it against this file's author.
- **`ill` → `I'll`.** `ill` is in the contraction table on purpose and correcting
  it is a documented coin flip (`apos-05`, `apos-06` in the frozen corpus). A row
  here would print red every run without anybody learning anything.
- **Wrong-layout typing.** `,usv` → `תודה` is a whole word keyed in the other
  alphabet, which is `LayoutTransposition`'s job and the frozen corpus's
  `wrong-layout` category, not a misspelling.

## Two runs, and what agreement is worth

`run.sh` runs the corpus twice by default and `judge.py` counts a row only when
every run agrees on both its verdict **and** the exact string it committed.
Anything that moved gets its own heading and is counted nowhere. This is the
sweep's rule for the sweep's reason: `UITextChecker`'s Hebrew completion list is
not stable between runs, or even between two identical questions inside one run.

It works, and the baseline below has one row to show for it: `עכדין` → `עכשיו`
committed `עדין` in one run and `כדין` in the other, both wrong, both different.
Also read `sweep/README.md`'s note on why a clean two-run agreement is weaker
evidence than it sounds: two runs of one corpus make the same calls in the same
order, so they reproduce each other, which proves the sequence is repeatable and
not that Apple's answer is stable.

## Baseline, 2026-08-18

Two runs, iPhone 17 Pro, iOS 26.2 Simulator. Both runs agreed on 127 of 128 rows.

**Measured against a working tree that was not clean, and here is exactly what
was in it.** `SuggestionEngine*.swift`, the seed model, the morphology and the
personal model were all at `4e68cc5b` — untouched. `KeyProximity.swift`, which
the harness also compiles, carried the uncommitted geometry rework described
above. That rule adds 50 to a neighbour *offer* and never changes what space
commits, so the commit columns here are a reading of the shipped engine and the
slot **order** on some Hebrew rows may not be. Nothing else the harness compiles
had been touched.

```
HEADLINE  typos 2 run(s) | stable 127/128 | corrections 106: 61 committed (57%),
          36 held, 9 WRONG | offered 88 | controls 21: 21 intact, 0 WRONG
```

| | n | committed | held | WRONG | offered |
|---|---|---|---|---|---|
| he `adjacent-1` | 13 | 0 | 12 | 1 | 12 |
| he `adjacent-2` | 4 | 0 | 1 | 3 | 0 |
| he `clitic` | 8 | 6 | 2 | 0 | 6 |
| he `double` | 4 | 3 | 1 | 0 | 3 |
| he `final-form` | 8 | 7 | 1 | 0 | 7 |
| he `final-form-wrong` | 4 | 4 | 0 | 0 | 4 |
| he `homophone` | 8 | 1 | 6 | 1 | 8 |
| he `mater-add` | 3 | 1 | 1 | 1 | 2 |
| he `mater-drop` | 6 | 1 | 5 | 0 | 1 |
| he `omit` | 5 | 3 | 2 | 0 | 5 |
| he `transpose` | 8 | 4 | 4 | 0 | 8 |
| he `must-not-correct` | 12 | — | 12 intact | 0 | — |
| en `adjacent-1` | 7 | 7 | 0 | 0 | 7 |
| en `adjacent-2` | 3 | 0 | 1 | 2 | 0 |
| en `apostrophe` | 7 | 7 | 0 | 0 | 7 |
| en `double` | 4 | 4 | 0 | 0 | 4 |
| en `omit` | 4 | 3 | 0 | 1 | 4 |
| en `phonetic` | 5 | 5 | 0 | 0 | 5 |
| en `transpose` | 5 | 5 | 0 | 0 | 5 |
| en `must-not-correct` | 9 | — | 9 intact | 0 | — |

**The controls are clean.** 21 of 21 intact in both runs, including every
loanword, every personal-dictionary entry and both English words kept out of the
contraction table. **No slot in the whole run held a non-word.** Those two
together are what makes the rest of this table readable as a conservatism problem
rather than a quality one.

**English is close to solved and Hebrew is not.** 31 of 35 English corrections
commit, including all 7 apostrophes, all 5 phonetic spellings, all 5
transpositions and all 7 one-key slips. 30 of 71 Hebrew ones do.

**The single biggest number in this file is `he adjacent-1`: 12 of 13 offered, 0
committed.** The word the person meant is sitting in the bar, usually in slot 1,
and the space bar will not take it — `בסגר` holds with `בסדר` beside it, and so do
`עכדיו`, `בבקדה`, `זליחה`, `טלפום`, `פכישה`, `מסכדה`, `כתובץ`, `משםחה`, `שטלה`,
`תוגה`. `he homophone` is the same shape and the same answer, 8 offered and 1
committed. This is not a defect: it is `.claude/rules/suggestion-bar.md`'s
same-length-substitution rule, which is Hebrew-only and exists because `מכונ` on
the way to `מכונית` is one substitution from `נכון`. What this instrument adds is
the size of it — 21 of the 72 Hebrew pairs here — and the fact that the
right word is generated and ranked first in nearly every one of them, so nothing
about generation or ranking has to move to change the answer.

**And the rule fires on the seed list, so the commoner the intended word, the
less likely the fix is committed.** `sameLengthSubstitution` requires
`neighbourMatch`, which asks `neighbourWords`, which is the seed list plus the
learned store — so a fix that is a common word is refused and a fix that is not is
allowed through to the four-letter gate. That is exactly the pattern in the table:
`הפטעה` → `הפתעה` commits, and `הפתעה` is the one target here that is not in
`LanguageModel.json`; `מהמשרג` → `מהמשרד` and `בבוקד` → `בבוקר` commit through
their clitic, where the neighbour search does not reach. Seed membership was
checked for every target in the class; the candidate's own `source` was not read
out of the engine, so treat this as the shape of the evidence rather than a
mechanism somebody proved. A probe that calls `completions(for:)` and
`shouldAutocorrect` directly is what would settle it.

**`mater-drop` fails somewhere else entirely, and the two must not be confused.**
1 of 6 committed, and only 1 of 6 **offered**: `דוגמאות`, `אמיתי`, `מכונית`,
`שיעור` and `טלוויזיה` are not in the bar at all. No ranking change reaches those,
because nothing generated them — Apple's checker answers `דוגמות` with
`דוגמותיך`, `דוגמותייך`, `דוגמותינו`, three inflections of the misspelling. The
one that works, `בנתיים` → `בינתיים`, is the one Apple's guesses happen to hold.
This is the commonest Hebrew misspelling there is and the engine is blind to it.

**`adjacent-2` is where the over-corrections live.** 0 of 7 committed across both
languages, 0 offered, and 5 of the 9 WRONG rows. Two edits is past every source
here, so the bar fills with words reached from the typo rather than from the
target, and the space bar takes one:

| typed | meant | commits |
|---|---|---|
| `דוגמטןת` | `דוגמאות` | `דוגמטית` |
| `נזעדה` | `מסעדה` | `נועדה` |
| `מעומית` | `מכונית` | `מעמית` |
| `yjis` | `this` | `egos` |
| `thsnkd` | `thanks` | `thanked` |

The flagship pair is in that list, which is the honest answer to the report that
started this work: today the keyboard does not fix `דוגמטןת`, and it does not
leave it alone either.

The other four WRONG rows are each their own thing and none of them is a
two-edit case: `מצטעד` → `מצעד` (a real word one deletion away, with `מצטער`
sitting in slot 2), `מסכורת` → `מסורת` (same shape, `משכורת` in slot 2), `מסויים`
→ `מסיים` (with `מסוים` in slot 3, which the bar would not have drawn anyway), and
`wich` → `with` while `which` sits in slot 2. All four are a ranking answer rather
than a generation one: the intended word was there and something else was bolder.

Cost, for the record: median 2.2-3.2 ms per entry over 128 entries, worst entry
25-37 ms, first Hebrew call 63-71 ms. Same instrument and same caveats as the
frozen 90's latency line.
