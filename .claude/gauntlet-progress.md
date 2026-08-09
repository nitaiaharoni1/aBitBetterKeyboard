# Gauntlet — harden every change since the mock UI commit

**Started:** 2026-08-09 · **Lead:** this session · **Status:** Round 1 closed, all gates green

> **This file is a log, not a reference.** Numbers here were true when written.
> For what is true now, read `.claude/CLAUDE.md`, the doc comments, and the
> committed `*_outputs.json` under `Bar/screen-context/`, which carry their dates.
> An earlier gauntlet (2026-08-07, "replace every mock with a real
> implementation") ran to completion; its log is in this file's git history.

## Goal

Harden the 16 commits since `8c7cb52` — backend, suggestions, rotation, capture
channel, claims — until fresh-context critics find nothing that survives
verification.

## The bar

Reproducibility, not a comp: every claim traceable to something a fresh agent can
run, and every gate green.

| # | Bar | Check |
|---|---|---|
| B1 | Suite green | `xcodebuild test … 'platform=iOS Simulator,name=iPhone 17 Pro'` |
| B2 | Cross-process proofs | boot the sim, then the three `Scripts/prove-*.sh` |
| B3 | Backend green | `cd Backend && npm test`, no network calls |
| B4 | Corpus not regressed | `score_cloud.py routed_outputs.json` ≥ 27/29/16 |
| B5 | Numbers trace to artifacts | reproducible, or labelled unverifiable-here |
| B6 | No claim contradicts a test | the test wins |

## Round 1 — five fresh critics, five verdicts

| # | Piece | Verdict | What it found |
|---|---|---|---|
| P1 | `Backend/` | **GAP** | Slow-POST: every pre-body branch (401, 413, 429, 404) answered and never hung up. Reproduced with a raw socket. Also: `temperature: 0` shipped on `/v1/text`, a config the ai-text corpus never graded |
| P2 | `SuggestionEngine` | **GAP** | Dropping `codeSwitchVocabulary` silently regressed the product's central case — `standup` never surfaces at any partial prefix inside a Hebrew sentence |
| P3 | Rotation | **BEATS THE BAR** | Upright path byte-identical, rect arithmetic sound, guess isolated to a 6-line switch. Found two doc comments describing the crop backwards |
| P4 | Read service / channel | **GAP** | `SampleHandler.reads` written on the lifecycle queue and read on the delivery queue with no lock — the third instance of a hazard already fixed twice |
| P5 | Claims | **GAP** | 24 findings. Worst: README and CLAUDE.md claimed `שלומ` → `שלום` was handled and test-pinned. It was neither, and the engine actively offered `שלומדים` |

## Fixes applied

- **Slow-POST closed.** Every branch answering before the body is consumed now
  closes the connection. Pinned by raw-socket tests; verified to fail without the
  fix (`server never hung up; it said: HTTP/1.1 401 Unauthorized`).
- **`temperature` split per endpoint** to match what each corpus actually scored.
- **`codeSwitchVocabulary` restored**, scoped to Latin-in-Hebrew only.
- **Hebrew final forms corrected.** The `שלומ` → `שלום` class is now fixed by
  orthography rather than dictionary lookup — because `isKnownWord("שלומ")`
  returns *true* inside the engine, so the dictionary-based version never fired.
- **`SampleHandler.reads` behind `OSAllocatedUnfairLock`**, read once per frame.
- **Fourteen doc claims corrected**, including two comments that described the
  fingerprint crop backwards and three that credited tests which assert nothing.

## Gates, after the fixes

| Gate | Result |
|---|---|
| `AIKeyboardCoreTests` | **286 tests, 2 skipped, 0 failures** |
| `prove-app-group.sh` | PASS |
| `prove-broadcast-extension.sh` | PASS |
| `prove-capture-channel.sh` | PASS |
| `Backend` | **70 tests, 0 fail** |

The 2 skips are `SpeechLanguageTests`, which refuses to assert over the
simulator's empty locale list rather than pass vacuously.

## Open, and honestly so

- **Nothing in the ReplayKit path has ever executed.** No `replayd` on the
  simulator. `Scripts/measure-on-device.sh` reads the ten device-only unknowns off
  a phone. Signing is no longer in the way: as of 2026-08-09 a Development
  certificate is installed, the three App IDs carry `group.com.nitai.aikeyboard`,
  the phone is in all three profiles, and `-destination generic/platform=iOS`
  builds clean. What is left is physically connecting it.
- Which physical rotation ReplayKit reports as `.left` vs `.right` is a guess,
  isolated to one 6-line switch.
- The backend's rate limit counts in-process against `--max-instances=10`.
- Dictation is blocked on a supported hand-off trigger, not on the microphone.
