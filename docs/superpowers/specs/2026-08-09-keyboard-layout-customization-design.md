# Keyboard layout customization

**Date:** 2026-08-09
**Status:** approved, not yet implemented

Let the user change the shape of the keyboard: pick a preset, turn optional rows
on, resize keys, and drag the keys of the bottom row into the order they want,
with a different job assigned to each one.

---

## 1. The decision that shapes everything else

**Letters are not editable. The chrome around them is.**

The three letter rows of this keyboard are not a design choice, they are
extracted data: 64 languages read out of Apple's own layout tables through
`UCKeyTranslate`, held to `Bar/layouts/apple-layouts.json` by
`LayoutProvenanceTests` and to `Bar/layouts/stock-rendered-rows.json` by
`RenderedRowOrderTests`, with reachability of every letter in every CLDR
alphabet pinned by `LanguageCatalogueTests`. A free canvas that lets a user drag
`e` out of the grid throws all of that away and replaces it with a keyboard that
can be silently broken.

So the editable surface is everything that is *not* a letter: the ends of the
suggestion bar, two optional rows, the whole bottom row, and the geometry of the
grid. That surface is also the one that is genuinely language-independent, which
is what makes a single stored layout correct for all 64 languages instead of
64 stored layouts.

The second decision follows from it: **customization is a source of `KeyRow`s,
not a second rendering path.** Everything the user configures compiles down into
the existing `KeySpec` / `KeyRow` types before it reaches the view, so the width
solver, `KeyView`, hit testing, the RTL pinning and every existing rendering
test keep working with no change.

---

## 2. What the user can change

| Zone | Contains | Default |
|---|---|---|
| Bar slots | leading and trailing ends of the suggestion bar | 😀 emoji leading; one-tap tone and ✨ AI menu trailing |
| Number row (optional) | `1234567890` above the letters | off |
| Bottom row | the whole row: order, widths, actions | `123 🌐 [space] 🎤 ⏎` |
| Cursor row (optional) | below the bottom row | off |
| Geometry | key height, row spacing, one-handed reach | 42pt, 12pt, full width |

Every editable slot carries a **width** and an **action**.

### Widths

`1.0x` to `3.0x` of the unit key, or `Fill`. `Fill` maps to the existing
`KeyWidth.flexible`, so a bottom row with two `Fill` keys splits the leftover
between them exactly as the solver already does for space.

The range starts at `1.0x` rather than offering sub-unit keys so that no slider
value can ever trip the 32pt minimum-width rail on its own. A key below 32pt is
then only reachable by crowding a row, which is a different mistake with its own
error.

`KeyWidth.remainderShare` is not offered to the user. It exists so shift and
delete can share what the letter rows leave over, which is a property of the
letter rows, and the user cannot edit those.

### Actions

Fifteen, and thirteen of them are things `KeyboardController` already does:

| Action | New work |
|---|---|
| Shift | none, existing `KeyCap.shift` |
| Delete | none, existing `KeyCap.backspace` |
| Numbers plane (`123`) | none, existing `KeyCap.plane` |
| Symbols plane (`#+=`) | none, existing `KeyCap.plane` |
| Globe | none, existing `KeyCap.globe` |
| Space | none, existing `KeyCap.space` |
| Return | none, existing `KeyCap.ret` |
| Dictation | none, existing `KeyCap.dictation` |
| Emoji panel | new `KeyCap`, controller already has `overlay = .emoji` |
| AI menu | new `KeyCap`, controller already has `overlay = .aiMenu` |
| One-tap tone | new `KeyCap`, controller already runs the default tone |
| Text / snippet | none, existing `KeyCap.character` with a longer string |
| Cursor ← | new, `UITextDocumentProxy.adjustTextPosition(byCharacterOffset: -1)` |
| Cursor → | new, the same with `+1` |
| Hide keyboard | new, `dismissKeyboard()` on the input view controller |

The `Text / snippet` action is what makes `,` `.` `@` `.com` and a user's own
string all one thing rather than four features.

### Geometry

