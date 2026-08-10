# The action row drives the banner — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** No tap on the keyboard's action row may cover the keys — every outcome,
including a refusal, is said in `ActionBanner`.

**Architecture:** The three panels that still paint over the key grid
(`AIMenuPanel`, `AIResultPanel`, `DictationPanel`) are deleted. Their four refusal
paths — Fix on an empty field, Rewrite on an empty field, Reply with no screen-context
session, Dictate with no app session — collapse into one new `BannerState.blocked` case
carrying a title, a detail and a remedy that is either a Dismiss button or Apple's
broadcast picker itself. `KeyboardOverlay` loses `.aiMenu`, `.aiResult` and `.dictation`
and keeps only the emoji-family cases.

**Tech Stack:** Swift 5.9, SwiftUI, UIKit, XCTest. No third-party dependencies. The
keyboard UI lives in the local package `Packages/AIKeyboardCore`, never in
`AIKeyboardExtension`.

**Spec:** `docs/superpowers/specs/2026-08-10-action-row-drives-banner-design.md`

## Global Constraints

- **Do not start until the parallel emoji session confirms it has landed.** That session
  owns `Models.swift`, `KeyboardView.swift`, `KeyboardView+Keys.swift`,
  `KeyboardController.swift`, `KeyboardController+Typing.swift`, `KeyView+Label.swift`
  and `SuggestionBar+Edges.swift`. Tasks 1 and 3 avoid all seven and may be done first;
  every later task touches at least one.
- **The baseline builds clean.** An earlier draft claimed a duplicate `AIAction`
  declaration blocked everything; that was a prefix match on `AIActionResultKind` and is
  not real. `xcodebuild build` succeeds on the tree this plan starts from.
- **`KeyboardOverlay` already carries `.emojiSearch`** and an `isEmoji` helper, landed by
  the parallel session. Task 7 deletes `.aiMenu`, `.aiResult` and `.dictation` and leaves
  both of those exactly as they are.
- **Never run the test suite.** The user's standing instruction. Verify every task with
  `xcodebuild build-for-testing`, which compiles the app *and* the test targets and runs
  nothing:
  ```bash
  xcodebuild build-for-testing -project AIKeyboard.xcodeproj -scheme AIKeyboard \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
  ```
  Tests are still written, and they must be honest. Running them is the user's call.
- **Work on `main`.** No feature branches, no worktrees. Commit on trunk.
- **Commit subject lines carry no em dashes or en dashes.** Bodies may use whatever reads
  best.
- **The banner is 48pt and must not grow.** `Theme.Metrics.bannerHeight` is capped by the
  frame fingerprint, not by taste — see `FrameReduction.Band.maximumOwnUI` and
  `.claude/rules/screen-context.md`. Nothing in this plan may raise it.
- **Assert against the broken build.** Before writing any assertion, work out what
  today's code returns and check the assertion rejects it. For every new banner
  assertion that means pairing the state with `XCTAssertEqual(controller.overlay, .none)`
  — asserting the state alone passes against a build that shows the state *and* a panel.
- `xcrun swift-format` runs automatically per edited file via a PostToolUse hook. Do not
  run it by hand.

## File Structure

**Created**
- none

**Modified**
- `Packages/AIKeyboardCore/Sources/AIKeyboardCore/BannerState.swift` — the new `.blocked`
  case and its `Block` payload; `.needsSetup` and `screenContextPromptTitle` removed
- `.../ActionBanner.swift` — `resolve` call site, `resultPanelIsOpen` removed
- `.../ActionBanner+Content.swift` — `.blocked` leading tag and caption; dictation
  countdown in the tag
- `.../ActionBanner+Trailing.swift` — `.blocked` trailing button and the picker chip
- `.../KeyboardController.swift` — one `@Published var block`
- `.../KeyboardController+Banner.swift` — `block(_:)`, and `block` cleared in `clearBanner`
- `.../KeyboardController+AI.swift` — Fix/Reply refusals become blocks; `beginWork` clears
  `block`; `run(.tone)` loses its panel
- `.../KeyboardController+Tone.swift` — `runTone` loses its `destination` computation
- `.../KeyboardController+Dictation.swift` — the no-session refusal becomes a block
- `.../KeyboardController+ScreenContext.swift` — `screenContextPrompt`, moved off the panel
- `.../KeyboardController+Typing.swift` — `.aiMenu` press removed; keystrokes clear `block`
- `.../SuggestionBar+ToneButton.swift` — `ToneTap.openMenu` → `.needsText`; `sparkleButton`
  removed
- `.../SuggestionBar+Edges.swift` — the `.aiMenu` arm of `slotButton` removed
- `.../Models.swift` — `KeyboardOverlay` loses three cases; `AIActionResultKind` removed
- `.../KeyboardView.swift` — `coversFullKeyArea` and `fullKeyAreaPanel` lose three branches
- `.../CustomLayout.swift`, `.../KeySpec.swift`, `.../SlotAction+KeyCap.swift`,
  `.../KeyView+Label.swift`, `.../LayoutPresets.swift` — `SlotAction.aiMenu` and
  `KeyCap.aiMenu` removed, two presets given real keys
- `.claude/rules/keyboard-layout.md` — the rule and the three costs

**Deleted**
- `.../AIMenuPanel.swift`
- `.../AIResultPanel.swift`, `.../AIResultPanel+Replies.swift`, `.../AIResultPanel+Variants.swift`
- `.../DictationPanel.swift`
- `.../PanelChrome.swift` (confirm against the rewritten emoji panel first)

**Tests modified** — surveyed rather than guessed; the first draft of this list missed
half of them.
- `AIKeyboardCoreTests/BannerStateTests.swift` — `resultPanelIsOpen` cases deleted, the
  two `resultsShownElsewhere` cases deleted, `block` added to the helper
- `AIKeyboardCoreTests/AIButtonTests.swift` — `:84` overlay assertion, `:106` `.openMenu`,
  and five `AIMenuPanel.isAvailable` / `.hasRunnableAction` call sites that move to
  `AIAction`
- `AIKeyboardCoreTests/CustomKeyActionTests.swift` — three tests whose *purpose* is that
  a menu opens (`testAIMenuKeyTogglesTheMenu`,
  `testTheQuickToneKeyOpensTheMenuWithNothingToRewrite`, and the empty-field routing test)
