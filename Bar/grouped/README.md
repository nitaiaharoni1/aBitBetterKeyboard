# Grouped keys: can a keyboard with a few big buttons be decoded?

A keyboard where one key carries several *neighbouring* letters — `q w` over
`a s` as one key — and a decoder works out which word was meant. This measures
whether that is possible before any of it is built. The design it serves is
`.claude/docs/grouped-keys-design.md`.

**A key is a block, not a run of one row.** The two letter rows that stand clear
of shift and delete are banded into one row of double-height keys, and a key is a
column slice of that band. Everything below was re-measured when that landed; the
row-at-a-time figures it replaced are in the git history, and the deltas are
called out where they matter.

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
random halves; the widest half-to-half standard deviation is 2.0%, at Hebrew L3.
Two conditions differing by less than about two points are not distinguishable
here.

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

| k | dial | keys | commit | offered | ranker | coll | vs row-at-a-time |
|---|---|---|---|---|---|---|---|
| 1 | control | 26 | 98.1% | 98.1% | 100.0% | 1.0 | — |
| 2 | | 14 | 96.5% | 98.1% | 98.3% | 2.9 | +0.0 |
| 3 | **L1** | 8 | 92.3% | 97.1% | 94.1% | 12.2 | **+1.8** |
| 4 | **L2** | 7 | 91.3% | 97.0% | 93.0% | 13.8 | **+4.4** |
| 5 | **L3** | 5 | 82.7% | 93.8% | 84.3% | 44.4 | +1.5 |
| 7 | | 4 | 74.1% | 89.9% | 75.5% | 76.6 | — |

Keys: `[qw/as] [er/df] [ty/gh] [ui/jk] [o/l] [p]` over `[zxcv] [bnm]` at L1.

OOV is 1.9% throughout, so it is never the binding constraint.

## Hebrew

Adjacent grouping, and the same rows with the seven clitics forced apart:

| k | dial | keys | adjacent | separated | gain | separated offered | clitic pairs split |
|---|---|---|---|---|---|---|---|
| 1 | control | 27 | 97.0% | 97.0% | — | 97.0% | n/a |
| 2 | | 14 | 84.7% | **91.7%** | +7.0 | 96.9% | all (1 of 1) |
| 3 | **L1** | 9 | 75.6% | **82.4%** | +6.8 | 94.0% | all (1 of 1) |
| 4 | **L2** | 7 | 71.2% | 71.2% | +0.0 | 88.7% | none (1 left) |
| 5 | **L3** | 6 | 65.0% | 67.9% | +2.9 | 85.5% | none (1 left) |
| 7 | | 4 | 51.2% | 51.2% | +0.0 | 69.1% | none |

Keys: `[קר/שד] [אט/גכ] [ו/ע] [ןם/יח] [פל/ך] [ף]` over `[זסב] [הנ] [מצתץ]` at L1.

OOV is 3.0%. `run.py` prints `INFEASIBLE` on any row where the constraint could
not be fully satisfied, which is k≥4 — but that flag is binary and the outcome is
not, so read the last column. Banding moved where the constraint binds: the band's
own columns hold no two clitics, so what is left to satisfy is the single row
`זסבהנמצתץ`, which holds three of them and gets two keys from k=4.

## The findings

**0. Banding helped English and hurt Hebrew, and both are outside the spread.**
Merging the top two rows into double-height keys — which is what makes a key a
target rather than a wide sliver — moved every stop:

| | English | Hebrew (best) |
|---|---|---|
| k=2, 14 keys | 96.5% → 96.5% | 93.5% → **91.7%** |
| **L1**, 8/9 keys | 90.5% → **92.3%** | 86.7% → **82.4%** |
| **L2**, 7 keys | 86.9% → **91.3%** | 79.1% → **71.2%** |
| **L3**, 5/6 keys | 81.1% → 82.7% | 71.3% → 67.9% |

