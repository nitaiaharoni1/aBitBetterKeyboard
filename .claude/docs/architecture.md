# Architecture

## Overview

A SwiftUI iOS app plus a keyboard extension, sharing one local Swift package that
holds the entire keyboard. All intelligence is mocked: no network, model,
microphone, or screen capture.

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
- AI actions read `aiTargetText` (the selection, else the current sentence), run a
  mock through `beginWork`, and write back by deleting exactly the characters
  that were sent before inserting the replacement.
- Screen context flows one way: `ScreenContextSession` publishes state,
  `KeyboardController` mirrors it via Combine, and the strip and Reply panel read
  only the controller.
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
- **Mocks are isolated behind named types** (`MockSuggestionEngine`,
  `MockDictation`, `MockScreenContext`) so each has a single obvious replacement
  point. See the mock-to-real table in `README.md`.
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
