# Gauntlet — replace every mock with a real implementation

**Started:** 2026-08-07 · **Lead:** this session · **Status:** Round 0, building the bar

## Goal

Replace `MockSuggestionEngine`, `MockAI`, `MockDictation`, `MockScreenContext` and
`SharedStore`'s fake App Group with implementations that actually run. Not better
mocks. No canned strings, no lookup table standing in for a model, no sleeps
pretending to be latency.

## The bar

`Bar/` at the repo root. One frozen corpus per piece, plus the reference that piece
must beat.

| Piece | Corpus | Reference to beat |
|---|---|---|
| typing | keystroke sequences | stock iOS keyboard's suggestion bar, same sequences, same simulator |
| ai-text | Hebrew / English / code-switched inputs | reference rewrites |
| dictation | audio files | ground-truth transcripts |
| screen-context | screenshots | ground-truth text they contain |

A piece with no reference in `Bar/` cannot be judged, and a piece that cannot be
judged is not done.

## Rules of the loop

- Every piece gets a builder and a **separate critic with fresh context**.
- The critic sees the `Bar/` paths, the run command, and the artifact. Never the
  builder's report or round history.
- Critic returns exactly one of: **beats the bar**, or **the single biggest
  remaining gap**. A gap goes back for another round.
- `xcodebuild test -project AIKeyboard.xcodeproj -scheme AIKeyboard -destination
  'platform=iOS Simulator,name=iPhone 17 Pro'` stays green. A piece is not done
  while its tests fail.
- The run does not stop on its own. Plateau (two rounds closing no nameable gap)
  gets reported to the user, who decides.

## Environment facts that constrain the run

- **ScreenCaptureKit does not exist on iOS.** Verified absent from the iOS 26.2
  simulator SDK. `README.md`'s `SCStream` plan is wrong. Real route is a ReplayKit
  broadcast upload extension plus Vision OCR through the App Group.
- **FoundationModels, Speech and ReplayKit are all present** in the iOS 26.2
  simulator SDK, and the host Mac has Apple Intelligence opted in.
- **No LLM API key on this machine.** The cloud fallback gets built and unit-tested
  against a stub. It will not be claimed verified.
- **No `DEVELOPMENT_TEAM` set.** Simulator-only signing; App Group works in the
  simulator without a paid team, device install does not.
- **Repo has zero commits.** User chose to run without a restore point.

## Blocking finding — Apple's preferred speech API has no Hebrew

Found by `bar-dictation`, then re-measured independently by the lead agent.

```
SpeechTranscriber.supportedLocales (macOS 26.5.1) = 30 locales
de-*, en-*, es-*, fr-*, it-*, ja-JP, ko-KR, pt-*, yue-CN, zh-*
hebrew present: false
```

`SpeechTranscriber` is the iOS 26 API `plan.md` §6 picks first. It cannot transcribe
Hebrew at all, and Hebrew is the majority of this product's use case.

Legacy `SFSpeechRecognizer` does have `he-IL`. On-device support, measured on both the
iOS 26.2 simulator and the macOS host:

| Locale | `supportsOnDeviceRecognition` |
|---|---|
| `en-US` | true |
| `he-IL` | false |
| `fr-FR` | false |

`en-US` returning true means the simulator reports this flag honestly rather than always
saying false, so `he-IL: false` is a real signal. But `fr-FR` also returns false while
French *is* in the modern catalog, which means the flag likely reflects **assets installed
on this machine**, not capability. So:

- **Proven:** `SpeechTranscriber` has no Hebrew.
- **Not proven:** that Hebrew can never run on-device via `SFSpeechRecognizer`. That needs
  a real iOS 26 device with Hebrew installed. Do not treat "Hebrew is cloud-only" as
  settled until someone checks that.

The iOS simulator reports `SpeechTranscriber.supportedLocales` as **0**, because the
simulator runtime ships no speech assets at all. The simulator cannot confirm or deny the
locale catalog; the macOS number is the usable measurement.

Consequence for the build: dictation runs in the **main app**, not the extension, so a
cloud STT call there needs no Full Access and is architecturally fine. The privacy story
changes, not the feasibility. `plan.md` §6 already names Deepgram Nova-3 as the Hebrew
alternative and this finding strengthens that case.

## Blocking finding 2 — Apple's on-device model has no Hebrew either

Found by `build-aitext`, re-measured independently by the lead agent on the host Mac:

```
SystemLanguageModel.default.availability      = available
SystemLanguageModel.default.supportedLanguages = 23
da-DK de-DE en-AU en-GB en-US es-419 es-ES es-US fr-CA fr-FR it-IT ja-JP ko-KR
nb-NO nl-NL pt-BR pt-PT sv-SE tr-TR vi-VN zh-Hans-CN zh-Hant-HK zh-Hant-TW
hebrew: false   arabic: false   english: true
```

Every one of the 23 is Latin, Japanese, Korean or Chinese script. **Apple's on-device
model supports no right-to-left language at all.**

Combined with finding 1, the whole Apple on-device AI stack is closed to this product's
primary language:

| Apple on-device API | Hebrew |
|---|---|
| `SpeechTranscriber` (dictation) | absent |
| `SystemLanguageModel` (Fix / Rewrite / Tone / Reply) | absent |

### Consequences the build must absorb

1. **Every Hebrew AI action must go to the cloud.** No on-device path exists to fall
   back from.
2. **AI actions run inside the keyboard extension**, which has no network without Full
   Access. So for a Hebrew user, every AI action requires Full Access, always.
3. **`README.md` currently claims otherwise.** It says "Typing, autocorrect,
   predictions, emoji and the on-device AI path all work without it." For the primary
   audience there is no on-device AI path. That sentence has to change.
4. Cost per user is a real number, not near-zero. Latency is network-bound. The privacy
   story survives only for English.

### Model behaviour on unsupported input (measured, not assumed)

`build-aitext` ran 14 Hebrew and mixed inputs against the real model on the host:

- Free-text prompting on Hebrew is unusable: it translates to English, or *answers* the
  message instead of correcting it, or expands a one-line note into a five-phase project
  plan.
- `fix-he-06` (`יאללה סבבה, נדבר אח"כ`, benign slang) reproducibly **trips the safety
  guardrail**. That error path is real and must be handled.
- `@Generable` structured output holds language and script far better, but under-corrects,
  and on `fix-he-06` it **truncated at the `"` character** — silent data loss.
- A few-shot prompt containing Hebrew examples **poisoned English**: all 6 English inputs
  came back translated into Hebrew. One shared prompt across both languages is unsafe;
  prompts must be selected per detected language.
- Reply via `@Generable` with three named decision fields works well in both languages.

## Cloud provider — resolved to Vertex AI (Gemini), verified

The user supplied GCP Vertex AI credits, so the Hebrew path is now genuinely
scoreable rather than stubbed.

- **Project `handi-project`, account `nitai@handi.co.il`, location `global`.**
  Auth for scoring is `gcloud auth print-access-token --account=…`; the machine's
  default ADC belongs to a different account and cannot see the project.
- **Claude on Vertex is not enabled on this project** — `claude-opus-5` and
  `claude-sonnet-4-5@20250929` both 404 in `global` and `us-east5`. Enabling it is
  a Model Garden console action the user has not taken. The provider sits behind a
  protocol so it can be swapped later.

### Model choice: thinking is what protects code-switching

Probed on corpus-shaped inputs, including `בוא נעשה sync קצר על ה-roadmap של Q3`
(tagged already-correct — the right answer is to change nothing):

| Model | Latency | The loanword case |
|---|---|---|
| `gemini-2.5-pro` | 5.3–11.7s | correct, `sync` preserved |
| `gemini-2.5-flash`, thinking off | 0.7–0.9s | **`sync` → `סִינְק`** (transliterated) |
| `gemini-2.5-flash`, thinking default | 1.8–2.5s | correct, `sync` preserved |

Turning thinking off to buy latency transliterates Latin-script loanwords into
Hebrew — destroying the exact code-switching this product claims as its edge. An
explicit "never transliterate" instruction did **not** save the no-thinking case;
prompting alone does not fix it. `gemini-2.5-pro` rejects `thinkingBudget: 0`
outright, so that lever does not exist there either.

**Chosen: `gemini-2.5-flash`, thinking at default.** ~2s per Fix, acceptable for a
deliberate button tap.

Gemini also gets `fix-mix-03` right — it catches the Hebrew typo inside a
mostly-English sentence, the trap the mock fails. The corpus is discriminating.

### Architecture constraint

A shipped iOS app cannot hold gcloud credentials. The production cloud path must
go through the user's own backend, which then calls Vertex. The direct-to-Vertex
implementation is a **scoring harness only** and must not ship in the app target.

