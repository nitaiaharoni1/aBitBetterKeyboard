# Suggestion bar — handoff for the next agent

Do this work in order. Do not start task 2 until task 1 is green. Read
`.claude/rules/suggestion-bar.md` and `Bar/typing/README.md` before any edit.
Keyboard UI lives in `Packages/AIKeyboardCore/`, not the extension.

These two local-tier changes are on `main` and have **not** been run on a
simulator:

1. Space no longer finishes an unfinished English stem (`respon` is
   `respond` / `response` / `responsible`). `schedule` / `scheduled` still
   commits. Context can still pick (`the quick` → `response`).
2. Ranking walks the whole field (`contextFollowers` /
   `followers(mentionedIn:)`), not only the last two words. Next-word stays
   inside the current sentence. A newline or full stop still closes the thought.
   Learning pairs still use `previousWords` (limit 2).

A Linux replica of the seed lookup passed 17/17 on those cases. That is not a
simulator score. Task 1 is proving what is on `main`, not rewriting it.

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
