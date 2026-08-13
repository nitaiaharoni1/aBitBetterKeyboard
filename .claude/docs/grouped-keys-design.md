# Grouped keys: one big button for several letters

A keyboard mode where each key carries two to six *neighbouring* letters instead
of one, and a local decoder works out which word was meant. The keys get two to
six times the area; the number of taps does not change.

**A key is a block of the keyboard it replaces.** The two letter rows that stand
clear of shift and delete merge into one band of double-height keys, and a key is
a column slice of that band: `q w` over `a s` is one key, drawn on two lines, two
key-heights tall. The third row keeps shift and delete, so it stays one row deep
and groups sideways. The keyboard's total height does not change, because the
band is two rows tall because it *is* two rows.

Status: **Phase A measured; Phase B built.** The harness is `Bar/grouped/` and
its findings are in `Bar/grouped/README.md`. The keyboard is `GroupedKeys.swift`,
`GroupedDecoder.swift`, `GroupedLexiconResource.swift` and
`KeyboardController+Grouped.swift`, with the dial in Settings ▸ Typing.

> **What still stands between this and shipping.** Hebrew L2 commits the wrong
> word about three times in ten, so `GroupedKeys.Level.hebrewCeiling` clamps
> Hebrew at L1 while English keeps the stop the user picked. The feature is off
> by default. The bundled word lists are Leipzig Corpora Collection frequency
> lists (CC BY 4.0); run `Scripts/generate-grouped-lexicon.py` to refresh them.

> **What the harness returned, in six lines.** Separating Hebrew's clitics is
> worth +7.0 points at thirteen keys and costs no extra keys; **L1 is the last stop
> where it is fully satisfiable**, and below that one pair is stuck. Hebrew caps
> lower than English at every level and the gap widens sharply under compression
> (about 3.5 points at thirteen keys, 22.9 at four). k=2 is the "Two letters" dial stop
> and costs about 3 points against an ungrouped English keyboard. Hebrew L2 commits the
> wrong word nearly three times in ten. **Banding gained English 1.8 to 4.4 points
> and cost Hebrew 1.8 to 7.9**, and neither side of that is the reason to do it —
> the perfect-thumb sweep cannot see target size. `harness/miss.py` can: at a fat
> thumb, English L1 commits 62.9% against ungrouped 38.1%. Every rate carries a
> **2-point** spread; read the README before quoting any of them.

## What the win actually is, and what it is not

**It is not fewer keystrokes.** One tap per letter, exactly as today. Any pitch
built on "type less" describes a different feature and this one will not deliver
it.

**It is target size, in both axes.** A 393pt screen gives ten columns of ~35pt
keys today, and the letter area is three rows of ~40pt. A banded key at L2 is two
columns wide and two rows tall: about 78 × 86pt, four times the area and roughly
square. Fitts's law does the rest: less aiming, fewer mistypes, and it pays off
one-handed, walking, eyes-off, and for anyone whose hands are not steady.

**Grouping sideways alone was half of this and the wrong half.** A row-at-a-time
key is wider and no taller — a sliver — and a thumb misses in both axes. It also
put `q` and `a` two keys apart when they are a few millimetres apart on the glass,
so the key a sloppy tap landed nearest was not the key that carried the letter
meant. The band is what fixes both.

**And it is permission.** iOS already decodes near-misses probabilistically
behind twenty-six drawn keys. Drawing the groups is what tells the user that
sloppiness is expected, and that is the part that changes how they type.

## Why it can work at all

English carries roughly 1.0–1.6 bits per character of real information against
4.7 for a naive 26-letter alphabet, so most of what a keystroke encodes is
already redundant. A June 2026 study (arXiv 2606.11642) swept 2–5 total keys
with three decoders:

| Total keys | Trie only | Trie + small LM | GPT-4o |
|---|---|---|---|
| 2 | 38.5% CER | 27.4% | 23.3% |
| 3 | 21.6% | 14.2% | 9.5% |
| 5 | 11.2% | — | 5.4% |

T9, at eight keys and dictionary-only, uniquely resolved 95% of a 9,025-word
dictionary.

**The finding that shaped this design: the letter-to-key mapping barely
matters.** That study compared QWERTY-shaped grouping, frequency-balanced
grouping, and a deliberately adversarial worst case, and the spread was under
0.5 percentage points. So grouping by physical adjacency — which is what keeps a
QWERTY typist's muscle memory intact — is close to free.

