# Suggestion bar — handoff for the next agent

Read `.claude/rules/suggestion-bar.md` and `Bar/typing/README.md` before any
edit. Keyboard UI lives in `Packages/AIKeyboardCore/`, not the extension.

**Status 2026-09-02: tasks 1, 2 and 4 below are done; task 3 remains, and tasks 5 to 7 were added by the 2026-09-02 engine review (`674598f7`). They live here rather than in Linear because the workspace is at its free-plan issue cap.**
The opening warning this file used to carry — two local-tier changes on `main`
never run on a simulator — was retired on 2026-08-24 by NIT-11's proof:
ContextAwareSuggestionTests 75/75 green including the five tests named under
Task 1, and the harness at 73/76 twice with identical failing sets. Task 2
(first backspace undoes autocorrect) shipped earlier and was hardened on
2026-08-25: the claim check is an exact snapshot built locally from the
pre-write context (never a post-write proxy read — see the rules file), plus a
selection guard and a document-switch clear. Task 4's offer-only proximity
re-rank ships too (`KeyProximity`, +50 on adjacent-key offers, commits
untouched). The task texts below are kept for their reasoning and their
do-not-do lists, which still bind.

## Task 1 — Prove what is on main

Needs a Mac and a booted iPhone simulator. Do not drive the simulator to look;
build and run the commands, then stop.

```bash
# Unit tests that reject the old defaults
xcodebuild test -project AIKeyboard.xcodeproj -scheme AIKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:AIKeyboardCoreTests/ContextAwareSuggestionTests

# Prefer UDID if two Pro devices are booted (see .claude/docs/testing.md).
# Never run two xcodebuild test invocations against one device.

# Corpus — two runs each side before believing a delta
Bar/typing/harness/run.sh            # keep this JSON
# stash / checkout the PR, run again
Bar/typing/harness/score.py before.json after.json
```

**Pass**

- New tests green: `testAnAmbiguousUnfinishedStemIsNotCommitted`,
  `testContextPicksTheNounReadingOfAnAmbiguousStem`,
  `testSeedFollowersReadTheWholeFieldNotOnlyTheLastWords`,
  `testACollocationEarlierInTheFieldStillRanksTheCompletion`,
  `testNextWordReadsEarlierPairsInThisSentence`.
- Existing ContextAware / SuggestionEngine / PersonalDictionary / IdleTyping
  tests still green. `sched` still commits `schedule`. `helo` still offers
  `hello`. `See you\n` still does not predict `tomorrow`.
- Harness headline does not drop below the current **72/76**. `en-comp-03`
  should stop failing commit (`response`, not `respond`). `apos-09`,
  `typo-10`, `typo-11` staying red is expected.
- Two identical-code runs of the *same* side still 72/76. A slot-2 flip on
  `he-comp-04` / `he-comp-05` is `UITextChecker` noise, not a regression.

If the headline drops, stop. Do not “fix” it by loosening `commitReason`.
Read the per-entry diff.

If task 1 is green, this slice is done. The rest is new work on a new branch.

## Task 2 — First backspace undoes autocorrect

Highest-value remaining change. Gboard and the system keyboard restore the
literal keystrokes when the user deletes immediately after space committed a
correction. We delete the space and leave the wrong word.

**Shape**

- Remember `(original, replacement)` only when `insertSpace` actually swapped.
- The next `deleteBackward` that would eat the trailing space restores
  `original` (and removes the space). Do not leave the replacement standing.
- Do not repeat that swap on the same spelling this session
  (`deletedWordPrefix` is the existing “this word is a hand repair” signal;
  extend it or add a small session set — do not add timestamps to
  `PersonalLanguageModel`).
- A later word, a caret jump, Return, a tapped candidate, or a new space
  clears the pending undo. A flag that outlives the word will suppress
  autocorrect on something nobody touched — same trap as the prefix snapshot
  in `isCorrectingWordByHand`.
- Offered candidates stay. Only the automatic replacement is undone.
- Autocorrect-off must not grow a new path; there was no swap to undo.

**Read first:** the `deleteBackward` / `isCorrectingWordByHand` /
`deletedWordPrefix` bullets in `.claude/rules/suggestion-bar.md`.
`CandidateCommitTests` is the suite that already pins “delete then space must
not put the correction back.” Add cases there, each with a control half that
*types* the same word, so a build that simply turns autocorrect off fails them.

**Do not** use `revertibleEdit` for this. That slot is Fix / Rewrite.

## Task 3 — Score the async tier (only if asked, or after 2)

`PredictiveRefiner` is unit-tested for guards and staleness. Its *quality* is
not measured. The typing corpus is 90 synchronous moments with no pauses.

A second corpus, same JSON shape as `Bar/typing/corpus.json`, entries that
include a pause and optional live screen context. Run it at least twice per
side. Do not quote a single-run total. Do not claim the local 72/76 moved
because the model did.

