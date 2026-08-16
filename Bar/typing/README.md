# Typing: the corpus, the harness, the sweep and the stock-keyboard reference

Four things live here, and they answer four different questions.

`harness/` is **the invigilator**: it runs the real `SuggestionEngine` over all 90
entries and grades the answers.

```bash
Bar/typing/harness/run.sh            # writes engine_outputs.json
Bar/typing/harness/score.py          # grades it
Bar/typing/harness/score.py before.json after.json   # diffs two runs
```

It needs a booted `iPhone 17 Pro` simulator and takes a couple of seconds. It
compiles for the **simulator, not macOS**, because `UITextChecker` is UIKit and
macOS spell-checks with `NSSpellChecker` — a different dictionary and a different
ranking, so a macOS score would not be a score of the shipping engine. It passes
an **empty in-memory `PersonalLanguageModel`**, so a run cannot inherit whatever
the machine it runs on has been typing, and the shipped personal dictionary,
because scoring with an empty one measures a keyboard nobody has.

`score.py` reports three things and keeps them apart. **commit** is whether the
bold slot — what the space bar inserts — is the right word, which for an
`intended` entry is the only number a user would recognise. **offered** is whether
the right word appeared in any of the three slots, counted separately because it
separates "the ranker is wrong" from "the candidate was never generated".
**intact** is `mustNotCorrect`: the bold slot still holds exactly what was typed.
Misses against an **open** `acceptable` list are printed but never counted as
failures, because that list is a sample and never a whitelist.

**The commit column used to be the offered column relabelled for `acceptable`
entries, which is 40 of the 76.** Their pass was computed from whether the right
word appeared anywhere and then printed under `commit`, so an entry that offered
the right word in slot 2 while bolding a non-word in slot 1 counted as a pass:
`he-comp-07` committed `מון` for `מונ` with `מונית` beside it, and the headline
never moved. It is measured now, for every entry that types a word, against the
test that the bold slot holds either what was typed or one of the good answers —
declining to complete is conservative, not wrong. An entry with an empty prefix is
not asked at all, because `insertSpace` commits nothing where no word is in
progress.

The score at the time of writing is **73/76 judged**, from 47/76 before the engine
was made context-aware. It read 73/76 under the scorer that did not measure the
commit column; the same engine scored 71/76 the first time it was measured
honestly, and the entry that closed the gap is `he-comp-07`. Two identical-code
simulator runs hold 73/76 with zero slot flips. `en-comp-03` commits `response`
after `the quick`. `cs-05` commits `screenshot` (`screenshot` / `screenshots`
are in `codeSwitchVocabulary`). `apos-09`, `typo-10` and `typo-11` stay red on
the local run on purpose. That 73/76 is the local engine only. The async corpus
is a different number.

Key proximity re-ranks neighbour *offers* by +50 when the differing letters sit
on adjacent keys. It does not change what space commits.

## Sweep

`sweep/` is **the other exam**, and it asks a question the frozen 90 cannot.

```bash
Bar/typing/sweep/run.sh              # two runs, ~25 s
```

It types whole words letter by letter through the same harness and judges the
bold slot against *the word being typed*, which the corpus never knows: an entry
there is a prefix and a list of acceptable answers, so it grades plausibility,
and `להתר` → `להתרופה` is a plausible completion of four letters and the wrong
word. Add words to `sweep/words.json`; the corpus it generates is disposable.
`harness/run.sh` reads `TYPING_CORPUS` so it can be pointed at that generated
file, or at any other corpus of the same shape. `sweep/README.md` has the rest.

## Async corpus

`async/corpus.json` is ~11 paused moments for the on-device refiner, including
`apos-09` (`were` → `we're`; `were` is not in the contraction table), English
next-word lines, one Hebrew next-word that Foundation Models cannot serve, and a
Messages screen question.

```bash
ASYNC_TYPING_OUT=/tmp/async.json Bar/typing/async/run.sh
# or: Bar/typing/async/run.sh /tmp/async.json
```