**That result is English-only and it did not transfer to Hebrew.** Measured here,
changing the mapping from row runs to 2D blocks moved English by +1.8 to +4.4 and
Hebrew by −1.8 to −7.9 — five to sixteen times the spread that study reported. The
reason is in the rows: English's second row is where its rare letters live, so a
band key is a common letter with ballast under it, while both of Hebrew's top rows
are dense with its commonest letters. Do not carry an English mapping result into
Hebrew again.

## The dial

Three stops, measured from the shipped row strings in `LetterLayouts`. The top
two rows are stacked into a band of _n_ columns, where _n_ is the longer of the
two and the shorter is aligned under it from the left; the band splits into
`round(total letters / k)` **columns groups**, and the remaining row splits into
the same number of letter groups it always did. Nothing merges across the band
boundary, so shift and delete keep a row of ordinary height to stand in.

**Four details of that rule are load-bearing and each produces a different
keyboard if got wrong.** The rounding is **half-up** (`int(n/k + 0.5)`), not
Python's built-in `round`, which is banker's rounding and would send 19 letters at
k=4 to four keys instead of five. Where the division is uneven the **leading**
groups take the extra, so ten columns in three is 4|3|3 and not 3|3|4. The
band asks `keyCount` **once for both its rows together**, which is what keeps the
key count at every stop equal to the row-at-a-time layout's. And the shorter row
is aligned **left**, which keeps `q w` over `a s` and `o p` over `l`; aligning
right moves every letter of the lower row one column across for no gain. The
minimum is one key per row, so a row can never vanish.

### English — `qwertyuiop` over `asdfghjkl`, then `zxcvbnm`

The band is the first two, ten columns wide with nothing under `p`.

| Level | Letters/key | Keys | Band | Third row |
|---|---|---|---|---|
| pairs | 2 | 12 | `[q/a][w/s][e/d][r/f][t/g][y/h][u/j][i/k][op/l]` | `[zx][cv][bnm]` |
| L1 | 3 | 7 | `[qw/as][er/df][ty/gh][ui/jk][op/l]` | `[zxcv][bnm]` |
| L2 | 4 | 7 | `[qw/as][er/df][ty/gh][ui/jk][op/l]` | `[zxcv][bnm]` |
| L3 | 5 | 5 | `[qwe/asd][rty/fgh][ui/jk][op/l]` | `[zxcvbnm]` |

### Hebrew — `קראטוןםפ` over `שדגכעיחלךף`, then `זסבהנמצתץ`

Eight letters over ten, so `ך` and `ף` have nothing above them.

| Level | Letters/key | Keys | Band | Third row |
|---|---|---|---|---|
| pairs | 2 | 13 | `[ק/ש][ר/ד][א/ג][ט/כ][ו/ע][ן/י][ם/ח][פ/ל][/ךף]` | `[זסב][הנ][מצ][תץ]` |
| L1 | 3 | 8 | `[קר/שד][אט/גכ][ו/ע][ןם/יח][פ/לךף]` | `[זסב][הנ][מצתץ]` |
| L2 | 4 | 7 | `[קר/שד][אט/גכ][ון/עי][םפ/חל][/ךף]` | `[זסבהנ][מצתץ]` |
| L3 | 5 | 6 | `[קר/שד][אט/גכ][ונם/עיח][פ/לךף]` | `[זסבהנ][מצתץ]` |

**The number on the dial is a target, not a promise, and banding is why.** A band
key takes whole columns, so it holds an even number of letters wherever both rows
reach. At three per key the band comes out in twos and fours around a mean of
3.17. What is exact is the **key count** at every stop, which is unchanged from
the row-at-a-time layout in both languages — because `keyCount` is asked once for
the band's two rows together rather than once each.

**Known weakness in these stops, and folding leftovers made it sharper.** English
L1 and L2 differ by **no keys and no points** (both 91.3%): leftover `p` used to
be the extra key at L1, and folding it in made the two stops the same English
keyboard. Hebrew still has one more key at L1 (8 against 7). Two stops that
differ by neither look nor accuracy are one stop. The sweep covers k=2 through 7;
k=2 is 12/13 keys, 94.9% English and 91.4% Hebrew.

## The Hebrew problem, measured