- `AIKeyboardCoreTests/DefaultToneTests.swift:208,236` — two `show(.aiMenu)` flows
- `AIKeyboardCoreTests/DictationKeyboardTests.swift:48` —
  `testWithNoSessionThePanelExplainsAndNothingIsDictated`, whose assertion is literally
  "the panel must still open, to explain"
- `AIKeyboardCoreTests/CustomLayoutTests.swift` — five `.aiMenu` references across the
  catalogue, cap and slot-action lists
- `AIKeyboardCoreTests/LayoutEditorTests.swift:223` — `model.add(.aiMenu, to: .barTrailing)`
- `AIKeyboardUITests/DemoWalkthroughTests.swift:173` — waits on `dictation-explanation`
- `AIKeyboardUITests/EmptyFieldBarTests.swift:75` — waits on `ai-action-reply`, an
  accessibility identifier that only exists on `AIMenuPanel`'s cards

**Two things the first draft of this plan got wrong**
- `AIMenuPanel.isAvailable(_:hasTextToWorkWith:)` and
  `AIMenuPanel.hasRunnableAction(hasTextToWorkWith:)` are **not** panel code.
  `SuggestionBar+Edges.swift:41` reads the second to decide the emoji key's tint, and
  five tests read both. They move to `AIAction` as
  `isAvailable(hasTextToWorkWith:)` and `static hasRunnableAction(hasTextToWorkWith:)`
  before the panel is deleted.
- Adding `BannerState.blocked` breaks the exhaustive switches in `ActionBanner+Content`
  and `+Trailing` immediately, so Tasks 1 and 3 cannot be separate commits. They landed
  together.

---

### Task 1: The `.blocked` state

The pure value-type half. Touches no file the emoji session owns, so it can be done
first and in isolation.

**Files:**
- Modify: `Packages/AIKeyboardCore/Sources/AIKeyboardCore/BannerState.swift`
- Test: `AIKeyboardCoreTests/BannerStateTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `BannerState.blocked(BannerState.Block)`;
  `BannerState.Block(action:title:detail:remedy:)` with
  `action: AIAction?`, `title: String`, `detail: String`,
  `remedy: BannerState.Block.Remedy` (`.none` | `.broadcastPicker`);
  a new `block: BannerState.Block?` parameter on `BannerState.resolve`, placed
  immediately after `error:` and before `resultsShownElsewhere:`.

- [ ] **Step 1: Write the failing tests**

Add to `AIKeyboardCoreTests/BannerStateTests.swift`. First extend the private
`resolve` helper with `block: BannerState.Block? = nil`, passed through to
`BannerState.resolve` in the same position. Then:

```swift
    // MARK: A refusal

    private let noSession = BannerState.Block(
        action: .reply,
        title: "Screen context is off",
        detail: "Tap to pick AI Keyboard, then Start Broadcast.",
        remedy: .broadcastPicker)

    /// **A recording outranks a refusal**, for the reason it outranks everything
    /// else here: it is running in another process and stopping it is the
    /// time-critical thing on screen. A refusal is a sentence about a tap that did
    /// nothing, and it can wait.
    func testARecordingOutranksARefusal() {
        let state = resolve(isDictating: true, block: noSession)
        XCTAssertEqual(state, .dictating(transcript: "", isListening: true))
    }

    /// **A refusal outranks the idle hint**, which is the ordering the whole case
    /// exists for. Resolved the other way the user taps Reply with no session and
    /// the strip goes on reading "Type, or pick an action below" — which is what
    /// today's build does before the panel opens over it.
    func testARefusalOutranksTheIdleHint() {
        let state = resolve(block: noSession)
        XCTAssertEqual(state, .blocked(noSession))
    }

    /// **A refusal outranks a live screen-context reading.** The idle branch prefers
    /// the reading over the hint, and a refusal about Reply drawn under the very
    /// message it refused to answer would be the worst of both.
    func testARefusalOutranksAScreenContextReading() {
        let context = ScreenContext(
            appName: "WhatsApp", appIcon: "message", sender: "Dana",
            message: "מה קורה", language: .hebrew)
        let state = resolve(block: noSession, screenContext: context)
        XCTAssertEqual(state, .blocked(noSession))
    }

    /// **A refusal does not survive the next call.** `beginWork` clears it, so a
    /// state carrying both is not reachable — but resolve is the one place that
    /// decides, and a version that tested `block` after `isWorking` would leave a
    /// stale refusal under a running shimmer if that clearing ever regressed.
    func testWorkOutranksARefusal() {
        let state = resolve(isWorking: true, runningAction: .fix, block: noSession)
        XCTAssertEqual(state, .working(.fix))
    }
```

- [ ] **Step 2: Build to verify the tests fail to compile**

Run:
```bash
xcodebuild build-for-testing -project AIKeyboard.xcodeproj -scheme AIKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
Expected: FAIL — "type 'BannerState' has no member 'blocked'" and no member `Block`.
A compile failure is this codebase's red step: `BannerState` is an enum with an
exhaustive `resolve`, so a missing case cannot fail at runtime.

- [ ] **Step 3: Add the case and the payload**

In `BannerState.swift`, after the `case dictationFailed(String)` declaration:

```swift
    /// An action the user tapped that could not run, and what they can do about it.
    ///
    /// **One case for four refusals, because each of them used to be a panel.**
    /// Fix and Rewrite on an empty field, Reply with no screen-context session, and
    /// Dictate with no session in the containing app all covered every key row to
    /// say one or two sentences. They differ only in the words and in whether there
    /// is anything to tap, so they differ only in this payload.
    case blocked(Block)

    public struct Block: Equatable, Sendable {

        /// What the user can do about it from inside the keyboard, which is almost
        /// never anything: a keyboard extension has no `UIApplication`, so it
        /// cannot open Settings, cannot launch the containing app and cannot start
        /// a dictation session. See `.claude/rules/dictation.md`.
        public enum Remedy: Equatable, Sendable {
            /// Nothing here can fix it. Dismiss is the only button.
            case none
            /// The trailing chip *is* `RPSystemBroadcastPickerView`, which is the
            /// one system affordance a keyboard extension can host. See
            /// `BroadcastPickerButton` for the disassembly that establishes it.
            case broadcastPicker
        }

        /// Which action was refused, so the strip can label it with the same glyph
        /// and word the key wears. `nil` is dictation, which is not an `AIAction`.
        public let action: AIAction?
        public let title: String
        public let detail: String
        public let remedy: Remedy

        public init(action: AIAction?, title: String, detail: String, remedy: Remedy) {
            self.action = action
            self.title = title
            self.detail = detail
            self.remedy = remedy
        }
    }
```

