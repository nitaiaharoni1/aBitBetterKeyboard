<!-- Single source of project instructions. Claude Code reads it via .claude/CLAUDE.md; Cursor, Codex and Copilot read this file directly. Keep it under ~150 lines: it loads into every session. Area-specific detail belongs in .claude/rules/, which loads only when a matching file is opened. -->

# AIKeyboard

A Hebrew/English iOS keyboard with AI text actions, dictation, and screen-context replies. Swift, SwiftUI, UIKit and a local Swift package; no third-party dependencies.

## Commands

```bash
# Build
xcodebuild build -project AIKeyboard.xcodeproj -scheme AIKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Test (add TEST_RUNNER_SHOT_DIR=/tmp/shots to keep the screenshots)
xcodebuild test -project AIKeyboard.xcodeproj -scheme AIKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Format (the PostToolUse hook already does this per edited file)
xcrun swift-format --in-place --recursive \
  AIKeyboard AIKeyboardExtension AIKeyboardBroadcast AIKeyboardUITests AIKeyboardCoreTests Packages
```

No linter is configured.

## Where things live

- **Keyboard UI is in `Packages/AIKeyboardCore/`, not `AIKeyboardExtension/`.** The extension is a thin host so the companion app can render the same keyboard in onboarding and the playground. New keyboard UI goes in the package, or it stops working in the app.
- **`AIKeyboardShared` is the Foundation-only target** that the keyboard and the broadcast extension both link. `AIKeyboardCore` re-exports it. `AIKeyboardBroadcast` links `AIKeyboardShared` alone and must never link `AIKeyboardCore` — that would drag SwiftUI and UIKit into a process capped at ~50 MB.
- **Targets use `PBXFileSystemSynchronizedRootGroup`** (`objectVersion = 77`), so any file dropped into `AIKeyboard/`, `AIKeyboardExtension/`, `AIKeyboardBroadcast/`, `AIKeyboardUITests/` or `AIKeyboardCoreTests/` is compiled into that target with no `.pbxproj` edit — all five are synchronized roots. A file that must *not* compile needs a `membershipExceptions` entry, as both `AIKeyboardExtension/Info.plist` and `AIKeyboardBroadcast/Info.plist` have.
- **`swift build` inside `Packages/AIKeyboardCore` fails on macOS.** `Package.swift` declares `platforms: [.iOS(.v17)]` and the sources import UIKit and AudioToolbox, so the package only builds through the Xcode project against an iOS Simulator destination.
- `Bar/` holds the frozen corpora and scoring harnesses (`ai-text`, `dictation`, `screen-context`, `layouts`, `typing`). `Scripts/prove-*.sh` hold the checks that fail the build when an architectural invariant is broken.

## What is real

`MockScreenContext` is the only mock left: the scripted demo the app plays when no broadcast is running, and it yields to a real session the moment one appears. `MockDictation`, `MockAI` and `MockSuggestionEngine` are all deleted — `DictationService` records in the containing app, `SpeechGate` decides on the device whether anybody spoke and `CloudDictation` transcribes; `RoutedIntelligence` picks between `FoundationModelsEngine` and `CloudIntelligence`; and `SuggestionEngine` runs on `UITextChecker` and `UILexicon`. `README.md` carries the table of what is measured and what is only compiled.

## Rules that apply to every change

