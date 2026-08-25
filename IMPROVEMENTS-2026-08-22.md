# Improvement review, 2026-08-22

A full architectural pass over the repo: four parallel explorers over distinct slices (extension lifecycle and memory, cross-process services, suggestion ranking, build/test/ship infrastructure), then lead judgment with every load-bearing claim re-verified directly in code. Linear decisions respected throughout: NIT-132 (frequency ranking) and NIT-161 (glide typing) stay killed; NIT-193/102/23 and NIT-115/116/129/131/133/127/89 were verified fixed in code rather than re-reported.

## Overview

Five targets. The app (`AIKeyboard`), a thin extension host (`AIKeyboardExtension`, one `KeyboardViewController` whose visible life lives in `Packages/AIKeyboardCore`), a ReplayKit broadcast extension deliberately capped at linking the Foundation-only `AIKeyboardShared`, and two test bundles (~1,523 unit methods, 22 UI tests of which 19 are red on one shared precondition). All keyboard state funnels through one `ObservableObject` (`KeyboardController`, ~40 published properties) built in `viewDidLoad`. Cross-process state is the App Group: a typed settings store (`SharedStore`), a personal language model JSON, CopyClip ledger, dictation mmap channel, and four boot-scoped diagnostic records. AI actions route `FoundationModelsEngine` (Fix/Tone, no Hebrew) then cloud (attested bearer, Cloud Run), with a single-flight reactive re-attest on 401. Around the product sits an unusually serious measurement layer: eight `Bar/` corpora, five prove scripts that fail the build on broken architectural invariants, and a drift runner that exists but is not running.

The architecture is sound. Boundaries land where they should, memory discipline in a 50 MB process is genuinely good (purgeable caches wired to `didReceiveMemoryWarning`, lazy emoji catalogue, off-main warming), flag holds are consistent on both producer and consumer sides, and analytics is structurally unreachable from the extensions. What follows is where the value is.

## Act on

### 1. `Bar/ai-text/harness/run-real.sh` is broken today, and it broke exactly the way its sibling predicted

The script copies a frozen subset including monolithic `AIPrompts.swift`. The prompts were since split into `AIPrompts+Fix/Rewrite/Tone/Reply/Continuation.swift`, and `CloudIntelligence.swift:35,109,131,175` calls `Prompts.fix/.tone/.rewrite/.reply`, which are defined only in the split files. Verified: `Prompts.fix` exists nowhere in the copied set. The harness cannot link, which silently takes out the flagship quality corpus and `Bar/drift --paid ai-text` underneath it. `Scripts/prove-cloud-backend.sh:161` hit this identical staleness on 2026-08-12 and fixed it with a `copy_family()` helper; `Bar/typing/harness/sources.sh:6` even predicts this failure in writing. Fix by sharing the same copy-list approach. Script-only, no product code, low risk. Nobody notices until the next time you want to score a prompt change, and then you get a link error instead of a score.

### 2. NIT-191, verified live: init-time `refreshSuggestions()` before first frame

`KeyboardController.init` calls `refreshSuggestions()` at `KeyboardController.swift:702`, before the first frame. Over an empty field it takes the cheap next-word path. Over a field that already has text (the common re-focus case) it reaches `UITextChecker`, whose first call per language builds Apple's lexicon on the main thread, measured at 70–280 ms in this repo's own harness, and arms the PredictiveRefiner clock. `viewWillAppear` already demonstrates the correct pattern: call `refreshDocumentState()` there instead, and let `textDidChange` trigger the first real refresh. Small diff, mirrors a proven path.

### 3. The build number exists in 10 hand-synced places and nothing checks them

`CURRENT_PROJECT_VERSION = 55` appears 10 times in `project.pbxproj` (5 targets × 2 configs); the bump commits touch all 10 by hand. A partial bump ships mismatched `CFBundleVersion` across app and extension, which App Store Connect rejects only after a full archive and upload attempt. Cheapest fix: a guard in `Scripts/release-testflight.sh` that greps all 10 values and aborts unless equal. An xcconfig dedupes properly but touches signing config, which is not worth the blast radius before a release.

## Consider

### 4. Decide whether drift runs