- [ ] **Step 4: Add the parameter and the branch to `resolve`**

In the signature, immediately after `error: AIEngineError?,`:

```swift
        /// An action the user tapped that refused to start. Set by the tap and
        /// cleared by `beginWork`, so it cannot describe the same tap as
        /// `isWorking` — the ordering below is decided rather than incidental.
        block: Block?,
```

In the body, immediately after the two dictation branches and **before**
`if resultsShownElsewhere`:

```swift
        // Above every idle branch and above the work branches, because this is a
        // sentence about the tap the user just made. Below dictation for the reason
        // dictation is first: that is a recording in another process.
        if let block { return .blocked(block) }
```

- [ ] **Step 5: Build to verify it compiles**

Run the same `build-for-testing` command.
Expected: SUCCEED. Every `resolve` call site now passes `block:`; there are two —
`ActionBanner.state` and the test helper. Add `block: nil` to `ActionBanner.state` for
now; Task 4 replaces it.

- [ ] **Step 6: Commit**

```bash
git add Packages/AIKeyboardCore/Sources/AIKeyboardCore/BannerState.swift \
  Packages/AIKeyboardCore/Sources/AIKeyboardCore/ActionBanner.swift \
  AIKeyboardCoreTests/BannerStateTests.swift
git commit -m "Give the banner a state for a tap that could not run"
```

---

### Task 2: The controller holds the block

**Files:**
- Modify: `.../KeyboardController.swift` (one line, ~line 63 beside `aiError`)
- Modify: `.../KeyboardController+Banner.swift`
- Modify: `.../KeyboardController+AI.swift:127-150` (`beginWork`)
- Modify: `.../KeyboardController+Typing.swift`
- Test: `AIKeyboardCoreTests/AIButtonTests.swift`

**Interfaces:**
- Consumes: `BannerState.Block` from Task 1.
- Produces: `KeyboardController.block: BannerState.Block?`;
  `KeyboardController.refuse(_ block: BannerState.Block)`;
  `clearBanner()` and `beginWork` both clear `block`.

- [ ] **Step 1: Write the failing test**

Add to `AIKeyboardCoreTests/AIButtonTests.swift`:

```swift
    /// **A refusal does not outlive the keystroke that answers it.** "Type something
    /// first" is true until the user types something, and a strip still saying it
    /// over a field with a word in it is worse than having said nothing.
    @MainActor
    func testTypingClearsARefusal() {
        let controller = KeyboardController.preview(language: .english, text: "")
        controller.refuse(
            .init(action: .fix, title: "Nothing to fix yet",
                  detail: "Type something first, then tap Fix.", remedy: .none))
        XCTAssertNotNil(controller.block)

        controller.press(.character("a"))

        XCTAssertNil(controller.block)
    }

    /// **A refusal is not drawn over the previous action's answer.** `refuse` clears
    /// the banner first, so a Reply refused for want of a session cannot appear with
    /// the three rewrites from a minute ago still paging underneath it.
    @MainActor
    func testARefusalClearsThePreviousAnswer() {
        let controller = KeyboardController.preview(language: .english, text: "hello")
        controller.variants = [RewriteVariant(tone: .shorter, text: "hi")]
        controller.runningAction = .rewrite

        controller.refuse(
            .init(action: .reply, title: "Screen context is off",
                  detail: "Tap to pick AI Keyboard, then Start Broadcast.",
                  remedy: .broadcastPicker))

        XCTAssertTrue(controller.bannerOptions.isEmpty)
        XCTAssertNil(controller.runningAction)
    }
```

- [ ] **Step 2: Build to verify it fails**

Run the `build-for-testing` command.
Expected: FAIL — no member `refuse`, no member `block`.

- [ ] **Step 3: Add the property**

In `KeyboardController.swift`, immediately after `@Published public var aiError: AIEngineError?`:

```swift
    /// An action the user tapped that refused to start. Beside `aiError` because it
    /// is the same kind of fact about a different moment: `aiError` is a call that
    /// failed, this is a call that never began.
    @Published public var block: BannerState.Block?
```

- [ ] **Step 4: Add `refuse` and the clearing**

In `KeyboardController+Banner.swift`, add:

```swift
    /// Refuses an action the user tapped, and says why in the strip.
    ///
    /// **Clears the banner first, and that is not tidiness.** `clearBannerState`
    /// empties `variants`, `replies` and `aiResultText`; without it a Reply refused
    /// for want of a session would draw its sentence over the three rewrites the
    /// previous action left in place, with the pager still offering to page through
    /// them.
    public func refuse(_ block: BannerState.Block) {
        Feedback.modifierPress()
        withAnimation(Theme.Motion.content) {
            clearBannerState()
            self.block = block
        }
    }
```

In the same file, add `block = nil` to `clearBannerState()`, at the end of its body.

In `KeyboardController+AI.swift`, inside `beginWork`, beside `aiError = nil`:

```swift
        block = nil
```

- [ ] **Step 5: Clear it on a keystroke**

In `KeyboardController+Typing.swift`, at the top of `insertCharacter(_:)` and at the
top of `deleteBackward()`:

```swift
        // Only the refusal, never the whole banner: an answer the user is reading
        // must survive them fixing a typo before they accept it.
        block = nil
```

- [ ] **Step 6: Build to verify it compiles**

Run the `build-for-testing` command. Expected: SUCCEED.

- [ ] **Step 7: Commit**

```bash
git add Packages/AIKeyboardCore/Sources/AIKeyboardCore/KeyboardController.swift \
  Packages/AIKeyboardCore/Sources/AIKeyboardCore/KeyboardController+Banner.swift \
  Packages/AIKeyboardCore/Sources/AIKeyboardCore/KeyboardController+AI.swift \
  Packages/AIKeyboardCore/Sources/AIKeyboardCore/KeyboardController+Typing.swift \
  AIKeyboardCoreTests/AIButtonTests.swift
git commit -m "Hold a refused action on the controller, and clear it on the next key"
```