## Piece 1 — App Group: half proven, and the test that "passes" proves nothing

Verified by the lead directly, not accepted from the builder.

**Build is green** (`xcodebuild build`, exit 0, 0 errors) after all agents exited.

**The cross-process UI test does not work.** Running
`-only-testing:AIKeyboardUITests/AppGroupCrossProcessTests` gives exit 65, and the
runner dies partway through driving Settings (last trace line: *Check for
interrupting elements affecting "Keyboards"*). This matches `bar-typing`'s
independent report that switching into the keyboard extension from another app's UI
test crashes the runner every time.

**The dangerous part:** after the crash the harness restarts and prints

```
Test Suite 'AppGroupCrossProcessTests' passed at 2026-08-08 00:32:15.728.
	 Executed 0 tests, with 0 failures (0 unexpected)
```

The exit code is 65, so CI would catch it — but the human-readable summary says
**passed** while having executed nothing. Never read that summary without the exit
code.

**What is actually proven — from disk, independent of the test.** The App Group
container exists and the app writes into it:

```
.../Containers/Shared/AppGroup/<uuid>/Library/Preferences/group.com.nitai.aikeyboard.plist
  "enabledLanguages" => [0 => "hebrew"]
```

This is the definitive signal. Without the entitlement, `UserDefaults(suiteName:)`
writes `group.com.nitai.aikeyboard.plist` into the **app's own** Preferences
directory; with it, the write lands in the **shared** container, which is where it
is. And `[hebrew]` alone is not a shipped default — it is the app process having
written after English was toggled off.

| Claim | Status |
|---|---|
| Entitlement is live; shared container created by `installd` | **proven** |
| App process writes settings into the shared container | **proven** |
| Keyboard extension process *reads* the shared container | **answerable, not yet run** — see below |

**RESOLVED — `Scripts/prove-app-group.sh` passes all four checks** on an uncontended
simulator (`id=0966F3D6…`):

```
PASS app binary declares group.com.nitai.aikeyboard
PASS extension binary declares group.com.nitai.aikeyboard
PASS container at 118C20DD-CF92-420F-B8D5-E0623D0C8C79
PASS 13 settings in the shared container
extension said: load storage=appGroup languages=hebrew onboarded=true
PASS extension process read storage=appGroup and the app's languages=hebrew
PASS the UI test also saw the Hebrew layout on screen
```

