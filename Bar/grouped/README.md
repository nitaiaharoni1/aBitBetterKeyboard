# Grouped keys: can a keyboard with a few big buttons be decoded?

A keyboard where one key carries several adjacent letters — `[qwer][tyu][iop]`
instead of ten keys — and a decoder works out which word was meant. This measures
whether that is possible before any of it is built. The design it serves is
`.claude/docs/grouped-keys-design.md`.

```bash
Bar/grouped/harness/run.sh                # self-tests, then sweeps; ~70s → results.json
python3 Bar/grouped/harness/validity.py   # how much those numbers can carry
python3 Bar/grouped/harness/lexsize.py    # accuracy against word-list size
```

**No simulator, no Swift, no network.** That is the whole design: `Bar/typing`
must build for the iOS Simulator because `UITextChecker` is UIKit, and takes
minutes per run. A dial cannot be swept at that price.

Regenerating the inputs:

```bash
python3 Bar/grouped/make-rows.py                          # from LetterLayouts.swift
Bar/grouped/.venv/bin/python Bar/grouped/make-lexicon.py   # from wordfreq
python3 Bar/grouped/make-testtext.py                      # from the other four Bar corpora
```

## Read this before quoting any number

**This measures the decoder, assuming the thumb always hits the intended group.**
Real thumbs miss. So every rate here is an **upper bound on decode quality** and
simultaneously a **lower bound on end-to-end benefit**, because it never counts
the mistypes that a key three to five times wider prevents — which is the entire
reason to want grouped keys. Both directions are real, and neither cancels the
other.

**The decoder is deliberately the weak one**: a frequency-ranked word list and a
sparse bigram pass, nothing else. The shipping engine also has `UITextChecker`,
the personal model that outranks everything, the learned word list and the
code-switch list. Read a number here as "at least this good".

**The spread is ±2 points.** `validity.py` splits the test text into twenty
random halves; the widest half-to-half standard deviation is 1.7%. Two conditions
differing by less than about two points are not distinguishable here.

**Two tables below are the no-context condition** — the split-half spread and the
lexicon-size curve, both of which run without the bigram pass so they isolate one
variable at a time. They therefore read about half a point to two points lower
than the headline tables for the same row. Where that matters it is said again in
place.

## What is measured

For each word: map its letters to the keys they press, collect every lexicon word
pressing the same keys, rank them, and record where the true word landed.

| Column | Meaning |
|---|---|
| **commit** | Top-1. What the space bar would insert. Of every word this layout is responsible for, so an out-of-vocabulary word counts as a failure — because it is one. |
| **offered** | Top-3. Did the word reach the suggestion bar at all. Separates "the ranker is wrong" from "the candidate never existed", the split `Bar/typing` already keeps. |
| **ranker** | Top-1 among only the words the lexicon knows. Isolates ranking from coverage. |
| **oov** | Not in the 200,000-word lexicon. Undecodable by any ranking. |
| **coll** | Mean number of lexicon words sharing the code. Ambiguity before ranking. |

`k` is letters per key. **`k=1` is a control, not a dial stop**: with one letter
per key every code is unique, so `ranker` must be exactly 100%. It is, for both
languages. Anything else would be a harness bug rather than a finding.

## English

| k | dial | keys | commit | offered | ranker | coll |
|---|---|---|---|---|---|---|
| 1 | control | 26 | 98.1% | 98.1% | 100.0% | 1.0 |
| 2 | | 14 | 96.5% | 98.1% | 98.3% | 3.1 |
| 3 | **L1** | 8 | 90.5% | 97.8% | 92.2% | 8.9 |
| 4 | **L2** | 7 | 86.9% | 97.3% | 88.6% | 12.9 |
| 5 | **L3** | 5 | 81.1% | 94.4% | 82.7% | 31.2 |
| 7 | | 3 | 59.5% | 79.8% | 60.7% | 230.9 |

OOV is 1.9% throughout, so it is never the binding constraint.

## Hebrew

Adjacent grouping, and the same rows with the seven clitics forced apart:

| k | dial | keys | adjacent | separated | gain | separated offered | clitic pairs split |
|---|---|---|---|---|---|---|---|
| 1 | control | 27 | 97.0% | 97.0% | — | 97.0% | n/a |
| 2 | | 14 | 88.6% | **93.5%** | +4.9 | 97.0% | all (1 of 1) |
| 3 | **L1** | 9 | 84.4% | **86.7%** | +2.3 | 95.9% | all (2 of 2) |
| 4 | **L2** | 7 | 77.7% | 79.1% | +1.4 | 93.1% | 1 of 2 |
| 5 | **L3** | 6 | 71.3% | 71.3% | +0.0 | 88.7% | none |
| 7 | | 3 | 42.0% | 42.0% | +0.0 | 58.9% | none |

