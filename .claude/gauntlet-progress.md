# Gauntlet — suggestion bar / autocomplete

Started 2026-08-24. Lead session: Claude Code (ultracode). User approved: run on main,
targeted unit suites allowed (CandidateCommitTests, PersonalDictionaryTests,
SuggestionEngineTests, ContextAwareSuggestionTests, IdleTypingTests; never the full suite).

## Goal

Three complaints from daily use, plus a sweep:
1. Hebrew slips ride through the space bar uncorrected (NIT-154 is the open ledger).
2. Accepting a candidate can leave two spaces when a space already follows.
3. A token typed every day (e.g. the owner's email address) is never learned or offered.
   Generic mechanism, nothing keyed to a specific string. NIT-182 names the Full Access gate.
4. Fresh-eyes bug/overengineering hunt across the suggestion area, adversarially verified.

## The bar

- `Bar/typing/typos/run.sh` — shipped baseline 85 committed / 19 held / 3 WRONG / 95 offered,
  controls 21/21. WRONG and controls may never worsen.
- `Bar/typing/harness/run.sh` + `score.py` — frozen 90, shipped 73/76, mustNotCorrect 12/12. May not drop.
- `Bar/typing/sweep/run.sh` — 612 held / 50 on track / 2 diverged / 0 non-words. Non-words stay 0.
- `Bar/typing/reference/manifest.json` — the stock keyboard's answers.
- Two runs per side, per-entry diffs, never totals. Instruments are serialized (shared output files).
- Controller-layer behavior (spacing, learning): macOS replica probes per `.claude/docs/testing.md`
  (both directions), plus the allowed targeted suites.

House rules: `.claude/rules/suggestion-bar.md` read in full before edits; the Do-not-do list in
`.claude/docs/suggestion-bar-next.md`; no simulator driving; main only; no worktrees; the dirty
files AppComponents.swift / HomeView.swift / SetupState.swift / IMPROVEMENTS-2026-08-22.md are
another session's and are untouched.

## Pieces

| # | Piece | State | Rounds |
|---|---|---|---|
| 1 | Hebrew misspelling commit quality (shipped level) | traced, build queued | scout ✓ |
| 2 | Spacing on candidate accept (double-space) | traced, build queued | scout ✓ |
| 3 | Generic learning of off-dictionary tokens (emails) | traced, build queued | scout ✓ |
| 4 | Bug/overengineering sweep | 2 of 4 lenses done, 2 re-running | scout (partial) |

## Scout results (2026-08-24)

**Piece 2 root cause:** `apply(_:)`'s non-selection branch unconditionally `insertText(" ")`
(KeyboardController+Suggestions.swift:486); nothing on the accept path reads `contextAfter`.
Fix: skip the insert and `adjustTextPosition(byCharacterOffset: 1)` when the after-caret text
starts with a plain space; shared helper also covers the grouped idle path (:376). Must NOT touch
`insertSpace` (pendingAutocorrectUndo assumes "replacement + space"). Verified in source.

**Piece 3 root cause:** `PersonalLanguageModel.record()` letters-only gate (line ~314) refuses
`@`/digits/dots, so an email is never stored; the offer path (words(startingWith:), Source.learned)
would already surface it. Fix: verbatim-token classifier admitting the email shape, skip bigram
write, require 3 sightings to surface; companion commit-exclusion in `commitReason` so space can
never auto-commit a non-letter token; matchCase guard. SecureField gate already wired. Verified.

**Piece 1 plan:** (a) pack (cost,count) lexicographically into TypoChannel's banded DP Int cells
(cost*16+count; ties are real: 40+20=60 vs transposition 60; argmin-following count matrix is
unsound) — zero behavior change alone; (b) split frequencyConfidence: count==2 && cost==110
(two 55-tier slips = displaced-hand motor error) priced by reasons.sh measurement, predicted +3
committed (דוגמטןת, thsnkd, wprkinh) with WRONG staying 3; (c) probe corpora for pricing width and
the stacked-clitic exposure. reasons.sh baseline: 2 identical runs captured.

**Piece 4 confirmed findings (skeptic-verified):**
- BUG high: adoptOpenWord learns word fragments on caret-only moves (Suggestions.swift:217).
- BUG high: stale empty-prefix refinement lands over a selection, re-marks a bold default (:258).
- BUG med: partial-word selection draws bold next-word predictions; space destroys the selection (:138).
- BUG med: pendingAutocorrectUndo suffix test is position-blind (Typing.swift:546).
- DEAD high: commitTrustsReading's .checker branch unreachable (Completions.swift:1426).
- DEAD high: SuggestionBar.isEnabled zero readers; anyActionCouldRun keep-comment false.
- DEAD high: refiner screen-context ternary not flag-gated (gate, do not delete: flags-not-deletions).
- OVER med: applyRefinement's one-entry `held` dictionary is dead generality (:261).
- DEAD med: TypoLexicon.Correction.rank written, never read.
- OVER med: isTransposition duplicates isOneEditApart's equal-length walk (SeedLanguageModel).
- REFUTED: final-form triplication (HebrewMorphology.finalForms is already the single source).

correctness + perf finders re-ran clean on resume (19 agents, 0 errors). Union across both runs:
**20 skeptic-confirmed findings**, 14 unverified (medium), 1 refuted. The additional confirmed set:
- BUG high: openWord survives a refused credential field, learned under the next field's permission.
- BUG high: backspace over a selection fires the autocorrect undo (delete + resurrect elsewhere).
- BUG high: pinningDefaultToTypedIfNeeded guard order leaves a bold, mislabelled default over a
  selection with an empty scoring prefix (two variants confirmed).
- BUG high: undoneAutocorrectSpellings is invisible to the bar, which bolds a correction the
  space bar will refuse.
- BUG high: KeyboardController.init runs a full refreshSuggestions (model call + possible lexicon
  builds) before the first frame (NIT-191 confirmed).
- PERF high: applyRefinement republishes suggestions unconditionally (4-6 full-keyboard publishes
  per keystroke on a refiner cache hit).
- DEAD high: PredictiveRefiner.tail(of:) is an identity shell; SuggestionEngine.script(of:among:)
  is a one-caller alias; screen-context ternary not flag-gated; SuggestionBar.isEnabled dead.
Unverified tail (perf mediums: contextFollowers whole-store scan, rank() score-in-comparator,
neighbourWords duplication; bug mediums: geresh/ZWNJ words never learned, pendingAutocorrectUndo
cross-document survival, complete-on-pause re-applies an undone swap; overengineering mediums).

## Build phase (sequential on the one tree)

Order: A double-space → D confirmed controller bugs → B verbatim-token learning → C Hebrew
count+split → E confirmed cleanups. Fresh critic after each.

**Piece 2 (double-space): BEATS THE BAR after 2 rounds.**
Round 1: fix + 5 tests, but the critic caught the rewired else branch also serving range
selections — SelectedWordSuggestionTests.testAMultiWordSelectionIsReplacedExactlyAsItStands
went red (the hop fired over `say ⟦hello world.⟧ now`).
Round 2: hop scoped to caret-only commits (hadSelection read before replaceCurrentWord; range
selections keep the pinned unconditional space; whole-word branch and insertSpace byte-identical).
34 tests green in one invocation (CommittalSpaceHopTests 6/6 incl. a rejector the round-1 build
fails, CandidateCommitTests 17/17, SelectedWordSuggestionTests 11/11); rejectors destructively
proven both rounds; grouped idle site safe by performIdleTyping's selection==nil guard.
Known recorded follow-up (deliberate, separate change): caret strictly mid-word still orphans
the after-caret tail ("The te|h quick" + tap → "The the h quick").

**Piece D (8 confirmed controller bugs): BEATS THE BAR after 2 rounds.**
Round 1: all 8 fixed (two with justified redesigns: openWordPermitted captured at adoption
instead of a blanket clear; init passes schedulingRefinement:false instead of a document-state-only
refresh, since several tests read controller.suggestions straight after construction). 13 new
tests across 5 files; 210/211 green (the 1 failure is the pre-recorded PersonalDictionaryTests
UITextChecker variance, test-suite-state.md line 21). Critic accepted 7/8 and caught that the
undo snapshot was a post-write proxy read — the exact staleness window the repo's own comments
document — which would silently kill the shipped backspace-undo on real devices.
Round 2: snapshot now BUILT locally (pre-write context minus original + replacement + " ");
StaleEchoTarget fixture added; new rejector destructively proven both directions; critic verified
the arithmetic through edge marks (restoringEdgeMarks symmetry) and Hebrew graphemes. 44/44 green.
Known disclosed limits: local-tier engine work still runs pre-frame in init (refiner call is
gone — the confirmed harm); a host whose proxy stays stale across several reads can still expire
the undo early, byte-identical exposure to the shipped design.
Process note: builder used git stash/pop once in round 1 (against standing rules); verified
harmless — the three foreign dirty files and the untracked notes file kept their diffs, stash
list empty. Explicitly forbidden in every later builder brief.

**Piece B (verbatim-token learning): BEATS THE BAR after 2 rounds.**
Round 1: record() gains isVerbatimToken (email shape, no bigram write) + isLearnableOrdinaryWord
(geresh/gershayim/interpunct/ZWNJ, mirrored into the bigram half); 3-sighting floor on all three
read surfaces; commitReason winner guard; matchCaseUnlessVerbatim; staysInsideWord moved into
SuggestionEngine (harness compiles no controller); 11 tests; instruments byte-stable. Builder
measured that letter+ZWNJ merges into one grapheme (old gate never refused the attached form) and
wrote the honest standalone-ZWNJ rejector instead. Critic confirmed classifier both directions,
guard placement below every displacing rule, GroupedDecoder feed safe (no key codes for @/digits),
paste needs a terminator + 3 sightings, Forget visible from sighting 1 — and found the gap:
Complete-on-pause auto-pasted the learned address over its own local part (no tap, no guard, and
recordCommittedWord counted the paste as a sighting), plus plain matchCase re-casing through the
neighbour door.
Round 2: one shared predicate SuggestionEngine.isAutomaticallyInsertable behind BOTH commitReason
and idleCompletion (falls through to next legitimate candidate); neighbour mapping through
matchCaseUnlessVerbatim; PII trade + both classifier decisions documented. Critic audited every
replaceCurrentWord/insertText writer: no automatic door remains. 81/81 green; frozen90 73/76 same
set; typos 85/19/3, controls 21/21.

**Piece C (Hebrew edit-count + measured split): BEATS THE BAR (+ micro round for 2 doc/test nits).**
Stage 1 (zero change, proven): packed lex (cost,count) DP — packed = cost·16+count, count ≤ 6 in
any budget, collisions unreachable-by-construction, all cost comparisons unpacked, TypoLexicon
sort stays cost-only. reasons.sh byte-identical to baseline; frozen90/typos/sweep unmoved; the
critic also took the one reading nobody had: AUTOCORRECT_LEVEL=full still 90/7/10.
Stage 2 (measured): reasons.sh extended with channelCost/editCount columns; the (110,2) cell reads
3 right / 0 wrong in the corpus and 8/0 in a new 25-pair probe (Bar/typing/typos/probes-motor2/,
adjacencies verified against the real Hebrew rows) — 11/11 across two independent corpora; priced
87 (the singleEdit evidence class). **Shipped result: typos 88 committed / 16 held / 3 WRONG,
controls 21/21, two runs a side; the three moved rows are exactly דוגמטןת→דוגמאות, thsnkd→thanks,
wprkinh→working.** Frozen90 73/76 same set; sweep 0 non-words 0 moved. Structural bonus from the
critic's enumeration: no (110,2) path can contain a wild 100-cost edit, so the class is two
explainable slips by construction. NIT-154's traps all intact (verified by diff grep).
Out-of-scope finding for the wrap-up: three mater-drop-double probe rows resolve WRONG through the
pre-existing cost≤60 tier (untouched here). Micro round 2 closed both nits (doc corrected; the
(120,2)-below-floor pin destructively proven against the sloppy signature).

**Piece E (8 confirmed cleanups): BEATS THE BAR, one round.**
isEnabled + anyActionCouldRun deleted (D8 tests repointed at AIAction directly — the forwarding
shell's own doc was false); tail(of:) deleted with its identity test replaced by an end-to-end
whole-context rejector; the refiner's screen-context ternary flag-gated (not deleted); script alias
inlined; the unreachable .checker fence deleted with docs corrected; Correction.rank dropped;
applyRefinement's held dictionary replaced by a seeded loop (D's guards preserved, traced over
three pool shapes); isTransposition/isOneEditApart share one classifier (decision-table traced).
Critic re-greped every deletion, attributed every hunk in the shared files, re-ran instruments.

## Final state (2026-08-25)

- App build: ** BUILD SUCCEEDED **.
- Mega suite (20 test classes, one invocation): 281 executed, 4 skipped (flag-gated, expected),
  **1 failure = exactly the pre-recorded PersonalDictionaryTests UITextChecker variance**
  (test-suite-state.md line 21). No Fatal error / Restarting lines.
- Typos shipped: **88 committed / 16 held / 3 WRONG, controls 21/21** (baseline 85/19/3).
- Typos full: 90/7/10, controls 21/21 — unmoved from the recorded baseline.
- Frozen 90: 73/76, failing set {apos-09, typo-07, typo-12} — unmoved, many runs.
- Sweep: 664 moments, 612 held / 50 on track / 2 diverged, **0 non-words**, 0 run-to-run movement.
- Docs refreshed: README numbers (85→88 + the new price row), suggestion-bar-next.md status header
  (tasks 1/2/4 done, task 3 = NIT-179 remains), rules file grew 12 bullets across the pieces.
- Linear: NIT-11 proven + In Review; NIT-154, NIT-191, NIT-182 commented. Nothing committed to git.

## Recorded, deliberately not done (candidates for new issues)

1. Mid-word candidate tap orphans the after-caret tail ("The te|h quick" + tap → "The the h quick").
2. mater-drop-double corrections resolve WRONG through the cost≤60 frequency tier (measured, probe).
3. Keystroke-path perf trio, scouted but unverified: contextFollowers whole-bigram scan per token,
   rank() score-in-comparator (~10x refolds), neighbourWords computed twice per unknown keystroke.
4. A partial-word selection still keeps a live bar whose taps type over half a word (the default
   and hint are fixed; the tap path remains).
5. init's local-tier pre-frame work (the refiner half is fixed; NIT-191 stays open for this).
6. Overengineering mediums unverified: commitReason's continuation predicate spelled three ways;
   the idle-typing cancel+reset triple copied four times.

## Log

- 2026-08-24: Run approved. Baselines being captured; scouts dispatched (read-only, no
  instrument runs, no edits).
- 2026-08-24: Baselines reproduce the recorded numbers exactly, two runs per side:
  frozen 90 = 73/76 twice (identical failing sets: apos-09, typo-07, typo-12);
  typos = 85/19/3 WRONG, 95 offered, controls 21/21, stable 128/128;
  sweep = 664 moments, 612 held / 50 on track / 2 diverged, 0 non-words, 0 run-to-run movement.
  Per-class holes for piece 1: he adjacent-2 (0/5 committed, 1/5 offered), he mater-drop (2/6),
  12 corrections never offered by any source.
- 2026-08-24: NIT-11 proven green: ContextAwareSuggestionTests 75/75 passed (real SUCCEEDED
  banner, no Fatal error / Restarting lines), all five named tests passed, harness ≥ 72/76 twice,
  en-comp-03 commits `response`. Logs in scratchpad/baseline/.
