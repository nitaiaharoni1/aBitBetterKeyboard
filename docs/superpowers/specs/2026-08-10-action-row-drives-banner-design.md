# The action row drives the banner, and never a drawer

Date: 2026-08-10
Status: approved, not implemented

## The problem

Tapping the action row still covers the keyboard three different ways.

Fix, Rewrite and Reply already run into `ActionBanner` when they can run at all —
`beginWork(_:showing: .none)` is the shipped path and `.claude/rules/keyboard-layout.md`
records why. What was never converted is the *refusal* half. Every path where the tap
cannot start a call falls back to a panel that paints over every key row:

| Tap | Condition | What opens |
|---|---|---|
| Rewrite (`quickTone`) | empty field | `AIMenuPanel` — a grid of the four AI actions |
| Reply | no live screen-context session | `AIResultPanel(.needsScreenContext)` |
| Dictate | no recording session in the containing app | `DictationPanel` |
| Fix | empty field | nothing at all — the key is silently dead |

So the states a user hits most often when they are new — empty field, screen context
never started, app never opened — are exactly the states that hide the keyboard. And
Fix is the dead button `AIMenuPanel.hasRunnableAction`'s doc comment says this repo has
already shipped once.

## The rule this establishes

**No tap on the action row may cover the keys.** The banner says what happened,
whatever happened, including "it did not run and here is why". Emoji is the single
exception and is already correct: it draws over the letter area only, inside `keyGrid`,
so the action row stays under the thumb that opened it.

`KeyboardOverlay` therefore collapses to `.none | .emoji`.

## Scope

In scope: the three panels above, the banner state that replaces them, the sparkle key
that has no behaviour left once `AIMenuPanel` is gone, and the two layout presets that
depend on it.

Out of scope, decided explicitly: **no visual restyle.** The action row keys keep
today's `KeyView` caps and the banner keeps today's surface, type and button shapes. The
banner looks different only in that it has states it did not have before, all drawn from
the vocabulary `ActionBanner+Content` and `ActionBanner+Trailing` already own — `tag`,
`caption`, `answer`, `button`.

## Design

### 1. One new banner state

```swift
public enum BannerState: Equatable {
    ...
    /// An action the user tapped that could not run, and what they can do about it.
    case blocked(Block)
}

extension BannerState {
    public struct Block: Equatable, Sendable {
        public enum Remedy: Equatable, Sendable {
            /// Nothing here can fix it. Dismiss is the only button.
            case none
            /// The trailing chip *is* `RPSystemBroadcastPickerView`.
            case broadcastPicker
        }
        /// Which action was refused. `nil` is dictation, which is not an `AIAction`.
        public let action: AIAction?
        public let title: String
        public let detail: String
        public let remedy: Remedy
    }
}
```

Backed by one new published property on `KeyboardController`:

```swift
@Published public var block: BannerState.Block?
```

`BannerState.resolve` takes it as a parameter like everything else, so the decision
stays in the one ordered place that has a test on it.

**Where it sits in the order:** after both dictation branches, before `isWorking`.
Dictation still outranks it because a recording is running in another process and
stopping it is time-critical. It outranks `isWorking` because setting a block clears the
running-action state (see below), so the two cannot describe the same tap — the ordering
is decided rather than incidental, and `BannerStateTests` gets a case that would fail if
someone reordered it.

**What clears it**, all three needed or the strip lies:

- `beginWork` — any action that actually starts clears the previous refusal.
- The banner's Dismiss button, through `clearBanner()`.
- The next keystroke. "Type something first" must not survive the user typing something.
  `clearBannerState()` is called today only from `dismissOverlay()`; `insertCharacter`
  and `deleteBackward` need to clear `block` (and only `block` — clearing the whole
  banner on every keystroke would throw away an answer the user is about to accept).

Setting a block calls `clearBannerState()` first, so a refusal cannot be drawn over the
previous action's answers.

### 2. The three refusals

**Fix / Rewrite on an empty field.** `run(_:)`'s `guard hasTextToWorkWith` and
`SuggestionBar.toneTap`'s `.openMenu` answer both become a block:

```
action: .fix / .rewrite
title:  "Nothing to fix yet" / "Nothing to rewrite yet"
detail: "Type something first, then tap \(action.title)."
remedy: .none
```

`SuggestionBar.ToneTap.openMenu` is renamed `.needsText` and stops naming a panel. Its
accessibility hint changes from "Opens the AI actions" to the same sentence the banner
prints, so the button and the strip cannot disagree — which is the D8 drift
`hasRunnableAction`'s comment records.

**Reply with no session.** `runReply`'s `withAnimation { overlay = .aiResult(.needsScreenContext) }`
becomes a block built from `ScreenContextPrompt`, which is untouched: it is a tested
value type carrying four distinct refusals (no Full Access / an ending a restart cannot
fix / no cloud model / simply off) and only one of them offers the picker.

```
action: .reply
title:  prompt.title
detail: prompt.detail
remedy: prompt.offersPicker ? .broadcastPicker : .none
```

`prompt.detail` is written for a panel and runs long. The banner's `caption` allows two
lines at 11pt, which fits the "Screen context is off" case if it is shortened to name
the two steps and the fallback: *"Tap to pick AI Keyboard, then Start Broadcast. If
nothing opens, start it in the app."* The three refusal details are already one sentence
each and fit as they are. `ScreenContextPromptTests` moves with the wording.

