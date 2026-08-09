# Gauntlet: first device run

**Goal.** Every defect the phone found is gone, and a fresh critic holding
`.claude/gauntlet-device-defects.md` cannot name a way the product still falls
short of the stock iOS keyboard.

**Bar.** `.claude/gauntlet-device-defects.md` — ten defects observed on a real
iPhone on 2026-08-09, each paired with what Apple's own keyboard does in the
same moment. Critics open that file and the code; they never see the builder's
report.

**Test command.**
`xcodebuild test -project AIKeyboard.xcodeproj -scheme AIKeyboard -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`

---

## Pieces

| # | Piece | Defects | State |
|---|---|---|---|
| P1 | Typing reaches the document | D1, D2 | round 3 done, 3 critic rounds, all gaps closed |
| P3 | Setup status stops lying, playground copy | D4, D7 | round 3 done, 2 critic rounds |
| P4 | Broadcast, keyboard start button, no frames | D5, D8, D9 | round 3 done, 2 critic rounds |
| P5 | One-tap Rewrite in the suggestion row + custom tone | D6 | round 1 done, 1 critic round; engine half landed in P11 |
| P9 | Every language (14 layouts) | D10 | round 2 done, 1 critic round |
| P2 | Swipe the space bar to switch language | D3 | round 2 done, 1 critic round |
| P10 | The cloud is not connected on a real install | — | `Settings › AI › Cloud model` ships; **deploy still needs the owner** |
| F1 | The app stops over-promising what it cannot do | — | done, closed the final critic's gap |
| P11 | Custom-tone engine, text replacement, 3 language gaps | D6, D10 | round 3 done, 2 critic rounds |
| P12 | Privacy manifests (submission blocker, found mid-run) | — | done by lead, reason codes need verifying |


## Final state, 2026-08-09

**499 tests, 0 failures**, 2 skipped. All nine UI tests pass, including the three
in `KeyboardTypesIntoHostTests` that press real keys on the real extension over a
real `UITextField` — nothing in this repo did that before this run. All three
`Scripts/prove-*.sh` pass. `swift-format lint --strict` silent. 54 files changed,
+4675 / -754.

Every piece went through at least one fresh-context critic; five went through
two or three. **Every single critic round found a real gap.** None returned
"beats the bar" first time.

### What the critics caught that the builders did not

- Nine separate tests that passed against the exact bug they were named after,
  each for a different reason: a `weak` reference held alive by a method-scoped
  local; `SuggestionEngine`'s hardcoded `["I","The","We"]` for an empty prefix;
  its unconditional echo of the typed prefix; a stub that never implemented the
  `@objc` optional it was asked about; `CaptureChannel.sweep` only removing
  directories; a language list of one that the product cannot produce; a test
  target with no `TEST_HOST`, where `store.userDefaults` *is* `.standard`; two
  that called the channel by hand instead of the decision that changed.
- A permanent, uncorrectable "Full Access ✓ On" after revocation — then, after
  that was fixed with a 72h decay, the same lie **resurrected by every reboot**,
  because `CLOCK_MONOTONIC_RAW` restarts at zero and an old stamp reads as fresh
  again once uptime passes it.
- A runaway backspace: fixing the typing bug armed a key-repeat loop that a
  cancelled touch never cancels, deleting into whichever field the user focused
  next at 22 presses a second.
- Autocorrect corrupting the language the user chose: the suggestion engine was
  never told which *layout* was on screen, so `dont` on a French keyboard became
  `don't`, and Persian beside Arabic got Arabic's dictionary.
- The custom tone splicing a Hebrew register into the English instruction set —
  the merge this repo has measured as unsafe — and, on the on-device path,
  rejecting the whole session.
- **The unit mismatch.** `String.count` is graphemes, `UITextInput` offsets are
  UTF-16, and `deleteBackward()` is neither: one press takes a whole flag or ZWJ
  sequence but takes Hebrew niqqud one mark at a time. Measured, not reasoned.
  Then the same bug found again in `replaceCurrentWord`, on the hotter path —
  `hi שָׁלומ` + space gave `hi שָשָׁלום`, corrupting the correction this repo
  built Hebrew final-form handling for.

### Still owed