OOV is 3.0%. `run.py` prints `INFEASIBLE` on any row where the constraint could
not be fully satisfied, which is k≥4 — but that flag is binary and the outcome is
not, so read the last column. At k=4 one of the two colliding pairs is still
separated and the layout is genuinely better than adjacent; from k=5 the flag and
the result agree that nothing was achieved.

## The five findings

**1. Separating the clitics is the biggest Hebrew win available, and it is free.**
Hebrew glues ה ב ל מ ו ש כ to the front of words, and adjacency grouping puts
pairs of them on one key — at L1 that is `[הנמ]`, making "the X" and "from X" one
keystroke. Moving the group boundaries to keep them apart, at the **same key
count**, is worth **+4.9 points at 14 keys** (88.6% → 93.5%) and +2.3 at 9 keys.
The first is well clear of the ±2 spread; the second sits at its edge.

**2. It runs out at seven keys, and that is arithmetic rather than tuning.** The
row `זסבהנמצתץ` holds three clitics (ב ה מ) and gets only two keys at k≥4, so one
key must take two of them; `split_row_avoiding` returns `None` and the row falls
back to a plain split. What it does **not** do is fall off a cliff:

| | keys | colliding pairs split | worth |
|---|---|---|---|
| k=2 | 14 | 1 of 1 | +4.9 |
| **L1** k=3 | 9 | 2 of 2 | +2.3 |
| **L2** k=4 | 7 | 1 of 2 | +1.4, inside the spread |
| **L3** k=5 and below | 6, 5, 3 | 0 | nothing at all |

So **L1 is the last stop where the constraint is fully satisfiable.** L2 keeps a
fraction of the benefit that this sample is too small to confirm, and from L3 the
idea is dead rather than merely weakened.

**3. Hebrew caps lower than English, and the gap widens as you compress.**

| keys | English | Hebrew (best) | gap |
|---|---|---|---|
| 14 | 96.5% | 93.5% | 3.0 |
| 7–9 | 90.5% (8) | 86.7% (**9**) | 3.8 |
| 5–6 | 81.1% (5) | 71.3% (**6**) | 9.8 |
| 3 | 59.5% | 42.0% | 17.5 |

The two middle rows are generous to Hebrew and it still loses: it is being given
an *extra key* in both, because the rows divide differently, and it is 3.8 and
9.8 points behind anyway.

The design predicted this and gave the wrong reason. It is not only that
unvocalized writing has already spent the redundancy. It is morphology, and it is
visible in the sample: Hebrew's type/token ratio is **0.55 against English's
0.41**, and its mean Zipf is 5.29 against 5.78. Hebrew spreads the same meaning
over more distinct word forms, each individually rarer, so more of them compete
inside a group. A larger corpus cannot fix that; it is a property of the language.

**4. Expanding the lexicon with glued clitic forms is a wash — every comparison
lands inside the spread.** Generating `לעבודה`, `בעבודה`, `מהעבודה` from one
entry for `עבודה` cuts OOV by a third, from 3.0% to 2.1%, and gives most of it
back in new collisions:

| L1, 9 keys | without expansion | with | delta |
|---|---|---|---|
| adjacent | 84.4% | 83.3% | −1.0 |
| clitic-separated | 86.7% | 85.7% | −1.0 |

At 14 keys it is −0.1 for adjacent and **+0.3** for clitic-separated — expansion
helping slightly, if anything. Nothing here clears the 1.7-point spread in either
direction, so the honest reading is **no measurable effect**, not a benefit and
not a cost. It is not worth the bundled bytes on this evidence, and it is not
ruled out either.

> **This finding was wrong in the first run and the error was worth 2.1 points.**
> `with_clitic_forms` let a synthesised frequency overwrite a word the corpus had
> actually measured, which corrupted **28.9% of the Hebrew lexicon** — `ללא`
> inflated 3.1× off `לא`, `בעל` 3.5× off `על`. It read as a clear 3.1-point loss
> and is a 1.0-point one. `selftest.py` now asserts no measured frequency moves.

None of this is an argument against `HebrewMorphology`, which exists to *complete*
a word in progress — a different question from decoding a finished one.

**5. Taking the five final forms off the keyboard buys nothing.** Hebrew's 27
glyphs become 22 (position determines the form, so a decoder can restore it), and
the result lands on the same accuracy-per-key curve as ordinary grouping: 8 keys
at 80.5%, against 81.1% for the midpoint of adjacent grouping's 9-key and 7-key
results — a difference well inside the ±2 spread. There is no free lunch here, so
there is no reason to take letters off a keyboard people can read.

## How big the word list has to be

`harness/lexsize.py` truncates the lexicon to its top N and re-measures. Two
effects pull against each other — a longer list covers more words but puts more
of them inside every group — and the answer is that **they never cross. Coverage
wins at every size tested**, so commit climbs monotonically to 200,000 words in
both languages.