That runs `AIKeyboardCoreTests/AsyncTypingCorpusTests` on the simulator UDID in
the script, then scores with `TYPING_CORPUS` pointed at `async/corpus.json`.
`score.py` reads `TYPING_CORPUS` and defaults to `Bar/typing/corpus.json`.
Two runs here were 5/6 both times with `engineAvailable: false`. That is the
local tier of those entries. Foundation Models did not run. Do not quote it as
a model quality number.

`corpus.json` is **the exam**: 90 frozen moments mid-typing, each one a context, a
word in progress, and a note saying what it is probing. It never changes once a
judgement has been made against it.

`reference/` is **the passing grade**: screenshots of what Apple's own keyboard did
when handed the same 90 moments, plus `manifest.json` transcribing the words it
offered. A prediction engine that does not beat this is not worth shipping, because
the user already has it for free.

## corpus.json

```json
{
  "id": "cs-07",
  "category": "code-switch",
  "language": "he-en",
  "keyboard": "en_US",
  "context": "צריך לסגור את ה",
  "prefix": "spri",
  "probes": "sprint after the Hebrew definite article, the most common code-switch shape there is."
}
```

`context` is text already committed. `prefix` is the partial word under the cursor;
empty means the probe is next-word prediction rather than completion. The field
holds `context + prefix`. `keyboard` is the layout active while the prefix is
typed — for code-switch entries that is deliberately not the layout the rest of the
sentence is in.

Two optional fields carry intent a bare string cannot:

- `intended` — what the person meant, on entries where the typed characters are a
  mistake with one obvious target (`teh` → `the`, `dont` → `don't`, `תדוה` → `תודה`).
  It is what a human would have meant, not a promise about what any engine returns.
- `mustNotCorrect` — entries where **changing** the typed text on space is the
  failure. The repo names one of these out loud in its README: an early version
  turned `I` into `idea`. That is `nc-01`.

### `acceptable` — the human side of the answer

The 24 `intended` and 12 `mustNotCorrect` entries can be judged with no reference at
all: one names the right answer, the other says the right answer is "unchanged". The
other 54 — completions, next-word, code-switch — had only prose. That is a problem
for a critic, because if a captured iOS reference is the *only* recorded answer then
every difference from iOS reads as a loss, including the differences that are wins.

So those 54 now carry:

```json
"acceptable": ["tomorrow", "soon", "there", "later", "then"],
"acceptableIsClosed": false,
"acceptableSource": "human-authored"
```

**What it is.** Human judgement about what a good keyboard would offer, written from
the `probes` line that was already in the corpus, without reading any captured
reference.

**What it is not.** Not a capture, not a prediction of what iOS does, and not a
substitute for the reference. If `reference/` gets filled in, keep both — they answer
different questions. `acceptable` asks "is this a good suggestion"; the reference
asks "is this better than what the user already has for free". An engine can pass one
and fail the other, and that is exactly the thing worth seeing.

`acceptableIsClosed` is the part to read carefully:

- **`true`** (40 entries) — the list is meant to be complete. `minu` has one good
  ending and it is `minutes`; a keyboard putting something else in slot one is wrong,
  and a miss is a real miss.
- **`false`** (14 entries) — the slot is genuinely open. `See you ___` legitimately
  takes tomorrow, soon, there, later, then and more. The list is a **sample of good
  answers, never a whitelist**: a suggestion outside it may be just as good, and
  absence from the list is not evidence of anything.

Six of the open ones also carry `acceptableNote`, because their real criterion is a
class rather than a set of words — "any Hebrew infinitive", "any weekday", "the next
word should come back in Hebrew after a Latin loanword". Judge those on the class;
the list is only the common fillers.

`acceptableSource` is on every one of the 54 so it can never be mistaken for
captured behaviour. One entry, `en-comp-01`, carries a note saying its list was
written after I had already seen the stock keyboard's answer for it — the list
matches the pre-capture prose, but it is the single non-blind item and a critic
should discount it accordingly.