- **No backend is deployed.** The app can now be pointed at one from
  `Settings › AI › Cloud model`, and that one string is what all four dead ends
  print. Until a server exists, screen context and every Hebrew AI action are
  inert — correctly and legibly so, but inert.
- **`PrivacyInfo.xcprivacy` reason codes are unverified.** `35F9.1` and `1C8F.1`
  are from knowledge; Apple's docs render client-side and could not be fetched,
  and Xcode ships no searchable list. Check before submitting.
- **`adjustTextPosition`'s unit is asserted by a double, not a host.** Nothing a
  user can reach calls it without a model answer in hand, and no simulator can
  produce one. A device with a backend configured closes it.
- Ten device-only capture unknowns (R1, R2, R2c, R3, R7, R8/9, R11, R14, R16,
  R17) remain unmeasured. The in-app diagnostics panel answers them from the
  phone with no Mac attached.
- The screen-context prompt still offers the model only "hebrew"/"english".
  Widening it re-opens a corpus scored against `Bar/screen-context/`; the exact
  artifacts owed are written into `ScreenPrompt`'s doc comment.

## P10, found while fixing D5 and bigger than it

`BackendTransport.configured()` reads `cloudBackendURL` from the shared store.
Nothing in the app can set it, and it has never been set — grep finds it in
`CloudTransport.swift:119` and in tests, nowhere else. So on the phone that
reported these defects: screen-context reading is dead (cloud-only), every
Hebrew AI action is dead (Foundation Models has no Hebrew), and only English
Fix/Rewrite works, on device. `Backend/deploy.sh` has never been run.

This is very likely the whole of D5. Needs: a way to set the URL from the app,
the setup checklist to count it, and a deployed service. The deploy bills the
owner's Google Cloud account, so it waits for them.

---

## P1 — Typing reaches the document

**Round 1 (lead).** Root cause found by reading, not by running:
`KeyboardController.target` was `weak`, and `KeyboardViewController` built its
`ProxyTextTarget` in argument position, so nothing retained it. It was gone
before the first keystroke and every `target?.insertText` was a no-op against
nil. The in-app playground hid this for the whole of development because
`KeyboardPreview` holds its `MockTextTarget` as a `@StateObject`.

Three changes:
- `KeyboardController.target` is strong. Nothing conforming to `TextTarget`
  references the controller back, so no cycle.
- `ProxyTextTarget` gained a resolving initialiser and asks
  `UIInputViewController` for `textDocumentProxy` per call, so a host swapping
  the focused field cannot leave the keyboard typing into the old one.
- `KeyboardViewController` holds the target itself as well.

`AIKeyboardCoreTests/KeyboardControllerTargetTests.swift` is the regression, and
its shape is the point: every existing test kept its target in a method-scoped
local, which outlives the assertion, so the suite was green against a keyboard
that could not type. These take the reference out of scope first.

**Round 1 critic: GAP.** The autocomplete regression passed against the exact bug
it described. With a nil target `currentWordPrefix` is empty, `SuggestionEngine`
takes its empty-prefix branch and returns the hardcoded `["I", "The", "We"]` —
three items, so `XCTAssertFalse(suggestions.isEmpty)` was true of the broken
keyboard too. `SuggestionEngineTests:107` pins that same triple, so the two files
agreed with each other and with nothing on the phone. The critic also noted that
the device symptom matches exactly: the bar never went blank, it sat on
`I / The / We` while the document underneath was unreadable.

Second finding, smaller: `[unowned self]` in the resolver was a new trap.
`KeyView.startRepeatIfNeeded` is an unstructured `Task` cancelled only from
`DragGesture.onEnded`, so a gesture interrupted by teardown calls back into a
dead controller. Pre-fix a silent leak; post-fix a crash.

**Round 2 (lead).**
- The autocomplete test asserts on content: a candidate must continue `"hel"`.
- The resolver returns `UITextDocumentProxy?` and every accessor answers nil
  rather than substituting a default; the extension uses `[weak self]`.
- `AIKeyboardUITests/KeyboardTypesIntoHostTests.swift` is new and is the only
  test in the repo that presses a key on the *real extension* over a real
  `UITextField` and reads the field back. The two existing cross-process tests
  already stood the extension over that field and asserted only that a key
  *existed*; neither ever pressed one.