---

### Task 3: The banner draws a refusal

Touches only `ActionBanner+*`, so it can be done alongside Task 1 without waiting for
the emoji session.

**Files:**
- Modify: `.../ActionBanner+Content.swift`
- Modify: `.../ActionBanner+Trailing.swift`

**Interfaces:**
- Consumes: `BannerState.blocked(_:)` from Task 1.
- Produces: nothing other tasks call.

- [ ] **Step 1: Add the leading tag**

In `ActionBanner+Content.swift`, in `leading`, replace the `.needsSetup` arm with:

```swift
        case .blocked(let block):
            tag(
                "exclamationmark.triangle",
                block.action?.title ?? "Dictation",
                tint: Theme.Semantic.warning)
```

- [ ] **Step 2: Add the middle**

In `content`, replace the `.needsSetup` arm with:

```swift
        case .blocked(let block):
            VStack(alignment: .leading, spacing: 0) {
                Text(block.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Keys.label)
                    .lineLimit(1)
                caption(block.detail)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(block.title). \(block.detail)")
            .accessibilityIdentifier("banner-blocked")
```

This is the same two-line shape `.failed` and `.dictationFailed` already use, which is
why no new visual vocabulary is needed. `caption` already allows two lines at 11pt.

- [ ] **Step 3: Add the trailing button**

In `ActionBanner+Trailing.swift`, replace the `.needsSetup` arm with:

```swift
        case .blocked(let block):
            switch block.remedy {
            case .none:
                button("Dismiss", tint: nil, filled: false) { controller.clearBanner() }
                    .accessibilityIdentifier("banner-blocked-dismiss")
            case .broadcastPicker:
                pickerChip(block)
            }
```

and add, beside `button(_:tint:filled:action:)`:

```swift
    /// Apple's own broadcast picker, sized to the strip.
    ///
    /// **The tap target is 10pt smaller than this in each dimension**, because
    /// `-[RPSystemBroadcastPickerView addBroadcastPickerButton]` insets its real
    /// `UIButton` by 5 on every edge — so 42 here is a 32pt target, against the 42
    /// the deleted panel could afford at 52. The strip cannot grow to buy it back:
    /// `Theme.Metrics.bannerHeight` is capped by the frame fingerprint, not by
    /// taste. See `BroadcastPickerButton` and `.claude/rules/screen-context.md`.
    ///
    /// White first, brand tint over it, like every other call site: the system
    /// assigns the glyph's colour itself from `UIScreen.main.isCaptured` and never
    /// inherits, so the background under it has to be light in both appearances.
    func pickerChip(_ block: BannerState.Block) -> some View {
        BroadcastPickerButton(width: 42, height: 42)
            .frame(width: 42, height: 42)
            .background(
                Circle()
                    .fill(Theme.Text.onBrand)
                    .overlay(Circle().fill(Theme.Brand.softGradient))
            )
            .accessibilityLabel("Start screen context")
            .accessibilityHint("Opens the iOS screen broadcast picker. \(block.detail)")
            .accessibilityIdentifier("banner-start-broadcast")
    }
```

- [ ] **Step 4: Build**

Run the `build-for-testing` command.
Expected: SUCCEED. `.needsSetup` is still declared in `BannerState`; it is deleted in
Task 4, and until then the compiler will demand it in both switches. Keep the
`.needsSetup` arms in place alongside the new `.blocked` ones for this task only.

- [ ] **Step 5: Commit**

```bash
git add Packages/AIKeyboardCore/Sources/AIKeyboardCore/ActionBanner+Content.swift \
  Packages/AIKeyboardCore/Sources/AIKeyboardCore/ActionBanner+Trailing.swift
git commit -m "Draw a refusal in the banner, with the picker as its button"
```

---

### Task 4: Reply refuses in the strip

**Files:**
- Modify: `.../KeyboardController+ScreenContext.swift`
- Modify: `.../KeyboardController+AI.swift:69-76` (`runReply`)
- Modify: `.../ActionBanner.swift:57-87`
- Modify: `.../BannerState.swift` (delete `.needsSetup` and `screenContextPromptTitle`)
- Modify: `.../ActionBanner+Content.swift`, `.../ActionBanner+Trailing.swift` (delete the
  `.needsSetup` arms left from Task 3)
- Test: `AIKeyboardCoreTests/AIButtonTests.swift:84`

**Interfaces:**
- Consumes: `refuse(_:)` from Task 2, `.blocked` rendering from Task 3.
- Produces: `KeyboardController.screenContextPrompt: ScreenContextPrompt`.

- [ ] **Step 1: Rewrite the failing test**

Replace the assertion at `AIKeyboardCoreTests/AIButtonTests.swift:84`:

```swift
        // The whole point of the change: the keys stay visible. Asserting the block
        // alone would pass against the build that sets it *and* opens the panel.
        XCTAssertEqual(controller.overlay, .none)
        XCTAssertEqual(controller.block?.action, .reply)
        XCTAssertFalse(controller.block?.title.isEmpty ?? true)
```

- [ ] **Step 2: Build to verify it fails**

Run the `build-for-testing` command.
Expected: FAIL — `.aiResult(.needsScreenContext)` is still what `runReply` sets, so the
first assertion is false. If the build succeeds, the test compiled but is not yet
red; that is expected here because this is a value assertion rather than a missing
symbol. Note it and continue to step 3.

- [ ] **Step 3: Move the prompt onto the controller**

Cut the `prompt` and `endedReason` computed properties out of
`AIResultPanel+Replies.swift:149-176` and add them to
`KeyboardController+ScreenContext.swift`, renamed and made public:

```swift
    /// The ending on the record, if the last thing that happened was one. `.off` is
    /// not an ending: it is the ordinary state of a phone that has never started a
    /// broadcast, and it has no reason to print.
    var screenContextEndReason: ScreenContextEndReason? {
        guard case .ended(let reason) = screenContext else { return nil }
        return reason
    }

    /// Why Reply cannot run, in the four distinct sentences `ScreenContextPrompt`
    /// separates, and whether starting a broadcast now could get further than the
    /// last one did.
    ///
    /// **Read at the tap, not held.** Both measurements are about another process:
    /// `CaptureChannel.isReachable` is whether this one can reach the App Group at
    /// all, and `BackendTransport.isReady()` is whether there is anywhere to send a
    /// screen once captured. `isReady`, not `configured() != nil` — a broadcast that
    /// starts with no token ends inside a second, after asking the user for the
    /// screen-recording permission and recording their screen for nothing.
    public var screenContextPrompt: ScreenContextPrompt {
        ScreenContextPrompt(
            canReachChannel: CaptureChannel.isReachable,
            cloudConfigured: BackendTransport.isReady(),
            ended: screenContextEndReason)
    }
```