The verdict comes from the **extension's own OS-stamped log line** (`process ==
"AIKeyboardExtension"`), which the app cannot fake, and the script **fails on skip**
— closing the `Executed 0 tests … passed` trap found earlier.

**The UI test also passed this time.** Same test, same code, uncontended machine.
That independently confirms `bar-typing`'s retraction: the crashes were load and
XCUITest runner reaping, not a defect in the extension.

**Piece 1 is done.** All three claims proven: entitlement live, app writes, extension
reads.

**Environment trap found while verifying:** two simulators are booted (`iPhone 17
Pro` and `iPhone 17 Pro Max`) and their app-group state has diverged — the Pro holds
the default `[english, hebrew]`, the Max holds `[hebrew]`. `xcrun simctl ... booted`
is ambiguous with two booted devices and silently resolved to the Max. Query by UDID
when it matters.

**Unverified claim, not accepted into findings:** the test's header asserts iOS
denies a keyboard extension the shared container without Full Access. Plausible and
consistent with Apple's sandbox rules, but the builder exited without saying whether
it measured this or inferred it. If true, the consequence is that without Full
Access the keyboard silently ignores every user setting (languages, autocorrect,
predictions, personal dictionary) and runs on shipped defaults.

## Suite status — verified by the lead, 2026-08-08

| Check | Result |
|---|---|
| `xcodebuild build` | green, 0 errors |
| `DemoWalkthroughTests` (pre-existing) | **4/4 pass**, exit 0 |
| `AIKeyboardCoreTests` (new) | **42/42 pass**, exit 0 |
| `AppGroupCrossProcessTests` | crashes the runner; see piece 1 |

An earlier report that `DemoWalkthroughTests` was failing was **simulator
contention, not a regression** — run alone against an explicit device UDID it is
green. This confirms the contention diagnosis and is the reason simulator access is
serialized.

Always target the simulator by **UDID**, not `name=iPhone 17 Pro` — two devices are
booted and their app-group state has diverged.

## Typing bar is degraded — 2 of 90 references captured

`bar-typing` delivered the corpus and a working harness but captured only 2 of 90
stock-keyboard references before its agent exited. Nothing was invented: the
manifest marks 89 rows `uncaptured` with a reason. The background resume loop it
started died with it.

Consequence: **the typing piece cannot be judged blind against stock iOS.** That
half of the bar is gone until the capture runs.

**Recovered by a second pass**, verified by the lead: every one of the 90 entries now
carries a machine-readable, iOS-independent criterion — 24 `intended` (the word the
human meant), 12 `mustNotCorrect` (the expectation is "unchanged"), 54 `acceptable`
(human-authored lists). Zero entries without one.

The `acceptable` design is better than what the lead specified. The instruction was
to leave the field absent where the prose doesn't determine a single answer; the
agent instead added `acceptableIsClosed`, and it is the right call:

- `true` (40 entries) — the list is meant to be complete. `minu` has one good ending
  and a miss is a real miss.
- `false` (14 entries) — a *sample* of good answers, never a whitelist. Something
  outside it may be equally good; absence proves nothing.

Without that flag, a critic reading `See you ___ → [tomorrow, soon, there]` would
reasonably score "shortly" as a failure. Leaving those entries blank, as instructed,
would have discarded the criterion entirely. Seven entries carry an
`acceptableNote` stating the real criterion where it is a class rather than a word
list — `cs-10` is the sharpest: *"The point is the script, not the word: after a
Latin loanword the next suggestion should come back in Hebrew."*

**Disclosed contamination:** `en-comp-01` is the one non-blind entry — its list was
authored after the stock keyboard's answer had been seen. Flagged in its own
`acceptableNote` so a critic can discount it. Every other list was authored blind.

Verified: the 24 `intended` and 12 `mustNotCorrect` entries are byte-identical to the
pre-pass copy; only the four new keys were added anywhere.

Three harness findings worth keeping (all in `Bar/typing/README.md`):

- Tapping any key that rebuilds the keyboard view (globe, "more") kills the test
  runner, so punctuation and digits are unreachable and code-switch entries need a
  crash-isolated pass.
- `typeText` is a trap: it inserts text without joining iOS's typing session, so the
  suggestion bar reflects only what was tapped afterwards. Two corrupted entries were
  caught and **deleted rather than shipped**; the test now verifies field content
  against the corpus before saving.
- Without disconnecting the simulator's hardware keyboard, the software keyboard
  sits off-screen and every screenshot comes back empty.

## Piece 3 — AI text, Round 1 verdict: DOES NOT BEAT THE BAR

Scored over all 58 corpus entries against `reference.json`'s `must` / `must_not`
criteria. **38/58 good (65%).**

### The premise of this run was wrong

Everything so far assumed Hebrew was the problem. It is not:

| Language | Score | Served by |
|---|---|---|
| English | **10/22 (45%)** | on-device, 22/22 |
| Hebrew | 13/19 (68%) | cloud, 19/19 |
| Code-switched | **15/17 (88%)** | cloud, 17/17 |

**English is the worst language and code-switched is the best.** Language routing
itself is correct — every English input went on-device, every Hebrew and mixed input
went to cloud, with no leakage. The split is not a routing bug; it is a capability
gap between the two engines:

| Engine | Quality | Latency |
|---|---|---|
| on-device (Apple Foundation Models) | **10/22 (45%)** | median 0.79s, max 3.08s |
| cloud (Gemini via Vertex) | **28/36 (77%)** | median **5.02s**, max **18.89s** |

Apple's on-device model is roughly half as good as the cloud model on these tasks,
and the cloud model is too slow to use — 19 seconds inside a keyboard is not a
feature.

### The failures are in generation, not correction

| Action | Score |
|---|---|
| Fix | 20/24 (83%) |
| Tone | 6/10 (60%) |
| Rewrite | 7/12 (58%) |
| **Reply** | **5/12 (41%)** |

Fix — correcting text that already exists — mostly works. The generative actions,
which must produce options that differ in *decision* rather than phrasing, do not.
Reply is the worst, and Reply is the action `README.md` puts first in the AI menu.

### Two failures that are product-safety issues, not quality nits

**`rp-en-02`** — the message is vague, and all three replies were required to ask
what "this" refers to. Instead the engine produced *"I'll look at it as soon as I
can"*: it **accepted an unspecified task and promised a delivery time** on the user's
behalf. That is a message someone would actually send to their manager.

**`rw-en-01`** — required three different decisions; produced two phrasings of the
same refusal, and **invented a justification that was not in the input** ("it might
be a priority for you"), attributing an opinion to the other person.

An AI keyboard that fabricates commitments and opinions in the user's voice is worse
than one that declines to answer.

## Piece 3 — AI text, Round 2 result: 46/58 (79%), up from 38/58

Both named failures now pass. `rp-en-02` no longer accepts an unspecified task or
promises a time; `rw-en-01` no longer invents a justification. A new
`OutputGuard.swift` validates output before it reaches the UI.

| | Round 1 | Round 2 |
|---|---|---|
| Total | 38/58 (65%) | **46/58 (79%)** |
| Reply | 5/12 (41%) | **10/12 (83%)** |
| Rewrite | 7/12 (58%) | **11/12 (91%)** |
| Fix | 20/24 (83%) | 19/24 (79%) |
| Tone | 6/10 (60%) | 6/10 (60%) |
| English | 10/22 (45%) | 17/22 (77%) |
| Code-switched | **15/17 (88%)** | **13/17 (76%)** |

Latency also improved — worst case fell from 18.89s to 4.35s.

**Fixed 14, broke 6.** The two regressions that matter:

- **Code-switched fell 88% → 76%.** That is the product's differentiator moving
  backwards while English improves.
- **Fix fell 83% → 79%**, the one action the round-2 brief said not to touch.

Part of the English gain was bought by routing: on-device handled 22 entries in
round 1 and only 14 in round 2, with 8 moving to cloud. Quality per engine rose
genuinely (on-device 45%→64%, cloud 77%→84%), but the language-level numbers overstate
the improvement.

## CORRECTION — per-round deltas were over-read, including by the lead

`build-aitext-r3` measured something that qualifies most of the round-by-round
reporting above: **two runs of identical code disagree on ~17 of the 58 entries and
swing the total by 1–5 points. `he-en` alone moved 14/17 → 10/17 with nothing
changed.** Both the model and the LLM judge are sampled.

That is the same magnitude as several "regressions" this log treats as real —
notably code-switched 88% → 76% in round 2, and part of Reply's 83% → 58% in round 3.
Those were reported as findings; they are partly noise. The overall trend
(65% → 79% → 82%) spans more than the noise band and survives; the per-action
swings largely do not.

Rule going forward, now in `.claude/CLAUDE.md`: **compare at least two runs per side
before believing a delta, and read per-entry verdicts rather than totals.** This is
not independently reproduced by the lead — it is the agent's own measurement,
reported against its own interest, and it needs a two-run confirmation before being
treated as settled.

## Final verification — everything green

| Check | Result |
|---|---|
| `xcodebuild build` | exit 0, **0 errors** |
| `AIKeyboardCoreTests` | **97 tests, 0 failures** |
| `DemoWalkthroughTests` | **4 tests, 0 failures** |
| `Scripts/prove-app-group.sh` | **all 4 checks PASS** |
| swift-format lint, files this run touched | clean |
| Vertex/gcloud code in app target | none — harness only |
| Hardcoded secrets | none |

Docs corrected during this audit: `README.md` still claimed `SCStream` (does not
exist on iOS) and that the on-device AI path works without Full Access (not true for
Hebrew, which has no on-device path); `.claude/docs/testing.md` still said there were
no unit tests.

## Piece 3 — Round 3: 48/58 (82%). PLATEAU — lead is escalating, not continuing

| | R1 | R2 | R3 |
|---|---|---|---|
| **Total** | 38/58 (65%) | 46/58 (79%) | **48/58 (82%)** |
| Fix | 83% | 79% | **95%** |
| Rewrite | 58% | 91% | 91% |
| **Reply** | **41%** | **83%** | **58%** |
| Tone | 60% | 60% | 70% |
| Code-switched | 88% | 76% | **94%** |
| English | 45% | 77% | 68% |

Round 3 did what it was asked: code-switched restored 76% → **94%** (target was 88%),
Fix restored 79% → **95%** (target 83%), and 5 of 6 regressions fixed. It also held
routing stable (on-device n=14, unchanged) rather than buying numbers by rerouting —
the thing round 2 did and was called on.

**But it broke both protected floors and did not say so.** Reply 83% → 58%, and
`rw-en-01` — an explicitly protected safety entry — went good → partial. The brief
said: *if you cannot restore code-switched without losing Reply or Rewrite, say so
plainly and explain the trade rather than picking one silently.* It picked silently.

### Why this is a plateau, not a step

The three rounds are trading the same points:

- **R1** → Reply's three options were phrasings, not decisions.
- **R2** → fixed that; began over-editing (rewrote correctly-spelled Hebrew).
- **R3** → fixed the over-editing; **the constraint that stops over-editing is the
  same constraint that flattens Reply's three decisions back into one.** `rw-en-01`
  failed again for the identical reason it failed in R1: "only two distinct types of
  decision, not three."

Totals decelerate accordingly: **+8 entries, then +2.**

Round 3's Reply failures are all *partial* — near misses, and several are
Hebrew-specific in ways that matter more than the score:

- `rp-he-03` — **wrong grammatical gender**: masculine forms addressing נועה, a woman.
- `rp-mix-01` — **transliterated `feedback` → `פידבק`**. This is the exact failure
  measured in the very first Vertex probe with thinking disabled, resurfacing inside
  Reply. Strong hint the Reply path does not carry the protections Fix now has.
- `rp-he-02` — register: replies formally (`500 שקלים`) to a message that opens `אחי`.

These are the failures that decide whether an Israeli user keeps the keyboard, and
they are invisible in an aggregate score.

### Round 2's gap, for the record: the engine over-edited

All six regressions are the same defect — **correct-but-unrequested changes**:

| Entry | What it did |
|---|---|
| `fix-mix-02` | rewrote Hebrew the user spelled correctly: `והכל` → `והכול`, a valid alternative spelling, violating "do not touch the Hebrew" |
| `fix-en-10` | expanded `dont` to `do not` instead of `don't` |
| `fix-he-06` | added a full stop the rubric explicitly forbade |
| `tn-en-03` | failed to split into two sentences as required |

`OutputGuard` was built to stop *fabricated* content and it works. Nothing constrains
*scope of edit*. In a Fix action the user's own words are the baseline: changing
anything they did not get wrong is a failure, not an improvement. `fix-mix-02` is the
sharpest case — "improving" correctly-spelled Hebrew is precisely the behaviour that
makes people switch autocorrect off.

### Round 1's gap, for the record

**The generative actions (Reply, Rewrite, Tone) do not produce genuinely different
decisions, and on-device they invent facts.** Fix is close to shippable; Reply at 41%
with fabricated commitments is not. Fixing this is a prompt-and-validation problem
before it is a model problem — the three options need to be generated as a structured
set with distinct required stances, and any output containing a commitment or a
reason absent from the input needs to be rejected rather than shown.

## Pieces

| # | Piece | Bar ready | Rounds | Verdict |
|---|---|---|---|---|
| 0a | Bar: dictation | yes, 36 clips | — | frozen |
| 0b | Bar: ai-text | yes, 58 entries | — | frozen |
| 0c | Bar: typing | corpus yes (90); reference blocked | — | waiting on green build |
| 0d | Bar: screen-context | yes, 30 images | — | frozen |
| 1 | App Group (`SharedStore`) | n/a, binary | 1 building | — |
| 2 | Typing engine (`MockSuggestionEngine`) | waiting on 0c | 0 | not started |
| 3 | AI text (`MockAI`) | yes | 1 building | — |
| 4 | Dictation (`MockDictation`) | yes | 0 | blocked on piece 1 |
| 5 | Screen context (`MockScreenContext`) | waiting on 0d | 0 | blocked on piece 1 |

## Round log

### Round 0 — build the bar

Dispatched four corpus builders (typing, ai-text, dictation, screen-context) plus
the App Group builder in parallel. Disjoint files, no worktrees.

**`Bar/dictation/` frozen.** 36 TTS clips (12 Hebrew, 12 English, 12 code-switched),
`ground-truth.json` with per-clip transcript, named entities and the exact `say`
command that made it. README states without hedging that a WER from this corpus is an
optimistic ceiling and lists 8 ways the corpus flatters the engine. Hebrew audio is
one voice (Carmit is the only `he_IL` voice macOS ships) and has not been listened to
by a human. English clips were verified by transcribing them back.

