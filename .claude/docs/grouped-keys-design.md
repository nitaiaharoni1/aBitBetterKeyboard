# Grouped keys: one big button for several letters

A keyboard mode where each key carries three to five adjacent letters instead of
one, and a local decoder works out which word was meant. The keys get three to
five times wider; the number of taps does not change.

Status: **Phase A measured; Phase B built and compiling, not yet shippable.** The
harness is `Bar/grouped/` and its findings are in `Bar/grouped/README.md`. The
keyboard is `GroupedKeys.swift`, `GroupedDecoder.swift`,
`GroupedLexiconResource.swift` and `KeyboardController+Grouped.swift`, with the
dial in Settings ▸ Typing.

> **What still stands between this and shipping**, in one place:
> **the lexicon licence.** `Scripts/generate-grouped-lexicon.py` builds the
> bundled word list from `wordfreq`, whose data is drawn from corpora with mixed
> and partly unstated licences, so the generated files are gitignored and must
> not ship. Without them `GroupedDecoder` reports `.seedOnly` and falls back to a
> few hundred seed words, which decodes the common core and almost nothing else.
> Nothing else is blocking; the feature is off by default and the code path is
> inert until somebody turns the dial.

> **What Phase A returned, in five lines.** Separating Hebrew's clitics is worth
> +4.9 points at 14 keys and costs no extra keys; **L1 is the last stop where it
> is fully satisfiable**, L2 keeps half of it, L3 none. Hebrew caps lower than
> English at every level and the gap widens sharply under compression (3.0 points
> at 14 keys, 17.5 at three). k=2 — not currently a dial stop — costs only 1.6
> points against an ungrouped English keyboard. L3 Hebrew commits the wrong word
> about three times in ten. Every rate carries a **1.7-point** spread, so two
> conditions closer than that are not distinguishable; read the README before
> quoting any of them.

## What the win actually is, and what it is not

**It is not fewer keystrokes.** One tap per letter, exactly as today. Any pitch
built on "type less" describes a different feature and this one will not deliver
it.

**It is target size.** A 393pt screen gives ten columns of ~35pt keys today. The
top row becomes three keys at L1 and two at L3, so those keys land around 125pt
and 190pt. Fitts's law does the rest: less aiming, fewer mistypes, and it pays
off one-handed, walking, eyes-off, and for anyone whose hands are not steady.

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

**The finding that shapes this design: the letter-to-key mapping barely
matters.** That study compared QWERTY-shaped grouping, frequency-balanced
grouping, and a deliberately adversarial worst case, and the spread was under
0.5 percentage points. So grouping by physical adjacency — which is what keeps a
QWERTY typist's muscle memory intact — is close to free.

**That result is English-only and does not transfer to Hebrew unexamined.** See
below.

## The dial

Three stops, measured from the shipped row strings in `LetterLayouts`. A row of
_n_ letters splits into `round(n/k)` keys, letters distributed as evenly as
possible, never merging across rows.

**Two details of that rule are load-bearing and produce different layouts if got
wrong.** The rounding is **half-up** (`int(n/k + 0.5)`), not Python's built-in
`round`, which is banker's rounding and would send a row of 10 at k=4 to two keys
instead of three. And where the division is uneven the **leading** groups take
the extra letter, so `qwertyuiop` at k=3 is `[qwer][tyu][iop]` and not
`[qwe][rty][uiop]`. The minimum is one key per row, so a row can never vanish.

### English — `qwertyuiop` / `asdfghjkl` / `zxcvbnm`

| Level | Letters/key | Keys | Groups |
|---|---|---|---|
| L1 | 3 | 8 | `[qwer][tyu][iop]` `[asd][fgh][jkl]` `[zxcv][bnm]` |
| L2 | 4 | 7 | `[qwer][tyu][iop]` `[asdfg][hjkl]` `[zxcv][bnm]` |
| L3 | 5 | 5 | `[qwert][yuiop]` `[asdfg][hjkl]` `[zxcvbnm]` |

### Hebrew — `קראטוןםפ` / `שדגכעיחלךף` / `זסבהנמצתץ`

| Level | Letters/key | Keys | Groups |
|---|---|---|---|
| L1 | 3 | 9 | `[קרא][טון][םפ]` `[שדגכ][עיח][לךף]` `[זסב][הנמ][צתץ]` |
| L2 | 4 | 7 | `[קראט][וןםפ]` `[שדגכ][עיח][לךף]` `[זסבהנ][מצתץ]` |
| L3 | 5 | 6 | `[קראט][וןםפ]` `[שדגכע][יחלךף]` `[זסבהנ][מצתץ]` |