- **Key height** — 36pt to 56pt, default 42pt (today's `Theme.Metrics.keyHeight`).
- **Row spacing** — 8pt to 16pt, default 12pt.
- **Reach** — Off / Left / Right. One-handed narrows the grid to 88% of the
  width and pins it to one side, leaving a tap strip on the other to switch back.

One-handed is deliberately a geometry toggle rather than a preset, because it
composes with all five presets and a user who wants "Power, one-handed" should
not have to choose.

---

## 3. Rails

A keyboard the user can break is a keyboard the user cannot type on, and the
person who breaks it will not connect the crash to the screen where they broke
it. `LayoutValidator` runs on every edit and returns `[LayoutIssue]`, each one
either an error or a warning. **Errors block Done.** Warnings show inline and
let the user through.

Errors:

- Space, delete, return and a plane switch must each exist and be reachable on
  the plane they belong to.
- The globe key cannot be removed while `showsGlobeKey` is true. That flag is
  `needsInputModeSwitchKey`, which is iOS telling us the key is required on this
  device, not a preference. The Remove button greys out and names the reason.
- No key narrower than 32pt at the current device width.
- Key height outside 36–56pt, or row spacing outside 8–16pt. The sliders are
  clamped, so this is reachable only from stored data written by another build.
- A row's total width must not exceed the language's column budget from
  `KeyboardLayout.columns(for:plane:)`. This is the check that catches the
  Bulgarian-class overrun already documented in `CLAUDE.md`, where a row ran
  45pt off the side of the screen.

Warnings:

- A duplicate action in the same row.
- A row with more than 12 keys, which is typeable but cramped.
- A `Text` snippet longer than 20 characters, which will not fit on its key cap.

`Theme.Metrics.minTouchTarget` is 44pt and stays where it is. It is not the
floor here, because the keyboard already ships at 42pt and a floor that fires on
the shipped default is noise, not a rail.

---

## 4. Presets

Five, each one a named `KeyboardCustomization` value:

| Preset | What it is |
|---|---|
| **Default** | exactly what ships today |
| **Compact** | 38pt keys, 9pt spacing, more of the host app visible |
| **Roomy** | 52pt keys, 14pt spacing |
| **Power** | number row on, cursor row on with ← →, `,` and `.` on the bottom row |
| **AI first** | AI menu promoted to a full bottom-row key beside space, one-tap tone in the bar's trailing slot |

Presets render as small wireframe thumbnails in a horizontal strip, not as a
list of names, because the thing being chosen is a shape.

Picking a preset replaces the whole customization. Editing afterwards sets
`preset` to nil and keeps `basedOn`, so the label reads "Custom (from Power)"
and Reset has somewhere to go back to.

---

## 5. Data model

New file, `Packages/AIKeyboardCore/Sources/AIKeyboardCore/CustomLayout.swift`.
It lives in `AIKeyboardCore` and not in `AIKeyboardShared`, because the
broadcast capture extension has no keyboard in it and must not gain a reason to
grow.

```swift
public struct KeyboardCustomization: Codable, Equatable, Sendable {
    public var preset: LayoutPreset.ID?      // nil once the user edits
    public var basedOn: LayoutPreset.ID      // what Reset goes back to
    public var geometry: LayoutGeometry
    public var barLeading: [SlotSpec]
    public var barTrailing: [SlotSpec]
    public var showsNumberRow: Bool
    public var bottomRow: [SlotSpec]
    public var cursorRow: [SlotSpec]         // empty means the row is off
}

public struct SlotSpec: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var action: SlotAction
    public var width: SlotWidth              // .units(CGFloat) | .fill
}

public enum SlotAction: Codable, Hashable, Sendable {
    case shift, backspace, numbersPlane, symbolsPlane, globe, space, ret
    case dictation, emoji, aiMenu, quickTone, cursorLeft, cursorRight, hideKeyboard
    case text(String)
}

public struct LayoutGeometry: Codable, Equatable, Sendable {
    public var keyHeight: CGFloat            // 36...56, default 42
    public var rowSpacing: CGFloat           // 8...16, default 12
    public var reach: Reach                  // .full, .left, .right
}

public struct LayoutPreset: Identifiable, Sendable {
    public typealias ID = String             // "default", "compact", …
    public let id: ID
    public let name: String
    public let customization: KeyboardCustomization
    public static let all: [LayoutPreset]
}
```

`SlotSpec.id` is a `UUID` rather than derived from the action, because two keys
with one identity is a `ForEach` with duplicate identity, and the whole point of
this feature is that a user can put two commas on a row if they want to.

### Persistence

`SharedStore` gains one key, `keyboardLayout`, holding JSON `Data` in the App
Group, and **two** accessors, following the rule this repo has already paid for
twice:

- `@Published var keyboardLayout: KeyboardCustomization` — the app's editor
  binds to this.
- `var storedKeyboardLayout: KeyboardCustomization` — reads through
  `UserDefaults` at the moment it is needed, which is what the keyboard
  extension uses.

The app and the keyboard are separate processes. `load()` fills the published
copy once per launch, so a keyboard already on screen when the user hits Done
would keep drawing the old layout. This is the same defect that
`storedPersonalDictionary` and `storedDefaultTone` exist to avoid.

Decoding failure falls back to `.default` and logs. A layout that fails
`LayoutValidator` on read also falls back to `.default` and logs, so a build
that adds a new required key cannot brick a keyboard saved by the previous
build.

`resetToDefaults()` clears the key and restores `.default`.

---

## 6. Rendering

### Compiling slots into rows

`KeyboardLayout` gains one entry point:

```swift
public static func rows(
    for language: KeyboardLanguage,
    plane: KeyboardPlane,
    showsGlobe: Bool,
    customization: KeyboardCustomization
) -> [KeyRow]
```

It returns the number row (if on), the existing letter or number or symbol rows
untouched, the compiled bottom row, and the cursor row (if non-empty).
`bottomRow(for:plane:showsGlobe:)` keeps its current signature and becomes the
implementation of `KeyboardCustomization.default`'s bottom row, so nothing that
calls it today has to change.

`SlotAction` maps to `KeyCap` one to one. `SlotWidth.fill` maps to
`KeyWidth.flexible`, `.units(n)` to `.unit(n)`.

### Direction

**Custom rows are stored and rendered left to right, in every language**, and
are pinned `.leftToRight` exactly like the letter rows in `KeyboardView`.

This is not a detail. Reading row data as logical order and setting
`layoutDirection: .rightToLeft` is what shipped all six right-to-left keyboards
mirrored, fixed in commit 593e7b2 two commits ago. A custom bottom row is the
obvious place for that mistake to come back, so a Hebrew rendered-order test
pins it before it can.

### Height

`Theme.Metrics.keyAreaHeight` currently hardcodes four rows:

```swift
keyHeight * 4 + rowSpacing * 3 + topInset + bottomInset
```

With an optional number row and an optional cursor row, the grid is four, five
or six rows tall and the key height is no longer a constant. Both
`keyAreaHeight` and `totalHeight(withContextStrip:)` become functions of the
customization, and the extension's height constraint has to be recomputed when
the layout changes, not only when the context strip appears.

`KeyboardView` reads its metrics from the controller rather than from the
`Theme.Metrics` constants directly. The constants stay as the default values.

---

## 7. The editor

One new screen, `AIKeyboard/Main/LayoutView.swift`, reached from
`Settings › Typing › Keyboard layout`, whose row shows the current preset name
as its value.

```
┌─── Keyboard layout ────────── ↺ Undo   Done ──┐
│  ┌─────────────────────────────────────────┐  │
│  │  LIVE KEYBOARD  (real KeyboardView)     │  │
│  │  letter rows dim and refuse drops       │  │
│  └─────────────────────────────────────────┘  │
│   Presets  [▢][▢][▣][▢][▢]   ← wireframes     │
│   ── Key: 🎤 Dictation ──────────────────     │
│   Width    ●──────────────────  1.0x          │
│   Action   [ Dictation              ▾ ]       │
│   ← Move    Move →                  Remove    │
│   ── Add ──                                   │
│   [⌫][↩][,][.][@][.com][←][→][✨][😀][⌄]     │
└───────────────────────────────────────────────┘
```

The canvas is the real `KeyboardView`, reused through the existing
`KeyboardPreview` in `AppComponents.swift`, in an editing mode where taps select
instead of type. Nothing about the keyboard is redrawn for the editor, so what
the user arranges is literally what they will get.

When nothing is selected, the inspector shows the geometry controls instead of
the per-key ones: key height, row spacing, number row, cursor row, one-handed
reach.

### Interaction

- **Tap** a key: select it, inspector fills.
- **Long press then drag**: move it. Neighbours part to show the insertion gap.
  Letter rows dim to 40% and reject the drop.
- **Drag onto the drawer**: remove, with the drawer tinting red.
- **Tap a drawer item**: append to the selected row, which is the fast path and
  the one that works when a drag is awkward.
- Haptics come from the existing `Feedback`: `modifierPress()` on pickup,
  `keyPress()` on each reorder crossing, `success()` on drop. Nothing new.

### Accessibility

Drag and drop is unusable under VoiceOver, so **every edit has a non-drag
route**:

- Move is a pair of buttons in the inspector, not only a drag.
- Rows expose `accessibilityCustomAction` for move left, move right and remove.
- Width is a slider, which is adjustable with the rotor.
- Each key on the canvas carries an accessibility label naming its action and
  position, "Dictation, key 4 of 5, bottom row".

### Undo

An explicit Undo in the navigation bar over a snapshot stack of
`KeyboardCustomization` values, capped at 20. Plus Reset, which goes back to
`basedOn`. No shake-to-undo: the user's hand is on the screen dragging things.

---

## 8. Testing

Following this repo's rule that an assertion has to reject the broken version:

**`CustomLayoutTests`**
- Codable round-trip for every preset and for a hand-built custom layout.
- Every preset validates with zero errors.
- The validator produces an error for each missing essential in turn: no space,
  no delete, no return, no plane switch, globe removed while `showsGlobe`.
- **Every preset against all 64 languages**: no compiled row exceeds
  `KeyboardLayout.columns(for:plane:)`. This is the Bulgarian check.
- A stored layout that fails validation decodes to `.default` rather than
  throwing.

**`CustomLayoutRenderingTests`**
- A custom bottom row under Hebrew renders in stored order, measured off the
  rendered key frames the way `RenderedRowOrderTests` does. A row-string
  assertion cannot see a reversal, because the string is right either way.
- `keyAreaHeight` for a layout with the number row on is exactly one
  `keyHeight + rowSpacing` taller than the same layout with it off.

**`SharedStoreTests`**
- A layout written through the published property is visible through
  `storedKeyboardLayout` without a reload. The broken version reads the
  launch-time copy, so the assertion has to change the value after `load()`.

**`AIKeyboardUITests`**
- A custom key added in the app types its character into a real `UITextField`
  through the real extension, in the shape of `KeyboardTypesIntoHostTests`. The
  in-app playground is not evidence that the keyboard works; this repo has
  already shipped a build where every key drew, animated and clicked and not one
  character reached the host.

---

## 9. Phases

Each phase is shippable on its own.

1. **Presets, geometry, optional rows.** The model, the validator, the store,
   the rendering change, the five presets, and a Settings screen that picks
   between them with sliders and toggles. No dragging. Most of the value, and
   none of the hardest work.
2. **The drag editor.** Canvas, inspector, drawer, undo, accessibility actions.
3. **Snippets and polish.** Custom text keys, pinch on the canvas as a second
   route to key height, wireframe thumbnails for user-modified layouts.

---

## 10. Not building

- **Per-language layouts.** The editable surface is chrome and chrome is
  language-independent. Space and the plane labels already localise themselves.
- **Sharing or importing layouts** as files, codes or links.
- **Theming and colours.** A separate feature that would want its own preset
  strip, and mixing the two makes both worse.
- **Editing the character rows of the numbers and symbols planes.**
- **Split keyboard.** One-handed reach covers the reachability problem at a
  fraction of the cost.
- **A free canvas.** See section 1.
