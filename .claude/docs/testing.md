# Testing

## Test Runner

XCUITest (XCTest) via `xcodebuild test`. There are no unit tests yet — every test
is a UI walkthrough that drives the app in the simulator.

## Running Tests

```bash
# Run all tests
xcodebuild test -project AIKeyboard.xcodeproj -scheme AIKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Run one test
xcodebuild test -project AIKeyboard.xcodeproj -scheme AIKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:AIKeyboardUITests/DemoWalkthroughTests/testKeyboardPanels

# Run with screenshots written to disk
TEST_RUNNER_SHOT_DIR=/tmp/shots xcodebuild test -project AIKeyboard.xcodeproj \
  -scheme AIKeyboard -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

`AIKeyboard` is the only shared scheme and it owns the test action; there is no
`AIKeyboardUITests` scheme to pass to `-scheme`.

## Test Structure

- `AIKeyboardUITests/` — one file, `DemoWalkthroughTests.swift`, with four tests
  split by area: onboarding, keyboard panels, screen context, companion screens.
- `Packages/AIKeyboardCore/` has no `Tests/` directory. The mock engines
  (`MockSuggestionEngine`, `MockAI`) are pure, deterministic functions and are
  the obvious first candidates for unit tests.

## Writing Tests

- Tap by accessibility identifier through the `element(_:)` helper, never by
  coordinate. Identifiers follow a prefix convention: `key-*` for keyboard keys,
  `bar-*` for suggestion-bar controls, `ai-action-*` for AI menu cards, `row-*`
  for navigation rows, `home-*` for Home cards.
- `element(_:)` searches `descendants(matching: .any)` on purpose: SwiftUI
  exposes keys as `.key` and cards as `.button`, and pinning the type at each
  call site makes tests brittle.
- Launch arguments set the starting state: `-uiTestReset` clears every stored
  setting, `-uiTestSkipOnboarding` jumps straight to the main tabs. Both are read
  in `AIKeyboard/AIKeyboardApp.swift`.
- `capture(_:)` writes a numbered PNG per screen, so a test doubles as the
  screenshot walkthrough. Keep the names descriptive; they become filenames.
- Mock timings are real sleeps (`MockAI.simulatedLatency`, dictation streaming),
  so `settle(_:)` waits have to exceed them or the assertion races the animation.

## Workflow

- Write or update tests alongside the code they verify, not as a separate step after.
- Bug fixes: add a failing test that reproduces the bug before writing the fix.
- After implementation, run the full test suite to verify nothing else broke.

## Coverage

Xcode's built-in coverage is enabled on the shared scheme
(`codeCoverageEnabled = "YES"`). Read a report from the result bundle:

```bash
xcodebuild test -project AIKeyboard.xcodeproj -scheme AIKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -resultBundlePath /tmp/AIKeyboard.xcresult

xcrun xccov view --report /tmp/AIKeyboard.xcresult
```

Expect low numbers: UI walkthroughs exercise view code broadly but assert little,
and the engines in `AIKeyboardCore` have no direct tests.