**Dictate with no app session.** `startDictation`'s `if !dictation.availability.isLive
{ overlay = .dictation }` becomes a block carrying the same two sentences
`DictationPanel.explanationText` prints today, for `.needsFullAccess` and
`.noSession(reason)`, `remedy: .none`. Nothing in a keyboard extension can start a
session or launch the app — `.claude/rules/dictation.md` — so there is no button to
offer and the banner must not grow one.

### 3. What the banner's two ends learn

`leading` gains one branch: `tag("exclamationmark.triangle", block.action?.title ?? "Dictation", tint: .warning)`,
which is what `.needsSetup` already draws.

`trailing` gains one branch, and it is the only genuinely new view in this change:

```swift
case .blocked(let block):
    switch block.remedy {
    case .none:            button("Dismiss", tint: nil, filled: false) { controller.clearBanner() }
    case .broadcastPicker: pickerChip
    }
```

`pickerChip` is `BroadcastPickerButton(width: 42, height: 42)` on the white-then-brand
background every other call site uses, because the system assigns the glyph's colour
itself and it is black in light mode.

### 4. What is deleted

- `AIMenuPanel.swift`
- `AIResultPanel.swift`, `AIResultPanel+Replies.swift`, `AIResultPanel+Variants.swift`
- `DictationPanel.swift`
- `PanelChrome.swift` — `PanelSurface` and `PanelHeader` have no other caller;
  `EmojiPanel` draws its own chrome.
- `AIActionResultKind`
- `BannerState`'s existing `.needsSetup` case and the `screenContextPromptTitle`
  constant beside it, both folded into `.blocked`
- `BannerState.resolve`'s `resultsShownElsewhere:` parameter,
  `ActionBanner.resultPanelIsOpen`, and `bannerOptions`' "empty while a result panel is
  open" guard — all three exist only to stop the banner and a panel drawing the same
  answer twice, and there is no longer a panel that can.
- `KeyboardController+Tone.runTone`'s `destination` computation, for the same reason:
  there is one home for an answer now.
- `SlotAction.aiMenu`, `KeyCap.aiMenu`, and `SuggestionBar.sparkleButton` — see below.

`run(.tone)` loses its `overlay = .aiResult(.variants(nil))` branch and runs the stored
default register instead, which is what `runDefaultTone()` does. `AIAction.tone` itself
stays: `FoundationModelsEngine.competentActions` and `TextIntelligence.route` use it to
tell a named-register rewrite from a three-way one, which has nothing to do with menus.

### 5. The sparkle key goes, and the presets get real keys

`SlotAction.aiMenu`'s only behaviour was opening `AIMenuPanel`, so it goes with it. Two
presets depend on it and their comments say why — both spend the action row on something
else, leaving the sparkle as their only route to the AI actions:

- **Power** — `barTrailing` becomes `[.reply, .quickTone]` instead of `[.aiMenu]`.
- **AI first** — the bottom row's `.aiMenu` slot becomes `.reply`; `barTrailing` already
  carries `.quickTone`.

Both keep a route to every AI action, and every route is now a key that runs something
rather than a key that opens a list.

Touched by the deletion: `CustomLayout` (catalogue and title), `KeySpec` (cap and
identifier), `KeyView+Label`, `SlotAction+KeyCap`, `SuggestionBar+Edges`,
`SuggestionBar+ToneButton`, `LayoutPresets`, `KeyboardController+Typing`. A saved layout
containing a sparkle key fails to decode and falls back to the default, which
`SharedStore.decodeLayout` already does for any invalid layout.

## What this costs, measured or stated

Three losses, all deliberate, all worth writing into `.claude/rules/keyboard-layout.md`
so the next person does not rediscover them:

1. **The broadcast picker's tap target shrinks from 42pt to 32pt.**
   `-[RPSystemBroadcastPickerView addBroadcastPickerButton]` insets its real `UIButton`
   5pt on every edge, so a 42×42 picker in the 48pt strip leaves 32pt of pressable area
   against 52×52 → 42pt in the panel today. The banner's height is capped at 48 by the
   frame fingerprint, not by taste — see `FrameReduction.Band.maximumOwnUI` — so this
   cannot be bought back by growing the strip.
2. **The dictation countdown survives, the language badge does not.** `12s left` moves
   into the leading tag, replacing the word `RECORDING` for the last minute only, because
   a session that closes itself is news. The `עב ⟷ EN` badge is dropped: the transcript
   is already written in its own script and there is no room beside it.
3. **The best-effort notice loses its line.** `AIResultPanel.bestEffortNotice` says the
   answer came from the on-device model in a language Apple does not list. It survives as
   an amber leading tag plus the full sentence in the accessibility label; the words
   themselves do not fit on a one-line strip.

## Tests

Per `AGENTS.md`: work out what the *broken* build returns before writing each assertion.
The broken build here is today's, where a refusal opens a panel — so every new assertion
pairs the banner state with `XCTAssertEqual(controller.overlay, .none)`. Asserting the
banner state alone passes against the panel build, because `resolve` would report
`.blocked` while a panel covered the keys.

- `BannerStateTests` — `.blocked` against each higher-ranked branch; delete the
  `resultPanelIsOpen` cases.
- `AIButtonTests` — the Reply-with-no-session case asserts a block and `.none` overlay
  instead of `overlay == .aiResult(.needsScreenContext)`.
- `DefaultToneTests` — `show(.aiMenu)` and `run(.tone)` both change meaning.
- `CustomLayoutTests` / `LayoutValidatorTests` / any catalogue test naming `.aiMenu`.
- `DemoWalkthroughTests` — the UI walkthrough drives panels and must drive the banner.
- New: an empty-field tap on Fix and on Rewrite produces a block rather than silence.

Nothing here asks for a test *run*; the suite must compile and the assertions must be
honest.

## Not doing

- Restyling the action row or the banner. Explicitly out, per the answers that shaped
  this spec.
- Removing the emoji key from the shipped action row. It stays, leading, five keys.
- Making the emoji grid stop covering the letters. It is the one panel that has to be a
  panel, and it already leaves the action row alone.