Hebrew glues seven single-letter clitics to the front of words — ה ב ל מ ו ש כ —
so `לעבודה` is one token and the prefix is doing the work English spends a
separate function word on. Plain grouping puts pairs of them on one key:

| Level | Colliding group | Cost |
|---|---|---|
| pairs | `[בה]` | ב+ה: "in X" and "the X" are one keystroke |
| L1 | `[הנמ]` | ה+מ: "the X" and "from X" are one keystroke |
| L2, L3 | `[זסבהנ]` | ב+ה again |

At every stop ה collides with another very common prefix, and every Hebrew
sentence hits it. English has no equivalent because English does not glue its
function words onto nouns.

**Banding made this constraint easier to satisfy, which was not a given.** A
column of the band is atomic: both its letters are on one key and no partition can
pull them apart, so a column holding two clitics would be a collision nothing
could fix. Hebrew's band — `קראטוןםפ` over `שדגכעיחלךף` — has none, because ו sits
over ע and ש, כ and ל are each in a column of their own. The **other** pairing of
its rows does have one (כ over ה), which is one of the two reasons the top two
rows are the ones that band; the other is that it measured 5.5 points better at
L1. All that is left to satisfy is `זסבהנמצתץ`, which holds three clitics and
splits sideways exactly as it did before.

**Second hypothesis: right conclusion, wrong reason.** The guess was that Hebrew
would cap at a lower dial setting than English despite having fewer letters (22
real ones, since the five final forms are positionally determined), because
unvocalized writing has already spent the redundancy grouping wants to borrow.

It does cap lower, and the dial does need per-language stops. But the measurable
driver is **morphology, not missing vowels**: Hebrew's type/token ratio is 0.55
against English's 0.41, so the same meaning is spread over more distinct word
forms, each individually rarer, and more of them compete inside a group. Dropped
vowels may contribute; nothing here shows that they do. See the answered
questions below.

## Out of scope

**Cloud sentence repair.** Considered and cut. It would have meant everything
typed leaving the device automatically, which is a different privacy posture from
today's tap-to-invoke cloud calls, plus per-sentence cost and latency. It also
collides with the rule that committed text must not change under the user.
**Fix already covers the job** — it is user-invoked, it writes into the field, and
it already has the undo button. Revisit only if the measured local ceiling turns
out to be unusable.

**Anything that adds a row, or any height at all.** The band is two key-heights
tall *plus the row gap it swallowed*, so the letter area still adds up to exactly
the three rows it replaced and the 368pt screen-context height cliff is untouched.
`KeyRow.heightUnits` is a multiplier rather than a point value precisely so a row
cannot invent space. Keep it that way, and see
`GroupedKeysTests.testTheBandIsTwoRowsTallAndTheKeyboardIsNot`.

## The two escape hatches

The repo's oldest suggestion-bar rule is that slot zero holds exactly what was
keyed, so a person who typed `qwt` can keep `qwt`. Grouped keys destroy the
premise: a keystroke sequence is not a string.

The rule survives in a weakened but honest form: **there is always a zero-AI
route to the exact characters.**

1. **Precise entry** — long-press a group and its letters fan out; pick one.
   `KeyView`'s alternates popup already does exactly this, with its 200ms delay,
   its 6pt slide threshold so lifting without moving changes nothing, and
   `accessibilityActions` on every item.
2. **Repair** — Fix, for a word that committed wrong.

Plus: grouped mode switches itself **off** when `UITextDocumentProxy.keyboardType`
is a password, email or URL field. Those are exactly the strings a decoder cannot
help with and must not touch.

This weakening is real and should be named as such in any user-facing copy, not
glossed.

---

# Phase A — the simulation

**Nothing here needs Swift, a simulator, or the keyboard.** That is the point:
`Bar/typing/harness` needs a booted simulator because `UITextChecker` is UIKit
and takes minutes per run, which is too slow to sweep a dial. This runs in
seconds.

Location: `Bar/grouped/`, alongside the five existing harnesses. Python, matching
`Bar/typing/harness/score.py` and `Scripts/generate-language-model.py`.

## Inputs

**Group mappings are generated from `LetterLayouts` row strings, never
hand-written.** Same rule `hebrewMarks` follows, and for the same reason: a row
edit must not be able to orphan a letter. The harness reads the rows from a
committed JSON export so it does not have to parse Swift.