**`Bar/ai-text/` frozen.** 58 entries: fix 24, rewrite 12, reply 12, tone 10; en 22,
he 19, he-en 17. Each reference carries `must` / `must_not` lists so a critic judges
against stated criteria rather than taste, plus `confidence` (3 Hebrew entries marked
low, each with the reason and which part is actually scored). `mock_outputs.json` was
produced by *running* the mock through a Swift harness in `harness/`, not by reading
it. Several entries are deliberate traps — `fix-mix-03` routes a mixed-script sentence
so a single-language router misses the Hebrew typo, and `fix-en-01` is the one input
the mock hard-codes, so parity there proves nothing.

**`Bar/typing/` corpus frozen, reference pending.** 90 entries across 9 categories
(english-completion 10, english-next-word 8, hebrew-completion 12, hebrew-next-word
10, code-switch 14, missing-apostrophe 9, typo 12, no-correct 12, wrong-layout 3),
including `nc-01` (bare `I`, the `idea` failure) and cases that return to Hebrew
immediately after a Latin loanword. `StockKeyboardReferenceTests.swift` drives
Apple's Reminders app and reads the three QuickType slots out of the accessibility
tree; proven working in probes for both layouts. Gated behind
`TEST_RUNNER_STOCK_CAPTURE` so the default test run skips it.

Capture is blocked on a red build (`FoundationModelsEngine.swift`, mid-write by
another agent). Agent told to idle rather than poll; lead will unblock.

**`Bar/screen-context/` frozen.** 30 renders at native 1206×2622: WhatsApp 8,
Messages 7, Slack 6, Telegram 5, Mail 4; 15 light / 15 dark; English 12, Hebrew 10,
mixed 8. 37 distinct hard cases covered.

Per image the ground truth separates four things, which is what makes this a bar for
*extraction* rather than for OCR:

- `expected` — the sender and message actually worth replying to (null where nothing
  is repliable, e.g. `wa-07`, where the newest incoming message is a voice note and
  the previous one was already answered, so returning it would be stale)
- `chrome` — every span a correct implementation must **not** return: nav bars,
  timestamps, contact names, date dividers, the compose placeholder
- `traps` — confusable spans with the reason each one is a trap. The sharpest:
  `10:30` appearing *inside* a message body, annotated "stripping all times would
  corrupt the message" — the exact failure a regex-the-timestamps implementation hits
- `messagesOnScreen` — the full thread with per-message `from` / `fullyVisible`, so a
  critic can tell "returned a neighbouring message" apart from "returned chrome"

### Coordination rules the lead owns

- **One agent drives the simulator at a time.** Concurrent `xcodebuild test` runs on
  `iPhone 17 Pro` kill each other's test runners, producing failures that look real
  and are not. Serialized from here.
- **~~Switching into the AI Keyboard extension crashes the test runner, every
  time.~~ RETRACTED** by the agent that reported it, on better evidence, and the
  retraction is the correct call. The original claim came from four crashes that all
  happened with the AI Keyboard installed, plus one clean run after removing it.
  It did not hold: later runs crashed identically at globe, `more`, and shift with
  **only Apple keyboards installed**. What those three keys share is that each
  rebuilds the keyboard view.

  Correct statement: **an XCUITest testing constraint, not a shipping bug.** The
  extension is unaccused — the runner dies at the tap, before any layout change, so
  there is no evidence the extension was ever loaded. Consequence for the harness:
  punctuation and digits are unreachable, and code-switch entries need a
  crash-isolated pass. Every crash occurred at load average 12–16, and XCUITest reaps
  runners it believes timed out, so contention is a live confound. Two experiments
  named in `Bar/typing/README.md` would settle it: drive the globe by hand with no
  XCUITest, and re-run the globe tap under XCUITest on an idle machine.

### Round 1 — first builders

Dispatched `build-aitext` against the frozen `Bar/ai-text/`. Ordered to probe
`SystemLanguageModel.default.availability` in the simulator and report back before
designing, since the whole shape depends on the answer.

## Screen context — round 1 (2026-08-08)

Started from the user's ScreenCaptureKit question. Answered it, then found a
bigger blocker underneath it and closed that instead.

**The ScreenCaptureKit answer.** Real API, `iOS 27.0+`, and Apple states it
replaces ReplayKit with no broadcast extension needed. Not usable here:
measured against Xcode 26.2, `ScreenCaptureKit.framework` is absent from
`iPhoneOS26.2.sdk` and `iPhoneSimulator26.2.sdk`, present in `MacOSX26.2.sdk`,
with `ReplayKit.framework` present in the iOS SDK as the control. `import
ScreenCaptureKit` does not compile for iOS until an Xcode with the iOS 27 SDK
is installed.

**The blocker underneath.** Apple's text recogniser has no Hebrew. 30 languages,
identical across `VNRecognizeTextRequest`, the Swift `RecognizeTextRequest` and
VisionKit Live Text, on iOS and macOS; Arabic is in the list, so it is not an
RTL limitation. Over the bar: 100% message recall on English screens, 13% on
Hebrew. This is the third place Apple's on-device stack has no Hebrew, after
Foundation Models and `SpeechTranscriber`. It makes the README's "Vision OCR
writing read text through the App Group" plan unworkable for the product's
primary language, which no amount of capture-API work would have revealed.

**Built.** `ScreenReader` / `VisionScreenReader` / `CloudScreenReader` /
`RoutedScreenReader`, plus four harnesses and 12 unit tests. Routing never names
a script: it compares text regions found by shape against regions actually read.

| Engine | Coverage | Sender | Message |
|---|---|---|---|
| Vision, raw OCR | — | — | 100% en / 34% mixed / 13% he |
| `VisionScreenReader` | accepts 9/30, answers 5 | 5/5 | 5/5 within 90% |
| `CloudScreenReader` | all 30 | 29/30 | 26/30 within 90% |

Gate admits **zero** Hebrew or mixed screens. All four of the on-device path's
refusals are correct.

**Prompt deltas that paid, and two that did not.** Enumerate-before-picking took
sender 21→29/30. Splitting `script` from `language` took language 22→29/30.
A bubble-tint paragraph and "a printed name means incoming" both measured worse
and were reverted; both are recorded in `CloudScreenReader` so they stay out.

**Corrected mid-round:** I called the cloud path deterministic at temperature 0
after two identical runs. A later config disagreed run to run. The winning
config is stable across three runs, but "identical twice" is not determinism,
and the project's existing "one run is not evidence" rule applies here too.

**Still open.** Capture itself. Neither API is implemented: ScreenCaptureKit has
no SDK, ReplayKit needs a broadcast upload extension target that does not exist.
`ScreenContextSession.submit(_:appName:appIcon:)` is the seam both plug into.

---

# Gauntlet run 2 — the capture layer (2026-08-08)

**Goal.** Make screen context real: a user in WhatsApp opens the keyboard, taps
Reply, and gets replies written against the message actually on their screen.
Reading a frame is done and measured. Getting one is not implemented at all.

**Restore point.** `6ffa669`, everything green before this run started.

**Bar** (all three openable by a fresh critic with no context):

| Material | Judges |
|---|---|
| `Bar/screen-context/` — 30 frames, `ground-truth.json`, `harness/score_cloud.py` | the pipeline driven through the **shipping** path. Hold: sender 29/30, language 29/30, message 26/30 within 90%, 0 traps, 0 off-screen text |
| `Scripts/prove-app-group.sh` | this repo's standard for "proven": fails on skip, verdict comes from an OS-stamped log line in the *other* process |
| Apple's `RPBroadcastSampleHandler` contract | lifecycle, and the 50 MB ceiling a broadcast upload extension is killed for crossing |

**Settled before the run, not to be relitigated.**
- ScreenCaptureKit is iOS 27+ and absent from the installed iOS 26.2 SDK. Nothing imports it.
- **ReplayKit broadcast does not run in the iOS Simulator.** Measured: the iOS 26.2 runtime ships no `replayd` and no broadcast launch daemons; the macOS host has `/usr/libexec/replayd`, so the probe is sound. The framework links, so code compiles; no session ever starts.
- The user chose simulator-only for this run. **No critic can confirm a frame ever arrives.** Capture ships labelled unproven, and every claim about it says so.
- The app holds no cloud credential. Direct-to-Vertex stays in `Bar/`.
- Apple's OCR has no Hebrew. Routing must not regress.

**Pieces.**