What does happen is diminishing returns, and they arrive early. **These are
no-context numbers**, so the full-list rows read 89.9% and 86.0% where the
headline tables say 90.5% and 86.7%:

| words | ~KB (uncompressed) | English L1 | Hebrew L1 separated |
|---|---|---|---|
| 10,000 | 215 / 254 | 85.2% | 75.5% |
| 20,000 | 430 / 508 | 87.6% | 80.0% |
| 50,000 | 1,074 / 1,270 | 89.2% | 84.1% |
| 100,000 | 2,148 / 2,539 | 89.7% | 85.5% |
| 200,000 | 4,297 / 5,078 | 89.9% | 86.0% |

**50,000 English words and 100,000 Hebrew ones land within the spread of the full
list** — 0.7 and 0.5 points against the measured 1.72. Hebrew at 50,000 is 1.82
short, just over that line, so the two languages genuinely want different sizes;
that is the type/token finding again, more distinct forms to cover.

This is the one place the rounded "±2" shorthand would give the wrong answer, so
the comparison uses the measured figure. It is close enough to the line that a
different corpus could move it, and the honest version of the claim is
"English needs meaningfully fewer words than Hebrew", not the exact cut-offs.

Two caveats. Those KB figures are raw JSON, which is the wrong format to ship —
a packed trie is several times smaller, and measuring one is Phase B's job, not a
guess to make here. And **the OOV rates are almost certainly optimistic**: they
are measured against 747 English and 805 distinct Hebrew words, where real typing
carries names, slang, abbreviations and typos that no frequency list has.

## The bigram pass, and why its gain is a floor

`decode.Bigrams` counts which word follows which **over the test text with the
sentence under test held out**, because counting a sentence toward its own
context is not a measurement. The gain rises with ambiguity — +0.6 points at
gentle grouping, and at three keys **+5.2 in English and +5.8 in Hebrew** — which
is the expected shape: context is worth most when the keystrokes are worth least,
and Hebrew's keystrokes are worth least of all.

Only the large end clears the ±2 spread. And a few thousand sentences is nowhere
near enough to cover a language, so this understates what real context is worth.
The shipping engine's `followsContext` term is worth 400 points, more than a whole
source tier.

## What this says about the dial

The chosen stops, at their best Hebrew variant:

| | keys (en/he) | English | Hebrew |
|---|---|---|---|
| **L1** k=3 | 8 / 9 | 90.5% | 86.7% |
| **L2** k=4 | 7 / 7 | 86.9% | 79.1% |
| **L3** k=5 | 5 / 6 | 81.1% | 71.3% |

Three things fall out, all of them decisions rather than conclusions:

- **k=2 is nearly free and is not currently a stop.** 14 keys, 96.5% English and
  93.5% Hebrew, with keys twice as wide. It costs 1.6 points against an ungrouped
  English keyboard.
- **L3 Hebrew commits the wrong word roughly three times in ten.** It is still
  *offered* 88.7% of the time, so with a glance at the bar it is usable, but as a
  space-bar default it is not.
- **L1 and L2 are one key apart in English** (8 and 7), which was flagged in the
  design and is confirmed here. They are 3.6 points apart, which is real, but they
  will not look like two different keyboards.

## Files

| | |
|---|---|
| `make-rows.py` | Extracts the letter rows from `LetterLayouts.swift`, and **fails loudly** if the Swift moved rather than emitting stale rows. |
| `make-lexicon.py` | `wordfreq` → `data/lexicon-{en,he}.json`, 200,000 words each. Needs the venv. |
| `make-testtext.py` | The repo's other four `Bar/` corpora → `data/testtext.json`. |
| `harness/grouping.py` | Row splitting, the clitic-avoiding partition, word → key code. |
| `harness/decode.py` | Lexicon, decoder, leave-one-out bigrams. |
| `harness/run.py` | The sweep. Writes `results.json`. |
| `harness/validity.py` | Sample size, Zipf distribution, split-half spread. Writes `validity.json`. |
| `harness/lexsize.py` | Accuracy against word-list size. Writes `lexsize.json`. |
| `harness/selftest.py` | Assertions, run before every sweep. |
| `harness/run.sh` | The entry point: self-test, then sweep. |
| `harness/swift-check.sh` | Compiles the shipping Swift and requires it to agree with this Python. |

### The port is checked against this harness

The keyboard implements the design in Swift (`GroupedKeys.swift`,
`GroupedDecoder.swift`), and **a port is exactly the thing that can be faithful
in design and wrong in a detail** — the rounding going the other way, the extra
letter landing on the wrong end — where every such detail is a different keyboard
that still compiles.

```bash
Bar/grouped/harness/swift-check.sh    # seconds; needs Xcode, no simulator
```