**Lexicon (measurement):** `wordfreq`, which covers both languages (Hebrew from
Wikipedia, OpenSubtitles, SUBTLEX, Google Books and OSCAR). Used only in
`Bar/grouped/` and gitignored.

**Lexicon (shipping):** Leipzig Corpora Collection Wikipedia word lists, CC BY
4.0. `Scripts/generate-grouped-lexicon.py` writes
`GroupedLexicon-{en,he}.txt` and `GroupedLexicon-NOTICE.txt`. Without those
files `GroupedDecoder` reports `.seedOnly` and Settings says so.

**Test text:** everything usable in the repo's four other `Bar/` corpora —
`typing`, `ai-text`, `dictation` and `screen-context` — which came out at **388
entries, of which 86 are from the typing corpus**. It was planned as "the 90
typing entries plus a larger held-out sample" and became this instead, because
ninety frozen moments are a regression guard rather than an examination: that
lesson is written down in `.claude/rules/suggestion-bar.md` and cost a round of
false confidence. `screen-context` supplies 210 of the 388, so chat is the
dominant register. `make-testtext.py` stamps the provenance of every entry.

## The loop

For each language, each dial level, each word in the test text:

1. Map every letter to its group, giving a code.
2. Look up every lexicon word sharing that code.
3. Rank by frequency and by whether the preceding word is known to be followed by
   it.
4. Record where the true word landed.

The keyboard itself also reads *where* on the key the thumb landed. A tap
clearly on one letter of the group pins that letter (the same hard filter a
long press uses). A tap in the middle leaves the decoder to guess. That pin is
not in the perfect-thumb sweep; `Bar/grouped/harness/miss.py` measures the
other half: Gaussian misses, so a bigger key can win even when the decoder is
worse.

## What it reports

Borrowing the vocabulary `Bar/typing/harness/score.py` already uses, because
these separate the same two failures:

- **commit** — top-1. What the space bar would insert. The only number a user
  would recognise.
- **offered** — top-3. Did the word reach the bar at all. Separates "the ranker
  is wrong" from "the candidate never existed".
- **collision size** — how many lexicon words share the code, before any ranking.
  Blames a bad score on the right half.

Keystrokes-per-character is 1.0 by construction and is not worth printing.
**Taps-to-correct-word** is: 1 if committed, 2 if offered, more otherwise.

## The four experiments

1. **Sweep k = 2…7**, both languages, so the dial stops come from a curve rather
   than from the table above.
2. **Pure adjacency vs clitic-separated (Hebrew).** Constrain the grouping so no
   two of ה ב ל מ ו ש כ share a key, disturbing adjacency as little as possible,
   and measure what the collisions were costing. This is the experiment that
   decides whether Hebrew can use the same grouping rule as English.
3. **Final-form folding (Hebrew).** Fold ם→מ, ן→נ, ך→כ, ף→פ, ץ→צ before
   grouping and let the decoder reinsert the right form from position.
   `SeedLanguageModel.shapeFolded` already implements this fold. Direction of
   effect is genuinely unclear, which is why it is measured.
4. **Clitic-aware lookup (Hebrew).** Reuse `HebrewMorphology.splits` so one
   lexicon entry for `עבודה` serves `לעבודה`, `בעבודה` and `מהעבודה`.

## The honesty note, which goes in the harness README

**This measures the decoder assuming the thumb always hits the intended group.**
Real thumbs miss.

So the number is an **upper bound** on decode quality, and simultaneously a
**lower bound** on end-to-end benefit, because it never counts the mistypes that
bigger keys prevent. Both directions are real. Neither should be discovered after
someone has quoted the figure.

---

# Phase B — the build (sketch only)

Not planned in detail until Phase A returns numbers. The shape, and what it
reuses:

| Piece | Reuses |
|---|---|
| Grouped letter rows | `KeyboardLayout.rows(for:plane:showsGlobe:customization:)` compiles them into the same `KeySpec`/`KeyRow` everything else already renders. Three things had to be added and only three: `KeyRow.heightUnits`, `KeyWidth.share` so a merged key collects the gutters it covered, and a `KeyView` label that draws a grouped cap one letter at a time — as a single string, bidi mirrors every Hebrew cap |
| Decoder candidates | A new `SuggestionEngine.Source` tier, scored by the existing `score(_:)` alongside checker, seed, learned and personal |
| Hebrew | `HebrewMorphology.splits`, `SeedLanguageModel.shapeFolded` |
| Precise entry | `KeyView` alternates popup |
| Repair | Fix, and `revertibleEdit`'s undo button |
| Scoring | `Bar/typing/harness`, extended |