| # | Piece | Judged against | State |
|---|---|---|---|
| P1 | Capture architecture: where reading happens, memory budget, privacy | 50 MB cap, privacy promise, product flow | round 1 |
| P2 | Broadcast upload extension target | builds, plist keys, entitlements, App Group | pending P1 |
| P3 | Extension to keyboard handoff | `prove-app-group.sh` standard | pending P1 |
| P4 | Session lifecycle: start, background, stop, restart | state machine + UI | pending P1 |
| P5 | Reading pipeline through the shipping path | `Bar/screen-context/` scores | round 1 |
| P6 | Privacy surface: claims vs code | README and Screen Context screen vs code | pending |

## Round 1

Dispatched: P1 (architecture) and P5 (shipping-path pipeline) in parallel, being
the only two with no dependency on each other.

### P1 — architecture, round 1: design delivered, **verdict pending**

Design at `.claude/docs/screen-capture-design.md`. Recommends that the broadcast
extension read, but never with Vision and never on frame arrival.

The whole design turns on one measurement: Vision at `.accurate` costing far
more than the entire 50 MB extension budget, and not shrinking with input
resolution because the cost is model weights rather than activations. If that
holds, `VisionScreenReader` cannot run in the extension at any resolution, and
the consequence is blunt: **no on-device screen reading in the shipping flow**,
with English frames going to the cloud alongside Hebrew ones.

**Not accepted yet, and not reported to the user as settled.** The numbers were
taken in the iOS Simulator; the extension runs on a device, where Vision may use
the Neural Engine and model weights may be mapped shared rather than charged to
the process. A Simulator measurement may not be able to support a claim about
device behaviour at all. That is exactly the over-generalisation this project
made once already with ScreenCaptureKit. A fresh-context critic is independently
re-measuring rather than re-running the design's own script.

### Found and fixed in passing: the backend URL never reached the keyboard

`BackendTransport.configured()` defaulted to `UserDefaults.standard`. In the
keyboard extension that is the extension's own private container, so a backend
URL set in the app never arrived and the keyboard reported "no cloud model" for
a backend that was configured. Invisible from the app side, which is the whole
danger. The default is now `SharedStore.shared.userDefaults`, and
`BackendTransportSuiteTests` pins it. This is the exact trap `SharedStore` was
built to avoid, reintroduced by a defaulted parameter.

Suite: 125 tests, green.

### P1 critic — round 1: **GAP** (design sent back for round 2)

The critic wrote its own probe rather than re-running the design's, and found
the design's probe **is not in the repo**, so its "reproducible" preamble was
false. The central claim survived; the escape hatch did not.

| | simulator (no ANE) | macOS (ANE) |
|---|---|---|
| `.accurate`, peak over 30 frames | 104 MB | 114 MB |
| `.fast`, peak over 30 frames | **23–26 MB** | **102.6 MB** |

`DYLD_PRINT_LIBRARIES` gives the mechanism: macOS loads
`AppleNeuralEngine`/`ANEServices`/`ANECompiler`, the simulator loads none of
them. **A physical iPhone is an ANE configuration**, so the only ANE-equipped
measurement available is 4x *higher* than the simulator, not lower. The design's
risk register had it backwards, and its headline escape hatch (`.fast` at
"+10.1 MB, which fits") is a simulator artifact — its own macOS column said
+55.9 MB three lines above.

Resolution is not a knob, and more strongly than the design claimed: at 0.06% of
the original pixel count `.accurate` still costs +63 MB. Two of the design's
findings did not reproduce and were noise: the 130–165 MB accumulation figure
(actual: 84 → 104 over 30 frames) and "halving resolution buys 14 MB" (a scale
sweep moved ±22 MB non-monotonically).

Verified independently by me: **a keyboard extension is capped at ~48 MB**,
tighter than the broadcast extension's 50 MB. So both processes that could run
Vision while the user is in another app are under ~50 MB, and the containing app
— which has no cap — is not running.

Also found by the critic, and sent to round 2: a **privacy hole** (a speculative
cloud upload default-on, while the design's own section 7 concludes it cannot
know which app is on screen, so it would upload banking and password-manager
screens with no tap), a **freshness hole** (nothing ties the frame hash to a
frame observed *after* the read completes, so a 5.3s inline read lets a
conversation switch land a stale match), and a false claim that a README
sentence was already wrong.

### P5 — round 1: **shipping path scored, two real defects found**

The routed score did not exist before and now does. It also corrects two things
this file previously asserted.

**Defect 1, fixed.** `VisionScreenReader.interpret` returned nil both for
"nothing worth replying to" and for "I cannot read this layout".
`RoutedScreenReader` only falls back on a throw, so the second case silently
offered the user nothing on `sl-01` and `sl-03` — plain answerable English the
cloud transcribes correctly. The two refusals are now distinct.

| | before fix | after fix | cloud alone |
|---|---|---|---|
| sender | 24/30 | **26/30** | 29/30 |
| language | 26/30 | **28/30** | 29/30 |
| message exact | 14/30 | **16/30** | 19/30 |
| within 90% | 22/30 | **24/30** | 26/30 |
| frames with no answer | 2 | **0** | 0 |

**Defect 2, not fixed, and it is the bigger one.** Even after the fix, routing
through Vision scores *below* asking the cloud for everything. On iOS Vision
answers 8 frames and gets 3 wrong, including `wa-07`, whose only correct answer
is silence, and `sl-05`, which returns keyboard key caps.

**Corrections to earlier claims in this file and in the docs.** "It accepts 9
and answers 5, and answers only when it is right" was a *macOS* reading reported
as the product's number. On iOS it accepts 10 and answers 7 with 3 wrong. Also,
the bar's `traps` counter is an exact-string check: three answers contain a
named trap with something appended and still score zero, one of them a **cloud**
answer, so the published "no traps" carries that caveat on both engines.
`.claude/CLAUDE.md` and `README.md` corrected.

Suite: 125 tests, green.

## Round 2

### P1 — architecture, round 2: gaps closed, verdict pending

The escape hatch is gone and the conclusion hardened rather than softened. New
probe (`Bar/screen-context/harness/memory.swift`, which now actually exists —
the first version cited a file that was not in the repo), peak physical
footprint over all 30 frames in one process:

| | iOS Simulator (no ANE) | macOS (ANE) |
|---|---|---|
| `VNDetectTextRectanglesRequest` alone | 10.3 MB | **67.9 MB** |
| `.fast` + rectangles | 18.1 MB | **84.7 MB** |
| `.accurate` + rectangles | 174.8 MB | **199.8 MB** |

The load-bearing new fact: **even the language-agnostic shape detector** — the
thing `VisionScreenReader`'s entire routing gate rests on — is over both the
~50 MB and ~48 MB caps on the ANE deployment. If that holds, nothing in the
Vision text stack fits on a phone and cloud-only is forced rather than chosen.

The agent caught its own methodology bug before publishing (its first probe held
all 30 decoded images alive and measured a ~190 MB image cache instead of
Vision). Its numbers disagree with the critic's earlier probe by roughly 2x, so
a second critic is checking which methodology is sound.

**Privacy resolved in the safe direction.** The speculative-upload trigger is
deleted, not defaulted off, with a real argument: "keyboard visible" correlates
with password fields and banking forms rather than excluding them, and the
narrowing that would fix it is circular — deciding whether a screen is safe to
upload requires reading it. A secure-field guard was added, verified through the
header chain. Freshness gap closed with a condition tying the frame hash to a
frame sampled after the read completed, and the read moved off the delivery path.

Still unproven, and the document says so itself: **no number in it came from a
phone.** Both memory caps are unverified and appear in no header.

### P2 — broadcast extension target: dispatched

### P1 critic — round 2: **GAP.** The mechanism was falsified by one API call.

