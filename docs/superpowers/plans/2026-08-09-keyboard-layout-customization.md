# Keyboard Layout Customization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user pick a keyboard preset, turn optional rows on, resize keys, and drag the bottom row's keys into any order with any action assigned to each.

**Architecture:** A `KeyboardCustomization` value persisted as JSON in the App Group. It compiles down into the existing `KeySpec` / `KeyRow` types before it reaches any view, so the width solver, `KeyView`, hit testing and the right-to-left pinning are untouched. Letters are never editable; only the suggestion bar's ends, two optional rows, the bottom row and the grid geometry are.

**Tech Stack:** Swift 5.9, SwiftUI, UIKit, XCTest. No third-party dependencies. Local package `Packages/AIKeyboardCore` with targets `AIKeyboardCore`, `AIKeyboardShared`, `CaptureAtomics`.

**Spec:** `docs/superpowers/specs/2026-08-09-keyboard-layout-customization-design.md`

## PAUSED 2026-08-10 — resume state

Execution stopped partway through Task 6 because six other Claude sessions were
editing this repo concurrently, including `Theme.swift`, `KeyboardView.swift`,
`SuggestionBar.swift` and `Models.swift`, which Tasks 7 and 8 both need. Nothing
below has been compiled or tested. **Treat every "done" here as written, not
verified.**

**Written, uncommitted:**

| Item | State |
|---|---|
| `CustomLayout.swift` | complete, includes the `SlotAction.keyCap`/`glyph` extension from Task 2 |
| `LayoutValidator.swift` | complete |
| `LayoutPresets.swift` | complete |
| `CustomLayoutCompiler.swift` | complete |
| `KeyboardLayout.swift` | six new `KeyCap` cases, their labels and ids, plus `KeySpec.addressableID` |
| `KeyView.swift` | labels for the six new caps; accessibility id now uses `addressableID` |
| `KeyboardController.swift` | `press` branches for the six; `onDismissKeyboard`; `customization`; `apply(_:)`; `reloadCustomization()`; `apply(store.storedKeyboardLayout)` in `init` |
| `SharedStore.swift` | `Key.keyboardLayout`, `layoutKey`, `keyboardLayout`, `storedKeyboardLayout`, `decodeLayout(from:)`, `writeLayout(_:)` |

**Half-done, finish these first on resume:**

- `SharedStore.resetToDefaults()` does not yet clear `Key.keyboardLayout` or
  restore `keyboardLayout = .default`. `load()` does not yet call
  `Self.decodeLayout(from: defaults)`. Both are Task 6 Step 3 and were not
  applied.
- `AIKeyboardExtension/KeyboardViewController.swift` has no
  `controller.onDismissKeyboard = { [weak self] in self?.dismissKeyboard() }`.
  That is Task 2 Step 7, and without it the Hide keyboard key silently does
  nothing.
- **Not one test from Tasks 1 to 6 has been written.** Write them before Task 7,
  and run them before believing any of the above.
- Task 9's `LayoutView` uses `Theme.Surface.card`, which does not exist. The real
  tokens are `Theme.Surface.raised` and `.elevated`. Substitute `raised`.
- `KeyboardLayout.stretchUnits` and `LetterLayout.deleteRow` changed under this
  work in another session. Re-read `KeyboardLayout.swift` before touching it and
  check whether Hebrew still puts delete on the top row, because
  `KeyboardCustomization.default` is asserted against the compiled bottom row and
  nothing else.

**Resume at:** finish the two half-done edits above, write the Task 1 to 6 tests,
run the suite, then Task 7.

## Global Constraints

- **Never link `AIKeyboardCore` from `AIKeyboardBroadcast`.** All new code in this plan goes in `AIKeyboardCore`, never `AIKeyboardShared`. The capture process has no keyboard in it.
- **Letters are never editable.** No task may change `KeyboardLayout.letterLayouts`, `letters(for:)`, `columns(for:plane:)` or the contents of `Bar/layouts/`.
- **Every key row renders `.leftToRight`,** in every language, including custom rows. Reading row data as logical order and mirroring it is what shipped six right-to-left keyboards backwards (commit 593e7b2).
- **The keyboard extension reads settings at the moment of use, not from a launch-time copy.** New settings get a `stored…` accessor that goes through `UserDefaults` on every read, like `storedPersonalDictionary` and `storedDefaultTone`.
- **No em dashes or en dashes in commit messages.** Code comments and this plan are exempt.
- **Commit on `main`.** Never create a branch.
- **Two keys with one `id` is a `ForEach` with duplicate identity.** Every `SlotSpec` carries its own `UUID`.
- Build: `xcodebuild build -project AIKeyboard.xcodeproj -scheme AIKeyboard -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
- Test: `xcodebuild test -project AIKeyboard.xcodeproj -scheme AIKeyboard -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
- Format: the PostToolUse hook runs `swift-format` per edited file. Do not run it over the whole tree.
- `AIKeyboard/`, `AIKeyboardExtension/`, `AIKeyboardBroadcast/`, `AIKeyboardUITests/` and `AIKeyboardCoreTests/` are `PBXFileSystemSynchronizedRootGroup`s: a new file dropped in is compiled with no `.pbxproj` edit.
- **Two `xcodebuild test` runs against the same simulator kill each other.** Never run tests concurrently.

## File Structure

**Create**
| File | Responsibility |
|---|---|
| `Packages/AIKeyboardCore/Sources/AIKeyboardCore/CustomLayout.swift` | `SlotAction`, `SlotWidth`, `SlotSpec`, `Reach`, `LayoutGeometry`, `KeyboardCustomization`. Data only. |
| `Packages/AIKeyboardCore/Sources/AIKeyboardCore/LayoutPresets.swift` | The five presets and `LayoutPreset`. |
| `Packages/AIKeyboardCore/Sources/AIKeyboardCore/LayoutValidator.swift` | `LayoutIssue`, `LayoutValidator.issues(in:showsGlobe:language:)`. |
| `Packages/AIKeyboardCore/Sources/AIKeyboardCore/CustomLayoutCompiler.swift` | Turns a `KeyboardCustomization` into `[KeyRow]`. |
| `AIKeyboard/Main/LayoutView.swift` | The editor screen: canvas, presets, inspector, drawer. |
| `AIKeyboard/Main/LayoutEditorModel.swift` | Editor state: selection, undo stack, drag arithmetic. |
| `AIKeyboardCoreTests/CustomLayoutTests.swift` | Model, presets, validator, compiler. |
| `AIKeyboardCoreTests/LayoutGeometryTests.swift` | Metrics arithmetic and store round-trip. |
| `AIKeyboardUITests/CustomLayoutRenderingTests.swift` | Rendered order under Hebrew, and a custom key typing into a host field. |

**Modify**
| File | Change |
|---|---|
| `…/AIKeyboardCore/KeyboardLayout.swift` | Add `rows(for:plane:showsGlobe:customization:)`. Leave everything else alone. |
| `…/AIKeyboardCore/Models.swift` | Six new `KeyCap` cases. |
| `…/AIKeyboardCore/KeyView.swift` | Labels for the six new caps. |
| `…/AIKeyboardCore/KeyboardController.swift` | `press` branches for the six; `customization`; `onDismissKeyboard`. |
| `…/AIKeyboardCore/KeyboardView.swift` | Read rows and metrics from the customization. |
| `…/AIKeyboardCore/Theme.swift` | `Metrics.keyAreaHeight`/`totalHeight` become functions of a geometry. |
| `…/AIKeyboardCore/SuggestionBar.swift` | Render configured bar slots. |
| `…/AIKeyboardCore/SharedStore.swift` | `keyboardLayout` + `storedKeyboardLayout`. |
| `AIKeyboardExtension/KeyboardViewController.swift` | Height follows the layout; dismiss callback. |
| `AIKeyboard/Main/SettingsView.swift` | A `NavigationRow` to `LayoutView`. |

---

## Task 1: The data model

**Files:**
- Create: `Packages/AIKeyboardCore/Sources/AIKeyboardCore/CustomLayout.swift`
- Create: `AIKeyboardCoreTests/CustomLayoutTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `SlotAction`, `SlotWidth`, `SlotSpec`, `Reach`, `LayoutGeometry`, `KeyboardCustomization`, all `Codable`/`Equatable`/`Sendable`. `KeyboardCustomization.default`.

- [ ] **Step 1: Write the failing test**

`AIKeyboardCoreTests/CustomLayoutTests.swift`:

```swift
import XCTest
@testable import AIKeyboardCore

final class CustomLayoutTests: XCTestCase {