- [ ] **Step 4: Refuse instead of opening the panel**

In `KeyboardController+AI.swift`, `runReply`, replace:

```swift
            withAnimation(Theme.Motion.panel) { overlay = .aiResult(.needsScreenContext) }
            return
```

with:

```swift
            let prompt = screenContextPrompt
            refuse(
                .init(
                    action: .reply,
                    title: prompt.title,
                    detail: prompt.detail,
                    remedy: prompt.offersPicker ? .broadcastPicker : .none))
            return
```

- [ ] **Step 5: Shorten the one detail written for a panel**

In `ScreenContextPrompt.swift:56-57`, replace the `offersPicker = true` branch's detail:

```swift
        detail =
            "Reply answers the message in front of you. Tap to pick AI Keyboard, then Start Broadcast. If nothing opens, start it in the app."
```

The three refusal details are already one sentence each and fit as they are. Update the
matching expectation in `AIKeyboardCoreTests/ScreenContextPromptTests.swift`.

- [ ] **Step 6: Delete `.needsSetup`**

In `BannerState.swift`, delete the `case needsSetup(String)` declaration, its
`if needsScreenContextSetup` branch in `resolve`, the `needsScreenContextSetup:`
parameter, and the `screenContextPromptTitle` constant at the bottom of the file.
Delete the `.needsSetup` arms from `ActionBanner+Content.swift` (both `leading` and
`content`) and `ActionBanner+Trailing.swift`. In `ActionBanner.state`, drop
`needsScreenContextSetup:` and replace `block: nil` with `block: controller.block`.
Delete the `needsScreenContextSetup:` parameter from the test helper in
`BannerStateTests.swift` and any case that passed it.

- [ ] **Step 7: Build**

Run the `build-for-testing` command. Expected: SUCCEED.

- [ ] **Step 8: Commit**

```bash
git add -A Packages/AIKeyboardCore/Sources/AIKeyboardCore AIKeyboardCoreTests
git commit -m "Refuse Reply in the banner instead of a full-screen panel"
```

---

### Task 5: Fix and Rewrite refuse in the strip

