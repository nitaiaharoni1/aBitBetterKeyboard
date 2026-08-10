# Testing

## Test Runner

XCTest via `xcodebuild test`, in two shapes:

- **`AIKeyboardCoreTests`** — unit tests over `AIKeyboardCore`: routing, language
  detection, `OutputGuard`, `EditScope`, the capture channel's seqlock and page
  layouts, the frame fingerprint's crop band, the freshness gate. Fast, no
  simulator UI. No count is quoted anywhere on purpose — it went stale three
  times in a single session, and a number that is wrong more often than it is
  right is worse than no number. Run the target.
- **`AIKeyboardUITests`** — UI walkthroughs that drive the app in the simulator,
  plus the two cross-process suites. Those two assert almost nothing themselves;
  they get both processes running and the verdict is read out of the log by
  `Scripts/prove-app-group.sh` and `Scripts/prove-capture-channel.sh`. That is
  deliberate: a process always sees its own writes, so the only honest evidence
  is a line the *other* process emitted, stamped with its name by the OS.

**Target the simulator by UDID, not by name.** Two devices are commonly booted here
and `name=iPhone 17 Pro` is ambiguous between `iPhone 17 Pro` and `iPhone 17 Pro
Max`, which have diverged App Group state:

```bash
-destination "platform=iOS Simulator,id=0966F3D6-2589-4E88-BE84-4A69CD64FEE8"
```

**Never run two test targets against one device at once.** The runners kill each
other and it reports as "crashed with signal kill", not as a test failure. Every
phantom failure in this project so far has been contention.

**A crashed UI test can print `passed`.** After a mid-run crash the harness restarts
and may report `Executed 0 tests … passed` while the exit code is 65. Trust the exit
code, never the summary line.

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

- `AIKeyboardUITests/` — `DemoWalkthroughTests.swift` has four tests split by
  area: onboarding, keyboard panels, screen context, companion screens.
  `KeyboardExtensionTestCase` holds the setup every cross-process test needs
  (install the keyboard, grant Full Access, focus a real text field, switch to
  our keyboard) and `AppGroupCrossProcessTests` and
  `CaptureChannelCrossProcessTests` inherit it. `StockKeyboardReferenceTests`
  also lives here and skips unless `Bar/typing/capture.sh` has been run. Steps
  that cannot be completed `throw XCTSkip`; the assertions come after setup has
  genuinely succeeded.
- `AIKeyboardCoreTests/` — unit tests for the AI engines, in a host-less
  unit-test target that links `AIKeyboardCore`. Like the other targets it is a
  `PBXFileSystemSynchronizedRootGroup`, so a new file in that folder is compiled
  with no `.pbxproj` edit. It covers language routing, prompt selection, engine
  failover and the cloud wire format; it cannot cover on-device generation,
  because no simulator ships model assets.

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
- Dictation crosses a process boundary, so its UI test holds both processes up
  for a fixed window rather than waiting on an element; the verdict is read out
  of the extension's log by `Scripts/prove-dictation.sh`, like the other two
  cross-process suites.

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
and `AIKeyboardUITests` drives the app rather than the engines. `AIKeyboardCoreTests` is where the engines are covered directly, and it is where almost all of the assertions in this repo live.
