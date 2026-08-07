<!-- Keep this file and .claude/docs/ updated when project structure, conventions, or tooling changes -->

# AIKeyboard

A mock Hebrew/English iOS keyboard with AI text actions, dictation, and screen-context replies. Built with Swift, SwiftUI, UIKit and a local Swift package; no third-party dependencies.

## Commands

```bash
# Build
xcodebuild build -project AIKeyboard.xcodeproj -scheme AIKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Test (add TEST_RUNNER_SHOT_DIR=/tmp/shots to keep the screenshots)
xcodebuild test -project AIKeyboard.xcodeproj -scheme AIKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Format (the PostToolUse hook already does this per edited file)
xcrun swift-format --in-place --recursive AIKeyboard AIKeyboardExtension AIKeyboardUITests Packages
```

No linter is configured.

## Documentation

Read the doc that matches the change — not all of them.

| Changing | Read first |
|---|---|
| Code | `.claude/docs/coding-guidelines.md` |
| Tests | `.claude/docs/testing.md` |
| Module structure or data flow | `.claude/docs/architecture.md` |

## Gotchas

- **Everything is mocked on purpose.** No network, model, microphone, or screen capture anywhere. `MockAI`, `MockSuggestionEngine`, `MockDictation` and `MockScreenContext` are the swap points; `README.md` carries the mock-to-real table. Do not "fix" a mock by making it real without being asked.
- **The keyboard UI lives in `Packages/AIKeyboardCore/`, not in `AIKeyboardExtension/`.** The extension is a thin host so the companion app can render the same keyboard in onboarding and the playground. New keyboard UI goes in the package, or it stops working in the app.
- **Targets use `PBXFileSystemSynchronizedRootGroup`** (`objectVersion = 77`), so any file dropped into `AIKeyboard/`, `AIKeyboardExtension/` or `AIKeyboardUITests/` is compiled into that target with no `.pbxproj` edit. A file that must *not* compile needs a `membershipExceptions` entry, as `AIKeyboardExtension/Info.plist` has.
- **`swift build` inside `Packages/AIKeyboardCore` fails on macOS.** `Package.swift` declares `platforms: [.iOS(.v17)]` and the sources import UIKit and AudioToolbox, so the package only builds through the Xcode project against an iOS Simulator destination.
- **The App Group is declared but not entitled.** `SharedStore` asks for suite `group.com.nitai.aikeyboard`, no `.entitlements` file exists, so it silently falls back to `.standard` and the app and extension do not share state today.