**Files:**
- Modify: `.../KeyboardController+AI.swift:17` (`run(_:)`'s guard)
- Modify: `.../KeyboardController+Tone.swift:55,107` (`selectTone(named:)`, `runDefaultTone`)
- Modify: `.../SuggestionBar+ToneButton.swift:15-32,105,153-157`
- Modify: `.../KeyboardController+Typing.swift:60-73` (the `.quickTone` press)
- Test: `AIKeyboardCoreTests/AIButtonTests.swift`

**Interfaces:**
- Consumes: `refuse(_:)` from Task 2.
- Produces: `SuggestionBar.ToneTap.needsText` replacing `.openMenu`;
  `KeyboardController.refuseForEmptyField(_ action: AIAction)`.

- [ ] **Step 1: Write the failing tests**

```swift
    /// **Fix on an empty field says so.** It used to return from a guard and draw
    /// nothing at all — the dead button `AIMenuPanel.hasRunnableAction` records this
    /// repo having shipped once already.
    @MainActor
    func testFixOnAnEmptyFieldSaysWhyRatherThanNothing() {
        let controller = KeyboardController.preview(language: .english, text: "")
        controller.run(.fix)
        XCTAssertEqual(controller.overlay, .none)
        XCTAssertEqual(controller.block?.action, .fix)
        XCTAssertEqual(controller.block?.remedy, BannerState.Block.Remedy.none)
    }

    /// **Rewrite on an empty field no longer opens a menu over the keys.** Asserting
    /// only that a block is set would pass against a build that sets one and opens
    /// `AIMenuPanel` on top of it, which is exactly what today does.
    @MainActor
    func testRewriteOnAnEmptyFieldRefusesWithoutCoveringTheKeys() {
        let controller = KeyboardController.preview(language: .english, text: "")
        controller.press(.quickTone)
        XCTAssertEqual(controller.overlay, .none)
        XCTAssertEqual(controller.block?.action, .rewrite)
    }
```

- [ ] **Step 2: Build to verify it fails**

Run the `build-for-testing` command.
Expected: FAIL — no member `refuseForEmptyField` is needed yet, but `.quickTone` still
resolves to `show(.aiMenu)`, so the overlay assertion is false.

- [ ] **Step 3: Add the shared refusal**

In `KeyboardController+Banner.swift`:

```swift
    /// The refusal Fix and Rewrite share: there is nothing in the field to work on.
    ///
    /// One function rather than two call sites writing the sentence, because the key
    /// and the suggestion bar's own button both reach it and this repo has already
    /// shipped a bar and a panel that disagreed about what an empty field means.
    public func refuseForEmptyField(_ action: AIAction) {
        refuse(
            .init(
                action: action,
                title: "Nothing to \(action.title.lowercased()) yet",
                detail: "Type something first, then tap \(action.title).",
                remedy: .none))
    }
```

- [ ] **Step 4: Call it from the three places that guard on text**

`KeyboardController+AI.swift:17`:
```swift
        guard hasTextToWorkWith else {
            refuseForEmptyField(action)
            return
        }
```

`KeyboardController+Tone.swift`, in both `selectTone(named:)` and `runDefaultTone()`,
replace `guard hasTextToWorkWith, !isWorking else { return }` with:
```swift
        guard !isWorking else { return }
        guard hasTextToWorkWith else {
            refuseForEmptyField(.rewrite)
            return
        }
```
A call in flight stays a silent ignore: the button is showing a spinner, so the tap has
already been answered.

- [ ] **Step 5: Rename `ToneTap.openMenu`**

In `SuggestionBar+ToneButton.swift`, rename the case and rewrite its comment:

```swift
        /// Nothing to rewrite. The tap says so in the banner rather than opening
        /// anything: the panel this used to be a shortcut through is deleted, and a
        /// tap that draws nothing is the defect this enum's third case exists to
        /// prevent.
        case needsText
```

Update `toneTap` to return `.needsText`, the `switch tap` in `toneButton` to
`case .needsText: controller.refuseForEmptyField(.rewrite)`, and `toneHint` to
`case .needsText: return "Nothing to rewrite yet. Says what to do about it"`.

In `KeyboardController+Typing.swift`'s `.quickTone` arm, replace
`case .openMenu: show(.aiMenu)` with `case .needsText: refuseForEmptyField(.rewrite)`.

- [ ] **Step 6: Build**

Run the `build-for-testing` command. Expected: SUCCEED.

- [ ] **Step 7: Commit**

```bash
git add -A Packages/AIKeyboardCore/Sources/AIKeyboardCore AIKeyboardCoreTests
git commit -m "Say why Fix and Rewrite did nothing on an empty field"
```

---

### Task 6: Dictation refuses in the strip, and the panel goes

**Files:**
- Modify: `.../KeyboardController+Dictation.swift:7-28,41`
- Modify: `.../ActionBanner+Content.swift` (the countdown in the tag)
- Modify: `.../ActionBanner.swift:60-61` (the `overlay != .dictation` clause)
- Delete: `.../DictationPanel.swift`
- Test: `AIKeyboardCoreTests/DictationKeyboardTests.swift`

**Interfaces:**
- Consumes: `refuse(_:)` from Task 2.
- Produces: nothing other tasks call.

- [ ] **Step 1: Write the failing test**

```swift
    /// **Dictate with no session in the app explains, and does not cover the keys.**
    /// The explanation is the important half: nothing in a keyboard extension can
    /// start a session or launch its own app, so this is a dead end the user has to
    /// be walked out of by hand. See `.claude/rules/dictation.md`.
    @MainActor
    func testDictateWithNoSessionExplainsWithoutCoveringTheKeys() {
        let controller = KeyboardController.preview(language: .english, text: "")
        controller.startDictation()
        XCTAssertEqual(controller.overlay, .none)
        XCTAssertNil(controller.block?.action)
        XCTAssertTrue(controller.block?.detail.contains("Start dictation") ?? false)
    }
```

- [ ] **Step 2: Build to verify it fails**

Run the `build-for-testing` command.
Expected: FAIL — `startDictation` sets `overlay = .dictation`.

- [ ] **Step 3: Refuse instead of opening the panel**

In `KeyboardController+Dictation.swift`, replace the opening of `startDictation`:

```swift
    public func startDictation() {
        guard dictation.availability.isLive else {
            refuse(
                .init(
                    action: nil,
                    title: dictationRefusalTitle,
                    detail: dictationRefusalDetail,
                    remedy: .none))
            return
        }
```

and add the two strings, carrying the same words `DictationPanel.explanationText`
printed:

```swift
    private var dictationRefusalTitle: String {
        switch dictation.availability {
        case .needsFullAccess: return "Dictation needs Full Access"
        default: return "No dictation session"
        }
    }

    /// **Names the app, the screen and the button**, because nothing in here can
    /// press any of them: a keyboard extension has no `UIApplication`, cannot open
    /// Settings and cannot launch its containing app. See `.claude/rules/dictation.md`.
    private var dictationRefusalDetail: String {
        switch dictation.availability {
        case .needsFullAccess:
            return
                "Recording happens in the AI Keyboard app. Turn on Full Access in Settings › General › Keyboard › Keyboards."
        case .noSession(let reason):
            let why = reason == .notEnded || reason == .stoppedByUser ? "" : reason.explanation + " "
            return "\(why)Open AI Keyboard, tap Start dictation, then come back."
        default:
            return ""
        }
    }
```

Delete `|| overlay == .dictation` from the guard in `stopDictation(insert:)` and
`&& controller.overlay != .dictation` from `ActionBanner.state`'s `dictationIsLive`.

- [ ] **Step 4: Keep the countdown, drop the badge**

In `ActionBanner+Content.swift`, replace the `.dictating` arm of `leading`:

```swift
        case .dictating(_, let isListening):
            // **The countdown replaces the word, and only in the last minute.** A
            // clock running for the whole session is one the user is invited to
            // watch; a clock that appears is news. It is the one thing the deleted
            // panel said that the strip has room to keep — the `עב ⟷ EN` badge is
            // not, and the transcript is already written in its own script.
            tag(
                "mic",
                dictationTagTitle(isListening: isListening),
                tint: Theme.Semantic.record)
```

and add:

```swift
    func dictationTagTitle(isListening: Bool) -> String {
        if let remaining = controller.dictationRemainingSeconds, remaining < 60 {
            return "\(Int(remaining))s left"
        }
        return isListening ? "Recording" : "Transcribing"
    }
```

- [ ] **Step 5: Delete the panel**

```bash
git rm Packages/AIKeyboardCore/Sources/AIKeyboardCore/DictationPanel.swift
```

`KeyboardView`'s `.dictation` branches still reference it and will not compile; Task 7
removes them. To keep this task independently buildable, do Step 5 and Task 7's Step 1
together if the build fails here.

- [ ] **Step 6: Build**

Run the `build-for-testing` command. Expected: SUCCEED.

- [ ] **Step 7: Commit**

```bash
git add -A Packages/AIKeyboardCore/Sources/AIKeyboardCore AIKeyboardCoreTests
git commit -m "Explain a missing dictation session in the banner, not over the keys"
```

---

### Task 7: The panels and the overlay cases go

**Files:**
- Modify: `.../Models.swift` (`KeyboardOverlay`, `AIActionResultKind`)
- Modify: `.../KeyboardView.swift:61-88`
- Modify: `.../ActionBanner.swift:78-87` (`resultPanelIsOpen`)
- Modify: `.../BannerState.swift` (`resultsShownElsewhere:`)
- Modify: `.../KeyboardController+Banner.swift:37-39` (`bannerOptions`' guard)
- Modify: `.../KeyboardController+Tone.swift:130-145` (`runTone`'s `destination`)
- Modify: `.../KeyboardController+AI.swift:53-58` (`run(.tone)`)
- Delete: `.../AIMenuPanel.swift`, `.../AIResultPanel.swift`,
  `.../AIResultPanel+Replies.swift`, `.../AIResultPanel+Variants.swift`,
  `.../PanelChrome.swift`
- Test: `AIKeyboardCoreTests/BannerStateTests.swift`, `DefaultToneTests.swift:225,254`

**Interfaces:**
- Consumes: everything above.
- Produces: `KeyboardOverlay` reduced to `.none`, `.emoji` and whatever emoji-family
  cases the parallel session added.

- [ ] **Step 1: Confirm `PanelChrome` is unused**

```bash
grep -rn "PanelSurface\|PanelHeader" --include="*.swift" Packages AIKeyboard
```
Expected after the deletions below: only `PanelChrome.swift` itself. If the rewritten
`EmojiPanel` or `EmojiSearchViews` uses either, keep `PanelChrome.swift` and say so in
the commit body.

- [ ] **Step 2: Delete the panels**

```bash
git rm Packages/AIKeyboardCore/Sources/AIKeyboardCore/AIMenuPanel.swift \
  Packages/AIKeyboardCore/Sources/AIKeyboardCore/AIResultPanel.swift \
  Packages/AIKeyboardCore/Sources/AIKeyboardCore/AIResultPanel+Replies.swift \
  Packages/AIKeyboardCore/Sources/AIKeyboardCore/AIResultPanel+Variants.swift \
  Packages/AIKeyboardCore/Sources/AIKeyboardCore/PanelChrome.swift
```

- [ ] **Step 3: Shrink the overlay**

In `Models.swift`, delete `case aiMenu`, `case aiResult(AIActionResultKind)` and
`case dictation` from `KeyboardOverlay`, and delete the whole `AIActionResultKind` enum.
Leave every emoji-family case exactly as the parallel session wrote it. Add:

```swift
/// What is drawn over the key grid, and it is only ever emoji now.
///
/// **Three cases were deleted rather than made to behave.** `.aiMenu`, `.aiResult`
/// and `.dictation` each painted over every key row to say one or two sentences, and
/// the states that reached them — an empty field, a screen-context session never
/// started, a dictation session never opened — are the ones a new user hits first. All
/// four of those paths are `BannerState.blocked` now. Emoji stays because it is drawn
/// inside the letter area and leaves the action row under the thumb that opened it.
```

- [ ] **Step 4: Simplify `KeyboardView`**

Replace `coversFullKeyArea` and `fullKeyAreaPanel` with whatever the emoji-family cases
require, and delete the `.aiMenu` / `.aiResult` / `.dictation` branches. If emoji search
is a full-key-area panel, it belongs in `coversFullKeyArea`; coordinate the exact shape
with the emoji session rather than guessing.

- [ ] **Step 5: Delete the arbitration that has nothing left to arbitrate**

- `ActionBanner.resultPanelIsOpen` — delete the function and its argument at the call
  site.
- `BannerState.resolve` — delete the `resultsShownElsewhere:` parameter and the
  `if resultsShownElsewhere { return idle(...) }` branch, plus the parameter from
  `BannerStateTests`' helper and the cases that pass it.
- `KeyboardController.bannerOptions` — delete the leading
  `if case .aiResult(let kind) = overlay, kind != .needsScreenContext { return [] }`.
- `runTone` — delete the `destination` computation and pass `showing: .none`.
- `run(_:)`'s `.tone` arm — replace the overlay assignment with `runTone(store.toneSetting)`,
  which is what `runDefaultTone` does. `AIAction.tone` itself stays:
  `FoundationModelsEngine.competentActions` and `TextIntelligence.route` use it to tell a
  named-register rewrite from a three-way one.

- [ ] **Step 6: Fix the tests that name the deleted things**

`DefaultToneTests.swift:225` (`controller.show(.aiMenu)`) and `:254`
(`controller.run(.tone)`) both change meaning. `BannerStateTests`' `resultPanelIsOpen`
cases are deleted outright.

- [ ] **Step 7: Build**

Run the `build-for-testing` command. Expected: SUCCEED.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Delete the three panels that covered the keys"
```

---

### Task 8: The sparkle key goes, the presets get real keys

**Files:**
- Modify: `.../CustomLayout.swift:60,78`
- Modify: `.../KeySpec.swift:65,132`
- Modify: `.../SlotAction+KeyCap.swift:23,54`
- Modify: `.../KeyView+Label.swift:86-90`
- Modify: `.../SuggestionBar+Edges.swift:16,63`
- Modify: `.../SuggestionBar+ToneButton.swift:153-180` (`sparkleButton`)
- Modify: `.../KeyboardController+Typing.swift:48-50`
- Modify: `.../LayoutPresets.swift:54,84`
- Test: `AIKeyboardCoreTests/CustomLayoutTests.swift`, `LayoutValidatorTests.swift`

**Interfaces:**
- Consumes: `AIMenuPanel` being gone (Task 7).
- Produces: `SlotAction` and `KeyCap` without `.aiMenu`.

- [ ] **Step 1: Write the failing test**

In `AIKeyboardCoreTests/CustomLayoutTests.swift`:

```swift
    /// **Every preset keeps a route to every AI action**, which is what the sparkle
    /// key used to buy for the two presets that spend the action row on something
    /// else. Asserting the sparkle is gone would pass against a build that deleted it
    /// and left "Power" with no way to reach Reply at all.
    func testEveryPresetReachesEveryAIAction() {
        for preset in LayoutPresets.all {
            let slots =
                preset.customization.barLeading + preset.customization.barTrailing
                + preset.customization.bottomRow + preset.customization.cursorRow
            let actions = Set(slots.map(\.action))
            XCTAssertTrue(
                actions.contains(.reply),
                "\(preset.id) has no way to reach Reply")
            XCTAssertTrue(
                actions.contains(.fix) || actions.contains(.quickTone),
                "\(preset.id) has no way to reach a text action")
        }
    }
```

- [ ] **Step 2: Build to verify it fails**

Run the `build-for-testing` command.
Expected: the build succeeds and the assertion is the red part — "Power" reaches Reply
only through `.aiMenu` today. Note it and continue.

- [ ] **Step 3: Delete the action and the cap**

- `CustomLayout.swift` — delete `case aiMenu` from `SlotAction`, its `"AI actions"`
  title, and its entry in the catalogue array at line 78.
- `KeySpec.swift` — delete `case aiMenu` from `KeyCap`, its `"AI actions"` name and its
  `"ai-menu"` identifier.
- `SlotAction+KeyCap.swift` — delete both `.aiMenu` arms.
- `KeyView+Label.swift` — delete the `.aiMenu` arm and its `SparkleMark(size: 18)`.
  `SparkleMark` itself stays; the containing app uses it in four places.
- `SuggestionBar+Edges.swift` — delete `.aiMenu` from the array at line 16 and the
  `case .aiMenu: sparkleButton` arm.
- `SuggestionBar+ToneButton.swift` — delete `sparkleButton` entirely.
- `KeyboardController+Typing.swift` — delete the `case .aiMenu` arm of `press(_:)`.

- [ ] **Step 4: Give the two presets real keys**

`LayoutPresets.swift`, "Power" — replace `layout.barTrailing = [SlotSpec(action: .aiMenu)]`:

```swift
                // **Two real keys instead of one key that opened a list.** This
                // preset spends the action row on arrows and punctuation, so
                // without these it would reach no AI action at all — and the menu
                // that used to cover that is deleted, because a list over the keys
                // is the thing this keyboard stopped doing.
                layout.barTrailing = [
                    SlotSpec(action: .reply),
                    SlotSpec(action: .quickTone)
                ]
```

"AI first" — replace `SlotSpec(action: .aiMenu, width: .units(1.2))` in `bottomRow` with
`SlotSpec(action: .reply, width: .units(1.2))`, and update the preset's `summary` from
`"The AI key in the grid, rewrite in the bar"` to `"Reply in the grid, rewrite in the bar"`.

- [ ] **Step 5: Handle a saved layout that names the deleted action**

`SlotAction` is `Codable`; a stored layout containing `aiMenu` now fails to decode.
Confirm `SharedStore.decodeLayout` falls back to `KeyboardCustomization.default` on a
decode failure rather than throwing, and add a test if it does not.

- [ ] **Step 6: Build**

Run the `build-for-testing` command. Expected: SUCCEED.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Replace the sparkle key with the actions it used to hide"
```

---

### Task 9: Write the rule down

**Files:**
- Modify: `.claude/rules/keyboard-layout.md`
- Modify: `.../ActionBanner+Content.swift` (the best-effort tag)

- [ ] **Step 1: Carry the best-effort notice into the tag**

`AIResultPanel.bestEffortNotice` is deleted with its panel. In `ActionBanner+Content.swift`,
in `leading`, replace the `.options` arm:

```swift
        case .working(let action):
            tag(action.icon, action.title, tint: Theme.Brand.solid)
        case .options(let action, _, _):
            // **Amber when the answer is a best effort**, which means the on-device
            // model answered in a language Apple does not list as supported because
            // no cloud engine was reachable. The panel said so in a sentence; a
            // one-line strip has no room for one, so the tag carries it and the
            // accessibility label carries the words.
            let bestEffort = controller.aiProvenance?.isBestEffort == true
            tag(
                bestEffort ? "info.circle" : action.icon,
                action.title,
                tint: bestEffort ? Theme.Semantic.warning : Theme.Brand.solid)
```

and append to the `.options` accessibility label in `content`:

```swift
                    + (controller.aiProvenance?.isBestEffort == true
                        ? ". Best effort, this language isn't fully supported on device" : "")
```

- [ ] **Step 2: Add the rule**

Append to `.claude/rules/keyboard-layout.md`:

```markdown
- **Nothing on the action row may cover the keys, and the refusals are what that cost.**
  Fix, Rewrite and Reply already reported in `ActionBanner` when they could run; every
  path where they *could not* fell back to a panel over every key row — `AIMenuPanel` for
  an empty field, `AIResultPanel(.needsScreenContext)` for Reply with no session,
  `DictationPanel` for a dictation session the app had never opened — so the states a new
  user hits first were exactly the ones that hid the keyboard, and Fix on an empty field
  drew nothing at all. All four are `BannerState.blocked` now, `KeyboardOverlay` carries
  only the emoji-family cases, and the three panels and `PanelChrome` are deleted. Three
  things were lost on purpose and are not worth rediscovering. **The broadcast picker's
  tap target went from 42pt to 32pt**: `-[RPSystemBroadcastPickerView
  addBroadcastPickerButton]` insets its real `UIButton` 5pt on every edge, so the 42×42
  chip the 48pt strip can afford leaves 32, against 52×52 in the panel — and the strip
  cannot grow to buy it back, because `Theme.Metrics.bannerHeight` is capped by the frame
  fingerprint. **The dictation countdown survived and the language badge did not**: `12s
  left` replaces the word `RECORDING` in the tag for the last minute only, because a
  session that closes itself is news, while the transcript is already written in its own
  script. And **the best-effort notice is a tag and an accessibility label**, not a
  sentence. `SlotAction.aiMenu` went with the menu it opened; "Power" and "AI first" carry
  real Reply keys instead, and `CustomLayoutTests.testEveryPresetReachesEveryAIAction` is
  what keeps them reaching everything.
```

- [ ] **Step 3: Build**

Run the `build-for-testing` command. Expected: SUCCEED.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Record what the banner-only action row cost"
```

---

## Self-review

**Spec coverage.** Every section maps to a task: the new state (1), the controller
plumbing (2), the rendering (3), the three refusals (4, 5, 6), the deletions (6, 7), the
sparkle key and the presets (8), the three costs and the rule (6, 9). The one spec item
with no code is the "not doing" list, which is correct.

**Placeholders.** Two steps deliberately stop short of exact code and say why: Task 7
Step 4 (`KeyboardView`'s overlay branches) and Task 8 Step 5 (`SharedStore.decodeLayout`).
Both depend on files the parallel emoji session is rewriting, and inventing their contents
here would be a worse failure than naming the dependency.

**Type consistency.** `BannerState.Block(action:title:detail:remedy:)` is used with those
four labels in Tasks 1, 2, 4, 5 and 6. `refuse(_:)` and `refuseForEmptyField(_:)` are
defined in Task 2 and Task 5 Step 3 respectively and called only after. `ToneTap.needsText`
replaces `.openMenu` in Task 5 and is not referenced before it. `screenContextPrompt` is
produced in Task 4 Step 3 and consumed in Step 4 of the same task.
