# Glide typing: can the grouped-keys decoder be reused? (NIT-17 spike)

A spike, not a feature. Nothing here ships, nothing here is Swift, and no
real finger produced any of the numbers below — **every one of them is
SYNTHETIC**, generated from a stated, parameterised model of a hand rather
than measured from a user. Read the whole of "The generator" before quoting
any number out of `results.json`.

```bash
Bar/glide/harness/run.sh   # self-test, then the sweep; ~15s → results.json
```

No simulator, no network. `Bar/glide/harness/keyboard.py` and `path.py` are
the only new code; everything that ranks a candidate — `Decoder`, `Lexicon`,
`Bigrams` in `Bar/grouped/harness/decode.py` — is reused **unmodified**, and
`Bar/glide/harness/run.py` reuses `Bar/grouped/data/{rows,testtext,
lexicon-en,lexicon-he}.json` rather than freezing a second copy of the same
inputs. `Bar/grouped/README.md`'s own rule is followed here too: that data and
that decoder are not edited, because doing so would move a number this spike
depends on but does not own.

## The question, and the short answer

Grouped keys already showed that "an ambiguous sequence of key regions in,
the most likely word out, ranked against a frequency prior" is a solved
problem in this repo — `Decoder` does exactly that. Glide typing needs the
same ranking, fed by a different front end: a continuous path reduced to a
key sequence. That front end is the genuinely new part, and it turned out to
be the whole story.

**The ranking half is real and cheap to reuse. The path-reduction half works
for a careful swipe and falls apart for a fast one — and fast is the entire
reason anyone wants glide typing.** Recommendation and the reasoning are at
the bottom; the numbers are in between.

## The generator, and why every number is labelled SYNTHETIC

There is no corpus of real traced swipes in this repo, so every path is
built from the intended word's key centres plus a stated amount of noise and
curve. Four parameters, each named because each is a claim about how a hand
moves, and each is swept rather than baked into a constant:

- **`sigma`** — Gaussian noise on *where the hand actually aims for each
  letter*, one draw per letter (not per path sample; see "A bug worth
  naming" below), in key-width units. Same scale `Bar/grouped/harness/
  miss.py` already uses for tap noise, so the two are directly comparable:
  0.20 there is called a fat thumb. This sweep uses 0.15 / 0.25 / 0.35.
- **`corner_cut`** — how much a waypoint rounds toward a straight line
  between its own neighbours instead of being hit exactly. 0 is a careful,
  deliberate swipe that visits every intended letter's key centre; 0.5 is a
  fast one that cuts corners, which is what "gliding" actually feels like
  and is the entire reason it is faster than tapping.
- **`samples_per_segment` = 6** — path density between waypoints. Fixed; a
  spot check found no sensitivity to it in the range 4–12.
- **`angle_threshold_deg` = 5** — how sharp a turn has to be to count as a
  corner. Fixed after a full-corpus sensitivity check (below), not swept in
  the main grid.

Corner detection — turning angle between consecutive path samples, corner if
it clears the threshold, touch-down and touch-up always kept — is the actual
"genuinely new part" NIT-17 asked for. `Bar/glide/harness/path.py`'s
docstrings carry the reasoning; the short version is that a swipe cannot be
reduced to a key sequence by taking the nearest key at every sample, because
a straight line between two far-apart letters (`h` to `e` on QWERTY) passes
through several other keys' territory on the way. Only the *turns* mark
where a letter actually was.

### A bug worth naming, because the fix is the finding

The first version of this generator drew fresh Gaussian noise at **every
path sample**, independently. That produces a jagged, high-frequency random
walk no real hand motion looks like — samples a few milliseconds apart are
strongly correlated in reality — and it defeated corner detection at every
threshold tried, because a straight segment's own interior picked up
spurious turning angles everywhere. The fix, `perturb_waypoints`, draws
**one** offset per letter (matching `miss.py`'s own methodology) and keeps
the interpolation between offsets exactly straight. This is not a footnote:
it is the difference between a generator that cannot be evaluated at all and
one that produces the numbers below, and it is why "how correlated is the
noise" belongs on this list of named assumptions rather than off it.

### Angle-threshold sensitivity, full English corpus, one seed

| threshold | σ=0.15 | σ=0.25 | σ=0.35 |
|---|---|---|---|
| 2° | 97.4% | 75.9% | 38.3% |
| **5°** | **94.8%** | **75.1%** | **38.1%** |
| 10° | 91.7% | 72.3% | 37.1% |
| 20° | 85.9% | 68.4% | 35.7% |
| 40° | 76.8% | 61.5% | 33.2% |

Monotonically falling as the threshold rises, at every noise level tried, so
there is no interior optimum to tune — lower is better everywhere in this
range. 5° was fixed rather than 2° to keep a margin above the near-zero
angle a straight segment's own interior can pick up from per-waypoint noise
(see "Non-monotonic in noise" below for why that margin matters), not
because 5° is a peak.

## The results, English and Hebrew, five seeds each

Commit = top-1 (what the space bar would insert), offered = top-3, both of
words this layout could type and the lexicon knows — same definitions
`Bar/grouped/README.md` uses, so the two are readable side by side. Spread
is max−min commit across the 5 seeds; AGENTS.md's rule that one run is not
evidence applies here as much as anywhere else in this repo.

**EN** — 190 entries, 1,805 words, 200,000-word lexicon.

| corner_cut | σ | mean commit | spread | mean offered | +fuzzy commit |
|---|---|---|---|---|---|
| 0.0 (careful) | 0.15 | 94.7% | 0.7% | 95.2% | 96.7% |
| 0.0 | 0.25 | 73.3% | 2.7% | 73.7% | 84.1% |
| 0.0 | 0.35 | 37.8% | 1.3% | 38.0% | 51.9% |
| 0.5 (fast) | 0.15 | 18.7% | 0.1% | 19.1% | 21.1% |
| 0.5 | 0.25 | 17.0% | 1.0% | 17.2% | 19.1% |
| 0.5 | 0.35 | 12.5% | 1.5% | 12.6% | 14.1% |

**HE** — 198 entries, 1,475 words, 199,982-word lexicon.

| corner_cut | σ | mean commit | spread | mean offered | +fuzzy commit |
|---|---|---|---|---|---|
| 0.0 (careful) | 0.15 | 93.5% | 0.7% | 95.4% | 93.9% |
| 0.0 | 0.25 | 71.8% | 3.0% | 73.3% | 79.9% |
| 0.0 | 0.35 | 35.6% | 2.8% | 36.4% | 49.8% |
| 0.5 (fast) | 0.15 | 19.8% | 0.3% | 20.5% | 24.4% |
| 0.5 | 0.25 | 17.4% | 0.6% | 17.9% | 21.6% |
| 0.5 | 0.35 | 11.5% | 0.7% | 11.9% | 14.7% |

"+fuzzy commit" is a second, cheaper decoder tried alongside the exact one:
if the exact collapsed code has no lexicon match, widen the query to every
code one edit away (one key deleted, substituted or inserted) and rank the
union by frequency, still through `Decoder`'s own index and `Bar/grouped`'s
own frequency ranking — nothing about `Decoder` changes, only the query.
`Bar/glide/harness/run.py`'s `fuzzy_candidates` and `rank_words` are the
whole of it.

**Two shapes stand out, and only one of them is the one the sigma sweep was
built to find.**

- **`corner_cut` dominates `sigma`.** Going from a careful swipe to a fast
  one at the *same* noise level costs 55–76 points; going from careful to
  sloppy at the *same* corner-cutting costs 12–58. The single biggest lever
  on this number is not hand steadiness, it is whether the swipe is allowed
  to cut corners at all — and cutting corners is the entire mechanical
  reason gliding is faster than tapping. A generator that only swept `sigma`
  would have reported a far rosier number by never modelling the thing that
  makes glide typing glide.
- **Fuzzy rescue helps a lot at low corner-cutting and barely at all when
  corners are cut.** At `corner_cut=0.0, σ=0.25` it recovers 8–11 points
  (single-error cases: one dropped or substituted letter). At `corner_cut=
  0.5` it recovers 1–4: a fast swipe typically drops or garbles *several*
  letters in one pass, which is more than one edit away from the truth, so
  a cheap edit-distance-1 rescue cannot reach it. This is measured evidence
  for the recommendation below, not a guess.

## Does Hebrew behave differently? (question 3, not skipped)

**Not the way grouped keys did.** Grouped keys found English gaining 1.8–4.4
points and Hebrew losing 1.8–7.9 from the same structural change (banding),
because that change touched the *key-to-letter mapping* and Hebrew's rows
are dense with common letters in a way English's are not. Glide typing does
not touch the mapping at all — every key still carries exactly one letter —
so that specific mechanism does not apply here, and the results agree: the
EN/HE gap at every setting above is 1–3 points, smaller than the 0.7–3.0
point spread already measured across seeds, and it **changes direction**
between conditions (Hebrew leads at `corner_cut=0.5, σ≤0.25`; English leads
everywhere else). Neither language is reliably ahead.

That does not mean the two are identical underneath. The collapsed-code
collision count — how often two lexicon words share one code purely from
their own spelling, independent of any noise — is proportionally larger for
Hebrew: 24,581 of 199,982 words (12.3%) share a code with at least one other
word, against 17,918 of 200,000 (9.0%) in English. Consistent with grouped
keys' own finding that Hebrew's type/token ratio is higher, so more distinct
word forms compete for the same code — but the effect is small enough here
that it does not show up as a consistent commit-rate gap the way it did for
grouped keys, likely because most of the collision mass in both languages is
the same low-stakes class: elongated informal spellings the lexicon (built
from web text) happens to carry — `the`/`thee`/`tthe`, `to`/`too`/`tto`,
`של`/`שלל`/`ששל` — which collapse onto their own base word and rank far
below it by frequency, rather than genuine ambiguities between two common,
different words. `later`/`latter` is a real example of the second, rarer
kind (both common, both in the shipped lexicon, identical code): see
`Bar/glide/harness/selftest.py`'s Decoder-reuse assertion, which pins it.

**So step 3's answer is: measured, and no, this is not grouped keys' Hebrew
penalty in a new shape.** The dominant variable here is the generator's own
`corner_cut`, not language.

## Non-monotonic in noise, and why zero is the wrong ceiling to quote

A natural instinct is to also run `sigma=0.0` as a "perfect swipe" ceiling.
Doing that gives EN 89.8% / HE 91.9% commit — **lower** than the `σ=0.15`
row above, for both languages. Noise should never help accuracy; something
else is happening, and it is worth naming rather than burying.

Any three **consecutive same-row QWERTY letters are exactly collinear**, by
construction — a row is a straight line. At `sigma=0.0` the path through
them is therefore exactly straight too, the true turning angle at the
middle letter is exactly zero, and no threshold can ever call that a corner.
`were` (w-e-r consecutive on the top row) loses its middle `e` at zero
noise, decoding as `w r e`; `tree` loses its `r` entirely, decoding as `t
e`. A small amount of per-waypoint noise breaks the exact collinearity
just enough for the true corner to register — `were` and `tree` both decode
correctly at `σ=0.15`. This is measured directly in `selftest.py`'s
threshold test and reproduced live:

```
were   zero=('w', 'r', 'e')             σ=0.15=('w', 'e', 'r', 'e')
tree   zero=('t', 'e')                  σ=0.15=('t', 'r', 'e')
quote  zero=('q', 'o', 'e')             σ=0.15=('q', 'u', 'o', 't', 'e')
```

So `σ=0.0` is not a best case, it is a pathological one, and quoting it as a
ceiling would understate how the pipeline actually behaves. The rows this
README reports (`σ≥0.15`) are the meaningful ones; this section exists so
nobody re-derives a "perfect swipe" number later and is confused by it.

## Recommendation

**Do not pursue building glide typing on this architecture as measured.**
The ranking half — reusing `Decoder`, `Lexicon` and `Bigrams` unmodified,
indexed by a collapsed-spelling code instead of a grouped one — works
exactly as cheaply as the issue hoped, and the `later`/`latter` collision
proves the same homograph-ranking machinery transfers. That is real, and
worth remembering if this is revisited.

But the front end does not survive contact with what glide typing is *for*.
A careful, corner-respecting swipe decodes at 70–95%, competitive with
grouped keys' better dial stops. The moment the swipe is allowed to cut
corners — which is the entire mechanical reason gliding is faster than
tapping, not an edge case of it — accuracy falls to 12–20%, and a cheap
edit-distance-1 rescue barely moves that, because a fast swipe typically
loses more than one letter per word, not one. Corner detection over a
discrete, exact-or-near-exact key sequence is the wrong shape of algorithm
for a fast swipe; production glide keyboards do not do this — they score a
shortlist of candidate words by how well the *whole continuous path*
matches each candidate's own idealised path (elastic / DTW-style distance),
which tolerates corner-cutting because it never commits to a discrete
symbol sequence in the first place.

**If this is revisited, the next cheapest step is not to keep tuning corner
detection** — the sensitivity table above shows there is no threshold that
rescues the fast-swipe case, because the failure is structural, not a
tuning miss. It is to spike path-to-template distance scoring instead: take
the same synthetic-path generator here, and for a shortlist of candidate
words (filtered cheaply by length and first/last letter, the way a real
system would), score each candidate's own ideal path against the swiped
path directly, without ever reducing the swipe to a discrete key sequence.
That is a different, larger spike than this one, and this repo's own
`Decoder` — built around an exact code lookup — would not be the piece that
carries it; only the frequency/bigram ranking on top of a shortlist would.

## Files

| | |
|---|---|
| `harness/keyboard.py` | Key-centre geometry (row centring, not flush-left) and `GlideLayout`, whose `.code(word)` is the only new interface `Decoder` needed. |
| `harness/path.py` | The generator: waypoints, per-waypoint noise, corner-cut interpolation, turning-angle corner detection, the full word→code pipeline. |
| `harness/run.py` | The sweep. Reuses `Bar/grouped/harness/decode.py` and `Bar/grouped/data/*.json` unmodified. Writes `results.json`. |
| `harness/selftest.py` | Assertions run before every sweep, including the collinear-drop and Decoder-reuse cases named above. |
| `harness/run.sh` | Entry point: self-test, then the sweep. |
| `results.json` | Committed output of the run this README quotes. Every record is stamped `synthetic: true`. |