It compiles the real `GroupedKeys.swift` and `GroupedDecoder.swift` against a
small shim, feeds both sides the rows out of `data/rows.json`, and compares
**structurally** rather than as text, because the two JSON writers disagree about
key order and whitespace and a `diff` would report formatting as a defect.
Currently: **8 grouping conditions and 272 decode answers agree exactly.**

Two things it does differently from `run.sh`, both on purpose. It builds for the
**host**, not the simulator — `Bar/typing` needs the simulator because
`UITextChecker` is UIKit, and there is no platform behaviour in a partition
function. And it compares *prefix* decoding: `run.py` matches a finished word's
code exactly, while the keyboard is asked mid-word and has to offer `that` two
keys into `the`. `python_side.py` implements the prefix query itself so the
measured harness is untouched by the check.

### The test text is authored, not observed

All 388 entries come from corpora written for this repo to exercise a keyboard —
`Bar/typing`, `Bar/ai-text`, `Bar/dictation`, `Bar/screen-context` — and
`data/testtext.json` stamps the provenance of every one. **Nobody's real typing is
in here.** 1,805 English and 1,475 Hebrew words, 747 and 805 distinct.

The sample is not obviously flattering — mean Zipf 5.78 and 5.29 against 7 for
`the`, and more than half the distinct words appear exactly once — but it is
small, it is one register (Israeli chat and short work messages), and 55 entries
are deliberately code-switched, which is over-represented against ordinary text.
`Bar/screen-context` supplies 210 of the 388 entries, so the chat register is the
dominant voice here.

### The one bias that was looked for and is not there

`Bar/typing`'s entries are frozen *mid-typing*, so `context + prefix` ends in a
non-word (`…in ten minu`) that no lexicon decoder can ever return.
`make-testtext.py` rebuilds the finished word from the corpus's own `intended` /
`mustNotCorrect` / `acceptable` fields instead, and records which rule it used in
each entry's `source`.

That is a decoder being tested partly on **words a human already judged a good
keyboard should produce**, which is exactly the shape of a flattering measurement.
Measured, it is not one, in two ways:

- Those reconstructed answers are **rarer than the words they are compared
  against** — mean Zipf 5.06 against 5.79 in English, 4.86 against 5.30 in
  Hebrew — so they are harder than the words around them, not easier. Those two
  baselines are the corpus **with these tokens removed**, which is why they sit a
  hundredth above the whole-corpus 5.78 and 5.29 quoted above rather than equal
  to them.
- They are also far more often **outside the lexicon entirely**, which means they
  are scored as outright failures: **28.6% OOV against 7.9%** for the rest of the
  Hebrew corpus, and 8.6% against 4.6% in English. A reconstruction that flattered
  the decoder could not look like this.
- They are 1.9% of tokens in both languages. Dropping the **entire** typing corpus
  moves commit by between −0.5 and +0.1 points, well inside the ±2 spread.

> The first version of this check compared Zipf only across words the lexicon
> *knew*, which quietly dropped the OOV ones — the very tokens that make the case.
> The measurement was right and too weak, which is its own kind of wrong.

### Code-switched words are excluded, not decoded

A word mixing scripts — `ל-TestFlight`, or a bare `sprint` inside a Hebrew
sentence — cannot be typed on either layout, so `Layout.code` returns `None` and
it is counted as **unmappable** and dropped from the denominator. That is the
right model of what a person does (they reach for the globe key), but it means
**this harness says nothing about grouped keys and code-switching**, which is a
case the product cares about a great deal.

It is 2.8% of English tokens and **7.3% of Hebrew ones**. Whatever grouped keys
do to the cost of switching layouts mid-sentence is unmeasured here and worth its
own experiment before shipping.

### The lexicon cannot be shipped as it stands

`wordfreq`'s Hebrew data is built from Wikipedia, OpenSubtitles, SUBTLEX, Google
Books and OSCAR, which is exactly right for measuring and unresolved for
bundling. Its *code* is Apache 2.0; its *data* is not uniformly licensed.
Whatever Phase B ships needs its license settled **before** it is bundled, and
the source stamped into the resource the way `LanguageModel.json` stamps
`source`.

`data/lexicon-*.json` is **gitignored** for that reason and because it is 11.7 MB
that `make-lexicon.py` reproduces exactly from a frozen `wordfreq` release. A
fresh checkout is therefore *expected* to be missing it, so all three entry points
call `run.require_data` and exit with the command that fixes it rather than a
traceback. Everything that is actually a *finding* — `results.json`,
`validity.json`, `lexsize.json`, `data/testtext.json`, `data/rows.json` — is
committed.

### `tapsPerWord` is a made-up weighting

`results.json` carries it: 1 tap when the word commits, 2 when it is offered in
the bar, 4 when it is neither. Those weights were chosen, not measured. It is a
convenience for ordering conditions and is not evidence of anything.
