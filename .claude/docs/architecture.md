# Architecture

## Overview

A SwiftUI iOS app, a keyboard extension and a ReplayKit broadcast extension,
sharing local Swift packages that hold the entire keyboard.

**The intelligence is not mocked, and this line used to say it was.** The text
actions run for real through `RoutedIntelligence`, which picks between
`FoundationModelsEngine` on device and `CloudIntelligence` over the network, and
screen context runs for real through `RoutedScreenReader` over frames a broadcast
extension captures. What is still mocked is narrower and named in `README.md`'s
mock-to-real table: the scripted screen-context demo (`MockScreenContext`) the
app plays when no broadcast is running. Dictation is no longer among them —
`DictationService` records in the app, `SpeechGate` decides on the device whether
anybody spoke, and `CloudDictation` transcribes; `MockDictation` is deleted.

## Directory Map

| Directory | Purpose |
|---|---|
| `Packages/AIKeyboardCore/Sources/AIKeyboardCore/` | The whole keyboard, the design system, and the engines. The app and the keyboard extension link it. Imports SwiftUI and UIKit throughout. |
| `Packages/AIKeyboardCore/Sources/AIKeyboardShared/` | Foundation-only: the capture channel, the frame fingerprint, `ScreenReadingRecord`, the end reasons. Its whole reason to exist is that the broadcast extension needs these types and must not link `AIKeyboardCore`. Re-exported from `AIKeyboardCore` by `SharedExports.swift`, so nothing above has to know about the split. |
| `Packages/AIKeyboardCore/Sources/CaptureAtomics/` | Four static inline C functions: the seqlock fences. C because Swift 5.9 has none — `Synchronization.Atomic` is iOS 18, `<stdatomic.h>` does not import, and `OSAtomic` has been deprecated since iOS 10. |
| `AIKeyboardExtension/` | Extension host only. `KeyboardViewController` installs `KeyboardView` and owns the height constraint; no UI is authored here. |
| `AIKeyboardBroadcast/` | The ReplayKit broadcast upload extension. Links `AIKeyboardShared` and nothing else of ours. Never runs on the Simulator: that runtime ships no `replayd`. |
| `AIKeyboardCoreTests/` | Host-less unit tests over `AIKeyboardCore`. |
| `AIKeyboardUITests/` | Screenshot walkthrough, plus the two cross-process proofs, which drive both processes and leave the verdict to a log line. |

## Data Flow

- Keystroke → `KeyView` gesture → `KeyboardController.press(_:)` → `TextTarget`.
  Views never touch the document directly.
- `TextTarget` is the seam that makes the keyboard runnable in two places:
  `ProxyTextTarget` wraps the real `UITextDocumentProxy` in the extension,
  `MockTextTarget` is an in-memory string used by the app's playground and
  onboarding.
- AI actions read `aiTargetText` (the selection, else the whole field), run
  `RoutedIntelligence` through `beginWork`, and write back by deleting exactly
  the characters that were sent before inserting the replacement. `MockAI` is
  gone; the engine behind `beginWork` is real.
- Screen context flows one way: `ScreenContextSession` publishes state,
  `KeyboardController` mirrors it via Combine, and the strip and Reply panel read
  only the controller. The session has two sources and they are not equals — a
  real capture session on `ScreenContextChannel`, and the scripted sample the app
  offers — and a real one cancels the script rather than racing it. `source` says
  which, so nothing paints a recording indicator over a demo.
- Reply does not use the state it is looking at. `KeyboardController.runReply`
  calls `ScreenContextSession.contextForReply()`, which polls the channel at the
  instant of the tap, raises `intent.readNow` when the gate refuses what it has,
  and waits for a record answering *that* sequence. A reading the gate refused is
  never returned; the failure is `AIEngineError.screenNotRead`.
- The capture channel is the one place two *processes* exchange state, and it is
  not `UserDefaults`. `AIKeyboardBroadcast` fingerprints each sampled frame and
  writes `channel/status.bin`; the keyboard maps the same page read-only at 4 Hz
  through `ScreenContextChannel` and runs `CaptureFreshness` over it. Both pages
  are `mmap(MAP_SHARED)` behind a seqlock, so a write is a memcpy inside a 60 fps
  callback and a half-written page is a retry rather than a wrong answer. A
  seqlock admits one writer at a time and the producing process writes from three
  threads (delivery queue, heartbeat timer, lifecycle callbacks), so `SharedPage`
  also holds an in-process lock across each transaction; readers take nothing. Only
  text and hashes cross: the pages hold timestamps, counters and a SHA-256, and
  `ScreenReadingRecord` has no image field by construction.

## Key Patterns

- **The keyboard lives in the package, not the extension.** This is what lets the
  companion app render the real keyboard before iOS has installed anything, and
  it is why `KeyboardViewController` is deliberately thin.
- **One controller owns all mutation.** `KeyboardController` is the only type that
  edits text or drives overlays; every view is a projection of its published
  state.
- **Mocks are isolated behind named types** (`MockScreenContext`) so each has a
  single obvious replacement point. See the mock-to-real table in `README.md`.
- **Design tokens are centralised in `Theme.swift`.** Colors resolve per
  appearance through `Color.adaptive(light:dark:)`; keyboard metrics live in
  `Theme.Metrics` because the extension and the in-app preview must agree on
  them exactly.

## Dependencies Between Modules

`AIKeyboard` (app) → `AIKeyboardCore`. `AIKeyboardExtension` → `AIKeyboardCore`.
`AIKeyboardBroadcast` → `AIKeyboardShared` **only**. `AIKeyboardCore` →
`AIKeyboardShared` → `CaptureAtomics`. The app embeds both extensions.
`AIKeyboardCore` depends on nothing but Apple frameworks, and must not import
either app target — that direction is what keeps the keyboard renderable from
both sides.

The one arrow that is a hard rule rather than a preference is the missing one:
**`AIKeyboardBroadcast` must never link `AIKeyboardCore`.** A broadcast upload
extension is killed at ~50 MB and `AIKeyboardCore` pulls in SwiftUI and UIKit for
nothing there. `Scripts/prove-capture-channel.sh` check 1 reads the Mach-O and
fails if either appears.
