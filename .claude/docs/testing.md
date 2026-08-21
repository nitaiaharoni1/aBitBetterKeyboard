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

**A `!` on nil in a *unit* test does the same thing, and the totals lie rather than
go missing.** `XCTAssert` failures are recorded; a force-unwrap of nil is a
`fatalError`, so it takes the whole `xctest` process down. The harness prints
`Restarting after unexpected exit, crash, or test timeout; summary will include
totals from previous launches`, relaunches, and then reports one stitched
`Executed N tests, with M failures` line that reads like a complete run. It is not
one — anything the crashed launch had not reached is simply absent from the count,
and the crash itself is not in the failure list. **Grep for `Fatal error` and
`Restarting after` before you believe any summary**, and never trust a failure
count you have not checked that way. It has happened three times here and always
the same way: a test reaching into `KeyboardCustomization.default` for a key that
had quietly left the shipped layout — `.dictation` when it moved to the action row,
then `.globe` when `.settings` took its slot. Prefer `try XCTUnwrap` over `!` in a
fixture, so the test fails and the bundle carries on.

## Running one file's logic without a simulator

**A test that has only compiled has not run, and in this repo a lot of them never
do.** `xcodebuild test` needs a simulator and is minutes long, so pure logic in
`AIKeyboardShared` can sit unexercised for a long time behind a green build. The
build proves it type-checks and nothing more.

For a Foundation-only type there is a third option between "compiled" and "ran
the suite": **compile the real source file on macOS with stubs for whatever it
names, and run the assertions as a command-line program.** `Bar/emoji/harness/
swift-check.sh` is the same idea for `EmojiSearch`. Copy the actual file rather
than transcribing the logic, or the harness proves your understanding instead of
the code:

```bash
cp Packages/AIKeyboardCore/Sources/AIKeyboardShared/KeyboardLaunchRecord.swift "$D/"
# Stubs.swift: public enum CaptureClock { public static func now() -> UInt64 { 0 } }
#              public enum KeyboardPresence { public static let bootIdentity: UInt64 = 0 }
#              public enum SharedContainer { public static var url: URL? { nil } }
swiftc -O -o check KeyboardLaunchRecord.swift Stubs.swift main.swift && ./check
```

Two things that bite. **The stubs have to be `public`** if the real type names
them in a default argument of a `public` function, or the compiler refuses the
default rather than the call. And **only stub what is off the path you are
testing** — pass `now:` and `bootIdentity:` explicitly and use the `at:` URL
overloads, so a stub returning 0 or nil can never be what the assertion is
reading.

This is what `KeyboardLaunchRecord`'s eight cases were verified with on
2026-08-21 and `SecureDecisionRecord`'s seven on 2026-08-22, since the suite was
not run either time. It works for anything in `AIKeyboardShared`; it does not
work for `AIKeyboardCore`, which imports UIKit and SwiftUI and drags in the whole
module.

**There is a weaker second form for `AIKeyboardCore`, and it is worth the
distinction.** Where the *type* cannot be lifted out, the **control flow**
sometimes can: copy the function bodies verbatim over a trivial stand-in for
whatever they operate on, and run the same scenarios. That is a test of the
control flow rather than of the shipping type, so it is evidence about the shape
of the code and not about the code. Say which one you did.

**Do both directions, or the harness proves nothing.** Run it against the fixed
version *and* against the broken one, and check the broken one fails. On
2026-08-22 that is what turned "10/10 assertions pass" into a real result:
swapping `FileManager.attributesOfItem` back to `URL.resourceValues` made 4 of
the 10 fail, and those four are the same four assertions `LaunchPathTests` makes
— which is how those XCTest cases are known to reject the broken build rather
than merely to compile.

**And this is not decoration: it found a bug reading did not.** `URL` caches
resource values on the `NSURL` behind it, so a stamp taken through a *stored*
`URL` never moves, and `PersonalLanguageModel` would have stopped re-reading the
learned-word file altogether. Reasoning about that API gave the wrong answer;
running it took a minute. Reach for this whenever a change rests on how a
Foundation API behaves rather than on what its documentation says.

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