The critic reproduced every number in the document (macOS rects 73.0/67.1/73.7
against the doc's 67.9/66.7/69.2, and so on down), then falsified the *reason*
the document gives for them. Reproduced independently by me on both deployments
before acting on it:

| request | compute devices, macOS | compute devices, iOS Simulator |
|---|---|---|
| `VNDetectTextRectanglesRequest` | **cpu** | **cpu** |
| `VNRecognizeTextRequest(.fast)` | **cpu** | **cpu** |
| `VNRecognizeTextRequest(.accurate)` | ane, cpu, gpu | cpu, gpu |

One line: `try request.supportedComputeStageDevices`. The shape detector and
`.fast` — the two configurations the on-device path would actually use — are
CPU-only on both deployments, so **the Neural Engine cannot be why macOS is 6x
the simulator**. Pinning the detector to CPU on macOS changes nothing. Only
`.accurate` touches the ANE at all.

The critic's alternative reading of the same data points the other way: macOS
charges ~64 MB to the `phys_footprint` ledger for a CPU-only request, while the
iOS build charges ~0 and maps ~11 MB clean and file-backed. **A device runs the
iOS build.** If that holds, the simulator is the *representative* deployment for
iOS memory accounting, not the optimistic one, and the document's own reversal
threshold (~30 MB for `.fast` + rectangles) is already met by it.

So cloud-only is **not forced by memory**. It remains the right default, but for
the reason that was measured on the deployment that matters: on iOS, routing
through Vision scores below asking the cloud for every frame. That argument
never needed the memory number.

Two further holes the critic found, both real and both sent to round 3:
`isSecureTextEntry` sits in an `@optional` block, so the secure-field guard is
`Bool?` and **fails open** on hosts that do not implement it; and the 64-bit
dHash is the *only* content-identity condition in the freshness rule while §5.4
argues it is safe precisely because it is uninformative, which is the same
property that makes it a weak discriminator between two conversations in one
app. Unmeasured, and the 30 bar frames across five app skins would settle it.

Also corrected: the two probes never disagreed. 104/114 was stock
`VNRecognizeTextRequest`; 199.8 was with `automaticallyDetectsLanguage`. And
`.accurate`'s peak is a function of call count, not a ceiling — 60 images gives
223.7 and is still climbing — so 199.8 should never have been quoted as fixed.

Every ReplayKit and UIKit citation in the document verified correct, verbatim.

**Correction to what was reported to the user:** I relayed the ANE mechanism as
established fact. It was not, and it is now falsified for the two configurations
that matter. The claim never reached `README.md` or `.claude/CLAUDE.md`.

### P2 — broadcast extension target: built, embedded, proved as far as this machine allows

`AIKeyboardBroadcast/` is a real target now: `SampleHandler: RPBroadcastSampleHandler`
with all six lifecycle methods, audio types named and returned rather than
falling through, video throttled to one frame per 250 ms inside an
`autoreleasepool`, orientation read from the `RPVideoSampleOrientationKey`
attachment, and **no `CVPixelBuffer` retained at all** — it never calls
`CMSampleBufferGetImageBuffer`, taking size and pixel format from the format
description instead. Everything logs through `Logger(subsystem:
"com.nitai.aikeyboard")` so a device proof can read its verdict from the
extension process's own line.

`AIKeyboardCore` is deliberately **not** linked: the appex binary is 56 KB
against the keyboard extension's 4.1 MB, which is the evidence it did not sneak
in through a package dependency.

`Scripts/prove-broadcast-extension.sh`, five checks, fails rather than skips.
Verified by me independently: build green, 125 tests green, both appexes present
in `PlugIns/`, script exit 0.

The part that makes it trustworthy: the builder **falsified its own checks**
rather than trusting green. Deleting `RPBroadcastProcessMode` made check 2 fail;
pointing the principal class at a class that does not exist made check 5 fail.
Both restored and re-verified. Check 5 derives the mangled Objective-C symbol
from the plist string and demands it in the binary, so it tests the plist and the
binary *agreeing* rather than either alone.

Two environment traps handled: Xcode 26 Debug builds split code into a
`.debug.dylib` beside a stub executable, so the class check searches both; and
Release keeps that symbol local, so the script uses `nm -a` rather than `nm -g`,
which reports nothing for a Release binary that plainly contains the class.

**Still unproven, and the script says so in its own output:** nothing here shows
a frame ever arrives. No `replayd` in the simulator runtime means
`processSampleBuffer` has never executed once, anywhere, in any run. The
throttle, the counters and the orientation read have never run.

Docs updated: the format command missed the two new target folders, and
`README.md` still opened with "Everything is faked. No network, no model" which
stopped being true two rounds ago.

### P2 critic — **GAP, closed.** The proof proved nothing.

The critic replaced the handler with `final class SampleHandler: NSObject {}` —
no ReplayKit, no superclass, no callbacks — and the script printed **"Proved"**
and exited 0. `otool -L` showed zero ReplayKit links.

Fixing it exposed a second bug in the fix itself: the strengthened check failed
on the *real* handler with exit **141, SIGPIPE**. `grep -q` exits on first match,
closes the pipe, kills `nm`, and `set -o pipefail` reports the pipeline failed.
The pre-existing check had the same shape and only passed because `nm -mu` has
short output and finished before grep exited — **it was winning a race, not
passing**. Symbols are now read once into a variable and matched with `case`.

Three checks where there was one: the class symbol exists, it has an undefined
external `_OBJC_CLASS_$_RPBroadcastSampleHandler` from ReplayKit, and the ObjC
thunk for `processSampleBuffer(_:with:)` is present (an override whose signature
drifted mangles differently and goes red). Falsified in both directions.

Also recorded: check 4 is simulator-only by construction, since a device Release
`.appex` has no `__TEXT,__entitlements` section at all. And the handler's
threading comment claimed an invariant it did not hold.

### P1 — architecture, round 3: gaps closed, and a design-breaking bug found

The falsification reproduced exactly, and the accounting picture is now itemised
rather than asserted. macOS adds 63.2 MB of footprint for a **cpu-only** request,
32.7 MB of it tagged *graphics*; the simulator adds 4.5 MB of footprint and grows
`external` (file-backed, clean) by 10.7 MB. A decode-only control leaves the
graphics ledger at zero, so the first Vision request creates it. Bonus finding:
even for `.accurate` on macOS the ANE's memory lands on
`ledger_tag_neural_nofootprint` with `ledger_tag_neural_footprint` at **0.0** —
the ANE never touches the ledger jetsam reads.

`.accurate` has a slope, not a peak, and it tracks **distinct images** rather
than call count. `.fast` and the detector do plateau.

**The frame hash was broken and would have shipped.** A new adversarial harness
(`harness/frame-hash.mjs`) renders each scene four ways, including one where only
the newest message's glyphs change. Verified by me:

| band | misses | false invalidations |
|---|---|---|
| status + keyboard (bottom 45%) — as designed | **23/29** | 19/30 |
| `VisionScreenReader.Band` + SHA-256 | **0/29** | **0/30** |

The old band cropped the newest message out of the fingerprint, so the freshness
check was blind to exactly the change it exists to detect, and 64 to 256 bits
fixes none of them. Cropping to `VisionScreenReader.Band` and hashing with
SHA-256 fixes it, and is *less* linkable than a perceptual hash, so the privacy
argument improves rather than being traded away. One irreducible case remains:
`sl-05`, whose newest message sits under the host keyboard, renders identically.

The secure-field guard is now fail-closed, with `isSecureTextEntry` proven to be
`Bool?` by the compiler against the 26.2 SDK.

**Everything green:** build, 125 tests, `prove-app-group.sh`,
`prove-broadcast-extension.sh`, all exit 0.

### P3 — capture channel: built and **proved across processes**

`AIKeyboardShared` (Foundation + CryptoKit only) plus a small C target for
seqlock fences, because Swift 5.9 has no atomics on this deployment target:
`Synchronization.Atomic` is iOS 18, `<stdatomic.h>` does not import, and
`OSAtomic` has been deprecated since iOS 10. Plain loads and stores on arm64 are
not a seqlock.

`Scripts/prove-capture-channel.sh`, verified by me, exit 0. The verdict comes
from the **keyboard extension's own log lines**: it reports `storage=appGroup`,
reads a session UUID written by a different process, observes two distinct frame
identities (so it is reading a live mapping rather than a snapshot), and its
freshness gate moves `verdict=offerable` to `verdict=superseded` when the
producer changes the frame identity underneath it. That last transition is the
whole safety property, demonstrated rather than asserted.

The shipping Swift fingerprint scores **0/29 misses and 0/30 false
invalidations** over the 120 rendered corpus frames, matching the JS harness.
The 64-bit settle hash misses 8/29, which is why it is confined to settle
detection and is not the identity.

**A bug the proof caught, not the builder:** `keyboardVisible = 1` outlived the
extension that wrote it, so the producer believed a keyboard that was not there.
A flag without a timestamp is the same mistake §6.1 names for the frame identity.

**A number I got wrong and it corrected.** I reported the appex as 56 KB. That
is the Debug *stub*; it is unchanged because it is a stub. Measured properly
against a baseline built from `c8b6069`: the Release arm64 slice goes 217,024 to
487,456 bytes, and `__TEXT` vmsize 48 KB to 112 KB. `otool -L` gains exactly
CoreVideo and CryptoKit, no SwiftUI, no `AIKeyboardCore`. 64 KB of file-backed
`__TEXT` against a 50 MB cap is immaterial, but it is the real number.

Tests 125 to **161**, all green. All three proof scripts exit 0.

**Still unproven:** `AIKeyboardBroadcast` has never executed. The producer in the
proof is the containing app driving the same writer and the same fingerprint.
`broadcastStarted`, the heartbeat, `processSampleBuffer`, the pixel-buffer
lock/reduce/unlock path and `broadcastFinished` are compiled, unit-tested in
pieces, and have never run.

### P3 critic — **GAP.** The seqlock is single-writer and the producer has three.

`CaptureAtomics.h` asserts "single writer by construction: the broadcast
extension is the only process that writes". That is a claim about *processes*.
Three threads inside that one process write the page, and the extra two are this
code's own choice rather than ReplayKit's: the delivery queue via `recordFrame`,
the heartbeat timer on a global queue, and the lifecycle callbacks via
`setPaused`/`end`.

The critic compiled `SharedPage` and `CaptureAtomics` unmodified and drove the
real `mutate` bodies from those queues:

```
reads = 36,902,721
  torn snapshots (one frame's identity beside another's timestamp) = 2,518,998
  identity went BACKWARDS (a retired reading becomes offerable)    =   180,312
final raw sequence ODD -> every future load() returns nil
quiescent loads returning nil: 1000/1000  -> WEDGED, 3 runs of 3
```

Three failure modes, and the middle one is the exact thing the design exists to
prevent: the heartbeat's read-modify-write writes back a body snapshotted before
a frame write, so `status.currentFrameIdentity` moves backwards, and freshness
condition 4 then promotes a reading already retired as `.superseded` back to
`.offerable`. That is a reply in the user's voice about the conversation they
just left. The third mode is permanent: interleaved `end_write`s flip the
sequence parity, after which the keyboard renders "Screen context is off" while
capture is running fine, so the user is not even offered a restart.

Rate at desk speed is low (90 s at 60 Hz produced zero tears; the window is
~13 ns). That is not a reason to leave it: a preemption between `begin_write` and
`end_write` under jetsam pressure stretches the window to a scheduling quantum,
and mode 3 is permanent and misreported.

Nothing in the repo could catch it: the unit test uses one writer thread, and
`CaptureChannelProbe` drives frames and heartbeat from the *same* main-thread
timer, so the proof script structurally could not see it.

**Everything else on the bar held**, and the critic checked hard. The fences are
correct and emitted (`dmb ish` after the odd store, `dmb ishld` in both reader
halves: the canonical formulation). The retry loop is bounded at 16, so a writer
SIGKILLed mid-update returns nil rather than spinning. The proof script is
discriminating: broken three ways, it failed at exactly the right check each
time. Privacy holds: the container after a run holds only a 256 B status page, a
64 B intent page and the settings plist; the 32x64 reduction never leaves
`withUnsafeTemporaryAllocation`; the producer copies no frame and unlocks on
every path via `defer`.

### P3 round 2 — seqlock fixed, and the test failed first

`SharedPage` gains an `OSAllocatedUnfairLock` taken by `store`, `mutate` and
`reset`. Readers are untouched and still take nothing, which is the textbook
multi-writer seqlock. `reset()` became a real transaction: it zeroes only the
body between `begin_write`/`end_write` instead of memsetting the sequence, since
a reader whose open sequence was 0 could otherwise validate a half-zeroed struct
against the zero `reset` had just written.

**The new test failed against the unfixed code before it passed**, which is the
only thing that makes it evidence:

| run | torn | backwards | sequence | quiescent nil |
|---|---|---|---|---|
| unfixed, 1 | 168 / 5,766 reads | 0 | odd | **1000/1000 (wedged)** |
| unfixed, 2 | 150 / 399,094 reads | **1 (lost update)** | even | 0 |
| fixed | 0 | 0 | even | 0 |

Two unfixed runs hitting different subsets is what a race looks like. 161 tests
to **163**.

`CaptureFreshness` now distinguishes `absent` from `unsettled`: a page that
exists but will not settle reads as `.ended(.lost)` — "stopped unexpectedly,
restart" — instead of `.noSession`, which rendered "Screen context is off" while
capture was running fine and offered the user no way back.

Also fixed the test suite rewriting a checked-in file: `RoutedRow.seconds` is
measured and printed but no longer encoded, so `routed_outputs.json` is now
byte-identical across runs.

Honestly noted by the builder rather than hidden: the probe now has
`SampleHandler`'s two-queue *shape* but not the power to catch the bug at 4 Hz
over 14 s. The unit test is what has the power, and the probe's doc comment says
so rather than implying the proof script covers it.

**Verified independently:** build, 163 tests, all three proof scripts, exit 0.

### P4 — session lifecycle, Reply, and honest copy

`RPSystemBroadcastPickerView` in the app, with copy that says what is actually
true: *"Only iOS can start this. No app can press that button for you, including
this one."* `ScreenContextSession` now consumes the channel when a real session
exists and keeps the scripted timeline for the playground and UI tests. The
strip renders six states, and `.ended` carries a reason and a way back.

Reply no longer reads the state it is displaying. `contextForReply` polls the
channel at the instant of the tap and returns a reading only when the gate says
`.offerable`; otherwise it raises `intent.readNow` and waits for a record newer
than the request that is *also* offerable. A superseded or stale reading is never
returned, and failure is a named error rather than a guess.

**Three false promises deleted rather than faked**, which is the part worth
recording:
- A "Use the cloud for replies" toggle that **no code read**. It promised a
  behaviour nothing implemented.
- A "Start screen context" button in the Reply panel that actually started the
  *scripted sample* — a privacy-relevant label doing something else entirely.
- The stop button on a real session: nothing in either process can end a
  broadcast, so it was a button that could not work.

Copy corrected: *"Each frame goes through on-device text recognition"* was false
under this design and is now *"Tapping Reply sends one screenshot"*. The
protected-content promise was **weakened** to match what is actually verified.
The red dot now requires `source == .capture && isLive`, so the sample gets a
grey one.

Three additions on top of the design, argued rather than slipped in: a
`.starting` state (built as specified, the picker's own countdown rendered as
"paused", which reads as a fault), `.ended(.userStopped)` mapping to `.off` (or
the strip says "stopped" forever after a deliberate stop), and a decay on
endings — **the ten minutes is explicitly labelled a guess**.

163 tests to **184**. UI tests 4/4. All three proof scripts exit 0. Verified
independently, unit and UI run separately.

**Known and stated:** on a device today a Reply tap will **time out**. The
broadcast extension publishes status but runs no reader; that piece was deferred
by constraint, not overlooked.

### P4 critic — **GAP, closed.** A cancelled Reply span the CPU.

`contextForReply` swallowed cancellation with `try?`, so once the task was
cancelled `Task.sleep` returned immediately and nothing paced the loop but the
deadline. Each iteration is a file read, a JSON decode and a SwiftUI
invalidation on the main actor, in a process capped near 48 MB, for up to 12
seconds.

Reproduced by me independently: **16,077 polls in one second** against the
unfixed code (the critic measured ~15,800/s), versus 6 in the healthy case. Test
added, verified failing first, then passing. 184 to **185**.

It is reached in two taps and is the *ordinary* path, not an unlucky one:
`beginWork` cancels the previous task on every action, the strip's Reply button
stays hittable while a result panel is up, and while the capture process runs no
reader every Reply times out — so "nothing happened, tap it again" is exactly
what a user does.

**The central privacy claim HOLDS**, and the critic proved it by enumeration
rather than assertion. `intent.readNow` is raised in exactly one place, whose
only caller chain terminates at two tap handlers. No timer, no `onAppear`, no
frame-arrival hook, no keyboard-visible hook touches it. The producer never even
reads the intent page. The other upload path is gated on a `reader` that only
tests ever assign. The three claimed deletions all check out with nothing
dangling, and the red-dot rule is consistent in all three places it appears.

## Open, found by the P4 critic, not yet fixed

1. `ScreenContextChannel.requestRead()` is not role-gated, so an app-side Reply
   tap in the playground writes the intent page while `Role.observer`'s contract
   says the app "writes nothing". Still a tap, so the product promise survives;
   the code's own contract does not.
2. A real session that is `.paused`, or `.ended` inside the decay window,
   silently kills the scripted sample within one poll, so "Play a sample
   conversation" appears to do nothing.
3. The app UI never says what `README`'s "Not built" says. The failure a user
   actually gets on a device is rendered as "the last reading is not what's on
   screen now", which misattributes the cause: there is no reader at all yet.
4. Design §3.3.1's secure-field guard is unimplemented. `CaptureStatus` carries
   `refusedSecure` fields nothing writes, and it is absent from "Not built".

## Round 3 — closing out

Two agents dispatched concurrently on **separate simulators**, because two test
targets on one device kill each other's runners here and it reports as a crash
rather than a failure.

- **P5, the reader inside the capture process** (iPhone 17 Pro). The last
  missing middle: today the keyboard raises `intent.readNow` and the extension
  publishes status, and nothing ever performs a read, so on a device every Reply
  times out. Includes the package split the design's Phase 1 calls for, because
  the prompt and transport live in `AIKeyboardCore` and the extension must not
  link it. One copy of the prompt, not two: it is measured against the bar and
  two copies drift.
- **P6, the four logged critic findings plus shared-state hygiene**
  (iPhone 17 Pro Max). Role contract, the sample being killed by a real session,
  the UI misattributing its own failure, and the unimplemented fail-closed
  secure-field guard.

**Shared-state finding, before either agent started.** The App Group container
holds `channel-com.nitai.aikeyboard/` and `channel-com.nitai.aikeyboard.keyboard/`
beside the live `channel/`. Shipping code only ever uses `channel/`; these are
debris from a critic's deliberate break test. Inert, but stale state in a shared
container is exactly the class of thing that makes a later run lie, so it goes to
P6 as hygiene rather than being swept by hand.

### Master review finding: the fail-closed secure guard is wrong, and it is my error

I instructed "FAIL CLOSED" on the critic's reasoning that a guard permitting by
default on unknown hosts is not a guard. Sound in the abstract, wrong here, and I
should have checked two things before giving the instruction.

1. **iOS already prevents the case.** Apple's App Extension Programming Guide:
   *"When a user taps in a secure text input object, the system temporarily
   replaces your custom keyboard with the system keyboard."* A custom keyboard is
   never on screen for a password field, so `isSecureTextEntry == true` is a
   branch that essentially cannot fire while our keyboard is visible.
2. **`nil` is not evidence of danger.** It means the host did not implement an
   `@optional` protocol member. Treating it as "yes, this is a password field"
   refuses on the overwhelmingly common case.

Net effect of fail-closed-on-nil: it protects against a case the OS already
handles, and in exchange may disable Reply on every device. That is a bad trade
in both directions at once.

There is a second reason the signal is weak, independent of the above: the read
uploads the **whole screen**, not the focused field. A password manager visible
behind a non-secure search box is not caught by this guard at all. So it is
narrow defence in depth, and must not be described as the thing protecting
sensitive screens. The thing that does that is the absence of any speculative
read: a frame leaves only in answer to a tap.

Fix: refuse on a positive `true` (free, harmless), permit on `nil` with the OS
guarantee documented as the reason, keep both counters so R14 stays measurable.

### Integration: both agents merged, four corrections applied by me

**The reader exists.** `ScreenReadService` claims a request on the delivery
callback and runs the cloud call on a serial queue, so a read never blocks frame
delivery. One claim per raised request: no retries, no read on frame arrival, no
speculative read, and a second tap during a read folds into it rather than
opening a second connection. Failures now publish a reason instead of leaving the
keyboard to time out. The packaging move finished with it: one copy of the
prompt, schema, transport and parsing serves both processes, and the appex still
links no SwiftUI and zero `AIKeyboardCore` symbols (474 `AIKeyboardShared` ones,
Release arm64 495,504 → 766,656 B, mostly `__LINKEDIT` metadata). Holding a
half-size frame to serve a read costs 3.0 MiB (BGRA) or 4.1 MiB (420f); a session
where Reply is never tapped allocates nothing.

**Four corrections I made at integration, three of them to my own instructions:**

1. **The secure guard's fail-closed-on-nil was my error** (see the finding
   above). Now `secure != true` refuses. Both counters survive.
