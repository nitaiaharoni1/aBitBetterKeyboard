# The letter-by-letter sweep

Types whole words through the real `SuggestionEngine`, one letter at a time, and
reports every keystroke where the space bar would have inserted a word the person
is not typing.

```bash
Bar/typing/sweep/run.sh                        # two runs, ~25 s, needs a booted simulator
Bar/typing/sweep/run.sh --runs=3
Bar/typing/sweep/run.sh --trace=בעבודה,מהעבודה # print a clean word's whole trail too
```

It is the same invigilator as the frozen exam next door: `expand.py` turns
`words.json` into `Bar/typing/corpus.json`'s own shape, `harness/run.sh` runs the
shipping engine over it on the iOS Simulator, and `judge.py` grades the bold
slot. Nothing here re-implements the engine, and the corpus it generates is
disposable by design: edit `words.json` and regenerate. The frozen 90 never
change; this list is meant to grow.

## Why the frozen 90 cannot replace it

**The corpus knows a prefix. The sweep knows the word.** Every entry in
`corpus.json` is one moment — a context, a partial word, and a list of answers a
human authored as acceptable. It cannot ask whether the keyboard is *on its way
to the right word*, because it was never told what the typist was reaching for.
So it grades plausibility, and the defect this tool exists for is the plausible
wrong answer: `להתר` completing to `להתרופה` ("to the medicine") is a perfectly
good completion of those four letters, and it is not the word anybody typing
`להתראות` ("goodbye") wants. A list of acceptable answers written for the prefix
`להתר` would very likely have contained it.

**Ninety moments are a sample of the keyboard, not the keyboard.** The corpus
holds 20 Hebrew entries with a word in progress; this sweep holds 268 Hebrew
keystroke moments and 315 English ones from 96 words. Three defects have been
found by sweeping and none of them by the corpus: the Hebrew final-form rule
firing on a fifth of all mid-word Hebrew keystrokes, a trailing comma collapsing
the bar to one slot, and `Nitai’s` losing the personal dictionary's protection.
The sweep that found each of them was rebuilt from memory and thrown away, which
is why this directory exists at all.

**And a whole word is where the keyboard has the least excuse.** The last
keystroke of every word is an entry here. A corpus of frozen prefixes never asks
what the space bar does to a word the user has finished typing.

The corpus is still the regression guard and this is not. Its entries are frozen
and scored; `words.json` is a list somebody keeps adding to, and its output is a
list of accusations to read rather than a number to defend.

## What it judges

`main.swift` writes `commits`: the text of the slot marked default, which is
exactly what `KeyboardController.insertSpace` inserts. That string, and nothing
else, is what `judge.py` compares. **Presence in the bar is not a pass**, because
`SuggestionEngine` pins the typed keystrokes into slot zero on purpose, so "the
right word is offered" stays true of an engine that has stopped working. The
scorer for the frozen 90 got this wrong once and mislabelled 40 of its 76 entries.

Three verdicts per keystroke:

| verdict | meaning |
|---|---|
| `held` | The bold slot is what was typed. Conservative, never a defect. |
| `ontrack` | The bold slot is a prefix of the word being typed, up to the whole of it. |
| `diverged` | Neither. Space would insert a word this person is not typing. |

`diverged` splits again, and the split matters more than it looks:

- **`continues`** — every typed letter survives and the engine guessed a
  different ending. `להתר` → `להתרופה` is this. Note that it *is* a
  prefix-completion of the keystrokes; "the bold slot completes what was typed"
  is not a test that catches it, and only knowing the target word does.
- **`replaces`** — a key the user pressed is gone. Worse: the evidence the engine
  overruled was unambiguous.

## Two runs, and why that is weaker evidence than it sounds

`run.sh` runs the corpus twice by default and `judge.py` only reports a moment
that diverged in *every* run. That is this repo's standing rule — one run is not
evidence — and here it is the interface rather than a note in a README.

**It does not make the reading airtight, and the sweep's own output is what shows
why.** `UITextChecker`'s Hebrew completion list depends on what it has already
been asked in that process. Two runs of the same corpus make the same calls in
the same order, so they reproduce each other; identical *inputs* inside one run
do not. Measured on 2026-08-16: 38 distinct inputs appear more than once in the
generated corpus, and one of them, the prefix `להתרא`, came back with a
different bold slot in the two places it was asked — `להתראיין` at one and
`להתראות` at the other, same process, same query. So a clean two-run agreement
means the sequence is reproducible, not that the answer is stable. Read a finding
that hangs on a single Hebrew completion with that in mind, and add the word to
`words.json` in more than one context if it matters.

## words.json

```json
{ "word": "מהעבודה", "keyboard": "he_IL", "context": "", "probes": "why this word is here" }
```

`word` is typed one letter at a time; `keyboard` is the layout it is typed on;
`context` is text already committed before it and defaults to empty, which is the
cleanest control because no sentence signal is in play. `intended` defaults to
`word` and is only spelled out when the entry is a misspelling on the way to
something else. Ids are numbered per language (`he-04-05` is the fifth keystroke
of the fourth Hebrew word), so appending an English word does not renumber the
Hebrew ones and turn the next run into an unreadable diff.