- `SuggestionBar` candidates gained `suggestion-<slot>` identifiers so the bar is
  addressable from a UI test.

**Round 2 critic: GAP, the same defect one level deeper.** `SuggestionEngine`
unconditionally offers the literal keystrokes as candidate zero
(`SuggestionEngine.swift:240`) so the user can never be trapped in a word they
did not type. So `hasPrefix("hel")` is true of *any* build that reads the
document at all — including one whose `UITextChecker` lookup is broken and shows
one chip reading `hel` beside two blanks. Both new assertions were true by
construction. It also caught that D2's end-to-end test `XCTSkip`ped when the
field stayed empty, which would turn D1's regression into a green skip on the one
test covering D2 end to end, and that a repeating `Timer` firing into an
`XCTestExpectation` with `assertForOverFulfill` set would raise.

It confirmed by building that the UI test compiles, that the accessibility
identifiers resolve, and that all five unit tests fail against the original code
under Debug. It found no second cause for D1.

**Round 3 (lead).** Both assertions now exclude the echo: only a word the engine
had to *generate* counts. D2's test asserts the keystrokes arrived instead of
skipping. `waitUntil` replaces the `Timer`/expectation pair.

Status: re-judging.

---

## P3 — Setup status stops lying (D4, D7)

**Round 1.** The three ticks were hardcoded `@State` booleans; nothing checked
anything. Replaced with a `KeyboardPresence` record the extension writes into the
App Group from `viewDidAppear`. Its *existence* is the proof — iOS grants a
keyboard the container only with Full Access — so one file answers "installed,
permitted, and opened at least once" at once. Microphone read from
`AVAudioApplication.recordPermission` and moved out of the score, because a
keyboard extension can never reach the microphone and a checklist that cannot
reach 3/3 is the same nag. Fake stats (`1,284 words fixed`, `37m time saved`)
deleted. `KeyboardPreview` gained a hint shown only while the seed text is
untouched.

**Round 1 critic: GAP, and it is a worse lie than the defect.** `.confirmed`
never expires. `recordedAt` is written but no reader consults it, and the writer
needs the container, which *is* the permission — so the only process that can
correct the record cannot run in the state needing correction. Revoke Full Access
and Home says "Ready to type 2/2, Full Access ✓ On" forever, with no Settings
button, while cloud rewrites and key clicks are dead. Terminal, uncorrectable.
Also: the "added but no Full Access" branch never says the words "Full Access"
and its advice cannot work; two tests cannot fail (`sweep` only removes
directories, so the survives-sweep test asserts a property no implementation
lacks); and `SetupState` lives in the app target, which the test target cannot
import, so the `nil → .unknown` mapping that *is* the D4 fix has no test at all.

**Round 2:** in progress — decay `.confirmed` against the monotonic stamp, name
the permission in the ambiguous copy, make the two tests able to fail, move the
decision function somewhere testable.

## P4 — Screen context (D5, D8, D9)

**Round 1.** Ruled out, by reading the built Mach-O: the extension is embedded,
signed, entitled and correctly addressed. Ruled out: crash paths in
`SampleHandler`, and a permanently stale `ended` (already capped at 10 minutes).
Found instead three ways the pipeline runs and does nothing, none of which had a
voice — no shared container (published nothing, keyboard showed no strip at all
while iOS showed a recording indicator), no reader (`BackendTransport.configured`
nil, the shipped default, while the strip promised "Reply can read this screen"),
and `broadcastFinished` writing `.stopped` unconditionally so a session that never
got a frame was indistinguishable from the user stopping it. Each now names
itself, and a broadcast that cannot work refuses to start.

D8: disassembled the simulator's ReplayKit. `-[RPSystemBroadcastPickerView
buttonPressed:]` is two XPC calls and nothing else — no `UIApplication`, no
presented view controller, and no ReplayKit header carries
`NS_EXTENSION_UNAVAILABLE`. So the picker moved into `AIKeyboardCore` and the
keyboard has a start button, with the open-the-app copy kept underneath because
whether `replayd` answers a keyboard extension is unproven.

D9: user-facing counters reframed; every raw row kept behind a collapsed
developer disclosure so R1/R2/R3/R7/R11/R17 stay answerable from the phone.

Status: critic running.