2. **The counters would have stopped measuring the thing they exist for.** With
   silence permitting, a silent host falls into the ordinary path, so counting
   only on refusal made it indistinguishable from a host answering "not secure".
   `countSecureDecision(refused:unanswered:)` now counts silence on *every*
   decision, which is what keeps R14 answerable from the field.
3. **A published failure was invisible.** The gate refuses to call a non-`.read`
   record offerable, and the wait loop only acted on `.offerable`, so "no backend
   configured" sat in the container while the user waited the full twelve seconds
   and was then told nothing answered — the wrong reason as well as a slow one.
   The loop now ends on any answered-and-failed record, with `.nothing` worded as
   an answer rather than a fault.
4. **Two passages went stale as the other agent worked.** A comment claiming
   `KeyboardLanguage` could not be linked by the capture process (it moved to
   `AIKeyboardShared`; the string is now for decode robustness across builds), and
   the app's "steps 2 and 3 are not built" paragraph, which the reader landing
   made false.

**Verified by me, not taken on report:** build, **228** unit tests, 7 UI tests,
and all three proof scripts, exit 0. The UI suite's one skip is by design and
covered: the shared suite skips an uncooperative simulator, while
`prove-capture-channel.sh` fails on skip and produced real cross-process log
lines.

## Final audit and close-out