Words are spelled correctly on purpose. The frozen corpus already asks what
happens to a typo; this file asks the question nothing else does, which is
whether typing a real word is ever hijacked between its first letter and its
last.

## What it found on 2026-08-16

Two runs, 583 moments, 460 held, 113 on track, **10 diverged in both runs**. A
third and fourth run on the same machine agreed exactly; a fifth, run by somebody
else, reported **9**, and the missing one is the instability described above —
see `להתרא` below.

Every provenance figure here was read out of the engine, not inferred: the top
four candidates for each moment, with `source`, `cliticDepth` and `score`, plus
what `shouldAutocorrect` returned. The reconstruction is faithful because the
candidate list it printed matches the slots the sweep recorded, moment for
moment.

### Against `SuggestionEngine.commitTrustsReading` (NIT-107)

- **`להתר` no longer commits `להתרופה`.** The bold slot holds `להתר` and
  `להתרופה` is still offered in slot 1. `להתרופה` arrives `.seed` at depth 2,
  scoring 2000, and it is the top-ranked non-typed candidate — so the ranking
  still prefers it and only the commit gate refuses it, which is precisely what
  that rule claims to do. First direct evidence it works; the frozen 90 could
  only show it does no harm.
- `בעבו` commits `בעבודה` (`.seed`, depth 1, 2500) and `מהעבו` commits
  `מהעבודה` (`.seed`, depth 2, 2000). Both controls hold.
- **`להתרא` still commits `להתראיין`, and NIT-107 never touched that keystroke.**
  The winner is `.checker` at `cliticDepth` **0**, score 1000, so
  `commitTrustsReading` returns true on its first line and the four-letter gate
  commits it. `UITextChecker` completes the *glued* form `להתרא` itself and
  returns `להתראיין` first; the `ל` + `התרא` reading the rule does reject scores
  500 lower and never reaches the bar at all. The issue's diagnosis of this
  moment was wrong about the mechanism.

  **What it is instead is an ambiguity, and the diverging pair proves it**:
  `להתראות` and `להתראיין` are two real words sharing five letters, so on the way
  to either one the space bar inserts the other. That is `respon` →
  `respond` / `response` in Hebrew. `hasDistinctLexemes` is the gate for that
  shape and neither of its two call sites can reach here: the seed-based one asks
  `SeedLanguageModel.words(startingWith:)`, and the seed has no `להתר` entry at
  all, and the offered-slots one is scoped to a Latin stem in a Hebrew sentence.
  **Widening the offered-slots test to Hebrew breaks the control, measured**:
  `בעבו` is offered `בעבודה`, `בעבור`, `בעבודת`, and `בעבור` is not a prefix of
  `בעבודה`, so `hasDistinctLexemes` would read two lexemes there and stop the
  correct commit. That is the objection already recorded against this fix, now
  with the slots behind it.

  It is also the moment that moves. `UITextChecker` returns `להתראיין` first
  here and `להתראות` first elsewhere in the same process, which flips one of the
  three `להתרא` moments between `diverged` and `ontrack` and is why one run of
  this sweep counted 9 and another 10.

### New, and none of them Hebrew morphology

- **`keyb`, `keybo`, `keyboa` and `keyboar` all commit `KeyboardKit`.** Source
  `.personal`, score 8000, from `supplementary` — that is
  `SharedStore.shippedPersonalDictionary`, which every install ships. **Not a
  leaked learned store**: the harness passes `PersonalLanguageModel(url: nil)`
  and it was asked, in the same process, for words starting with `key` and
  returned none. The personal dictionary's own guard in `shouldAutocorrect` only
  protects an *exact* match (`keyb` is not `KeyboardKit`), so the four-letter
  gate commits the highest-ranked candidate, which is a top-tier entry that
  happens to start with the same four letters. `keyboard` sits in slot 2 the
  whole time and only wins at the eighth letter, where `isKnownWord` finally
  refuses the gate. The general shape: **any personal-dictionary entry that
  extends a common word hijacks that word for as many keystrokes as they share.**
- **`scr` commits `דבר` after `אני מצרף `.** Source `.layout`, score 9045, from
  `LayoutTransposition`, and `shouldAutocorrect` returns true on the
  different-script branch above every other question. All of that rule's gates
  pass at exactly three letters: `scr` is not an English word, not in the seed,
  and `ד ב ר` are the keys `s c r` sit on, which *is* a common Hebrew word. It
  self-heals at four letters, where `scre` transposes to nothing the seed knows.
  `screenshot` was already in slot 2 from `codeSwitchVocabulary`, so the
  wrong-layout rule outranks the list written for this exact sentence.
- **`ano` commits `and`** (`.neighbour`, 2281, over `another` at `.checker`
  1000). Behaving as designed: same-length substitutions commit in English, and
  the exclusion that would stop it is Hebrew-only on purpose, because
  `definately` and `seperate` need it. Worth watching rather than filing.
- **`im` commits `I'm`** (`.orthography`, 7000). The contraction table doing its
  job on a two-letter non-word. Not a defect.