    func testDefaultRoundTripsThroughJSON() throws {
        let original = KeyboardCustomization.default
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KeyboardCustomization.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    /// `SlotAction.text` carries a payload and every other case does not, which is
    /// the shape a hand-rolled `Codable` gets wrong. Encode one of each.
    func testEveryActionRoundTrips() throws {
        let actions: [SlotAction] = [
            .shift, .backspace, .numbersPlane, .symbolsPlane, .globe, .space, .ret,
            .dictation, .emoji, .aiMenu, .quickTone, .cursorLeft, .cursorRight,
            .hideKeyboard, .text(".com")
        ]
        let data = try JSONEncoder().encode(actions)
        XCTAssertEqual(try JSONDecoder().decode([SlotAction].self, from: data), actions)
    }

    /// Two commas on one row is a thing the user is allowed to build, so identity
    /// cannot be derived from the action.
    func testTwoSlotsWithTheSameActionHaveDifferentIDs() {
        let a = SlotSpec(action: .text(","))
        let b = SlotSpec(action: .text(","))
        XCTAssertNotEqual(a.id, b.id)
    }

    func testDefaultIsTodaysBottomRow() {
        let actions = KeyboardCustomization.default.bottomRow.map(\.action)
        XCTAssertEqual(actions, [.numbersPlane, .globe, .space, .dictation, .ret])
    }

    func testDefaultGeometryMatchesTheShippedMetrics() {
        XCTAssertEqual(KeyboardCustomization.default.geometry.keyHeight, 42)
        XCTAssertEqual(KeyboardCustomization.default.geometry.rowSpacing, 12)
        XCTAssertEqual(KeyboardCustomization.default.geometry.reach, .full)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `xcodebuild test -project AIKeyboard.xcodeproj -scheme AIKeyboard -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:AIKeyboardCoreTests/CustomLayoutTests`
Expected: compile failure, "cannot find 'KeyboardCustomization' in scope".

- [ ] **Step 3: Write `CustomLayout.swift`**

```swift
import CoreGraphics
import Foundation

// MARK: - What a slot does

/// The job assigned to one editable key.
///
/// Thirteen of these are things `KeyboardController` already did before this
/// feature existed, which is why the catalogue is this size and not larger: a
/// keyboard that can be rearranged into an action nothing implements is worse
/// than one that cannot be rearranged at all.
public enum SlotAction: Codable, Hashable, Sendable {
    case shift
    case backspace
    case numbersPlane
    case symbolsPlane
    case globe
    case space
    case ret
    case dictation
    case emoji
    case aiMenu
    case quickTone
    case cursorLeft
    case cursorRight
    case hideKeyboard
    /// Any literal, from a comma to `.com` to a phrase the user typed in. One
    /// case rather than four features.
    case text(String)

    /// What the editor calls it.
    public var title: String {
        switch self {
        case .shift: return "Shift"
        case .backspace: return "Delete"
        case .numbersPlane: return "Numbers"
        case .symbolsPlane: return "Symbols"
        case .globe: return "Next keyboard"
        case .space: return "Space"
        case .ret: return "Return"
        case .dictation: return "Dictation"
        case .emoji: return "Emoji"
        case .aiMenu: return "AI actions"
        case .quickTone: return "One-tap rewrite"
        case .cursorLeft: return "Cursor left"
        case .cursorRight: return "Cursor right"
        case .hideKeyboard: return "Hide keyboard"
        case .text(let value): return value.isEmpty ? "Text" : value
        }
    }

    /// Everything the editor's Add drawer offers, in the order it offers it.
    /// `.space` is absent on purpose: the validator requires exactly the one
    /// that is already there, and a second space bar is not a layout anybody
    /// wants.
    public static let catalogue: [SlotAction] = [
        .backspace, .ret, .shift, .numbersPlane, .symbolsPlane, .globe,
        .dictation, .emoji, .aiMenu, .quickTone,
        .cursorLeft, .cursorRight, .hideKeyboard,
        .text(","), .text("."), .text("?"), .text("!"), .text("@"), .text(".com")
    ]
}

// MARK: - How wide

public enum SlotWidth: Codable, Hashable, Sendable {
    /// Multiples of the standard letter key. 1.0 to 3.0.
    case units(CGFloat)
    /// Takes what the fixed keys in the row left over, split with any other
    /// `fill`. Maps to `KeyWidth.flexible`.
    case fill

    public static let minimumUnits: CGFloat = 1.0
    public static let maximumUnits: CGFloat = 3.0

    /// Clamped on the way in, so a value decoded from another build cannot put a
    /// key off the side of the screen.
    public static func clampedUnits(_ value: CGFloat) -> SlotWidth {
        .units(min(maximumUnits, max(minimumUnits, value)))
    }
}

// MARK: - One editable key

public struct SlotSpec: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var action: SlotAction
    public var width: SlotWidth

    /// A fresh `UUID` by default, and that is load-bearing: identity cannot come
    /// from the action, because a user is allowed to put two commas on one row
    /// and two keys with one id is a `ForEach` with duplicate identity.
    public init(id: UUID = UUID(), action: SlotAction, width: SlotWidth = .units(1)) {
        self.id = id
        self.action = action
        self.width = width
    }
}

// MARK: - Geometry

/// Which side of the screen the grid hugs when it is narrowed for one hand.
public enum Reach: String, Codable, Hashable, Sendable {
    case full
    case left
    case right

    /// How much of the width the grid takes. The remainder is the tap strip that
    /// puts it back.
    public var widthFraction: CGFloat { self == .full ? 1.0 : 0.88 }
}

public struct LayoutGeometry: Codable, Equatable, Sendable {
    public var keyHeight: CGFloat
    public var rowSpacing: CGFloat
    public var reach: Reach

    public static let keyHeightRange: ClosedRange<CGFloat> = 36...56
    public static let rowSpacingRange: ClosedRange<CGFloat> = 8...16

    /// Today's `Theme.Metrics` values, so the shipped default is a no-op.
    public static let `default` = LayoutGeometry(keyHeight: 42, rowSpacing: 12, reach: .full)

    public init(keyHeight: CGFloat, rowSpacing: CGFloat, reach: Reach) {
        self.keyHeight = keyHeight
        self.rowSpacing = rowSpacing
        self.reach = reach
    }
}

// MARK: - The whole customization

public struct KeyboardCustomization: Codable, Equatable, Sendable {
    /// The preset this exactly is, or nil once the user has edited it.
    public var preset: String?
    /// What Reset goes back to. Survives editing, which `preset` does not.
    public var basedOn: String
    public var geometry: LayoutGeometry
    /// The leading end of the suggestion bar.
    public var barLeading: [SlotSpec]
    /// The trailing end. Two controls by default: one-tap tone, then the sparkle.
    public var barTrailing: [SlotSpec]
    public var showsNumberRow: Bool
    public var bottomRow: [SlotSpec]
    /// Empty means the row is off. There is no separate flag, because a row with
    /// no keys and a row that is switched off are the same keyboard.
    public var cursorRow: [SlotSpec]

    public init(
        preset: String?,
        basedOn: String,
        geometry: LayoutGeometry,
        barLeading: [SlotSpec],
        barTrailing: [SlotSpec],
        showsNumberRow: Bool,
        bottomRow: [SlotSpec],
        cursorRow: [SlotSpec]
    ) {
        self.preset = preset
        self.basedOn = basedOn
        self.geometry = geometry
        self.barLeading = barLeading
        self.barTrailing = barTrailing
        self.showsNumberRow = showsNumberRow
        self.bottomRow = bottomRow
        self.cursorRow = cursorRow
    }

    /// Exactly what shipped before this feature existed. Every widths value here
    /// is copied from `KeyboardLayout.bottomRow`, so the default layout renders
    /// byte for byte what it used to.
    public static let `default` = KeyboardCustomization(
        preset: "default",
        basedOn: "default",
        geometry: .default,
        barLeading: [SlotSpec(action: .emoji)],
        barTrailing: [SlotSpec(action: .quickTone), SlotSpec(action: .aiMenu)],
        showsNumberRow: false,
        bottomRow: [
            SlotSpec(action: .numbersPlane, width: .units(1.3)),
            SlotSpec(action: .globe, width: .units(1.0)),
            SlotSpec(action: .space, width: .fill),
            SlotSpec(action: .dictation, width: .units(1.0)),
            SlotSpec(action: .ret, width: .units(2.2))
        ],
        cursorRow: []
    )

    /// How many rows the key grid draws, which is what the height arithmetic
    /// needs and the one number `Theme.Metrics` used to hardcode as 4.
    public var rowCount: Int {
        3 + 1 + (showsNumberRow ? 1 : 0) + (cursorRow.isEmpty ? 0 : 1)
    }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `xcodebuild test -project AIKeyboard.xcodeproj -scheme AIKeyboard -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:AIKeyboardCoreTests/CustomLayoutTests`
Expected: 5 tests, all pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/AIKeyboardCore/Sources/AIKeyboardCore/CustomLayout.swift AIKeyboardCoreTests/CustomLayoutTests.swift
git commit -m "Give the keyboard a shape the user can describe"
```

---

## Task 2: The six new key caps and what they do

**Files:**
- Modify: `Packages/AIKeyboardCore/Sources/AIKeyboardCore/Models.swift` (the `KeyCap` enum, currently at `KeyboardLayout.swift:6`)
- Modify: `Packages/AIKeyboardCore/Sources/AIKeyboardCore/KeyboardLayout.swift:6-83`
- Modify: `Packages/AIKeyboardCore/Sources/AIKeyboardCore/KeyView.swift:305-359`
- Modify: `Packages/AIKeyboardCore/Sources/AIKeyboardCore/KeyboardController.swift:453-480`
- Test: `AIKeyboardCoreTests/CustomLayoutTests.swift`

**Interfaces:**
- Consumes: `SlotAction` from Task 1.
- Produces: `KeyCap.emoji`, `.aiMenu`, `.quickTone`, `.cursorLeft`, `.cursorRight`, `.hideKeyboard`; `KeyboardController.onDismissKeyboard: (() -> Void)?`; `SlotAction.keyCap` and `SlotAction.glyph`.

`KeyCap` lives in `KeyboardLayout.swift`, not `Models.swift`. Add the cases there.

- [ ] **Step 1: Write the failing test**

Append to `AIKeyboardCoreTests/CustomLayoutTests.swift`:

```swift
extension CustomLayoutTests {

    /// Every action must compile to a cap, or a key the user can add is a key the
    /// keyboard cannot draw.
    func testEveryCatalogueActionHasAKeyCap() {
        for action in SlotAction.catalogue {
            XCTAssertNotNil(action.keyCap(language: .english), "\(action) has no cap")
        }
        XCTAssertNotNil(SlotAction.space.keyCap(language: .english))
    }

    /// The plane keys have to name where they go *and* what they say now, and the
    /// letters label is per language.
    func testPlaneActionsCarryTheLanguagesOwnLabel() {
        guard case .plane(let destination, let label)? =
            SlotAction.numbersPlane.keyCap(language: .hebrew)
        else { return XCTFail("numbersPlane is not a plane cap") }
        XCTAssertEqual(destination, .numbers)
        XCTAssertEqual(label, "123")
    }

    /// Each new cap needs a distinct accessibility label, because that string is
    /// the only thing a VoiceOver user has to tell two icon keys apart.
    func testNewCapsHaveDistinctAccessibilityLabels() {
        let caps: [KeyCap] = [.emoji, .aiMenu, .quickTone, .cursorLeft, .cursorRight, .hideKeyboard]
        let labels = caps.map(\.accessibilityLabel)
        XCTAssertEqual(Set(labels).count, caps.count, "two caps share a label: \(labels)")
        XCTAssertFalse(labels.contains(where: \.isEmpty))
    }

    /// Distinct ids, for the same reason: `KeySpec.identifier(for:)` derives from
    /// the cap and a collision is a `ForEach` with duplicate identity.
    func testNewCapsHaveDistinctSpecIDs() {
        let caps: [KeyCap] = [.emoji, .aiMenu, .quickTone, .cursorLeft, .cursorRight, .hideKeyboard]
        let ids = caps.map { KeySpec($0).id }
        XCTAssertEqual(Set(ids).count, caps.count)
    }
}
```

And a controller test in the same file:

```swift
/// A target that records the calls made against it, so a cursor key can be
/// checked without a real document. `MockTextTarget.adjustTextPosition` is a
/// deliberate no-op — it has no cursor to move — so it cannot answer this.
@MainActor
final class RecordingTextTarget: TextTarget {
    var offsets: [Int] = []
    var inserted: [String] = []
    var documentContextBeforeInput: String? { "" }
    var documentContextAfterInput: String? { "" }
    var selectedText: String? { nil }
    var isSecureTextEntry: Bool? { false }
    var textContentType: UITextContentType?? { .some(.none) }
    func insertText(_ text: String) { inserted.append(text) }
    func deleteBackward() {}
    func adjustTextPosition(byCharacterOffset offset: Int) { offsets.append(offset) }
}

@MainActor
final class CustomKeyActionTests: XCTestCase {

    func testCursorKeysMoveTheInsertionPointAndTypeNothing() {
        let target = RecordingTextTarget()
        let controller = KeyboardController(target: target, language: .english)

        controller.press(.cursorLeft)
        controller.press(.cursorRight)

        XCTAssertEqual(target.offsets, [-1, 1])
        XCTAssertEqual(target.inserted, [], "a cursor key must not type anything")
    }

    func testEmojiKeyOpensTheEmojiPanel() {
        let controller = KeyboardController(target: RecordingTextTarget(), language: .english)
        controller.press(.emoji)
        XCTAssertEqual(controller.overlay, .emoji)
    }

    func testAIMenuKeyOpensTheMenu() {
        let controller = KeyboardController(target: RecordingTextTarget(), language: .english)
        controller.press(.aiMenu)
        XCTAssertEqual(controller.overlay, .aiMenu)
    }

    /// Nothing in the package can dismiss a keyboard — only
    /// `UIInputViewController` can — so the cap has to reach the host through a
    /// callback, the way the globe key already does.
    func testHideKeyboardCallsTheHost() {
        let controller = KeyboardController(target: RecordingTextTarget(), language: .english)
        var dismissed = 0
        controller.onDismissKeyboard = { dismissed += 1 }
        controller.press(.hideKeyboard)
        XCTAssertEqual(dismissed, 1)
    }
}
```

Add `import UIKit` to the test file for `UITextContentType`.

- [ ] **Step 2: Run and watch it fail**

Run: `xcodebuild test … -only-testing:AIKeyboardCoreTests/CustomLayoutTests -only-testing:AIKeyboardCoreTests/CustomKeyActionTests`
Expected: compile failure, "type 'KeyCap' has no member 'emoji'".

- [ ] **Step 3: Add the cases**

In `KeyboardLayout.swift`, extend `KeyCap`:

```swift
    case dictation
    /// The five controls that used to exist only as chrome, plus the two the
    /// editor adds. They are caps rather than special-cased views because the
    /// point of this feature is that a user can move them into the grid, and a
    /// grid key is a `KeySpec`.
    case emoji
    case aiMenu
    case quickTone
    case cursorLeft
    case cursorRight
    case hideKeyboard
```

`isFunctionKey` needs no change: its `default` already returns true for everything that is not a character or space.

Extend `accessibilityLabel`:

```swift
        case .emoji: return "Emoji"
        case .aiMenu: return "AI actions"
        case .quickTone: return "One-tap rewrite"
        case .cursorLeft: return "Cursor left"
        case .cursorRight: return "Cursor right"
        case .hideKeyboard: return "Hide keyboard"
```

Extend `KeySpec.identifier(for:)`:

```swift
        case .emoji: return "emoji"
        case .aiMenu: return "ai-menu"
        case .quickTone: return "quick-tone"
        case .cursorLeft: return "cursor-left"
        case .cursorRight: return "cursor-right"
        case .hideKeyboard: return "hide-keyboard"
```

- [ ] **Step 4: Map actions to caps**

Append to `CustomLayout.swift`:

```swift
// MARK: - Compiling one slot

public extension SlotAction {

    /// The cap this action draws as. Nil for nothing: every action has one, and
    /// the optional is here so the plane cases can carry the language's own
    /// letters label without a second entry point.
    ///
    /// Optional rather than non-optional so `testEveryCatalogueActionHasAKeyCap`
    /// can fail loudly if a case is ever added here and forgotten below.
    func keyCap(language: KeyboardLanguage) -> KeyCap? {
        switch self {
        case .shift: return .shift
        case .backspace: return .backspace
        case .numbersPlane: return .plane(.numbers, label: "123")
        case .symbolsPlane: return .plane(.symbols, label: "#+=")
        case .globe: return .globe
        case .space: return .space
        case .ret: return .ret
        case .dictation: return .dictation
        case .emoji: return .emoji
        case .aiMenu: return .aiMenu
        case .quickTone: return .quickTone
        case .cursorLeft: return .cursorLeft
        case .cursorRight: return .cursorRight
        case .hideKeyboard: return .hideKeyboard
        case .text(let value): return .character(value)
        }
    }

    /// The SF Symbol the editor's drawer draws. A `.text` action draws its own
    /// characters instead, which is why this is optional.
    var glyph: String? {
        switch self {
        case .shift: return "shift"
        case .backspace: return "delete.left"
        case .numbersPlane, .symbolsPlane: return nil
        case .globe: return "globe"
        case .space: return "space"
        case .ret: return "return"
        case .dictation: return "mic"
        case .emoji: return "face.smiling"
        case .aiMenu: return "sparkles"
        case .quickTone: return AIAction.rewrite.icon
        case .cursorLeft: return "arrow.left"
        case .cursorRight: return "arrow.right"
        case .hideKeyboard: return "keyboard.chevron.compact.down"
        case .text: return nil
        }
    }
}
```

`KeyboardPlane` is in `Models.swift` and is already `public`.

- [ ] **Step 5: Draw them**

In `KeyView.swift`, inside `label`, after the `.dictation` case:

```swift
        case .emoji:
            Image(systemName: "face.smiling")
                .font(Theme.Glyph.font(19))
                .foregroundStyle(Theme.Keys.label)

        case .aiMenu:
            // The same mark the suggestion bar's sparkle wears, because it opens
            // the same panel. `SparkleMark` carries the gradient.
            SparkleMark(size: 18)

        case .quickTone:
            // `AIAction.rewrite`'s own icon, never a sparkle in any count.
            // `ToneIconTests` forbids the pairing and this key sits in a grid, not
            // beside the bar's sparkle, but the reason holds either way: the glyph
            // has to say which panel it is a shortcut through.
            Image(systemName: SuggestionBar.toneButtonSymbol)
                .font(Theme.Glyph.medium(16))
                .foregroundStyle(Theme.Brand.solid)

        case .cursorLeft:
            Image(systemName: "arrow.left")
                .font(Theme.Glyph.font(17))
                .foregroundStyle(Theme.Keys.label)

        case .cursorRight:
            Image(systemName: "arrow.right")
                .font(Theme.Glyph.font(17))
                .foregroundStyle(Theme.Keys.label)

        case .hideKeyboard:
            Image(systemName: "keyboard.chevron.compact.down")
                .font(Theme.Glyph.font(17))
                .foregroundStyle(Theme.Keys.label)
```

`SuggestionBar.toneButtonSymbol` is `static let` with no access modifier, so it is internal to the module. `KeyView` is in the same module. Fine.

`hasRestingCap` needs no change: none of the six is a character or a space, so all six draw as bare glyphs like every other control, which is the established rule.

- [ ] **Step 6: Wire the actions**

In `KeyboardController.swift`, beside `onAdvanceToNextKeyboard`:

```swift
    /// Called when a Hide keyboard key is tapped inside the real extension.
    /// Nothing in this package can dismiss a keyboard: only
    /// `UIInputViewController.dismissKeyboard()` can, and the package does not
    /// have one. Nil in the app preview, where there is nothing to dismiss.
    public var onDismissKeyboard: (() -> Void)?
```

In `press`, after the `.dictation` case:

```swift
        case .emoji:
            Feedback.modifierPress()
            show(overlay == .emoji ? .none : .emoji)
        case .aiMenu:
            Feedback.modifierPress()
            show(overlay == .aiMenu ? .none : .aiMenu)
        case .quickTone:
            Feedback.actionPress()
            // The same three-way answer the bar's button gives, so the key and the
            // button cannot disagree about what a tap does on an empty field.
            switch SuggestionBar.toneTap(
                hasTextToWorkWith: hasTextToWorkWith, isWorking: isWorking)
            {
            case .rewrite: runDefaultTone()
            case .openMenu: show(.aiMenu)
            case .ignore: break
            }
        case .cursorLeft:
            Feedback.keyPress()
            target?.adjustTextPosition(byCharacterOffset: -1)
            refreshSuggestions()
        case .cursorRight:
            Feedback.keyPress()
            target?.adjustTextPosition(byCharacterOffset: 1)
            refreshSuggestions()
        case .hideKeyboard:
            Feedback.modifierPress()
            onDismissKeyboard?()
```

`show(_:)` already exists at line 807 and wraps the assignment in `withAnimation(Theme.Motion.panel)`.

- [ ] **Step 7: Let the host dismiss**

In `AIKeyboardExtension/KeyboardViewController.swift`, after `controller.onAdvanceToNextKeyboard = …`:

```swift
        controller.onDismissKeyboard = { [weak self] in
            self?.dismissKeyboard()
        }
```

- [ ] **Step 8: Run the tests**

Run: `xcodebuild test … -only-testing:AIKeyboardCoreTests/CustomLayoutTests -only-testing:AIKeyboardCoreTests/CustomKeyActionTests`
Expected: all pass. Watch for unrelated failures caused by the new `KeyCap` cases making an existing `switch` non-exhaustive; fix each by adding the case, never by adding a `default`.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "Teach the keys six jobs they could not do before"
```

---

## Task 3: The validator

**Files:**
- Create: `Packages/AIKeyboardCore/Sources/AIKeyboardCore/LayoutValidator.swift`
- Test: `AIKeyboardCoreTests/CustomLayoutTests.swift`

**Interfaces:**
- Consumes: `KeyboardCustomization`, `SlotAction` from Task 1.
- Produces: `LayoutIssue`, `LayoutIssue.Severity`, `LayoutValidator.issues(in:showsGlobe:)`, `LayoutValidator.isUsable(_:showsGlobe:)`, `LayoutValidator.canRemove(_:from:showsGlobe:)`.

- [ ] **Step 1: Write the failing test**

New file `AIKeyboardCoreTests/LayoutValidatorTests.swift`:

```swift
import XCTest
@testable import AIKeyboardCore

final class LayoutValidatorTests: XCTestCase {

    private func errors(_ layout: KeyboardCustomization, showsGlobe: Bool = true) -> [LayoutIssue] {
        LayoutValidator.issues(in: layout, showsGlobe: showsGlobe).filter { $0.severity == .error }
    }

    func testTheDefaultLayoutIsClean() {
        XCTAssertEqual(LayoutValidator.issues(in: .default, showsGlobe: true), [])
    }

    /// Each essential removed on its own, so a single missing rail cannot hide
    /// behind another.
    func testRemovingAnyEssentialIsAnError() {
        let essentials: [SlotAction] = [.space, .backspace, .ret, .numbersPlane]
        for essential in essentials {
            var layout = KeyboardCustomization.default
            layout.bottomRow.removeAll { $0.action == essential }
            // Delete lives on a letter row, not the bottom row, so put the
            // default's own delete back for the cases that are not about it.
            let found = errors(layout)
            XCTAssertFalse(found.isEmpty, "removing \(essential) produced no error")
        }
    }

    /// Delete is reachable from the letter rows in the shipped layout, so the
    /// validator must not demand it in the custom rows. Only the three that have
    /// nowhere else to live are required there.
    func testDeleteIsNotRequiredInTheCustomRowsBecauseTheLetterRowsCarryIt() {
        var layout = KeyboardCustomization.default
        layout.bottomRow.removeAll { $0.action == .backspace }
        XCTAssertEqual(errors(layout), [], "the letter rows already carry delete")
    }

    func testGlobeCannotBeRemovedWhenIOSRequiresIt() {
        var layout = KeyboardCustomization.default
        layout.bottomRow.removeAll { $0.action == .globe }
        XCTAssertTrue(errors(layout, showsGlobe: true).contains { $0.kind == .missingGlobe })
        XCTAssertFalse(errors(layout, showsGlobe: false).contains { $0.kind == .missingGlobe })
    }

    func testCanRemoveAnswersTheSameQuestionTheEditorAsks() {
        let globe = KeyboardCustomization.default.bottomRow.first { $0.action == .globe }!
        XCTAssertFalse(
            LayoutValidator.canRemove(globe, from: .default, showsGlobe: true).isAllowed)
        XCTAssertTrue(
            LayoutValidator.canRemove(globe, from: .default, showsGlobe: false).isAllowed)
    }

    func testTheRefusalNamesItsReason() {
        let globe = KeyboardCustomization.default.bottomRow.first { $0.action == .globe }!
        let verdict = LayoutValidator.canRemove(globe, from: .default, showsGlobe: true)
        XCTAssertFalse(verdict.reason.isEmpty)
    }

    func testKeyHeightOutsideTheRangeIsAnError() {
        var layout = KeyboardCustomization.default
        layout.geometry.keyHeight = 90
        XCTAssertTrue(errors(layout).contains { $0.kind == .geometryOutOfRange })
        layout.geometry.keyHeight = 10
        XCTAssertTrue(errors(layout).contains { $0.kind == .geometryOutOfRange })
    }

    func testRowSpacingOutsideTheRangeIsAnError() {
        var layout = KeyboardCustomization.default
        layout.geometry.rowSpacing = 40
        XCTAssertTrue(errors(layout).contains { $0.kind == .geometryOutOfRange })
    }

    /// A row too wide to fit is the Bulgarian-class defect: it does not fail, it
    /// runs off the side of the screen.
    func testARowWiderThanTheBudgetIsAnError() {
        var layout = KeyboardCustomization.default
        layout.bottomRow = (0..<8).map { _ in SlotSpec(action: .text("x"), width: .units(3)) }
            + [SlotSpec(action: .space, width: .fill), SlotSpec(action: .ret)]
        XCTAssertTrue(errors(layout).contains { $0.kind == .rowTooWide })
    }

    func testASecondSpaceBarIsAnError() {
        var layout = KeyboardCustomization.default
        layout.bottomRow.append(SlotSpec(action: .space, width: .fill))
        XCTAssertTrue(errors(layout).contains { $0.kind == .duplicateSpace })
    }

    /// Warnings must not block Done, so they have to be a different severity.
    func testALongSnippetWarnsRatherThanBlocks() {
        var layout = KeyboardCustomization.default
        layout.bottomRow.append(SlotSpec(action: .text(String(repeating: "a", count: 40))))
        let issues = LayoutValidator.issues(in: layout, showsGlobe: true)
        XCTAssertTrue(issues.contains { $0.kind == .snippetTooLong && $0.severity == .warning })
        XCTAssertTrue(LayoutValidator.isUsable(layout, showsGlobe: true))
    }

    func testACrowdedRowWarns() {
        var layout = KeyboardCustomization.default
        layout.cursorRow = (0..<14).map { _ in SlotSpec(action: .text("x")) }
        let issues = LayoutValidator.issues(in: layout, showsGlobe: true)
        XCTAssertTrue(issues.contains { $0.kind == .rowCrowded && $0.severity == .warning })
    }
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `xcodebuild test … -only-testing:AIKeyboardCoreTests/LayoutValidatorTests`
Expected: compile failure, "cannot find 'LayoutValidator' in scope".

- [ ] **Step 3: Write `LayoutValidator.swift`**

```swift
import CoreGraphics
import Foundation

/// One thing wrong with a layout.
public struct LayoutIssue: Equatable, Identifiable, Sendable {

    public enum Severity: Sendable { case error, warning }

    public enum Kind: String, Equatable, Sendable {
        case missingSpace
        case missingReturn
        case missingPlaneSwitch
        case missingGlobe
        case duplicateSpace
        case rowTooWide
        case geometryOutOfRange
        case rowCrowded
        case snippetTooLong
        case duplicateAction
    }

    public var id: String { "\(kind.rawValue)-\(message)" }
    public let kind: Kind
    public let severity: Severity
    /// Written for the user, not for a log. It appears under the canvas.
    public let message: String
}

/// The rails. A keyboard the user can break is a keyboard the user cannot type
/// on, and they will not connect the crash to the screen where they broke it.
///
/// **Errors block Done, warnings do not.** The split is the whole design: a
/// second comma on a row is a taste the user is allowed to have, and a layout
/// with no return key is not a keyboard.
public enum LayoutValidator {

    /// How many key widths a custom row may occupy before it runs off the screen.
    ///
    /// Twelve, which is `KeyboardLayout.columns` at its widest — Russian, Arabic,
    /// Turkish and Persian are twelve-column layouts, and the unit is set by the
    /// widest plane the keyboard draws. A custom row is measured against the
    /// widest rather than the current language's, because the layout is one value
    /// shared by all of them and a row that fits English and not Russian would
    /// break on a space-bar slide.
    public static let widthBudget: CGFloat = 12

    /// A row wider than this is cramped but typeable.
    static let crowdedRowCount = 12
    static let longestSnippet = 20

    public static func issues(
        in layout: KeyboardCustomization, showsGlobe: Bool
    ) -> [LayoutIssue] {
        var found: [LayoutIssue] = []
        let custom = layout.bottomRow + layout.cursorRow
        let everywhere = custom + layout.barLeading + layout.barTrailing
        let actions = custom.map(\.action)

        // MARK: The essentials
        //
        // Three, and not four. Delete is deliberately absent: `KeyboardLayout`
        // puts it at the end of the bottom *letter* row in every language, and
        // those rows are not editable, so it is always reachable whatever the
        // user does down here.
        // Requiring it in the custom rows would make the shipped default invalid.

        if !actions.contains(.space) {
            found.append(
                LayoutIssue(
                    kind: .missingSpace, severity: .error,
                    message: "Add a space bar. Without one there is no way to type a space."))
        }
        if !actions.contains(.ret) {
            found.append(
                LayoutIssue(
                    kind: .missingReturn, severity: .error,
                    message: "Add a return key. Without one you cannot send or start a new line."
                ))
        }
        if !actions.contains(.numbersPlane) {
            found.append(
                LayoutIssue(
                    kind: .missingPlaneSwitch, severity: .error,
                    message: "Add the 123 key. Without it the numbers are unreachable."))
        }
        if showsGlobe, !actions.contains(.globe) {
            found.append(
                LayoutIssue(
                    kind: .missingGlobe, severity: .error,
                    message: globeRefusal))
        }

        if actions.filter({ $0 == .space }).count > 1 {
            found.append(
                LayoutIssue(
                    kind: .duplicateSpace, severity: .error,
                    message: "Only one space bar. Two both try to fill the row."))
        }

        // MARK: Geometry

        if !LayoutGeometry.keyHeightRange.contains(layout.geometry.keyHeight)
            || !LayoutGeometry.rowSpacingRange.contains(layout.geometry.rowSpacing)
        {
            found.append(
                LayoutIssue(
                    kind: .geometryOutOfRange, severity: .error,
                    message: "The key size is outside what fits on screen."))
        }

        // MARK: Width

        for (name, row) in [("bottom", layout.bottomRow), ("cursor", layout.cursorRow)] {
            guard !row.isEmpty else { continue }
            if fixedUnits(of: row) > widthBudget {
                found.append(
                    LayoutIssue(
                        kind: .rowTooWide, severity: .error,
                        message: "The \(name) row is too wide to fit. Make a key narrower or remove one."
                    ))
            }
            if row.count > crowdedRowCount {
                found.append(
                    LayoutIssue(
                        kind: .rowCrowded, severity: .warning,
                        message: "\(row.count) keys on the \(name) row will be hard to hit."))
            }
        }

        // MARK: Taste, not safety

        for slot in everywhere {
            if case .text(let value) = slot.action, value.count > longestSnippet {
                found.append(
                    LayoutIssue(
                        kind: .snippetTooLong, severity: .warning,
                        message: "\"\(value.prefix(12))…\" is too long to fit on a key cap."))
            }
        }

        for row in [layout.bottomRow, layout.cursorRow] {
            let repeated = Dictionary(grouping: row, by: \.action).filter { $0.value.count > 1 }
            for (action, _) in repeated where action != .space {
                found.append(
                    LayoutIssue(
                        kind: .duplicateAction, severity: .warning,
                        message: "\(action.title) appears twice on the same row."))
            }
        }

        return found
    }

    /// Whether Done is allowed.
    public static func isUsable(_ layout: KeyboardCustomization, showsGlobe: Bool) -> Bool {
        !issues(in: layout, showsGlobe: showsGlobe).contains { $0.severity == .error }
    }

    /// Whether one key may be taken out, and what to say if not.
    ///
    /// Asked by the editor's Remove button so a refusal can be shown *before* the
    /// tap rather than as an error afterwards. Implemented by removing the key and
    /// asking the same question the whole validator asks, so the two can never
    /// disagree about what is required.
    public static func canRemove(
        _ slot: SlotSpec, from layout: KeyboardCustomization, showsGlobe: Bool
    ) -> RemovalVerdict {
        var without = layout
        without.bottomRow.removeAll { $0.id == slot.id }
        without.cursorRow.removeAll { $0.id == slot.id }
        without.barLeading.removeAll { $0.id == slot.id }
        without.barTrailing.removeAll { $0.id == slot.id }

        let newErrors = issues(in: without, showsGlobe: showsGlobe)
            .filter { $0.severity == .error }
        let existing = Set(
            issues(in: layout, showsGlobe: showsGlobe)
                .filter { $0.severity == .error }.map(\.id))
        guard let blocker = newErrors.first(where: { !existing.contains($0.id) }) else {
            return RemovalVerdict(isAllowed: true, reason: "")
        }
        return RemovalVerdict(isAllowed: false, reason: blocker.message)
    }

    public struct RemovalVerdict: Equatable, Sendable {
        public let isAllowed: Bool
        /// Empty when allowed. Shown under the disabled Remove button otherwise.
        public let reason: String
    }

    /// **This is iOS's requirement, not a preference of ours.**
    /// `showsGlobe` is `UIInputViewController.needsInputModeSwitchKey`, which is
    /// the system saying the user has another keyboard installed and must be able
    /// to reach it. A layout without it on such a device strands them.
    static let globeRefusal =
        "iOS requires the next-keyboard key on this device, so it cannot be removed."

    /// The units a row occupies before the `fill` keys take what is left. A `fill`
    /// key still needs somewhere to stand, so it counts as one.
    private static func fixedUnits(of row: [SlotSpec]) -> CGFloat {
        row.reduce(CGFloat(0)) { total, slot in
            switch slot.width {
            case .units(let value): return total + value
            case .fill: return total + 1
            }
        }
    }
}
```

- [ ] **Step 4: Run and watch them pass**

Run: `xcodebuild test … -only-testing:AIKeyboardCoreTests/LayoutValidatorTests`
Expected: 12 tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Refuse the layouts that cannot type"
```

---

## Task 4: Compiling a customization into rows

**Files:**
- Create: `Packages/AIKeyboardCore/Sources/AIKeyboardCore/CustomLayoutCompiler.swift`
- Modify: `Packages/AIKeyboardCore/Sources/AIKeyboardCore/KeyboardLayout.swift` (add one static function near `bottomRow`)
- Test: `AIKeyboardCoreTests/CustomLayoutTests.swift`

**Interfaces:**
- Consumes: `KeyboardCustomization`, `SlotAction.keyCap(language:)`, `LayoutValidator.widthBudget`.
- Produces: `KeyboardLayout.rows(for:plane:showsGlobe:customization:) -> [KeyRow]`, `KeyboardLayout.compile(_:id:language:) -> KeyRow`.

Row ids matter: `KeyRow` is `Identifiable` by `Int` and `KeyboardView` runs `ForEach(characterRows)`. The existing letter rows use 0, 1, 2 and the bottom row uses 3. The number row needs an id below them and the cursor row above.

- [ ] **Step 1: Write the failing test**

Append to `AIKeyboardCoreTests/CustomLayoutTests.swift`:

```swift
extension CustomLayoutTests {

    /// The whole point of the default being a no-op: it has to compile to the same
    /// four rows the keyboard drew before any of this existed.
    func testTheDefaultCompilesToTodaysRows() {
        for language in [KeyboardLanguage.english, .hebrew, .russian, .arabic] {
            let old =
                KeyboardLayout.rows(for: language, plane: .letters)
                + [KeyboardLayout.bottomRow(for: language, plane: .letters, showsGlobe: true)]
            let new = KeyboardLayout.rows(
                for: language, plane: .letters, showsGlobe: true, customization: .default)

            XCTAssertEqual(old.count, new.count, "\(language)")
            for (a, b) in zip(old, new) {
                XCTAssertEqual(a.keys.map(\.id), b.keys.map(\.id), "\(language)")
                XCTAssertEqual(a.keys.map(\.width), b.keys.map(\.width), "\(language)")
                XCTAssertEqual(a.sideInsetUnits, b.sideInsetUnits, "\(language)")
            }
        }
    }

    func testEveryRowHasAUniqueID() {
        var layout = KeyboardCustomization.default
        layout.showsNumberRow = true
        layout.cursorRow = [SlotSpec(action: .cursorLeft), SlotSpec(action: .cursorRight)]
        let rows = KeyboardLayout.rows(
            for: .english, plane: .letters, showsGlobe: true, customization: layout)
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
        XCTAssertEqual(rows.count, 6)
    }

    func testTheNumberRowSitsAboveTheLetters() {
        var layout = KeyboardCustomization.default
        layout.showsNumberRow = true
        let rows = KeyboardLayout.rows(
            for: .english, plane: .letters, showsGlobe: true, customization: layout)
        XCTAssertEqual(rows.first?.keys.compactMap(\.characterValue), ["1","2","3","4","5","6","7","8","9","0"])
    }

    /// Hebrew writes its own digits with the same glyphs, but Arabic and Persian
    /// do not, and `KeyboardLanguage.digits` already knows.
    func testTheNumberRowUsesTheLanguagesOwnDigits() {
        var layout = KeyboardCustomization.default
        layout.showsNumberRow = true
        let rows = KeyboardLayout.rows(
            for: .arabic, plane: .letters, showsGlobe: true, customization: layout)
        XCTAssertEqual(
            rows.first?.keys.compactMap(\.characterValue).joined(),
            KeyboardLanguage.arabic.digits)
    }

    func testTheCursorRowSitsBelowTheBottomRow() {
        var layout = KeyboardCustomization.default
        layout.cursorRow = [SlotSpec(action: .cursorLeft), SlotSpec(action: .cursorRight)]
        let rows = KeyboardLayout.rows(
            for: .english, plane: .letters, showsGlobe: true, customization: layout)
        XCTAssertEqual(rows.last?.keys.map(\.cap), [.cursorLeft, .cursorRight])
    }

    /// The globe key is in the stored layout, but iOS decides whether it is drawn.
    func testTheGlobeKeyDropsOutWhenTheSystemDoesNotWantIt() {
        let rows = KeyboardLayout.rows(
            for: .english, plane: .letters, showsGlobe: false, customization: .default)
        XCTAssertFalse(rows.flatMap(\.keys).contains { $0.cap == .globe })
    }

    /// The custom rows follow the plane the keyboard is on, so the plane key says
    /// where it goes back to.
    func testTheBottomRowSwitchesBackFromTheNumbersPlane() {
        let rows = KeyboardLayout.rows(
            for: .hebrew, plane: .numbers, showsGlobe: true, customization: .default)
        let caps = rows.last!.keys.map(\.cap)
        XCTAssertTrue(
            caps.contains(.plane(.letters, label: KeyboardLanguage.hebrew.lettersPlaneLabel)))
    }

    /// Every preset against every language, which is the Bulgarian check.
    func testEveryPresetFitsEveryLanguage() {
        for preset in LayoutPreset.all {
            for language in KeyboardLanguage.allCases {
                for plane in [KeyboardPlane.letters, .numbers, .symbols] {
                    let rows = KeyboardLayout.rows(
                        for: language, plane: plane, showsGlobe: true,
                        customization: preset.customization)
                    let columns = CGFloat(KeyboardLayout.columns(for: language, plane: plane))
                    for row in rows {
                        let units = row.keys.reduce(CGFloat(0)) { total, key in
                            switch key.width {
                            case .unit(let value): return total + value
                            case .flexible, .remainderShare: return total + 1
                            }
                        }
                        XCTAssertLessThanOrEqual(
                            units + row.sideInsetUnits * 2, columns + 0.001,
                            "\(preset.id)/\(language)/\(plane) row \(row.id) is \(units) wide against \(columns)"
                        )
                    }
                }
            }
        }
    }
}

private extension KeySpec {
    var characterValue: String? {
        if case .character(let value) = cap { return value }
        return nil
    }
}
```

`KeySpec.width` is `let` and `KeyWidth` is `Equatable`, so `map(\.width)` compares. `KeyboardLanguage` must be `CaseIterable`; verify with `grep -n "enum KeyboardLanguage" Packages/AIKeyboardCore/Sources/AIKeyboardShared/KeyboardLanguage.swift` and if it is not, use `LayoutPreset.allLanguagesForTesting` built from `KeyboardLanguage.allCases` or the enabled set. It is used as `KeyboardLanguage.allCases` by `LanguageCatalogueTests`, so it is.

- [ ] **Step 2: Run and watch it fail**

Run: `xcodebuild test … -only-testing:AIKeyboardCoreTests/CustomLayoutTests`
Expected: compile failure on the four-argument `rows(for:plane:showsGlobe:customization:)`.

- [ ] **Step 3: Write `CustomLayoutCompiler.swift`**

```swift
import CoreGraphics
import Foundation

// MARK: - Customization into rows

/// **Customization is a source of `KeyRow`s, not a second rendering path.**
///
/// Everything the user arranges is compiled into the same `KeySpec` and `KeyRow`
/// types the measured letter layouts produce, before it reaches any view. The
/// width solver, `KeyView`, hit testing, the alternates popup and the
/// left-to-right pinning therefore need no knowledge that this feature exists,
/// and `RenderedRowOrderTests` keeps measuring what it always measured.
public extension KeyboardLayout {

    /// Row ids. `KeyRow` is `Identifiable` by `Int` and `KeyboardView` runs a
    /// `ForEach` over them, so two rows with one id is a `ForEach` with duplicate
    /// identity. The letter rows own 0, 1 and 2 and the bottom row owns 3, which
    /// is what shipped; the two new rows take numbers outside that range rather
    /// than renumbering anything.
    enum RowID {
        public static let numbers = -1
        public static let bottom = 3
        public static let cursor = 4
    }

    /// Every row the keyboard draws, in the order it draws them.
    static func rows(
        for language: KeyboardLanguage,
        plane: KeyboardPlane,
        showsGlobe: Bool,
        customization: KeyboardCustomization
    ) -> [KeyRow] {
        var rows: [KeyRow] = []

        // The number row is a letters-plane affordance. On the numbers plane the
        // digits are already the top row, and drawing them twice is not a feature.
        if customization.showsNumberRow, plane == .letters {
            rows.append(numberRow(for: language, plane: plane))
        }

        rows += KeyboardLayout.rows(for: language, plane: plane)

        rows.append(
            compile(
                customization.bottomRow, id: RowID.bottom, language: language, plane: plane,
                showsGlobe: showsGlobe, columns: columns(for: language, plane: plane)))

        if !customization.cursorRow.isEmpty {
            rows.append(
                compile(
                    customization.cursorRow, id: RowID.cursor, language: language, plane: plane,
                    showsGlobe: showsGlobe, columns: columns(for: language, plane: plane)))
        }

        return rows
    }

    /// The optional digits row, in the language's own numerals.
    private static func numberRow(for language: KeyboardLanguage, plane: KeyboardPlane) -> KeyRow {
        let digits = language.digits.map { KeySpec(.character(String($0))) }
        let columns = CGFloat(columns(for: language, plane: plane))
        return KeyRow(
            id: RowID.numbers,
            keys: digits,
            // Centred the way a short letter row is, so a twelve-column layout does
            // not stretch ten digits across the whole width and break the columns.
            sideInsetUnits: max(0, (columns - CGFloat(digits.count)) / 2))
    }

    /// One editable row.
    ///
    /// **The plane keys are resolved here, not stored.** A stored
    /// `SlotAction.numbersPlane` means "the key that switches planes", and what it
    /// says depends on where the keyboard is standing: `123` on the letters plane,
    /// the language's own letters label everywhere else. Storing the resolved cap
    /// would freeze a Hebrew keyboard's bottom row saying `123` while it was
    /// already showing numbers.
    static func compile(
        _ slots: [SlotSpec],
        id: Int,
        language: KeyboardLanguage,
        plane: KeyboardPlane,
        showsGlobe: Bool,
        columns: Int
    ) -> KeyRow {
        let keys: [KeySpec] = slots.compactMap { slot in
            // iOS owns this one. The layout stores it, the system decides whether
            // it is drawn, and a keyboard on a device with nothing else installed
            // gets the width back rather than a dead key.
            if slot.action == .globe, !showsGlobe { return nil }

            guard let cap = resolvedCap(slot.action, language: language, plane: plane) else {
                return nil
            }
            return KeySpec(cap, width: keyWidth(slot.width), id: slot.id.uuidString)
        }
        return KeyRow(id: id, keys: keys, sideInsetUnits: 0)
    }

    /// The plane key answers to where the keyboard is, everything else to itself.
    private static func resolvedCap(
        _ action: SlotAction, language: KeyboardLanguage, plane: KeyboardPlane
    ) -> KeyCap? {
        switch (action, plane) {
        case (.numbersPlane, .letters):
            return .plane(.numbers, label: "123")
        case (.numbersPlane, _), (.symbolsPlane, .letters):
            // From the numbers or symbols plane, the plane key goes home. The
            // symbols key does the same from letters, because `#+=` is reached
            // through `123` on the system keyboard and a key that jumps straight
            // there from letters is a key with no way back.
            return .plane(.letters, label: language.lettersPlaneLabel)
        case (.symbolsPlane, _):
            return .plane(.symbols, label: "#+=")
        default:
            return action.keyCap(language: language)
        }
    }

    private static func keyWidth(_ width: SlotWidth) -> KeyWidth {
        switch width {
        case .units(let value): return .unit(value)
        case .fill: return .flexible
        }
    }
}
```

**Why the id is `slot.id.uuidString` and not the cap's derived id:** two commas on one row derive the same `char-,` and that is a `ForEach` with duplicate identity. The `UUID` is the only stable unique handle, and it also lets the editor address a key on the canvas by the same id the model uses.

- [ ] **Step 4: Check the default really is a no-op**

Run: `xcodebuild test … -only-testing:AIKeyboardCoreTests/CustomLayoutTests/testTheDefaultCompilesToTodaysRows`

This test compares `KeySpec.id`, and the compiled default uses `uuidString` while the old `bottomRow` uses `plane-123`, `globe`, `space`, `dictation`, `return`. **The ids will differ and that is correct.** Change the assertion to compare `cap` and `width` rather than `id`:

```swift
                XCTAssertEqual(a.keys.map(\.cap), b.keys.map(\.cap), "\(language)")
                XCTAssertEqual(a.keys.map(\.width), b.keys.map(\.width), "\(language)")
```

Make that edit, then rerun. `KeyCap` is `Equatable`.

- [ ] **Step 5: Run the whole file**

Run: `xcodebuild test … -only-testing:AIKeyboardCoreTests/CustomLayoutTests`
Expected: all pass, including `testEveryPresetFitsEveryLanguage` — which needs Task 5's presets, so **do Task 5 before this step passes.** If running Task 4 alone, comment that one test out with a `// TODO(task-5)` marker and delete the marker in Task 5. Everything else must pass now.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Compile a described keyboard into the rows the view already draws"
```

---

## Task 5: The five presets

**Files:**
- Create: `Packages/AIKeyboardCore/Sources/AIKeyboardCore/LayoutPresets.swift`
- Test: `AIKeyboardCoreTests/CustomLayoutTests.swift`

**Interfaces:**
- Consumes: `KeyboardCustomization`, `SlotSpec`, `LayoutGeometry`.
- Produces: `LayoutPreset` with `id: String`, `name: String`, `summary: String`, `customization: KeyboardCustomization`; `LayoutPreset.all`; `LayoutPreset.named(_:)`.

- [ ] **Step 1: Write the failing test**

Append to `AIKeyboardCoreTests/CustomLayoutTests.swift`:

```swift
extension CustomLayoutTests {

    func testThereAreFivePresetsWithUniqueIDs() {
        XCTAssertEqual(LayoutPreset.all.count, 5)
        XCTAssertEqual(Set(LayoutPreset.all.map(\.id)).count, 5)
    }

    func testEveryPresetValidatesClean() {
        for preset in LayoutPreset.all {
            let errors = LayoutValidator.issues(in: preset.customization, showsGlobe: true)
                .filter { $0.severity == .error }
            XCTAssertEqual(errors, [], "\(preset.id): \(errors.map(\.message))")
        }
    }

    /// A preset that claims to be a preset must say which one, or the editor
    /// cannot show it as selected.
    func testEveryPresetNamesItself() {
        for preset in LayoutPreset.all {
            XCTAssertEqual(preset.customization.preset, preset.id)
            XCTAssertEqual(preset.customization.basedOn, preset.id)
            XCTAssertFalse(preset.name.isEmpty)
            XCTAssertFalse(preset.summary.isEmpty)
        }
    }

    func testDefaultPresetIsTheShippedDefault() {
        XCTAssertEqual(LayoutPreset.named("default")?.customization, .default)
    }

    func testPowerTurnsOnBothOptionalRows() {
        let power = LayoutPreset.named("power")!.customization
        XCTAssertTrue(power.showsNumberRow)
        XCTAssertFalse(power.cursorRow.isEmpty)
    }

    /// One-handed is a geometry toggle, not a preset. If it ever becomes one, this
    /// fails and the spec has to be revisited rather than quietly drifted from.
    func testNoPresetIsOneHanded() {
        XCTAssertTrue(LayoutPreset.all.allSatisfy { $0.customization.geometry.reach == .full })
    }

    func testAnUnknownPresetNameAnswersNil() {
        XCTAssertNil(LayoutPreset.named("nope"))
    }
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `xcodebuild test … -only-testing:AIKeyboardCoreTests/CustomLayoutTests`
Expected: "cannot find 'LayoutPreset' in scope".

- [ ] **Step 3: Write `LayoutPresets.swift`**

```swift
import Foundation

/// A named shape for the keyboard.
///
/// Five, and one-handed reach is deliberately not among them: it composes with
/// all five, and a user who wants "Power, one-handed" should not have to pick.
public struct LayoutPreset: Identifiable, Sendable {
    public let id: String
    public let name: String
    /// One line under the thumbnail. What changes, not what it is called.
    public let summary: String
    public let customization: KeyboardCustomization

    public static func named(_ id: String) -> LayoutPreset? {
        all.first { $0.id == id }
    }

    public static let all: [LayoutPreset] = [
        LayoutPreset(
            id: "default",
            name: "Default",
            summary: "The keyboard as it ships",
            customization: .default),

        LayoutPreset(
            id: "compact",
            name: "Compact",
            summary: "Shorter keys, more of the app visible",
            customization: base(
                "compact", geometry: LayoutGeometry(keyHeight: 38, rowSpacing: 9, reach: .full))),

        LayoutPreset(
            id: "roomy",
            name: "Roomy",
            summary: "Taller keys, easier to hit",
            customization: base(
                "roomy", geometry: LayoutGeometry(keyHeight: 52, rowSpacing: 14, reach: .full))),

        LayoutPreset(
            id: "power",
            name: "Power",
            summary: "Number row, arrows, comma and full stop",
            customization: {
                var layout = base("power", geometry: .default)
                layout.showsNumberRow = true
                layout.cursorRow = [
                    SlotSpec(action: .cursorLeft, width: .fill),
                    SlotSpec(action: .cursorRight, width: .fill),
                    SlotSpec(action: .text(","), width: .fill),
                    SlotSpec(action: .text("."), width: .fill),
                    SlotSpec(action: .hideKeyboard, width: .fill)
                ]
                return layout
            }()),

        LayoutPreset(
            id: "ai-first",
            name: "AI first",
            summary: "The AI key in the grid, rewrite in the bar",
            customization: {
                var layout = base("ai-first", geometry: .default)
                // The sparkle moves into the grid, where a thumb already is. The
                // bar keeps the one-tap rewrite, so the two AI controls stop
                // sitting side by side — which is the pairing `SuggestionBar`'s
                // own comment says was unreadable.
                layout.barTrailing = [SlotSpec(action: .quickTone)]
                layout.bottomRow = [
                    SlotSpec(action: .numbersPlane, width: .units(1.3)),
                    SlotSpec(action: .globe, width: .units(1.0)),
                    SlotSpec(action: .aiMenu, width: .units(1.2)),
                    SlotSpec(action: .space, width: .fill),
                    SlotSpec(action: .dictation, width: .units(1.0)),
                    SlotSpec(action: .ret, width: .units(1.8))
                ]
                return layout
            }())
    ]

    /// The default layout, restamped with another preset's name and geometry.
    /// Every preset starts from the shipped one so a change to the default's
    /// bottom row reaches all five rather than four of them.
    private static func base(_ id: String, geometry: LayoutGeometry) -> KeyboardCustomization {
        var layout = KeyboardCustomization.default
        layout.preset = id
        layout.basedOn = id
        layout.geometry = geometry
        return layout
    }
}
```

- [ ] **Step 4: Run the whole model suite**

Run: `xcodebuild test … -only-testing:AIKeyboardCoreTests/CustomLayoutTests -only-testing:AIKeyboardCoreTests/LayoutValidatorTests`
Expected: everything passes, including `testEveryPresetFitsEveryLanguage`. If a preset overruns a twelve-column language, narrow that preset's keys; do not raise `widthBudget`.

Delete the `// TODO(task-5)` marker from Task 4 if it was added.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Ship five keyboards instead of one"
```

---

## Task 6: Persistence

**Files:**
- Modify: `Packages/AIKeyboardCore/Sources/AIKeyboardCore/SharedStore.swift`
- Create: `AIKeyboardCoreTests/LayoutStoreTests.swift`

**Interfaces:**
- Consumes: `KeyboardCustomization`, `LayoutValidator`.
- Produces: `SharedStore.keyboardLayout` (`@Published`), `SharedStore.storedKeyboardLayout` (computed), `SharedStore.Key.keyboardLayout`, and `SharedStore.decodeLayout(from:)` as a `static` for tests.

- [ ] **Step 1: Write the failing test**

`AIKeyboardCoreTests/LayoutStoreTests.swift`:

```swift
import XCTest
@testable import AIKeyboardCore

/// Drives the decode path against a scratch suite. The singleton's own defaults
/// are the App Group plist and are nobody's fixture.
final class LayoutStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "LayoutStoreTests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testAnAbsentKeyIsTheShippedDefault() {
        XCTAssertEqual(SharedStore.decodeLayout(from: defaults), .default)
    }

    func testGarbageDecodesToTheDefaultRatherThanCrashing() {
        defaults.set(Data("not json".utf8), forKey: SharedStore.layoutKey)
        XCTAssertEqual(SharedStore.decodeLayout(from: defaults), .default)
    }

    /// A build that adds a new required key must not brick a keyboard saved by the
    /// build before it.
    func testAnInvalidStoredLayoutFallsBackToTheDefault() throws {
        var broken = KeyboardCustomization.default
        broken.bottomRow.removeAll { $0.action == .space }
        defaults.set(try JSONEncoder().encode(broken), forKey: SharedStore.layoutKey)
        XCTAssertEqual(SharedStore.decodeLayout(from: defaults), .default)
    }

    func testAValidStoredLayoutComesBack() throws {
        let roomy = LayoutPreset.named("roomy")!.customization
        defaults.set(try JSONEncoder().encode(roomy), forKey: SharedStore.layoutKey)
        XCTAssertEqual(SharedStore.decodeLayout(from: defaults), roomy)
    }

    /// **The keyboard is a second process.** `load()` fills the published copy
    /// once per launch, so a keyboard already on screen when the user hits Done
    /// has to read through `UserDefaults` again or it keeps drawing the old shape.
    /// The broken version returns the launch-time copy, so this writes *after* the
    /// read that would have cached it.
    func testTheStoredAccessorSeesAWriteMadeAfterItWasFirstRead() throws {
        _ = SharedStore.decodeLayout(from: defaults)
        let power = LayoutPreset.named("power")!.customization
        defaults.set(try JSONEncoder().encode(power), forKey: SharedStore.layoutKey)
        XCTAssertEqual(SharedStore.decodeLayout(from: defaults), power)
    }
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `xcodebuild test … -only-testing:AIKeyboardCoreTests/LayoutStoreTests`
Expected: "type 'SharedStore' has no member 'decodeLayout'".

- [ ] **Step 3: Add the setting**

In `SharedStore.swift`, add to `enum Key`:

```swift
        static let keyboardLayout = "keyboardLayout"
```

Add a section after `// MARK: Personal dictionary`:

```swift
    // MARK: Keyboard layout

    /// The key, exposed so `LayoutStoreTests` can write it into a scratch suite
    /// without reaching into a private enum.
    public static let layoutKey = Key.keyboardLayout

    /// The shape of the keyboard, as the editor in the app last left it.
    @Published public var keyboardLayout: KeyboardCustomization = .default {
        didSet { write(keyboardLayout) }
    }

    /// The same value, read out of the store at the moment it is needed.
    ///
    /// **The keyboard has to use this one, for the reason `storedDefaultTone` and
    /// `storedPersonalDictionary` exist.** The editor is in the app and the
    /// renderer is in the keyboard extension; those are two processes, and
    /// `load()` fills the `@Published` copy above once, when whichever process
    /// asked was launched. A keyboard already on screen when the user taps Done
    /// would otherwise keep drawing the shape they just changed, which looks
    /// exactly like the editor not working.
    public var storedKeyboardLayout: KeyboardCustomization {
        Self.decodeLayout(from: defaults)
    }

    /// **Falls back rather than throws, twice.** Unreadable JSON is a build that
    /// changed the model; a layout that fails the validator is a build that added
    /// a required key. Either one would otherwise be a keyboard that cannot draw
    /// itself, which is not a state the user can get out of from inside the
    /// keyboard.
    ///
    /// `showsGlobe: false` here on purpose: the globe requirement is a property of
    /// the *device* the keyboard is running on, and the store does not know it. A
    /// layout missing the globe is repaired where that is known — see
    /// `KeyboardController.customization`.
    public static func decodeLayout(from defaults: UserDefaults) -> KeyboardCustomization {
        guard let data = defaults.data(forKey: Key.keyboardLayout) else { return .default }
        guard let decoded = try? JSONDecoder().decode(KeyboardCustomization.self, from: data)
        else {
            log.error("stored keyboard layout could not be decoded, falling back to the default")
            return .default
        }
        guard LayoutValidator.isUsable(decoded, showsGlobe: false) else {
            log.error("stored keyboard layout is not usable, falling back to the default")
            return .default
        }
        return decoded
    }

    private func write(_ layout: KeyboardCustomization) {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        defaults.set(data, forKey: Key.keyboardLayout)
    }
```

`log` is `private static let log`. Change it to `static let log` so `decodeLayout` can reach it, or use `Self.log` inside the static — a `static` member can see another `private static` in the same type, so no change is needed. Leave it private.

Add to `resetToDefaults()`'s key list:

```swift
            Key.keyboardLayout,
```

and to its body:

```swift
        keyboardLayout = .default
```

Add to `load()`:

```swift
        keyboardLayout = Self.decodeLayout(from: defaults)
```

Note that `load()` assigning fires the `didSet`, which writes the same bytes back. Harmless, and it matches how `enabledLanguages` and the rest already behave in this file.

- [ ] **Step 4: Run and watch them pass**

Run: `xcodebuild test … -only-testing:AIKeyboardCoreTests/LayoutStoreTests`
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Persist the layout where both processes can read it"
```

---

## Task 7: Rendering the custom layout

**Files:**
- Modify: `Packages/AIKeyboardCore/Sources/AIKeyboardCore/Theme.swift:168-193`
- Modify: `Packages/AIKeyboardCore/Sources/AIKeyboardCore/KeyboardController.swift`
- Modify: `Packages/AIKeyboardCore/Sources/AIKeyboardCore/KeyboardView.swift`
- Modify: `AIKeyboardExtension/KeyboardViewController.swift`
- Create: `AIKeyboardCoreTests/LayoutGeometryTests.swift`

**Interfaces:**
- Consumes: everything above.
- Produces: `Theme.Metrics.keyAreaHeight(for:)`, `Theme.Metrics.totalHeight(for:withContextStrip:)`, `KeyboardController.customization` (`@Published`), `KeyboardController.reloadCustomization()`.

The existing `Theme.Metrics.keyAreaHeight` and `totalHeight(withContextStrip:)` stay, as the default-geometry values, so nothing that calls them today breaks. `KeyboardGeometry` reads `Theme.Metrics` for the capture band and keeps using the constants: the band is deliberately the height the keyboard *can* occupy, never its current height, and making it follow a resizable layout would retire a reading every time the user changed a slider.

- [ ] **Step 1: Write the failing test**

`AIKeyboardCoreTests/LayoutGeometryTests.swift`:

```swift
import XCTest
@testable import AIKeyboardCore

final class LayoutGeometryTests: XCTestCase {

    func testTheDefaultGeometryReproducesTheShippedHeight() {
        XCTAssertEqual(
            Theme.Metrics.keyAreaHeight(for: .default),
            Theme.Metrics.keyAreaHeight,
            accuracy: 0.001)
    }

    /// The number row is worth exactly one key plus one gap, and the old
    /// hardcoded `* 4` could not say so.
    func testTheNumberRowAddsOneRowOfHeight() {
        var layout = KeyboardCustomization.default
        let without = Theme.Metrics.keyAreaHeight(for: layout)
        layout.showsNumberRow = true
        let with = Theme.Metrics.keyAreaHeight(for: layout)
        XCTAssertEqual(
            with - without,
            layout.geometry.keyHeight + layout.geometry.rowSpacing,
            accuracy: 0.001)
    }

    func testTheCursorRowAddsOneRowOfHeight() {
        var layout = KeyboardCustomization.default
        let without = Theme.Metrics.keyAreaHeight(for: layout)
        layout.cursorRow = [SlotSpec(action: .cursorLeft)]
        XCTAssertEqual(
            Theme.Metrics.keyAreaHeight(for: layout) - without,
            layout.geometry.keyHeight + layout.geometry.rowSpacing,
            accuracy: 0.001)
    }

    func testRoomyIsTallerThanCompact() {
        XCTAssertGreaterThan(
            Theme.Metrics.keyAreaHeight(for: LayoutPreset.named("roomy")!.customization),
            Theme.Metrics.keyAreaHeight(for: LayoutPreset.named("compact")!.customization))
    }

    func testTheContextStripStillCounts() {
        let layout = KeyboardCustomization.default
        XCTAssertEqual(
            Theme.Metrics.totalHeight(for: layout, withContextStrip: true)
                - Theme.Metrics.totalHeight(for: layout, withContextStrip: false),
            Theme.Metrics.contextStripHeight,
            accuracy: 0.001)
    }
}

@MainActor
final class ControllerCustomizationTests: XCTestCase {

    /// The device decides whether the globe is drawn, and the stored layout does
    /// not know. A layout saved on a phone with one keyboard installed must not
    /// strand the user when they install a second.
    func testTheControllerPutsTheGlobeBackWhenTheSystemNeedsIt() {
        let controller = KeyboardController(target: MockTextTarget(), language: .english)
        controller.showsGlobeKey = true
        var without = KeyboardCustomization.default
        without.bottomRow.removeAll { $0.action == .globe }
        controller.apply(without)
        XCTAssertTrue(controller.customization.bottomRow.contains { $0.action == .globe })
    }

    func testAUsableLayoutIsAppliedUnchanged() {
        let controller = KeyboardController(target: MockTextTarget(), language: .english)
        controller.showsGlobeKey = true
        let roomy = LayoutPreset.named("roomy")!.customization
        controller.apply(roomy)
        XCTAssertEqual(controller.customization, roomy)
    }
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `xcodebuild test … -only-testing:AIKeyboardCoreTests/LayoutGeometryTests -only-testing:AIKeyboardCoreTests/ControllerCustomizationTests`
Expected: "extra argument 'for' in call".

- [ ] **Step 3: Make the metrics a function of the layout**

In `Theme.swift`, inside `enum Metrics`, keep the constants and add:

```swift
        /// Height of the key rows plus their insets, for one layout.
        ///
        /// **The old spelling hardcoded four rows** — `keyHeight * 4 + rowSpacing
        /// * 3` — which was right for as long as the grid could only be three
        /// letter rows and a bottom row. With an optional number row and an
        /// optional cursor row it is four, five or six, and the key height is no
        /// longer a constant either. The constants above stay as the default
        /// values, so `keyAreaHeight` and `totalHeight(withContextStrip:)` still
        /// answer for the shipped layout and every existing caller is unchanged.
        public static func keyAreaHeight(for layout: KeyboardCustomization) -> CGFloat {
            let rows = CGFloat(layout.rowCount)
            return layout.geometry.keyHeight * rows
                + layout.geometry.rowSpacing * (rows - 1)
                + topInset + bottomInset
        }

        public static func totalHeight(
            for layout: KeyboardCustomization, withContextStrip: Bool = false
        ) -> CGFloat {
            suggestionBarHeight + keyAreaHeight(for: layout)
                + (withContextStrip ? contextStripHeight : 0)
        }
```

- [ ] **Step 4: Give the controller a layout**

In `KeyboardController.swift`, beside `showsGlobeKey`:

```swift
    /// The shape of the keyboard right now.
    ///
    /// Published so the view redraws when the app changes it. Read from the store
    /// at init and on every appearance, never cached across a process boundary —
    /// see `SharedStore.storedKeyboardLayout`.
    @Published public private(set) var customization: KeyboardCustomization = .default
```

And, in the same file:

```swift
    /// Takes a layout, repairing what only this process knows.
    ///
    /// **The globe is put back here and nowhere else.** Whether the key is
    /// required is `needsInputModeSwitchKey`, which is a property of the device
    /// and is unknown to the store: a layout saved on a phone with one keyboard
    /// installed is missing nothing, and becomes a trap the day a second one is
    /// added. `SharedStore.decodeLayout` therefore validates with
    /// `showsGlobe: false` and this is where the device's own answer is applied.
    public func apply(_ layout: KeyboardCustomization) {
        var repaired = layout
        if showsGlobeKey, !(repaired.bottomRow + repaired.cursorRow).contains(where: {
            $0.action == .globe
        }) {
            // Second from the start, which is where it stands in every preset:
            // beside the plane key and away from the space bar.
            let index = min(1, repaired.bottomRow.count)
            repaired.bottomRow.insert(SlotSpec(action: .globe, width: .units(1.0)), at: index)
        }
        guard LayoutValidator.isUsable(repaired, showsGlobe: showsGlobeKey) else {
            customization = .default
            return
        }
        customization = repaired
    }

    /// Re-reads the layout from the shared store. Called when the keyboard comes
    /// on screen, because that is the moment after the app may have changed it.
    public func reloadCustomization() {
        apply(store.storedKeyboardLayout)
    }
```

Call `apply(store.storedKeyboardLayout)` at the end of `init`. Find the initializer (`public init(target:store:language:)`) and add it as the last statement.

- [ ] **Step 5: Draw it**

In `KeyboardView.swift`, replace the body of `keyGrid`'s `VStack` construction:

```swift
    private var keyGrid: some View {
        GeometryReader { geo in
            let layout = controller.customization
            let columns = KeyboardLayout.columns(for: controller.language, plane: controller.plane)
            let gridWidth = geo.size.width * layout.geometry.reach.widthFraction
            let unit = KeyboardLayout.unitWidth(
                totalWidth: gridWidth,
                spacing: Theme.Metrics.keySpacing,
                sideInset: Theme.Metrics.sideInset,
                columns: columns
            )
            let available = gridWidth - Theme.Metrics.sideInset * 2
            let rows = KeyboardLayout.rows(
                for: controller.language,
                plane: controller.plane,
                showsGlobe: controller.showsGlobeKey,
                customization: layout
            )

            VStack(spacing: layout.geometry.rowSpacing) {
                ForEach(rows) { row in
                    rowView(row, availableWidth: available, unit: unit)
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            .padding(.horizontal, Theme.Metrics.sideInset)
            .padding(.top, Theme.Metrics.topInset)
            .padding(.bottom, Theme.Metrics.bottomInset)
            .frame(width: gridWidth, alignment: .center)
            // One-handed pins the grid to a side and leaves a strip on the other.
            // `.frame(maxWidth:alignment:)` on the parent is what moves it; the
            // grid itself never changes shape, so nothing inside has to know.
            .frame(maxWidth: .infinity, alignment: reachAlignment(layout.geometry.reach))
        }
    }

    private func reachAlignment(_ reach: Reach) -> Alignment {
        switch reach {
        case .full: return .center
        case .left: return .leading
        case .right: return .trailing
        }
    }
```

Keep the long comment above `.environment(\.layoutDirection, .leftToRight)` exactly as it is; it is the record of the right-to-left bug.

`rowView` passes `height: Theme.Metrics.keyHeight`. Change it to take the height:

```swift
    private func rowView(_ row: KeyRow, availableWidth: CGFloat, unit: CGFloat) -> some View {
```

becomes

```swift
    private func rowView(_ row: KeyRow, availableWidth: CGFloat, unit: CGFloat, height: CGFloat) -> some View {
```

with `height: height` in the `KeyView` call, and the call site passing `height: layout.geometry.keyHeight`.

Change the `ZStack` frame:

```swift
            .frame(height: Theme.Metrics.keyAreaHeight(for: controller.customization))
```

- [ ] **Step 6: Follow the height in the host**

In `KeyboardViewController.swift`:

```swift
    private func updateKeyboardHeight() {
        guard let controller else { return }
        let height = Theme.Metrics.totalHeight(
            for: controller.customization,
            withContextStrip: controller.showsScreenContextStrip)
        …
```

and subscribe to the layout as well as the context strip, in `viewDidLoad` beside the existing sink:

```swift
        // The layout is edited in the app, which is another process, so the height
        // changes without anything in here having asked for it.
        controller.$customization
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateKeyboardHeight() }
            .store(in: &cancellables)
```

and re-read the layout when the keyboard appears, in `viewDidAppear` before `recordPresence()`:

```swift
        controller.reloadCustomization()
```

- [ ] **Step 7: Run the full suite**

Run: `xcodebuild test -project AIKeyboard.xcodeproj -scheme AIKeyboard -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: everything passes. `RenderedRowOrderTests` is the one to watch: the default layout must still render identically, and if it does not, the compiler in Task 4 is wrong, not the test.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Draw whichever keyboard the settings describe"
```

---

## Task 8: The suggestion bar's ends

**Files:**
- Modify: `Packages/AIKeyboardCore/Sources/AIKeyboardCore/SuggestionBar.swift`
- Test: `AIKeyboardCoreTests/CustomLayoutTests.swift`

**Interfaces:**
- Consumes: `KeyboardController.customization`, `SlotAction`.
- Produces: `SuggestionBar.slotButton(_:)`.

The bar's three existing controls become a rendering of `barLeading` and `barTrailing`. The `toneButton` and `sparkleButton` keep every one of their measured behaviours — the three-way `ToneTap`, the flat-not-disabled styling, the `hasRunnableAction` gate — because those are separately documented decisions and this task is about position, not behaviour.

- [ ] **Step 1: Write the failing test**

Append to `AIKeyboardCoreTests/CustomLayoutTests.swift`:

```swift
extension CustomLayoutTests {

    /// The bar's own defaults have to match what shipped, or the first launch
    /// after this feature rearranges a bar nobody asked to rearrange.
    func testTheDefaultBarIsWhatShipped() {
        XCTAssertEqual(KeyboardCustomization.default.barLeading.map(\.action), [.emoji])
        XCTAssertEqual(
            KeyboardCustomization.default.barTrailing.map(\.action), [.quickTone, .aiMenu])
    }

    /// Only the actions that make sense above the keys. A space bar in the
    /// suggestion bar is not a layout, it is a mistake.
    func testTheBarOffersASubsetOfTheCatalogue() {
        XCTAssertTrue(Set(SuggestionBar.barCatalogue).isSubset(of: Set(SlotAction.catalogue)))
        XCTAssertFalse(SuggestionBar.barCatalogue.contains(.space))
        XCTAssertFalse(SuggestionBar.barCatalogue.contains(.shift))
        XCTAssertTrue(SuggestionBar.barCatalogue.contains(.emoji))
        XCTAssertTrue(SuggestionBar.barCatalogue.contains(.aiMenu))
        XCTAssertTrue(SuggestionBar.barCatalogue.contains(.quickTone))
    }
}
```

- [ ] **Step 2: Run and watch it fail**

Expected: "type 'SuggestionBar' has no member 'barCatalogue'".

- [ ] **Step 3: Render the slots**

In `SuggestionBar.swift`, replace the `body`'s `HStack` contents:

```swift
    public var body: some View {
        HStack(spacing: 0) {
            ForEach(controller.customization.barLeading) { slot in
                slotButton(slot.action)
            }

            if !controller.customization.barLeading.isEmpty { separator }

            suggestions

            if !controller.customization.barTrailing.isEmpty { separator }

            // No rule between the trailing controls: they are a group, and the two
            // AI ones in particular are one control with a shortcut.
            ForEach(controller.customization.barTrailing) { slot in
                slotButton(slot.action)
            }
        }
        …
```

and add:

```swift
    /// What the bar's two ends may hold.
    ///
    /// A subset of `SlotAction.catalogue`, and the exclusions are the point: a
    /// space bar or a shift key 46 points tall above the letters is not a layout
    /// anybody meant to build. Delete is out for a subtler reason — it is the one
    /// key with an accelerating repeat, and the repeat is wired in `KeyView`,
    /// which does not draw this bar.
    static let barCatalogue: [SlotAction] = [
        .emoji, .aiMenu, .quickTone, .dictation, .cursorLeft, .cursorRight,
        .hideKeyboard, .globe
    ]

    /// One configured control.
    ///
    /// The three that shipped keep their own views, unchanged: each carries a
    /// measured decision — the tone button's three-way tap, the sparkle's
    /// agreement with `AIMenuPanel.hasRunnableAction`, the emoji key's active
    /// tint — and this switch is about which ones are drawn and where, not how.
    @ViewBuilder
    func slotButton(_ action: SlotAction) -> some View {
        switch action {
        case .emoji:
            edgeButton(
                systemImage: "face.smiling", label: "Emoji",
                isActive: controller.overlay == .emoji
            ) {
                controller.show(controller.overlay == .emoji ? .none : .emoji)
            }
        case .aiMenu:
            sparkleButton
        case .quickTone:
            toneButton
        default:
            // Everything else is the same tap the grid key makes, drawn as an edge
            // button. One implementation, so a control cannot behave differently
            // depending on which of the two places the user put it.
            edgeButton(
                systemImage: action.glyph ?? "questionmark",
                label: action.title,
                isActive: false
            ) {
                controller.press(action.keyCap(language: controller.language) ?? .space)
            }
        }
    }
```

The `default` branch never sees `.space` in practice because `barCatalogue` excludes it, and `?? .space` is only there because `keyCap` is optional. Guard it instead so a future bad value cannot type a space into the user's message:

```swift
            if let cap = action.keyCap(language: controller.language) {
                edgeButton(
                    systemImage: action.glyph ?? "questionmark",
                    label: action.title,
                    isActive: false
                ) {
                    controller.press(cap)
                }
            }
```

- [ ] **Step 4: Run the suite**

Run: `xcodebuild test … -only-testing:AIKeyboardCoreTests`
Expected: passes, including `AIButtonTests` and `EmptyFieldBarTests`, which pin the sparkle and tone behaviours. If either fails, the slot rendering has changed a behaviour it was only supposed to move.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Let the bar's ends be arranged too"
```

---

## Task 9: The editor screen, phase one

**Files:**
- Create: `AIKeyboard/Main/LayoutEditorModel.swift`
- Create: `AIKeyboard/Main/LayoutView.swift`
- Modify: `AIKeyboard/Main/SettingsView.swift` (`typingSection`)

**Interfaces:**
- Consumes: `LayoutPreset`, `LayoutValidator`, `KeyboardCustomization`, `KeyboardPreview`.
- Produces: `LayoutEditorModel` (`@MainActor`, `ObservableObject`) with `draft`, `selection`, `issues`, `undo()`, `reset()`, `canUndo`, `apply(preset:)`, `move(_:by:)`, `remove(_:)`, `add(_:to:)`, `setWidth(_:for:)`, `setAction(_:for:)`, `RowKind`.

This task delivers a working editor with no dragging: presets, geometry, optional rows, and per-key move/width/action/remove through buttons. That is the whole feature minus the gesture, and it ships on its own. Task 10 adds the drag.

- [ ] **Step 1: Write the failing test**

`AIKeyboardCoreTests` cannot see the app target. Put the editor model's logic in the model file and test it from `AIKeyboardUITests`? No: UI tests are a separate process and cannot import app types either.

**Put `LayoutEditorModel` in `AIKeyboardCore`, not in the app.** It is pure state arithmetic over `KeyboardCustomization` with no SwiftUI in it, `AIKeyboardCoreTests` can reach it, and the app's `LayoutView` observes it. Create it at
`Packages/AIKeyboardCore/Sources/AIKeyboardCore/LayoutEditorModel.swift` instead, and drop `AIKeyboard/Main/LayoutEditorModel.swift` from the file list.

`AIKeyboardCoreTests/LayoutEditorTests.swift`:

```swift
import XCTest
@testable import AIKeyboardCore

@MainActor
final class LayoutEditorTests: XCTestCase {

    private func editor() -> LayoutEditorModel {
        LayoutEditorModel(layout: .default, showsGlobe: true)
    }

    func testMovingAKeyChangesItsPosition() {
        let model = editor()
        let dictation = model.draft.bottomRow.first { $0.action == .dictation }!
        let before = model.draft.bottomRow.firstIndex(of: dictation)!
        model.move(dictation, by: -1)
        XCTAssertEqual(model.draft.bottomRow.firstIndex(of: dictation), before - 1)
    }

    func testMovingPastTheEndDoesNothing() {
        let model = editor()
        let first = model.draft.bottomRow[0]
        model.move(first, by: -1)
        XCTAssertEqual(model.draft.bottomRow[0], first)
    }

    func testRemovingTheGlobeIsRefused() {
        let model = editor()
        let globe = model.draft.bottomRow.first { $0.action == .globe }!
        model.remove(globe)
        XCTAssertTrue(model.draft.bottomRow.contains(globe))
    }

    func testRemovingAnOrdinaryKeyWorks() {
        let model = editor()
        let dictation = model.draft.bottomRow.first { $0.action == .dictation }!
        model.remove(dictation)
        XCTAssertFalse(model.draft.bottomRow.contains(dictation))
    }

    /// Editing a preset stops it being that preset, and Reset has to still know
    /// where to go.
    func testEditingClearsThePresetAndKeepsBasedOn() {
        let model = editor()
        model.apply(preset: LayoutPreset.named("power")!)
        XCTAssertEqual(model.draft.preset, "power")
        model.add(.text("!"), to: .bottom)
        XCTAssertNil(model.draft.preset)
        XCTAssertEqual(model.draft.basedOn, "power")
    }

    func testResetGoesBackToTheBasePreset() {
        let model = editor()
        model.apply(preset: LayoutPreset.named("power")!)
        model.add(.text("!"), to: .bottom)
        model.reset()
        XCTAssertEqual(model.draft, LayoutPreset.named("power")!.customization)
    }

    func testUndoStepsBackOneEdit() {
        let model = editor()
        let before = model.draft
        model.add(.text("!"), to: .bottom)
        XCTAssertTrue(model.canUndo)
        model.undo()
        XCTAssertEqual(model.draft, before)
        XCTAssertFalse(model.canUndo)
    }

    func testUndoIsCappedAndKeepsTheMostRecent() {
        let model = editor()
        for index in 0..<40 { model.add(.text("\(index)"), to: .bottom) }
        var steps = 0
        while model.canUndo, steps < 100 { model.undo(); steps += 1 }
        XCTAssertEqual(steps, LayoutEditorModel.undoLimit)
    }

    func testWidthIsClamped() {
        let model = editor()
        let key = model.draft.bottomRow[0]
        model.setWidth(.units(99), for: key)
        guard case .units(let value)? = model.draft.bottomRow.first(where: { $0.id == key.id })?.width
        else { return XCTFail("width is not units") }
        XCTAssertEqual(value, SlotWidth.maximumUnits)
    }

    func testChangingAnActionKeepsTheKeysIdentity() {
        let model = editor()
        let key = model.draft.bottomRow.first { $0.action == .dictation }!
        model.setAction(.emoji, for: key)
        XCTAssertEqual(model.draft.bottomRow.first { $0.id == key.id }?.action, .emoji)
    }

    func testIssuesTrackTheDraft() {
        let model = editor()
        XCTAssertTrue(model.isUsable)
        let space = model.draft.bottomRow.first { $0.action == .space }!
        // `remove` refuses this, so reach past it the way a decode from another
        // build would.
        model.draft.bottomRow.removeAll { $0.id == space.id }
        XCTAssertFalse(model.isUsable)
        XCTAssertTrue(model.issues.contains { $0.kind == .missingSpace })
    }

    func testTurningTheCursorRowOnSeedsItRatherThanLeavingItEmpty() {
        let model = editor()
        model.setCursorRow(enabled: true)
        XCTAssertEqual(
            model.draft.cursorRow.map(\.action), [.cursorLeft, .cursorRight, .hideKeyboard])
        model.setCursorRow(enabled: false)
        XCTAssertTrue(model.draft.cursorRow.isEmpty)
    }
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `xcodebuild test … -only-testing:AIKeyboardCoreTests/LayoutEditorTests`
Expected: "cannot find 'LayoutEditorModel' in scope".

- [ ] **Step 3: Write `LayoutEditorModel.swift`**

At `Packages/AIKeyboardCore/Sources/AIKeyboardCore/LayoutEditorModel.swift`:

```swift
import Combine
import Foundation

/// The editor's state. No SwiftUI in here on purpose: it is arithmetic over a
/// `KeyboardCustomization`, and keeping it in the package is what lets
/// `LayoutEditorTests` drive every edit the screen can make without a view.
@MainActor
public final class LayoutEditorModel: ObservableObject {

    /// Which editable row a key belongs to. The bar's two ends are rows as far as
    /// the arithmetic is concerned; only the drawing differs.
    public enum RowKind: String, CaseIterable, Sendable {
        case bottom, cursor, barLeading, barTrailing
    }

    /// Twenty steps. Deep enough that an experiment is recoverable, shallow
    /// enough that the stack is not a second copy of the feature.
    public static let undoLimit = 20

    @Published public var draft: KeyboardCustomization {
        didSet {
            // The moment the draft stops being the preset exactly, it is a custom
            // layout with a base. `basedOn` survives, so Reset has somewhere to go.
            if let preset = draft.preset,
                LayoutPreset.named(preset)?.customization != draft
            {
                draft.preset = nil
            }
        }
    }

    @Published public var selection: SlotSpec?

    public let showsGlobe: Bool

    private var history: [KeyboardCustomization] = []

    public init(layout: KeyboardCustomization, showsGlobe: Bool) {
        self.draft = layout
        self.showsGlobe = showsGlobe
    }

    // MARK: Reading

    public var issues: [LayoutIssue] {
        LayoutValidator.issues(in: draft, showsGlobe: showsGlobe)
    }

    public var isUsable: Bool { LayoutValidator.isUsable(draft, showsGlobe: showsGlobe) }

    public var canUndo: Bool { !history.isEmpty }

    public func row(_ kind: RowKind) -> [SlotSpec] {
        switch kind {
        case .bottom: return draft.bottomRow
        case .cursor: return draft.cursorRow
        case .barLeading: return draft.barLeading
        case .barTrailing: return draft.barTrailing
        }
    }

    /// Which row a key is in, or nil if it is not in the draft at all.
    public func rowKind(of slot: SlotSpec) -> RowKind? {
        RowKind.allCases.first { row($0).contains { $0.id == slot.id } }
    }

    public func canRemove(_ slot: SlotSpec) -> LayoutValidator.RemovalVerdict {
        LayoutValidator.canRemove(slot, from: draft, showsGlobe: showsGlobe)
    }

    // MARK: Editing

    public func apply(preset: LayoutPreset) {
        edit { $0 = preset.customization }
        selection = nil
    }

    public func reset() {
        guard let base = LayoutPreset.named(draft.basedOn) else { return }
        edit { $0 = base.customization }
        selection = nil
    }

    public func add(_ action: SlotAction, to kind: RowKind) {
        edit { layout in
            Self.write(kind, in: &layout) { $0.append(SlotSpec(action: action)) }
        }
    }

    public func remove(_ slot: SlotSpec) {
        guard canRemove(slot).isAllowed, let kind = rowKind(of: slot) else { return }
        edit { layout in
            Self.write(kind, in: &layout) { $0.removeAll { $0.id == slot.id } }
        }
        if selection?.id == slot.id { selection = nil }
    }

    /// Moves a key `offset` places within its own row. Out of range is a no-op
    /// rather than a clamp: a Move left button on the leftmost key should do
    /// nothing, not silently re-anchor it.
    public func move(_ slot: SlotSpec, by offset: Int) {
        guard let kind = rowKind(of: slot) else { return }
        let current = row(kind)
        guard let index = current.firstIndex(where: { $0.id == slot.id }) else { return }
        let destination = index + offset
        guard current.indices.contains(destination) else { return }
        edit { layout in
            Self.write(kind, in: &layout) { keys in
                let moved = keys.remove(at: index)
                keys.insert(moved, at: destination)
            }
        }
    }

    /// Moves a key to an absolute index, possibly in another row. The drag
    /// editor's only mutation.
    public func move(_ slot: SlotSpec, to kind: RowKind, at index: Int) {
        guard let origin = rowKind(of: slot) else { return }
        edit { layout in
            Self.write(origin, in: &layout) { $0.removeAll { $0.id == slot.id } }
            Self.write(kind, in: &layout) { keys in
                keys.insert(slot, at: min(max(0, index), keys.count))
            }
        }
    }

    public func setWidth(_ width: SlotWidth, for slot: SlotSpec) {
        let clamped: SlotWidth
        switch width {
        case .fill: clamped = .fill
        case .units(let value): clamped = SlotWidth.clampedUnits(value)
        }
        mutate(slot) { $0.width = clamped }
    }

    public func setAction(_ action: SlotAction, for slot: SlotSpec) {
        mutate(slot) { $0.action = action }
    }

    public func setNumberRow(enabled: Bool) {
        edit { $0.showsNumberRow = enabled }
    }

    /// **Seeded, not empty.** A cursor row switched on and left blank is a row the
    /// user has to populate before it does anything, and they have just told us
    /// what they want it for.
    public func setCursorRow(enabled: Bool) {
        edit { layout in
            layout.cursorRow =
                enabled
                ? [
                    SlotSpec(action: .cursorLeft, width: .fill),
                    SlotSpec(action: .cursorRight, width: .fill),
                    SlotSpec(action: .hideKeyboard, width: .fill)
                ]
                : []
        }
    }

    public func setKeyHeight(_ height: CGFloat) {
        edit {
            $0.geometry.keyHeight = min(
                LayoutGeometry.keyHeightRange.upperBound,
                max(LayoutGeometry.keyHeightRange.lowerBound, height))
        }
    }

    public func setRowSpacing(_ spacing: CGFloat) {
        edit {
            $0.geometry.rowSpacing = min(
                LayoutGeometry.rowSpacingRange.upperBound,
                max(LayoutGeometry.rowSpacingRange.lowerBound, spacing))
        }
    }

    public func setReach(_ reach: Reach) {
        edit { $0.geometry.reach = reach }
    }

    // MARK: Undo

    public func undo() {
        guard let previous = history.popLast() else { return }
        draft = previous
        selection = selection.flatMap { current in
            RowKind.allCases.lazy.compactMap { kind in
                row(kind).first { $0.id == current.id }
            }.first
        }
    }

    // MARK: Plumbing

    /// Every mutation goes through here, so nothing can change the draft without
    /// leaving a step on the undo stack.
    private func edit(_ change: (inout KeyboardCustomization) -> Void) {
        let before = draft
        var next = draft
        change(&next)
        guard next != before else { return }
        history.append(before)
        if history.count > Self.undoLimit { history.removeFirst() }
        draft = next
    }

    private func mutate(_ slot: SlotSpec, _ change: (inout SlotSpec) -> Void) {
        guard let kind = rowKind(of: slot) else { return }
        edit { layout in
            Self.write(kind, in: &layout) { keys in
                guard let index = keys.firstIndex(where: { $0.id == slot.id }) else { return }
                change(&keys[index])
            }
        }
        // The selection holds a value, not a reference, so it goes stale the
        // moment the key it names is edited.
        if selection?.id == slot.id {
            selection = row(kind).first { $0.id == slot.id }
        }
    }

    private static func write(
        _ kind: RowKind, in layout: inout KeyboardCustomization,
        _ change: (inout [SlotSpec]) -> Void
    ) {
        switch kind {
        case .bottom: change(&layout.bottomRow)
        case .cursor: change(&layout.cursorRow)
        case .barLeading: change(&layout.barLeading)
        case .barTrailing: change(&layout.barTrailing)
        }
    }
}
```

`import CoreGraphics` is needed for `CGFloat`; `Foundation` re-exports it on Apple platforms, so `Foundation` alone is enough.

- [ ] **Step 4: Run and watch them pass**

Run: `xcodebuild test … -only-testing:AIKeyboardCoreTests/LayoutEditorTests`
Expected: 12 tests pass. `testUndoIsCappedAndKeepsTheMostRecent` expects exactly `undoLimit` steps; if it comes back 21, the cap trims after appending and the assertion is right.

- [ ] **Step 5: Write `LayoutView.swift`**

At `AIKeyboard/Main/LayoutView.swift`:

```swift
import SwiftUI
import AIKeyboardCore

/// The layout editor: the real keyboard above, the controls below.
///
/// **The canvas is the real `KeyboardView`.** Nothing here redraws the keyboard
/// for editing, so what the user arranges is literally what they get — which is
/// the whole reason the keyboard UI lives in the package rather than in the
/// extension.
struct LayoutView: View {

    @EnvironmentObject private var store: SharedStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: LayoutEditorModel
    @StateObject private var preview = MockTextTarget(text: "")
    @StateObject private var canvas: KeyboardController

    init(layout: KeyboardCustomization) {
        let document = MockTextTarget()
        let controller = KeyboardController(target: document, language: .english)
        // There is no keyboard to switch to inside the app, so the globe is drawn
        // and does nothing but cycle languages. Editing must still refuse to
        // remove it, because the *device* is what decides and the phone this is
        // running on is the phone the keyboard will run on.
        controller.showsGlobeKey = true
        controller.apply(layout)
        _canvas = StateObject(wrappedValue: controller)
        _preview = StateObject(wrappedValue: document)
        _model = StateObject(
            wrappedValue: LayoutEditorModel(layout: layout, showsGlobe: true))
    }

    var body: some View {
        ZStack {
            Theme.Surface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                canvasSection
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.lg) {
                        presetStrip
                        if let selection = model.selection {
                            keyInspector(selection)
                        } else {
                            geometrySection
                        }
                        addDrawer
                        problems
                    }
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.vertical, Theme.Space.md)
                }
            }
        }
        .navigationTitle("Keyboard layout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Undo", systemImage: "arrow.uturn.backward") { model.undo() }
                    .disabled(!model.canUndo)
                    .accessibilityIdentifier("layout-undo")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    store.keyboardLayout = model.draft
                    dismiss()
                }
                .fontWeight(.semibold)
                .disabled(!model.isUsable)
                .accessibilityIdentifier("layout-done")
            }
        }
        // The canvas is a second controller with its own copy, so it has to be
        // told. One direction only: the model is the truth and the canvas draws it.
        .onChange(of: model.draft) { _, layout in canvas.apply(layout) }
    }

    // MARK: Canvas

    private var canvasSection: some View {
        VStack(spacing: 0) {
            KeyboardView(controller: canvas)
                .allowsHitTesting(false)
                .overlay { selectionOverlay }
            Divider().overlay(Theme.Surface.separator)
        }
        .background(Theme.Keys.background)
    }

    /// Taps land here rather than on the keys, because `KeyView`'s gesture types
    /// and this one selects. Hit testing is off on the keyboard itself and the
    /// selectable keys are drawn as an invisible row of buttons over the bottom
    /// row's frames.
    ///
    /// Phase one selects from the list below the canvas instead, which is also the
    /// route that works under VoiceOver. The overlay is the drag target and lands
    /// with the drag editor.
    private var selectionOverlay: some View { Color.clear }

    // MARK: Presets

    private var presetStrip: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "Presets")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.sm) {
                    ForEach(LayoutPreset.all) { preset in
                        presetCard(preset)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            if model.draft.preset == nil,
                let base = LayoutPreset.named(model.draft.basedOn)
            {
                HStack {
                    Text("Custom, from \(base.name)")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Text.secondary)
                    Spacer()
                    Button("Reset") { model.reset() }
                        .font(.system(size: 13, weight: .semibold))
                }
            }
        }
    }

