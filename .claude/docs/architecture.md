# Architecture

## Overview

A SwiftUI iOS app plus a keyboard extension, sharing one local Swift package that
holds the entire keyboard. All intelligence is mocked: no network, model,
microphone, or screen capture.

## Directory Map

| Directory | Purpose |
|---|---|
| `Packages/AIKeyboardCore/` | The whole keyboard, the design system, and the mock engines. Both app targets link it. |
| `AIKeyboardExtension/` | Extension host only. `KeyboardViewController` installs `KeyboardView` and owns the height constraint; no UI is authored here. |
| `AIKeyboardUITests/` | Screenshot walkthrough, not assertions. Each test writes a numbered PNG per screen. |

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

## Key Patterns

- **The keyboard lives in the package, not the extension.** This is what lets the
  companion app render the real keyboard before iOS has installed anything, and
  it is why `KeyboardViewController` is deliberately thin.
- **One controller owns all mutation.** `KeyboardController` is the only type that
  edits text or drives overlays; every view is a projection of its published
  state.
- **Mocks are isolated behind named types** (`MockSuggestionEngine`, `MockAI`,
  `MockDictation`, `MockScreenContext`) so each has a single obvious replacement
  point. See the mock-to-real table in `README.md`.
- **Design tokens are centralised in `Theme.swift`.** Colors resolve per
  appearance through `Color.adaptive(light:dark:)`; keyboard metrics live in
  `Theme.Metrics` because the extension and the in-app preview must agree on
  them exactly.

## Dependencies Between Modules

`AIKeyboard` (app) → `AIKeyboardCore`. `AIKeyboardExtension` → `AIKeyboardCore`.
The app also embeds the extension. `AIKeyboardCore` depends on nothing but Apple
frameworks, and must not import either app target — that direction is what keeps
the keyboard renderable from both sides.