The nine categories, and how many entries each has:

| Category | n | What it is for |
|---|---|---|
| `english-completion` | 10 | English word in progress |
| `english-next-word` | 8 | English sentence, empty prefix |
| `hebrew-completion` | 12 | Hebrew word in progress, including clitics (`מהגן`, `לעבודה`) |
| `hebrew-next-word` | 10 | Hebrew sentence, empty prefix |
| `code-switch` | 14 | Latin word inside a Hebrew sentence, and the return to Hebrew after one |
| `missing-apostrophe` | 9 | `dont`, `im`, `ill` — including the ones where correcting is wrong |
| `typo` | 12 | Plausible slips with a real intended word, English and Hebrew |
| `no-correct` | 12 | Short or already-correct input where any change is the bug |
| `wrong-layout` | 3 | Hebrew typed under the Latin mapping and back |

The sentences are things people in Israel actually type: `אני מגיע בעוד עשר דקות`,
`הזמנתי אוכל בWolt`, `צריך לסגור את הsprint`, `Ask Tzachi`, `Pay with Bit`.

## reference/

```
reference/
  manifest.json     one row per corpus id
  <id>.png          full-screen shot with the stock suggestion bar visible
  <id>-failed.png   what the screen looked like when an entry could not be driven
  raw/<id>.json     what the test wrote for that entry, before assembly
  capture-*.log     the xcodebuild output of each pass
```

Each manifest row is either `captured` — with `screenshot`, `fieldText` read back
out of the field, and `suggestions`, the three words transcribed from the bar — or
`uncaptured`, with a `reason`. There is no third state. **Nothing in this directory
is invented.** If the stock keyboard was never asked, the row says so, because a
made-up reference is worse than a missing one: the critic cannot tell the
difference, and every later judgement inherits the lie.

Two fields appear only when they apply, and both exist to keep the row honest:

- `skippedCharacters` — characters the capture could not type. In practice this is
  the apostrophe, which is not on the letter plane (see below). `fieldText` is what
  finally sat in the field, so on `en-comp-01` you can see `Ill` going in and
  `I'll be there in ten minu` coming out, because iOS put the apostrophe back.
- `note` — set to `the suggestion bar was photographed but not transcribed` when the
  screenshot exists but the runner died before reading the labels. The picture is
  still evidence; the empty `suggestions` list is not.

`suggestions` are read from the accessibility labels of the three slots under the
element iOS labels `Typing Predictions`, ordered **left to right on screen**. Hebrew
renders right to left, so on a Hebrew entry the last item in the list is the
leftmost slot, not the least likely word.

## Rebuilding the reference

```bash
Bar/typing/capture.sh
```

That is the whole command. It prepares the simulator, runs two capture passes, and
writes `reference/manifest.json`. Expect tens of minutes. It needs the `iPhone 17
Pro` simulator and macOS Accessibility permission for whatever runs it, because one
step drives a Simulator menu.

To re-assemble the manifest from an existing run without re-capturing:

```bash
python3 Bar/typing/make-manifest.py
```

To capture a handful of entries by hand:

```bash
TEST_RUNNER_STOCK_CAPTURE=1 \
TEST_RUNNER_CORPUS_PATH=$PWD/Bar/typing/corpus.json \
TEST_RUNNER_REF_DIR=$PWD/Bar/typing/reference \
TEST_RUNNER_ONLY_IDS=en-comp-01,nc-01 \
TEST_RUNNER_RETRY_FAILED=1 \
xcodebuild test -project AIKeyboard.xcodeproj -scheme AIKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:AIKeyboardUITests/StockKeyboardReferenceTests/testCaptureStockSuggestionBar
```

The `TEST_RUNNER_` prefix is not decoration: `xcodebuild` strips it and forwards the
rest to the test runner, which is why the test reads plain `ONLY_IDS`. The
environment variables it understands:

| Variable | Effect |
|---|---|
| `STOCK_CAPTURE` | Required. Without it the test skips instantly. |
| `CORPUS_PATH` | Required. Absolute path to `corpus.json`. |
| `REF_DIR` | Where PNGs and `raw/` are written. |
| `ONLY_IDS` | Comma-separated corpus ids; everything else is ignored. |
| `RETRY_FAILED` | `1` re-attempts entries already recorded as uncaptured. |
| `ALLOW_LAYOUT_SWITCH` | `1` permits the globe key. Only phase 2 sets this. |

### This does not run with the normal test suite

`AIKeyboardUITests/StockKeyboardReferenceTests.swift` compiles into the UI test
target — `AIKeyboardUITests/` is a `PBXFileSystemSynchronizedRootGroup`, so the file
is picked up with no `.pbxproj` edit — but its one test calls `XCTSkipIf` on the
`STOCK_CAPTURE` environment variable and returns in well under a second when it is
absent. So

```bash
xcodebuild test -project AIKeyboard.xcodeproj -scheme AIKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

still passes and is no slower than before; the capture reports as skipped. The
exclusion lives in the test file, not in the shared scheme, on purpose: it needed no
project change, and nobody can run the slow path by accident.

## How the capture works, and why it works that way

`XCUIApplication(bundleIdentifier: "com.apple.reminders")` launches Apple's
Reminders app and taps its keys. Reminders is the host because its new-reminder row
is one tap away and it needs no account. Every character of `context + prefix` is a
real tap on the system keyboard — the suggestion bar reacts to keystrokes, not to
text, so there is no shortcut here. Between entries the field is emptied with the
delete key.

Two facts shaped everything else, and both were found the hard way.

**Anything that rebuilds the keyboard view kills the test runner.** Not the app —
the runner, mid-tap, with `Test crashed with signal kill`, losing the rest of the
run. That covers the globe key and `more`, the one that opens the numbers plane.
Consequences:

- Punctuation and digits are unreachable. Entries needing them in the *word in
  progress* (`nc-07`, `wl-02`) come out `uncaptured`.
- The apostrophe is skipped instead, because iOS puts it back on the next space,
  which is exactly what a person relies on: nobody opens the numbers plane to type
  "I'll". `skippedCharacters` and `fieldText` record what happened.
- Code-switch entries need the globe, so they run in a **second phase, one
  `xcodebuild` invocation per entry**, where a crash costs one entry instead of
  thirteen.
- Phase 1 writes a placeholder record for an entry *before* typing it, so a crash
  cannot put the retry loop into a livelock re-attempting the same entry forever.

**The AI Keyboard is temporarily removed from the simulator's keyboard list.**
`capture.sh` parks it at the start and restores it on exit, including on failure.
This is a precaution that removes one variable, not a proven fix — see below.

### The one that took the longest to find

During a UI test the runner looks to iOS like an attached hardware keyboard, so the
software keyboard is minimised: every key still exists in the accessibility tree,
but at `y≈959` on an 874-point screen, and every tap computes a hit point of
`{-1, -1}`. Screenshots come back with no keyboard in them at all and nothing says
why. Undoing it takes two switches, both of which `setup-simulator.sh` handles:

- the Simulator's **I/O ▸ Keyboard ▸ Connect Hardware Keyboard** menu item, which
  only affects the running device and has to be clicked, not written to a plist;
- the device's own `AutomaticMinimizationEnabled` preference in
  `com.apple.keyboard.preferences`, which is what ⌘K toggles.

If the capture still reports the keyboard off-screen, the device is holding a
minimised keyboard from an earlier session and needs a reboot:

```bash
xcrun simctl shutdown "iPhone 17 Pro" && xcrun simctl boot "iPhone 17 Pro"
```

### Two things that do not work, so nobody has to try them again

**Pasting the context.** It would be faster and would keep the context
byte-identical, but long-pressing a reminder's title opens the *row* context menu
(Delete, Mark as Completed, Due Date, Priority, Cut, Copy) — never Paste.

**`typeText`.** It does insert the text, including Hebrew while the English layout
is up, which looked like the answer to code-switching. But the suggestion bar does
not react: after `typeText("צריך לסגור את ה")` the bar still showed the
empty-field defaults `זה · לא · אני`. Text inserted that way never reaches the
keyboard's prediction engine, so a reference built on it would be a picture of
nothing.

### Running two UI tests on one simulator

Concurrent `xcodebuild test` runs against the same device kill each other's
runners. If a capture reports `Early unexpected exit … while preparing to run
tests`, check whether something else is driving the same simulator before
believing any of the failures.

## The keyboard-switch crash, and what it is not

Tapping the globe key on the system keyboard, from a UI test driving another app,
kills the XCUITest runner. This is the single fact that shaped `capture.sh`, so it
is worth being precise about what was and was not established — particularly
because the first version of this note blamed the wrong thing.

**What happens.** The test taps or long-presses `app.buttons["Next keyboard"]`
inside Reminders. The log reaches `Synthesize event` and stops. `xcodebuild` then
prints `Restarting after unexpected exit, crash, or test timeout`. The
`AIKeyboardUITests-Runner` process is gone; Reminders itself is still running and
still has a focused field. Everything not yet written to disk is lost, which is why
each entry is claimed in `reference/raw/` before it is typed.

**It is not specific to this project's keyboard extension.** The first four
crashes all happened with `com.nitai.aikeyboard.keyboard` in the simulator's
`AppleKeyboards` list, which made the extension look like the cause. Removing it
and re-running produced one clean success — the globe picker rendered and was
screenshotted. That success did not hold: with only Apple's keyboards installed,
the very next capture run died at the same globe long-press, and later runs died
the same way on **`more`** (the numbers plane) and on **shift**. Three different
keys, no third-party keyboard anywhere. What they share is that each one rebuilds
the keyboard view.

**So the honest read is a testing constraint, not a shipping bug**, and the
extension was never shown to be involved. Two things in particular were never
observed: the keyboard actually switching *into* the AI Keyboard — the runner died
at the tap, before any layout change was visible — and therefore the extension
being loaded at all. There is no evidence here that `AIKeyboardExtension` crashes
anything.

**What would settle it**, for anyone who wants to close this properly:

1. Drive the same globe tap by hand in the simulator, no XCUITest involved. If the
   keyboard switches cleanly into the AI Keyboard, the extension is fine and this is
   purely an automation constraint.
2. Re-run the globe tap under XCUITest on an idle machine. Every crash here happened
   at load average 12-16 with other agents building, and XCUITest kills a runner it
   thinks has timed out. A quiet machine separates "rebuilding the keyboard view
   breaks the automation session" from "the tap took too long and got reaped."

Until one of those is done, treat the constraint as real and the extension as
unaccused. `capture.sh` still parks the AI Keyboard for the duration, because the
globe cycles through every installed keyboard and there is no reason to leave a
third-party one in the cycle while capturing Apple's behaviour. That is hygiene, not
a fix.

## What a critic should do with this

For each corpus entry, put the same `context` and `prefix` into the AIKeyboard bar
and read its three slots. Then ask **two** questions, not one:

1. **Is it good?** Against the corpus alone: `intended`, `mustNotCorrect`, or
   `acceptable`. This needs no reference and works today.
2. **Is it better than free?** Against `suggestions` in `reference/manifest.json`.
   This needs the capture, and only some rows have it.

Keeping them apart is the whole point. An engine can offer a genuinely good word that
iOS does not, and question 2 alone would score that as a loss.

The entries worth weighting heaviest are the ones the stock keyboard cannot do at
all — `code-switch`, Hebrew clitic completions — and the ones where it is already
right and the risk is regressing: every `no-correct` entry, and `apos-05`,
`apos-06`, `apos-09`, where correcting is a coin flip and confidence is the wrong
answer.

Rows marked `uncaptured` are not evidence in either direction. Judge those on
question 1 alone; do not read a missing reference as the stock keyboard failing.