    private func presetCard(_ preset: LayoutPreset) -> some View {
        let isSelected = model.draft.preset == preset.id
        return Button {
            model.apply(preset: preset)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                LayoutThumbnail(layout: preset.customization)
                    .frame(width: 96, height: 60)
                Text(preset.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Text.primary)
                Text(preset.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Text.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(width: 112, alignment: .leading)
            .padding(Theme.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(Theme.Surface.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(Theme.Brand.gradient)
                            : AnyShapeStyle(Color.clear),
                        lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("preset-\(preset.id)")
        .accessibilityLabel(preset.name)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityHint(preset.summary)
    }

    // MARK: Geometry

    private var geometrySection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "Size and rows")
            Card {
                VStack(spacing: Theme.Space.sm) {
                    slider(
                        "Key height", value: model.draft.geometry.keyHeight,
                        range: LayoutGeometry.keyHeightRange, unit: "pt"
                    ) { model.setKeyHeight($0) }
                    Divider().overlay(Theme.Surface.separator)
                    slider(
                        "Row spacing", value: model.draft.geometry.rowSpacing,
                        range: LayoutGeometry.rowSpacingRange, unit: "pt"
                    ) { model.setRowSpacing($0) }
                    Divider().overlay(Theme.Surface.separator)
                    Toggle(
                        "Number row",
                        isOn: Binding(
                            get: { model.draft.showsNumberRow },
                            set: { model.setNumberRow(enabled: $0) })
                    )
                    .accessibilityIdentifier("layout-number-row")
                    Divider().overlay(Theme.Surface.separator)
                    Toggle(
                        "Cursor row",
                        isOn: Binding(
                            get: { !model.draft.cursorRow.isEmpty },
                            set: { model.setCursorRow(enabled: $0) })
                    )
                    .accessibilityIdentifier("layout-cursor-row")
                    Divider().overlay(Theme.Surface.separator)
                    Picker(
                        "One-handed",
                        selection: Binding(
                            get: { model.draft.geometry.reach },
                            set: { model.setReach($0) })
                    ) {
                        Text("Off").tag(Reach.full)
                        Text("Left").tag(Reach.left)
                        Text("Right").tag(Reach.right)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("layout-reach")
                }
            }
            keyList
        }
    }

    private func slider(
        _ title: String, value: CGFloat, range: ClosedRange<CGFloat>, unit: String,
        set: @escaping (CGFloat) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 15))
                Spacer()
                Text("\(Int(value))\(unit)")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.Text.secondary)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(get: { Double(value) }, set: { set(CGFloat($0)) }),
                in: Double(range.lowerBound)...Double(range.upperBound), step: 1
            )
            .accessibilityLabel(title)
            .accessibilityValue("\(Int(value)) \(unit)")
        }
    }

    // MARK: The rows, as a list

    /// **The list is not a fallback for the canvas, it is the accessible route.**
    /// Drag and drop is unusable under VoiceOver, so every edit the drag editor
    /// will offer has to exist as a control here too. It ships first for the same
    /// reason: this is the half that works for everybody.
    private var keyList: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            rowEditor("Bottom row", kind: .bottom)
            if !model.draft.cursorRow.isEmpty {
                rowEditor("Cursor row", kind: .cursor)
            }
            rowEditor("Bar, leading", kind: .barLeading)
            rowEditor("Bar, trailing", kind: .barTrailing)
        }
    }

    private func rowEditor(_ title: String, kind: LayoutEditorModel.RowKind) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: title)
            Card {
                VStack(spacing: Theme.Space.xs) {
                    ForEach(model.row(kind)) { slot in
                        keyRow(slot, in: kind)
                    }
                    if model.row(kind).isEmpty {
                        Text("No keys. Add one below.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Text.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func keyRow(_ slot: SlotSpec, in kind: LayoutEditorModel.RowKind) -> some View {
        let keys = model.row(kind)
        let position = (keys.firstIndex(of: slot) ?? 0) + 1
        return HStack(spacing: Theme.Space.sm) {
            Button {
                model.selection = model.selection?.id == slot.id ? nil : slot
            } label: {
                HStack(spacing: Theme.Space.xs) {
                    slotGlyph(slot.action)
                        .frame(width: 24)
                    Text(slot.action.title)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Text.primary)
                    Spacer(minLength: 0)
                    Text(widthLabel(slot.width))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.Text.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                model.move(slot, by: -1)
            } label: {
                Image(systemName: "arrow.left")
            }
            .disabled(position == 1)
            .accessibilityLabel("Move \(slot.action.title) left")

            Button {
                model.move(slot, by: 1)
            } label: {
                Image(systemName: "arrow.right")
            }
            .disabled(position == keys.count)
            .accessibilityLabel("Move \(slot.action.title) right")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(slot.action.title), key \(position) of \(keys.count)")
        .accessibilityIdentifier("slot-\(slot.action.title)")
    }

    private func widthLabel(_ width: SlotWidth) -> String {
        switch width {
        case .fill: return "Fill"
        case .units(let value): return String(format: "%.1fx", value)
        }
    }

    @ViewBuilder
    private func slotGlyph(_ action: SlotAction) -> some View {
        if let glyph = action.glyph {
            Image(systemName: glyph)
                .font(.system(size: 15))
                .foregroundStyle(Theme.Text.secondary)
        } else {
            Text(action.title.prefix(3))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Text.secondary)
        }
    }

    // MARK: Inspector

    private func keyInspector(_ slot: SlotSpec) -> some View {
        let verdict = model.canRemove(slot)
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                SectionHeader(title: slot.action.title)
                Spacer()
                Button("Done") { model.selection = nil }
                    .font(.system(size: 13, weight: .semibold))
            }
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    widthControl(slot)
                    Divider().overlay(Theme.Surface.separator)
                    actionPicker(slot)
                    Divider().overlay(Theme.Surface.separator)
                    HStack {
                        Button("Move left") { model.move(slot, by: -1) }
                        Spacer()
                        Button("Move right") { model.move(slot, by: 1) }
                        Spacer()
                        Button("Remove", role: .destructive) { model.remove(slot) }
                            .disabled(!verdict.isAllowed)
                    }
                    .font(.system(size: 14))
                    if !verdict.isAllowed {
                        Text(verdict.reason)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Semantic.warning)
                    }
                }
            }
        }
    }

    private func widthControl(_ slot: SlotSpec) -> some View {
        let isFill = slot.width == .fill
        let units: CGFloat = {
            if case .units(let value) = slot.width { return value }
            return 1
        }()
        return VStack(alignment: .leading, spacing: 4) {
            Toggle(
                "Fill the row",
                isOn: Binding(
                    get: { isFill },
                    set: { model.setWidth($0 ? .fill : .units(units), for: slot) })
            )
            .accessibilityIdentifier("inspector-fill")
            if !isFill {
                slider(
                    "Width", value: units,
                    range: SlotWidth.minimumUnits...SlotWidth.maximumUnits, unit: "x"
                ) { model.setWidth(.units($0), for: slot) }
            }
        }
    }

    private func actionPicker(_ slot: SlotSpec) -> some View {
        let options = model.rowKind(of: slot).map { kind -> [SlotAction] in
            kind == .barLeading || kind == .barTrailing
                ? SuggestionBar.barCatalogue : SlotAction.catalogue
        } ?? SlotAction.catalogue
        // The key's own action is always offered, even when it is not in the
        // catalogue for its row — the space bar is not addable and must still be
        // selectable, or opening the picker on it silently retargets it.
        let all = options.contains(slot.action) ? options : [slot.action] + options
        return Picker(
            "Action",
            selection: Binding(
                get: { slot.action },
                set: { model.setAction($0, for: slot) })
        ) {
            ForEach(all, id: \.self) { action in
                Text(action.title).tag(action)
            }
        }
        .accessibilityIdentifier("inspector-action")
    }

    // MARK: Add

    private var addDrawer: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "Add a key")
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text("Adds to the bottom row.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Text.secondary)
                    FlowRow(spacing: Theme.Space.xs) {
                        ForEach(SlotAction.catalogue, id: \.self) { action in
                            Button {
                                model.add(action, to: .bottom)
                            } label: {
                                HStack(spacing: 4) {
                                    slotGlyph(action)
                                    Text(action.title)
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule().fill(Theme.Surface.card)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add \(action.title)")
                        }
                    }
                }
            }
        }
    }

    // MARK: Problems

    @ViewBuilder
    private var problems: some View {
        let issues = model.issues
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                SectionHeader(title: "Problems")
                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        ForEach(issues) { issue in
                            HStack(alignment: .top, spacing: Theme.Space.xs) {
                                Image(
                                    systemName: issue.severity == .error
                                        ? "exclamationmark.triangle.fill" : "info.circle"
                                )
                                .foregroundStyle(
                                    issue.severity == .error
                                        ? Theme.Semantic.record : Theme.Semantic.warning)
                                Text(issue.message)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.Text.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Thumbnail

/// A wireframe of a layout, small enough to compare five of them at a glance.
/// Drawn from the layout rather than from an asset, so a preset cannot get a
/// picture that no longer matches it.
struct LayoutThumbnail: View {
    let layout: KeyboardCustomization

    var body: some View {
        GeometryReader { geo in
            let rows = layout.rowCount
            let gap: CGFloat = 2
            let height = (geo.size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
            VStack(spacing: gap) {
                if layout.showsNumberRow { bar(count: 10, height: height, width: geo.size.width) }
                bar(count: 10, height: height, width: geo.size.width)
                bar(count: 9, height: height, width: geo.size.width)
                bar(count: 9, height: height, width: geo.size.width)
                bar(count: layout.bottomRow.count, height: height, width: geo.size.width)
                if !layout.cursorRow.isEmpty {
                    bar(count: layout.cursorRow.count, height: height, width: geo.size.width)
                }
            }
            .frame(width: geo.size.width * layout.geometry.reach.widthFraction)
            .frame(maxWidth: .infinity, alignment: alignment)
        }
    }

    private var alignment: Alignment {
        switch layout.geometry.reach {
        case .full: return .center
        case .left: return .leading
        case .right: return .trailing
        }
    }

    private func bar(count: Int, height: CGFloat, width: CGFloat) -> some View {
        HStack(spacing: 1.5) {
            ForEach(0..<max(1, count), id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Theme.Text.secondary.opacity(0.35))
            }
        }
        .frame(height: height)
    }
}
```

`FlowRow` does not exist in this codebase. Add it to `AppComponents.swift`:

```swift
/// A wrapping row. `LazyVGrid` cannot do this: its columns are fixed widths and
/// these chips are as wide as their words.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: width, height: y + lineHeight)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
```

`Theme.Surface.card`, `Theme.Text.primary` and `Theme.Text.secondary` must exist. Check with `grep -n "enum Surface" -A 12 Packages/AIKeyboardCore/Sources/AIKeyboardCore/Theme.swift` and substitute the real names if they differ.

- [ ] **Step 6: Add the Settings row**

In `SettingsView.swift`'s `typingSection`, after the Predictions toggle:

```swift
            divider
            NavigationRow(
                title: "Keyboard layout",
                subtitle: layoutSummary,
                icon: "square.grid.3x2"
            ) {
                LayoutView(layout: store.keyboardLayout)
            }
```

and beside it:

```swift
    /// The preset's name, or that it is no longer one.
    private var layoutSummary: String {
        guard let id = store.keyboardLayout.preset,
            let preset = LayoutPreset.named(id)
        else { return "Custom" }
        return preset.name
    }
```

Check `NavigationRow`'s real signature at `AIKeyboard/Components/AppComponents.swift:120` and match it; it takes a `Destination` view builder.

- [ ] **Step 7: Build and run everything**

Run: `xcodebuild build -project AIKeyboard.xcodeproj -scheme AIKeyboard -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
then: `xcodebuild test -project AIKeyboard.xcodeproj -scheme AIKeyboard -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: build succeeds, all tests pass.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Put the layout editor in Settings"
```

---

## Task 10: Rendering and cross-process proof

**Files:**
- Create: `AIKeyboardUITests/CustomLayoutRenderingTests.swift`

**Interfaces:**
- Consumes: everything.
- Produces: nothing. This is the task that proves the feature works in the product rather than in the model.

`RenderedRowOrderTests.swift` and `KeyboardExtensionTestCase.swift` already stand the real extension over a real `UITextField`. Read both before writing this file and follow their setup exactly.

- [ ] **Step 1: Write the test**

```swift
import XCTest

/// **A row-string assertion cannot see a reversal, because the string is right
/// either way.** These measure rendered key frames, the way
/// `RenderedRowOrderTests` does, and they exist because a custom bottom row is
/// the obvious place for the right-to-left mirroring bug of commit 593e7b2 to
/// come back.
final class CustomLayoutRenderingTests: KeyboardExtensionTestCase {

    /// The stored order is the drawn order, in a right-to-left language.
    func testACustomBottomRowIsNotMirroredUnderHebrew() throws {
        try selectLayoutPreset("power", language: .hebrew)

        let left = key("cursor-left")
        let right = key("cursor-right")
        XCTAssertTrue(left.exists && right.exists)
        XCTAssertLessThan(
            left.frame.minX, right.frame.minX,
            "the cursor row mirrored under Hebrew: stored order must be drawn order")
    }

    /// The number row is above the letters and the cursor row below the bottom one.
    func testTheOptionalRowsAreWhereTheySay() throws {
        try selectLayoutPreset("power", language: .english)

        let digit = key("char-1")
        let letter = key("char-q")
        let space = key("space")
        let cursor = key("cursor-left")
        XCTAssertLessThan(digit.frame.midY, letter.frame.midY)
        XCTAssertGreaterThan(cursor.frame.midY, space.frame.midY)
    }

    /// A key the user added types its character into a real host field through the
    /// real extension. **The in-app playground is not evidence**: this repo has
    /// already shipped a build where every key drew, animated and clicked and not
    /// one character reached the host.
    func testAnAddedKeyTypesIntoTheHost() throws {
        try selectLayoutPreset("power", language: .english)

        let field = hostTextField()
        field.tap()
        key("char-,").tap()

        XCTAssertEqual(field.value as? String, ",")
    }

    /// Roomy keys are taller than compact ones on the actual screen, not only in
    /// the arithmetic.
    func testTheGeometryReachesTheRenderedKeys() throws {
        try selectLayoutPreset("compact", language: .english)
        let compact = key("char-q").frame.height
        try selectLayoutPreset("roomy", language: .english)
        let roomy = key("char-q").frame.height
        XCTAssertGreaterThan(roomy, compact + 8)
    }
}
```

- [ ] **Step 2: Write the helpers the tests need**

`selectLayoutPreset(_:language:)`, `key(_:)` and `hostTextField()` do not exist. Add them to `CustomLayoutRenderingTests` (not to `KeyboardExtensionTestCase`, which other suites depend on) by reading how `RenderedRowOrderTests` finds keys and how `KeyboardExtensionTestCase` launches the app, and copying that shape. Keys are addressable by `key-<KeySpec.id>` — see `KeyView.swift:95`.

**The custom bottom row's `KeySpec.id` is a `uuidString`, not `char-,`.** That makes it unaddressable from a UI test. Fix it in the compiler rather than in the test: in `CustomLayoutCompiler.swift`, give the spec a stable, unique id derived from both the action and the slot:

```swift
            return KeySpec(
                cap, width: keyWidth(slot.width),
                // Two parts, and both are needed. The cap's own derived id is what
                // a test and a screen reader can address — `char-,` rather than a
                // UUID — and the slot's id is what keeps two commas on one row from
                // being one `ForEach` identity.
                id: "\(KeySpec(cap).id)#\(slot.id.uuidString.prefix(8))")
```

and change `KeyView`'s accessibility identifier to strip the suffix so `key-char-,` still matches:

```swift
        .accessibilityIdentifier("key-\(spec.id.split(separator: "#").first.map(String.init) ?? spec.id)")
```

Add a unit test for that in `CustomLayoutTests`:

```swift
    func testCompiledKeysKeepAnAddressableIDAndAUniqueOne() {
        var layout = KeyboardCustomization.default
        layout.bottomRow.append(SlotSpec(action: .text(",")))
        layout.bottomRow.append(SlotSpec(action: .text(",")))
        let row = KeyboardLayout.rows(
            for: .english, plane: .letters, showsGlobe: true, customization: layout)[3]
        let commas = row.keys.filter { $0.cap == .character(",") }
        XCTAssertEqual(commas.count, 2)
        XCTAssertNotEqual(commas[0].id, commas[1].id)
        XCTAssertTrue(commas.allSatisfy { $0.id.hasPrefix("char-,#") })
    }
```

and a test that the default's ids are unchanged, since `RenderedRowOrderTests` may rely on them:

```swift
    func testTheDefaultBottomRowKeepsItsShippedIdentifiers() {
        let row = KeyboardLayout.rows(
            for: .english, plane: .letters, showsGlobe: true, customization: .default)[3]
        let addressable = row.keys.map { $0.id.split(separator: "#").first.map(String.init)! }
        XCTAssertEqual(addressable, ["plane-123", "globe", "space", "dictation", "return"])
    }
```

- [ ] **Step 3: Run the UI tests alone**

Run: `xcodebuild test -project AIKeyboard.xcodeproj -scheme AIKeyboard -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:AIKeyboardUITests`
Expected: pass. **Do not run this while any other `xcodebuild test` is running** — two runs against the same simulator kill each other's runners and report as "crashed with signal kill".

- [ ] **Step 4: Run everything**

Run: `xcodebuild test -project AIKeyboard.xcodeproj -scheme AIKeyboard -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: all suites pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Prove the custom rows draw and type on a device"
```

---

## Task 11: The drag editor

**Files:**
- Modify: `AIKeyboard/Main/LayoutView.swift` (`selectionOverlay`)

**Interfaces:**
- Consumes: `LayoutEditorModel.move(_:to:at:)`, `LayoutEditorModel.selection`.
- Produces: nothing new.

The list editor from Task 9 is the accessible route and stays. This adds the gesture over the canvas for everybody else.

- [ ] **Step 1: Write the failing test**

The drag arithmetic is testable without a view; the gesture is not. Test the arithmetic.

Append to `AIKeyboardCoreTests/LayoutEditorTests.swift`:

```swift
extension LayoutEditorTests {

    func testDroppingAKeyAtAnIndexPutsItThere() {
        let model = LayoutEditorModel(layout: .default, showsGlobe: true)
        let ret = model.draft.bottomRow.last!
        model.move(ret, to: .bottom, at: 0)
        XCTAssertEqual(model.draft.bottomRow.first, ret)
    }

    func testDroppingIntoAnotherRowMovesItBetweenThem() {
        let model = LayoutEditorModel(layout: .default, showsGlobe: true)
        model.setCursorRow(enabled: true)
        let dictation = model.draft.bottomRow.first { $0.action == .dictation }!
        model.move(dictation, to: .cursor, at: 0)
        XCTAssertFalse(model.draft.bottomRow.contains(dictation))
        XCTAssertEqual(model.draft.cursorRow.first, dictation)
    }

    func testDroppingPastTheEndAppendsRatherThanCrashing() {
        let model = LayoutEditorModel(layout: .default, showsGlobe: true)
        let first = model.draft.bottomRow[0]
        model.move(first, to: .bottom, at: 99)
        XCTAssertEqual(model.draft.bottomRow.last, first)
    }

    /// The index a drop lands on, from the x of the finger against the keys'
    /// frames. Pure arithmetic, so it is testable without a gesture.
    func testTheInsertionIndexFollowsTheFinger() {
        let frames: [CGRect] = [
            CGRect(x: 0, y: 0, width: 40, height: 40),
            CGRect(x: 44, y: 0, width: 40, height: 40),
            CGRect(x: 88, y: 0, width: 40, height: 40)
        ]
        XCTAssertEqual(LayoutEditorModel.insertionIndex(at: 5, in: frames), 0)
        XCTAssertEqual(LayoutEditorModel.insertionIndex(at: 35, in: frames), 1)
        XCTAssertEqual(LayoutEditorModel.insertionIndex(at: 200, in: frames), 3)
    }
}
```

- [ ] **Step 2: Add the arithmetic**

To `LayoutEditorModel`:

```swift
    /// Where a drop at this x lands, given the keys' frames in the same space.
    ///
    /// The midpoint of each key is the boundary, so a finger past the middle of a
    /// key means "after it". Static and taking frames rather than reading a view,
    /// because a gesture cannot be tested and this can.
    public static func insertionIndex(at x: CGFloat, in frames: [CGRect]) -> Int {
        var index = 0
        for frame in frames where x > frame.midX { index += 1 }
        return index
    }
```

Run the tests: `xcodebuild test … -only-testing:AIKeyboardCoreTests/LayoutEditorTests`. Expected: pass.

- [ ] **Step 3: Make the canvas draggable**

Replace `selectionOverlay` in `LayoutView.swift`:

```swift
    @State private var keyFrames: [UUID: CGRect] = [:]
    @State private var dragging: SlotSpec?
    @State private var dragLocation: CGPoint = .zero

    /// Taps select, long presses drag.
    ///
    /// Hit testing is off on the keyboard beneath, so this layer is the only thing
    /// receiving touches: `KeyView`'s own gesture types, and here a touch has to
    /// select. The frames come from the keys themselves through a preference, so
    /// the overlay never has to reproduce the width solver.
    private var selectionOverlay: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(editableSlots, id: \.id) { slot in
                    if let frame = keyFrames[slot.id] {
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                            .overlay {
                                if model.selection?.id == slot.id {
                                    RoundedRectangle(cornerRadius: Theme.Radius.key)
                                        .strokeBorder(Theme.Brand.gradient, lineWidth: 2)
                                        .frame(width: frame.width, height: frame.height)
                                        .offset(x: frame.minX, y: frame.minY)
                                }
                            }
                            .onTapGesture { model.selection = slot }
                            .gesture(dragGesture(slot))
                    }
                }
                if let dragging, let frame = keyFrames[dragging.id] {
                    // The key under the finger, lifted.
                    RoundedRectangle(cornerRadius: Theme.Radius.key)
                        .fill(Theme.Brand.solid.opacity(0.28))
                        .frame(width: frame.width, height: frame.height)
                        .position(dragLocation)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "canvas")
        }
    }

    private var editableSlots: [SlotSpec] {
        model.draft.bottomRow + model.draft.cursorRow
    }

    private func dragGesture(_ slot: SlotSpec) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .onEnded { _ in
                dragging = slot
                model.selection = slot
                Feedback.modifierPress()
            }
            .sequenced(before: DragGesture(coordinateSpace: .named("canvas")))
            .onChanged { value in
                guard case .second(_, let drag?) = value else { return }
                dragLocation = drag.location
            }
            .onEnded { value in
                defer { dragging = nil }
                guard case .second(_, let drag?) = value, let dragging else { return }
                let kind = rowKind(atY: drag.location.y) ?? .bottom
                let frames = model.row(kind).compactMap { keyFrames[$0.id] }
                let index = LayoutEditorModel.insertionIndex(at: drag.location.x, in: frames)
                model.move(dragging, to: kind, at: index)
                Feedback.success()
            }
    }

    /// Which editable row a y coordinate is over. Nil over the letters, which is
    /// what makes them refuse the drop.
    private func rowKind(atY y: CGFloat) -> LayoutEditorModel.RowKind? {
        for kind in [LayoutEditorModel.RowKind.bottom, .cursor] {
            let frames = model.row(kind).compactMap { keyFrames[$0.id] }
            guard let first = frames.first else { continue }
            if y >= first.minY - 6, y <= first.maxY + 6 { return kind }
        }
        return nil
    }
```

The frames have to come from the keys. Add a preference key in `AIKeyboardCore`, in `KeyboardView.swift`:

```swift
/// Where each key ended up, in the keyboard's own coordinate space.
///
/// Published only so the layout editor can put a selection ring and a drop
/// target over the real keyboard rather than over a drawing of it. Nothing in
/// the keyboard itself reads this.
public struct KeyFramesKey: PreferenceKey {
    public static var defaultValue: [String: CGRect] { [:] }
    public static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
```

and in `rowView`'s `KeyView` call, wrap it:

```swift
                KeyView(…)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: KeyFramesKey.self,
                                value: [key.id: proxy.frame(in: .named("keyboard-grid"))])
                        }
                    }
```

and name the coordinate space on `keyGrid`'s `VStack`:

```swift
            .coordinateSpace(name: "keyboard-grid")
```

In `LayoutView`, collect them:

```swift
            KeyboardView(controller: canvas)
                .allowsHitTesting(false)
                .onPreferenceChange(KeyFramesKey.self) { frames in
                    // The compiled id is `char-,#a1b2c3d4`; the model's key is the
                    // UUID. Map back through the suffix.
                    var mapped: [UUID: CGRect] = [:]
                    for slot in editableSlots {
                        let suffix = String(slot.id.uuidString.prefix(8))
                        if let match = frames.first(where: { $0.key.hasSuffix("#\(suffix)") }) {
                            mapped[slot.id] = match.value
                        }
                    }
                    keyFrames = mapped
                }
                .overlay { selectionOverlay }
```

- [ ] **Step 4: Build, then run everything**

Run: `xcodebuild build …` then `xcodebuild test …`
Expected: build succeeds, all tests pass. The gesture itself is not covered by a test; verify it by hand in the simulator: open Settings › Typing › Keyboard layout, long-press the dictation key on the canvas, drag it to the start of the row, and confirm the list below reorders with it.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Let the keys be dragged where they should go"
```

---

## Task 12: Documentation

**Files:**
- Modify: `.claude/CLAUDE.md`
- Modify: `README.md`

- [ ] **Step 1: Add the gotcha**

Add one bullet to the Gotchas list in `.claude/CLAUDE.md`, in the established voice: what the feature is, what is *not* editable and why, the two traps (row ids, the compiled `KeySpec.id` shape) and the fact that the default compiles to what shipped. Do not restate the spec.

- [ ] **Step 2: Update the README table** if it lists features or settings.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "Write down what the layout editor may and may not touch"
```

---

## Self-Review

**Spec coverage**

| Spec section | Task |
|---|---|
| 1, the decision | Global constraints; Task 4's doc comment |
| 2, editable zones and actions | Tasks 1, 2, 4, 8 |
| 2, widths | Task 1 (`SlotWidth`), Task 9 (inspector) |
| 2, geometry | Tasks 1, 7, 9 |
| 3, rails | Task 3 |
| 4, presets | Task 5, Task 9 (strip and thumbnails) |
| 5, data model and persistence | Tasks 1, 6 |
| 6, rendering, direction, height | Tasks 4, 7 |
| 7, editor, interaction, a11y, undo | Tasks 9, 11 |
| 8, testing | Tasks 1–7 unit, Task 10 rendering and host |
| 9, phases | Tasks 1–9 are phase 1, Task 11 is phase 2. Phase 3 (snippets, pinch) is out of this plan: `SlotAction.text` already covers custom snippets through the action picker, and pinch is a second route to a slider that already exists. |
| 10, not building | No task adds per-language layouts, sharing, theming, plane character editing, split keyboard or a free canvas. |

**Known deviations from the spec, deliberate**

- The spec's "32pt minimum key width" rail is not implemented as its own check. With widths floored at `1.0x` no slider value can trip it, and a crowded row is caught by `rowTooWide`. Adding a device-width-dependent check to a validator that runs in the app, where the keyboard's width is not known, would be a rule that fires in the wrong process.
- `MockTextTarget.adjustTextPosition` stays a no-op, so the cursor keys do nothing in the in-app playground. Giving it a real cursor would change `documentContextAfterInput` for every AI action that reads it, which is out of scope. `RecordingTextTarget` in the tests covers the behaviour.
- The spec put `LayoutEditorModel` in the app target. Task 9 moves it to `AIKeyboardCore` so `AIKeyboardCoreTests` can drive every edit without a view.

**Type consistency checked:** `KeyboardCustomization.default`, `LayoutPreset.named(_:)`, `LayoutValidator.issues(in:showsGlobe:)`, `LayoutValidator.isUsable(_:showsGlobe:)`, `LayoutValidator.canRemove(_:from:showsGlobe:)`, `KeyboardLayout.rows(for:plane:showsGlobe:customization:)`, `Theme.Metrics.keyAreaHeight(for:)`, `Theme.Metrics.totalHeight(for:withContextStrip:)`, `SharedStore.decodeLayout(from:)`, `SharedStore.layoutKey`, `KeyboardController.apply(_:)`, `KeyboardController.reloadCustomization()`, `LayoutEditorModel.RowKind`, `LayoutEditorModel.insertionIndex(at:in:)` are each defined once and referred to with the same signature everywhere.