**The decoder is a source, not a parallel engine.** Candidates arrive with
provenance and are ranked by the machinery that already exists, so grouped mode
inherits context bigrams, the personal model that outranks everything, the Hebrew
clitic penalty, and the harness that grades all of it.

**Grouping is orthogonal to `KeyboardCustomization`.** That feature deliberately
excludes the letter rows, which is exactly and only what grouping changes, so
neither has to learn about the other.

## The questions Phase A was built to answer, answered

Numbers from `Bar/grouped/results.json`, `validity.json` and `lexsize.json`. All
carry a ±2 point spread.

1. **Where does each language's usable ceiling sit?** English holds up well to
   five keys (82.7% commit) and falls apart at four (74.1%). Hebrew is already at
   67.9% by six keys and 51.2% at four. Both are comfortable at 14 keys — 96.5%
   and 91.7%.
2. **Does clitic separation justify breaking adjacency in Hebrew?** Yes, and it
   does not even cost adjacency in practice: the boundaries move but the order
   does not, so muscle memory survives. Worth +7.0 points at 14 keys and +6.8 at
   nine, for zero extra keys. **L1 is the last stop where it is fully
   satisfiable** — the row that keeps delete holds three clitics and gets two keys
   at k≥4, so one must take two. That ceiling is harder than the accuracy curve,
   because no ranking fixes it.
3. **Same dial stops for both languages?** No, and banding widened the case. The
   gap runs from 4.8 points at 14 keys to 22.9 at four, and Hebrew's usable range
   now stops at L1 rather than L2. A shared dial either caps English early or
   hands Hebrew a stop that commits the wrong word three times in ten.
4. **How large a lexicon?** 50,000 English words and 100,000 Hebrew ones sit
   within the spread of a 200,000-word list. As raw JSON that is roughly 1.0 MB
   and 2.5 MB; a packed trie should be several times smaller, and measuring one
   is Phase B work rather than a guess. Bigger always helped — coverage beat
   added collisions at every size tested.

### The two experiments that returned nothing, which is also an answer

Experiments 3 and 4 in the Phase A plan above were both **negative results**, and
neither changes the design because neither is worth doing. Recorded here so the
plan and its outcome sit together; the numbers are README Findings #5 and #4.

5. **Taking the five final forms off the Hebrew keyboard buys nothing.** 27
   glyphs become 22 and the result lands on the same accuracy-per-key curve as
   ordinary grouping — 8 keys at 76.1% against 73.4% for the midpoint of the
   9-key and 7-key adjacent results, inside the spread. No free lunch, so no
   reason to take letters off a keyboard people can read.
6. **Expanding the lexicon with glued clitic forms is a wash.** It cuts OOV by a
   third, 3.0% to 2.1%, and gives most of it back in new collisions: −1.3 points
   at L1 either way, −0.5 and +0.3 at 14 keys. Nothing clears the spread in
   either direction. Not an argument against `HebrewMorphology`, which
   *completes* a word in progress — a different question from decoding a
   finished one.

### And one the harness answered without being asked

Hebrew decodes worse than English **because of morphology, not only because it
drops vowels**. Its type/token ratio in the sample is 0.55 against English's
0.41, and its mean Zipf 5.29 against 5.78: the same meaning is spread over more
distinct word forms, each rarer, so more of them compete inside a group. The
design guessed unvocalized orthography was the cause. That may contribute, but
the measurable driver is morphological richness, and no larger corpus fixes it.

## Risks

- **A same-length neighbour replacing a word still being typed** is already an
  open defect in the suggestion bar (2 of 35 Hebrew keystroke moments). Grouping
  makes every keystroke ambiguous, so this gets worse before it gets better.
- **Bundle size inside a memory-capped keyboard extension.**
- **The dial does not have three distinguishable stops.** L1 and L2 are one key
  and 1.0 point apart in English — banding narrowed that from 3.6 — and Hebrew's
  usable range now ends at L1. The honest shape is probably k=2 / k=3 / k=4 with
  Hebrew capped, not the three that shipped.