## Task 4 — Key-neighbour ranking, offers only (only if asked)

Fat-finger substitutions are real. **Do not commit them.** A same-length
substitution is a word still being typed (`מכונ` → `נכון`). Space still
commits a same-length neighbour only when `SeedLanguageModel.isTransposition`
says so.

Proximity may re-rank which correction is *offered*. Use the letter rows in
`KeyboardLayout` / `LetterLayouts`. No capacitive heatmaps — not a public
keyboard-extension API. Run the harness twice. Headline must not drop.

## Do not do

- Do not put `were` in the contraction table. `apos-09` is the async tier.
- Do not commit `תדוה` / `שלמו` just to close `typo-10` / `typo-11`. Apple's
  Hebrew checker accepts those typos; being conservative is the product.
- Do not let the Hebrew space-bar override (`commitReason` followers
  check) read the whole field. Ranking already does. Replacing a real Hebrew
  word because `בעוד` appeared earlier is the defect that rule exists to stop.
- Do not add timestamps or a ring buffer to `PersonalLanguageModel`. Two
  counters, nothing readable as a message.
- Do not vendor Hspell (AGPL) or invent seed lists for the other twelve
  languages.
- Do not lower the four-letter gate to three.
- Do not reorder `controller.suggestions` to put the default in the middle.
  Drawing order is `SuggestionBar.centeredSlots`.
- Do not drive the simulator to verify (`simctl io`, clicks, XCUITest you
  started). Build, then stop.
- Do not treat one corpus run as evidence.

## Files that own this area

| Change | Start here |
|---|---|
| Ranking, commit, completions | `SuggestionEngine*.swift`, `SeedLanguageModel.swift` |
| Space / delete / learn | `KeyboardController+Suggestions.swift`, `KeyboardController+Typing.swift` |
| Pause / model | `PredictiveRefiner.swift` |
| Tests | `ContextAwareSuggestionTests.swift`, `CandidateCommitTests.swift`, `IdleTypingTests.swift` |
| Score | `Bar/typing/harness/run.sh`, `score.py`, `corpus.json` |
| Traps | `.claude/rules/suggestion-bar.md` |

New findings go in that rule file, not in `AGENTS.md`.

## Task 5 — Contractions with an ordinary reading (only if asked)

`SuggestionEngine.contractions` commits `its` → `it's`, `ill` → `I'll` and
`lets` → `let's` at confidence 98 on every space. Three `must-not-correct` rows
measure the cost (`en-nc-05` to `en-nc-07` in `Bar/typing/typos/typos.json`,
all WRONG by design); `apos-05` and `apos-06` in the frozen 90 measure the other
side. **Decision on 2026-09-02: leave the table.** Removing `its` and `ill`
trades the two controls for those two entries one for one, and neither word
list carries an apostrophe form, so there is no frequency to break the tie.

The fix that would settle it is the previous word, not a price: `wagged`,
`feel` and `he` each decide the reading on their own. Shape: a small
previous-word table applied only to the ambiguous rows, one corpus row per
signal. `lets` alone could leave the table for free (no corpus row wants
`let's`), but one row is not a reason to move. Do not lower the price for the
whole table; the other seven apostrophe rows are 7/7.

## Task 6 — Touch geometry into the typo channel (only if asked)

`TypingTouchTrace` is spent only on ranking (`score` adds up to 250 for
`touchSupport`, neighbours only). `TypoChannel.substitutionCost` charges a flat
55 for any adjacent key, and cost plus count are what price
`CommitReason.frequency`. Pricing a substitution toward the key the finger
leaned into below 55 would move commits on the motor-slip class without the
global adjacent-cost cut NIT-154 records as a trap.

Before code: the typos corpus has no touch traces, so each pair needs a
synthesised trace plus a centred-evidence control set; `TypoChannel.cost` is a
pure function of two character arrays and the harness copies `KeyProximity.swift`;
`frequencyConfidence` is keyed on exact cost values and would need re-probing
with `Bar/typing/typos/reasons.sh`. Two runs per side on all three corpora,
headline not below 73/76 and 88 / 16 / 3.

## Task 7 — The letter after an autocorrect undo arrives shifted (bug)

`PendingAutocorrectClaimTests.testImmediateAutocorrectUndoDiscardsTheStagedLearning`
fails on pristine HEAD with `("heloW") is not equal to ("helow")`: type `helo`,
space, backspace (undo restores `helo`), type `w`, and it lands as `W`. Something
on the undo path arms shift; `undoAutocorrectIfPending` goes through
`replaceCurrentWord`, so `armShiftAtBoundary` or the field's autocapitalization
adoption is the place to look. User-visible mid-word capital. Not chased.
`MissingSpacesTests.testAPrematureFinalFormMovesAcrossExactlyOneSpace` is the
other newly noticed pre-existing failure; decide whether it is a defect or a
stale fixture. Both are listed in `.claude/docs/test-suite-state.md`.