`Bar/drift/runs/` holds 5 records (4 grouped, 1 typing), all written 2026-08-15. Its trend detector needs 10 runs before it can fire once. Nothing schedules it on this machine. The directory reads like an operating instrument and is not one, which is worse than not having it, because it manufactures confidence in numbers nobody is taking. Either install the crontab line the README already drafts (the free grouped corpus costs seconds and no money) or put one line in the README saying it is dormant. Paid scheduling stays your call.

### 5. The canonical test command is red by construction

The shared scheme's TestAction includes both test bundles (`AIKeyboard.xcscheme:40-59`), so AGENTS.md's own invocation reports ~25 failures until NIT-178 resolves. Nineteen of those are one precondition (XCUITest no longer matching the tab bar type), not nineteen regressions. Two ways out: chase the `TabBarAccessibilityProbe` lead in NIT-178, or add a CoreTests-only scheme and point the docs' Commands section at it so green means green. The second is an hour; the first is the real fix and is already filed High.

### 6. No retry on transient cloud failures

`BackendTransport+Send.swift:126-127` maps 429 and 5xx to honest "try again" messages and stops, while 401 got a full single-flight re-attest mechanism (`CloudTransport.swift:137-162`). One short-delay retry on 429/5xx, never on 401/403/422, would match the message's own advice. Modest value; small, contained risk.

### 7. `SharedStore` fixes its suite at init

`SharedStore.swift:137-142` resolves the App Group suite once. A keyboard process started without Full Access stays `.processLocal` even after the user grants it, while `SharedContainer.swift:44-51` deliberately never caches nil so the *container* recovers mid-process. The repo's own `recordPresence` retry loop implies grant-mid-process is considered real. Whether iOS relaunches the extension on grant decides if this matters at all, and only a device answers that. It belongs on the device-test checklist before anyone writes code.

## Noted

- `captureFromPasteControl` reads `changeCount` after an async provider load, so a board change inside a millisecond window attributes old text to a newer generation (`CopyClipPasteControl.swift:110-120`, `KeyboardController+CopyClip.swift:208-218`). Snapshot the count at paste entry if it ever bites.
- `DictationChannel.prepareDirectory` lacks the directory-protection attribute `CaptureChannel` sets (`DictationChannel.swift:110-114`). OS defaults cover it. Consistency only.
- Three small perf residues, none user-perceptible today: the `objectWillChange` sink hops to main on every publication (`KeyboardViewController.swift:136-146`), `warmRebuildableCaches` re-probes UITextChecker on cache-hit appearances (`KeyboardViewController.swift:342-344`), three dormant screen-context sinks carry `.receive(on: RunLoop.main)` for the day the capture flag flips.
- Doc rot in two places: AGENTS.md's Bar list omits `emoji/` and `glide/`; testing.md says "two cross-process suites", three exist.
- Analytics derives its endpoint from `BackendTransport.effectiveURL()` (`Analytics.swift:204`), so events follow a user-set backend URL. Deliberate or not, worth knowing.
- The typing harness is structurally blind to select-a-word, centeredSlots drawing, and idle-typing paths; the unit tests are the whole regression net there. Known shape, worth remembering when a bar-drawing change "passes everything".

## Dismissed

- Any frequency-based completion ranking, reserved checker slot, or tier swap. NIT-132 killed these with measurement (4 gains vs 48 exposures; 2 rescued vs 6 spent) and the structural tier argument stands.
- Building glide typing now. NIT-161: the path-reduction front end fails structurally at corner-cutting swipes (12-20%); the honest next step is the DTW spike, and the recommendation is post-launch.
- Extracting the prove scripts' shared ~60 lines of boilerplate. Four scripts, self-explanatory, deliberate. Revisit at a fifth.
- Further work on NIT-186. Already addressed since filing, byte-keyed caches throughout.
- Lowering the adjacent-key typo cost below 50 or raising `Source.frequency` above `.neighbour`. Both are documented traps in `.claude/rules/suggestion-bar.md` with measurements behind them.
- Flipping either feature flag. Each names its own condition; neither condition is met.

## Missing from everyone's list

Nothing large. One genuine gap: the repo has no answer for "what did the last TestFlight build do in the wild" beyond Apple's crash reports and the six app-side analytics events. That is consistent with the written analytics policy, so treat it as a product-stage decision, not an oversight.