- **Apple's on-device stack has no Hebrew in three places, and that is not a blanket rule.** Foundation Models does not list it, `SpeechTranscriber` does not list it, and Vision's text recogniser does not list it (30 languages, identical across `VNRecognizeTextRequest`, the newer Swift `RecognizeTextRequest` and VisionKit Live Text, on both iOS and macOS). Arabic *is* in that list, so none of this is a right-to-left limitation. The counterexample is `UITextChecker`, whose `availableLanguages` lists `he_IL` among 42 and which completes `אנ` to `אני` and corrects `שלומ` to `שלום`, pinned by `SuggestionEngineTests`. It is an older API with its own language list, so do not reason from "Apple has no Hebrew" to a fourth API without checking it.
- **The App Group is real, and the keyboard needs Full Access to use it.** Both targets carry `com.apple.security.application-groups` for `group.com.nitai.aikeyboard` via `CODE_SIGN_ENTITLEMENTS`. iOS only grants a keyboard extension the shared container when the user allows Full Access, which is why `RequestsOpenAccess` is `true` in `AIKeyboardExtension/Info.plist`. `SharedStore.storage` reports `.appGroup` or `.processLocal` — it never pretends. Prove the round trip with `Scripts/prove-app-group.sh`; `UserDefaults(suiteName:)` being non-nil proves nothing, because it succeeds without the entitlement.
- **On the simulator, entitlements live in the binary, not the signature.** `codesign -d --entitlements` prints an empty dict for a simulator build; read `__TEXT,__entitlements` from the Mach-O instead, as the prove scripts do.
- **One corpus run is not evidence.** Two runs of *identical* code disagree on ~17 of the 58 entries and swing the total by 1–5 points; `he-en` alone moved 14/17 to 10/17 with nothing changed. Judge and model are both sampled. Compare at least two runs per side before believing a delta, and read per-entry verdicts rather than the total. Several of the "regressions" chased in round 3 turned out to be this.
- **Write assertions that reject the broken build.** Three tests in a row passed against the bug they were named after, each for a different reason. A `weak` reference held in a method-scoped local stays alive to the end of the method, so a test asserting through it proves nothing — take the reference out of scope first. `SuggestionEngine` returns a hardcoded `["I", "The", "We"]` for an empty prefix, so `XCTAssertFalse(suggestions.isEmpty)` was true of a keyboard whose document was unreadable — and that is exactly what the phone showed, a bar frozen on those three words. And `SuggestionEngine` unconditionally echoes the typed prefix as candidate zero (deliberately: the user must never be trapped in a word they did not type), so `contains { $0.hasPrefix(typed) }` is true even when the dictionary lookup is dead. Assert on something only the *fixed* build produces: a completion that is not the echo. Before writing any assertion here, work out what the broken version returns and check the assertion rejects it.
- **UI tests that drive the keyboard need an uncontended simulator.** Two `xcodebuild test` runs against the same device kill each other's runners, which reports as "crashed with signal kill" rather than a test failure.

## Where the traps are

Each area has hard-won findings with measured numbers behind them. Claude Code loads these automatically when you open a matching file. In Cursor, read the file yourself before changing anything in that area.

| Area | The trap in one line | Read before changing |
|---|---|---|
| Dictation | The microphone cannot live in the extension, and the model invents a sentence out of silence. | `.claude/rules/dictation.md` |
| AI text actions | Every generated option is vetted before it reaches the panel, and the schema field order is load-bearing. | `.claude/rules/ai-text.md` |
| Screen context and capture | The router never names a script, the thresholds differ between iOS and macOS, and the fingerprint band was wrong twice. | `.claude/rules/screen-context.md` |
| Suggestion bar | The personal dictionary is read at the keystroke, punctuation defeats it, and both brand-tinted buttons were wrong. | `.claude/rules/suggestion-bar.md` |
| Keyboard layout | Right-to-left rows are *not* mirrored; delete moves to a strictly shortest top row, otherwise the bottom row. | `.claude/rules/keyboard-layout.md` |
| Extension wiring | The in-app playground is not evidence that the keyboard works. | `.claude/rules/keyboard-wiring.md` |

## Documentation

Read the doc that matches the change, not all of them.

| Changing | Read first |
|---|---|
| Code | `.claude/docs/coding-guidelines.md` |
| Tests | `.claude/docs/testing.md` |
| Module structure or data flow | `.claude/docs/architecture.md` |
| ReplayKit capture contract | `.claude/docs/replaykit-contract.md` |