English gains because the letter under a common one is usually a rare one — `q`
over `a`, `p` beside `l` — so a band key is a common letter plus ballast, where a
row run is four consecutive common letters. Hebrew has no such luck: `קראטוןםפ`
and `שדגכעיחלךף` are both dense with its commonest letters, so banding pairs
common with common and the mean collision at L2 goes from 12.5 words to 20.3.

**None of that is the reason to do it, and this harness cannot see the reason.**
It measures the decoder assuming the thumb always hits the intended key. A key
twice the area is invisible to it by construction. So read this table as the
price, with the benefit unmeasured — and read the Hebrew column as the number
that would decide it, if the price ever has to be paid back.

**1. Separating the clitics is the biggest Hebrew win available, and it is free.**
Hebrew glues ה ב ל מ ו ש כ to the front of words, and plain grouping puts pairs of
them on one key — at L1 that is `[הנמ]`, making "the X" and "from X" one
keystroke. Moving the group boundaries to keep them apart, at the **same key
count**, is worth **+7.0 points at 14 keys** (84.7% → 91.7%) and +6.8 at 9 keys.
Both are well clear of the ±2 spread, and both are larger than they were before
banding, because banding gives the constraint an easier problem to solve.

**2. It runs out at seven keys, and that is arithmetic rather than tuning.** The
row `זסבהנמצתץ` holds three clitics (ב ה מ) and gets only two keys at k≥4, so one
key must take two of them; `split_row_avoiding` returns `None` and the row falls
back to a plain split. What it does **not** do is fall off a cliff:

| | keys | colliding pairs left | worth |
|---|---|---|---|
| k=2 | 14 | 0 | +7.0 |
| **L1** k=3 | 9 | 0 | +6.8 |
| **L2** k=4 | 7 | 1 | nothing |
| **L3** k=5 | 6 | 1 | +2.9 |

So **L1 is the last stop where the constraint is fully satisfiable**, as it was
before banding — but for a different reason. It used to run out because the band's
own rows carried clitics that adjacency forced together; now the band is clean
(ו sits over ע, and ש, כ and ל are each in a column of their own) and the only
place left to fail is the row that keeps delete.

**A column of a band is atomic, and that was the risk worth checking.** Both its
letters are on one key and no partition can pull them apart, so a column holding
two clitics would be a collision nothing could fix. Hebrew's band has none. The
*other* pairing of its rows does — band `שדגכעיחלךף` over `זסבהנמצתץ` and column 3
is כ over ה — which is one of the two reasons the top two rows are the ones that
band. The other is that it measured better: 82.4% against 76.9% at L1.

**3. Hebrew caps lower than English, and the gap widens as you compress.**

| keys | English | Hebrew (best) | gap |
|---|---|---|---|
| 14 | 96.5% | 91.7% | 4.8 |
| 7–9 | 92.3% (8) | 82.4% (**9**) | 9.9 |
| 5–6 | 82.7% (5) | 67.9% (**6**) | 14.8 |
| 4 | 74.1% | 51.2% | 22.9 |

The two middle rows are generous to Hebrew and it still loses: it is being given
an *extra key* in both, because the rows divide differently, and it is 9.9 and
14.8 points behind anyway. Banding widened this gap at every row.

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
| adjacent | 75.6% | 74.3% | −1.3 |
| clitic-separated | 82.4% | 81.1% | −1.3 |

At 14 keys it is −0.5 for adjacent and **+0.3** for clitic-separated — expansion
helping slightly, if anything. Nothing here clears the 2-point spread in either
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
at 76.1%, against 73.4% for the midpoint of adjacent grouping's 9-key and 7-key
results — a difference inside the ±2 spread. There is no free lunch here, so there
is no reason to take letters off a keyboard people can read.

## How big the word list has to be

`harness/lexsize.py` truncates the lexicon to its top N and re-measures. Two
effects pull against each other — a longer list covers more words but puts more
of them inside every group — and the answer is that **they never cross. Coverage
wins at every size tested**, so commit climbs monotonically to 200,000 words in
both languages.

What does happen is diminishing returns, and they arrive early. **These are
no-context numbers**, so the full-list rows read 91.7% and 81.4% where the
headline tables say 92.3% and 82.4%:

| words | ~KB (uncompressed) | English L1 | Hebrew L1 separated |
|---|---|---|---|
| 10,000 | 215 / 254 | 87.3% | 72.2% |
| 20,000 | 430 / 508 | 89.5% | 76.3% |
| 50,000 | 1,074 / 1,270 | 90.9% | 79.7% |
| 100,000 | 2,148 / 2,539 | 91.5% | 80.9% |
| 200,000 | 4,297 / 5,078 | 91.7% | 81.4% |

**50,000 English words and 100,000 Hebrew ones land within the spread of the full
list** — 0.8 and 0.5 points against the measured 2.02. Hebrew at 50,000 is 1.7
short, which is now *inside* the spread rather than just outside it, so the
separation between the two languages is weaker than it looked before banding.
The claim that survives is the direction, not the cut-offs: **English needs
meaningfully fewer words than Hebrew**, because Hebrew spreads the same meaning
over more distinct forms.

Two caveats. Those KB figures are raw JSON, which is the wrong format to ship —
a packed trie is several times smaller, and measuring one is Phase B's job, not a
guess to make here. And **the OOV rates are almost certainly optimistic**: they
are measured against 747 English and 805 distinct Hebrew words, where real typing
carries names, slang, abbreviations and typos that no frequency list has.

## The bigram pass, and why its gain is a floor

`decode.Bigrams` counts which word follows which **over the test text with the
sentence under test held out**, because counting a sentence toward its own
context is not a measurement. The gain rises with ambiguity — +0.1 points at 14
keys, +0.6 and +1.0 at L1, and at four keys **+3.7 in English and +5.0 in
Hebrew** — which is the expected shape: context is worth most when the keystrokes
are worth least, and Hebrew's keystrokes are worth least of all.

Only the large end clears the ±2 spread. And a few thousand sentences is nowhere
near enough to cover a language, so this understates what real context is worth.
The shipping engine's `followsContext` term is worth 400 points, more than a whole
source tier.

## What this says about the dial

The chosen stops, at their best Hebrew variant:

| | keys (en/he) | English | Hebrew |
|---|---|---|---|
| **L1** k=3 | 8 / 9 | 92.3% | 82.4% |
| **L2** k=4 | 7 / 7 | 91.3% | 71.2% |
| **L3** k=5 | 5 / 6 | 82.7% | 67.9% |

Four things fall out, all of them decisions rather than conclusions:

- **k=2 is nearly free in English and is not currently a stop.** 14 keys, 96.5%,
  with keys twice the area. It costs 1.6 points against an ungrouped keyboard.
  Hebrew pays 5.3 for the same stop, which is the shape of the whole table.
- **Hebrew L2 commits the wrong word nearly three times in ten**, and L3 more than
  three. Both are still *offered* 88.7% and 85.5% of the time, so with a glance at
  the bar they are usable, but as a space-bar default they are not.
- **L1 and L2 are one key apart in English** (8 and 7), which was flagged in the
  design and is confirmed here. Banding made that worse rather than better: they
  are now **1.0 point apart**, against 3.6 before, so the two stops differ by
  neither look nor accuracy. That is an argument for replacing one of them with
  k=2.
- **Hebrew's usable range now stops at L1.** Before banding, L2 was 79.1% and
  arguably shippable; at 71.2% it is not.

## Files

| | |
|---|---|
| `make-rows.py` | Extracts the letter rows from `LetterLayouts.swift`, and **fails loudly** if the Swift moved rather than emitting stale rows. |
| `make-lexicon.py` | `wordfreq` → `data/lexicon-{en,he}.json`, 200,000 words each. Needs the venv. |
| `make-testtext.py` | The repo's other four `Bar/` corpora → `data/testtext.json`. |
| `harness/grouping.py` | Banding the top two rows into columns, row splitting, the clitic-avoiding partition, word → key code. |
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
letter landing on the wrong end, the shorter row of a band aligned right instead
of left — where every such detail is a different keyboard that still compiles.

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