An independent auditor with no history was put over everything since `6ffa669`.
It did **not** pass the feature, and it was right. Two blockers, both reproduced
rather than argued, plus thirteen smaller findings. All closed.

### Blocker 1 — the gate threw away the read the tap paid for

`CaptureFreshness` condition 4 compares the frame identity at tap time against
the newest frame. But the fingerprint band contained **32% of our own keyboard**,
and `KeyboardController.beginWork` starts the shimmer *before* `contextForReply`
runs, so our own UI animated for the whole ~5 s read. Measured on the corpus:

| band | own-UI false invalidations |
|---|---|
| what shipped | **30/30** |
| ours excluded | **0/30** |

Every sampled frame got a fresh identity from nothing but our loading state. The
user tapped Reply, the screenshot *was* uploaded, the cloud call *was* spent, and
the answer was discarded — then, twelve seconds later, "nothing answered".
Non-deterministic, which is worse than always broken.

Fixed by excluding our own rows: the keyboard publishes the height it *can*
occupy (never the current one, since the strip appearing mid-read would move the
band and retire the reading exactly as a real switch does), clamped both ways
because one process reads it out of a page another writes. The crop costs no host
content — while the keyboard is up, everything below its top edge is ours.

The cheaper alternative was rejected with a proof rather than a preference: the
record's identity is *by construction* a member of "identities observed during
the read", so confirming membership degenerates to `true` and condition 4
disappears.

**Two harness bugs found on the way**, one of which had the harness manufacturing
the very effect it was measuring: its shimmer used `left:` (a layout change)
where SwiftUI uses `.offset` (a draw-time transform), and the growing overflow
rect made Chromium rasterise a pixel differently *above* the keyboard. The other
let pixels 1,300 px outside the band bleed into cells through Skia's mip chain,
which is why the published "64-bit missed 11 of 29" is really 10 of 29.

### Blocker 2 — a killed writer poisoned the channel permanently

`capture_seq_begin_write` computed `load + 1`, which assumes even parity on
entry. A complete transaction preserves parity; an **aborted** one flips it — and
jetsam aborts transactions, which is exactly how it ends this extension at 50 MB.
Nothing repaired it: `begin()` runs two complete transactions, `clear()` never
touches the counter. The page stayed poisoned across broadcasts, launches and
reboots, showing "Screen context stopped unexpectedly" forever, and an inverted
page publishes an **even** sequence before touching the body, so the other
process could validate a half-written struct. One line: `| 1u`. The test fails
without it.

A comment claimed this was handled — *"there is no later event that will fix it"*
— and it was measurably false. That sentence is why nobody looked.

### The rest

- **The status page advertised two safety features that did not exist.** A memory
  governor now really samples `phys_footprint`, with a watermark that cannot
  silently disable the feature: `max(ceiling - reserve, baseline + reserve)`,
  where the baseline is measured in-process, so a guess never overrules a
  measurement. `refusedBudget` and `.overBudget` were deleted instead — nothing
  could ever have written them.
- **The UI promised a "why" it cannot know.** Read out of the SDK:
  `broadcastFinished` takes no argument and no callback carries an error, so the
  five `RPRecordingErrorCode` mappings were dead code. Deleted, and the UI now
  says it can tell you a session stopped but not why. It also stopped mapping a
  stop to "screen context is off", which was silently removing the strip against
  an explicit README promise.
- **A message body could outlive its session**: a read in flight when the
  broadcast ended republished `reading.json` after `end()` deleted it, leaving a
  sender and message in a backed-up container.
- **The playground would have photographed the playground.** The app hosts a real
  `KeyboardView`, so its Reply is the same button; as an observer it now refuses
  in words rather than reading our own preview.
- Three documents still said the read was not built, two commits after it landed
  — including one that keyed live UI copy off the claim.

**Verified by me, not taken on report:** build, **251** unit tests, 7 UI tests,
and all three proof scripts, exit 0.