**Known weakness in these stops, now confirmed.** English L1 and L2 differ by one
key out of eight. Rows are only 7–10 letters long, so k=3 and k=4 cannot produce
visibly different key sizes. Measured, they are 3.6 points apart (90.5% against
86.9%) — a real accuracy difference that will not read as two different
keyboards. The sweep covers k=2 through 7, and **k=2 is the stop this table is
missing**: 14 keys, 96.5% English and 93.5% Hebrew, 1.6 points off an ungrouped
keyboard.

## The Hebrew problem, measured

Hebrew glues seven single-letter clitics to the front of words — ה ב ל מ ו ש כ —
so `לעבודה` is one token and the prefix is doing the work English spends a
separate function word on. Adjacency grouping puts pairs of them on one key:

| Level | Colliding groups | Cost |
|---|---|---|
| L1 | `[שדגכ]`, `[הנמ]` | ה+מ: "the X" and "from X" are one keystroke |
| L2 | `[שדגכ]`, `[זסבהנ]` | ב+ה: "in X" and "the X" are one keystroke |
| L3 | `[שדגכע]`, `[זסבהנ]` | same |

At every stop, ה collides with another very common prefix. Every Hebrew sentence
hits this. English has no equivalent because English does not glue its function
words onto nouns.

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

**Anything that adds a row.** Grouping changes the letter rows in place, so the
368pt screen-context height cliff is untouched. Keep it that way.

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

**Lexicon: `wordfreq`**, which covers both languages (Hebrew from Wikipedia,
OpenSubtitles, SUBTLEX, Google Books and OSCAR). Used for measurement only in
Phase A.

> **Licensing gate before anything ships.** Hspell-derived Hebrew wordlists are
> GPL and the OpenSubtitles lists are CC BY-SA. Neither suits a closed App Store
> binary. Whatever Phase B bundles needs its license checked *before* it is
> bundled, and the chosen source recorded in the resource itself, the way
> `LanguageModel.json` stamps `source`.

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
| Grouped letter rows | `KeyboardLayout.rows(for:plane:showsGlobe:customization:)` compiles them into the same `KeySpec`/`KeyRow` everything else already renders |
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
   five keys (81.1% commit) and falls apart at three (59.5%). Hebrew is already
   at 71.3% by six keys and 42.0% at three. Both are comfortable at 14 keys —
   96.5% and 93.5%.
2. **Does clitic separation justify breaking adjacency in Hebrew?** Yes at the
   gentle end, and it does not even cost adjacency in practice: the boundaries
   move but the order does not, so muscle memory survives. Worth +4.9 points at
   14 keys and +2.3 at nine, for zero extra keys. **L1 is the last stop where it
   is fully satisfiable** — a row holding three clitics gets two keys at k≥4, so
   one must take two. It degrades rather than snapping: L2 still splits one pair
   of the two and keeps +1.4, inside the spread; from L3 nothing is recoverable.
   That ceiling is harder than the accuracy curve, because no ranking fixes it.
3. **Same dial stops for both languages?** No. Hebrew's usable range is strictly
   narrower and the gap widens under compression, from 3.0 points at 14 keys to
   17.5 at three. A shared dial either caps English early or hands Hebrew a stop
   that commits the wrong word three times in ten.
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
   ordinary grouping — 8 keys at 80.5% against 81.1% for the midpoint of the
   9-key and 7-key adjacent results, well inside the spread. No free lunch, so no
   reason to take letters off a keyboard people can read.
6. **Expanding the lexicon with glued clitic forms is a wash.** It cuts OOV by a
   third, 3.0% to 2.1%, and gives most of it back in new collisions: −1.0 point
   at L1 either way, −0.1 and +0.3 at 14 keys. Nothing clears the spread in
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

- **The lexicon license** may force a weaker source than `wordfreq`. Gate before
  bundling.
- **A same-length neighbour replacing a word still being typed** is already an
  open defect in the suggestion bar (2 of 35 Hebrew keystroke moments). Grouping
  makes every keystroke ambiguous, so this gets worse before it gets better.
- **Bundle size inside a memory-capped keyboard extension.**
- **The dial may not have three distinguishable stops** at k=3/4/5. Sweep first.
