import Foundation

/// A named shape for the keyboard.
///
/// Five, and one-handed reach is deliberately not among them: it composes with
/// all five, and a user who wants "Power, one-handed" should not have to pick
/// between the two. `testNoPresetIsOneHanded` fails if that ever drifts.
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
            summary: "Number row, arrows, comma and question mark",
            customization: {
                var layout = base("power", geometry: .default)
                layout.showsNumberRow = true
                // **Two real keys instead of one key that opened a list.** The
                // shipped default carries Reply, Fix and Rewrite in the action row
                // and nothing in the bar; this preset spends that row on arrows, so
                // without these a user picking "Power" loses every route to the AI
                // actions at once and has no way to tell that is what happened. It
                // used to be a single sparkle opening `AIMenuPanel`; that panel is
                // deleted, because a list drawn over the keys is the thing this
                // keyboard stopped doing. `ai-first` keeps its own way in.
                layout.barTrailing = [
                    SlotSpec(action: .reply),
                    SlotSpec(action: .quickTone)
                ]
                // No full stop here: the bottom row already carries the script's
                // own punctuation key, with the other four marks behind a long
                // press. A second one would be a duplicate that is also worse.
                layout.cursorRow = [
                    SlotSpec(action: .cursorLeft, width: .fill),
                    SlotSpec(action: .cursorRight, width: .fill),
                    SlotSpec(action: .text(","), width: .fill),
                    SlotSpec(action: .text("?"), width: .fill),
                    SlotSpec(action: .hideKeyboard, width: .fill)
                ]
                return layout
            }()),

        LayoutPreset(
            id: "ai-first",
            name: "AI first",
            summary: "Reply in the grid, rewrite in the bar",
            customization: {
                var layout = base("ai-first", geometry: .default)
                // Reply moves into the grid, where a thumb already is, and the
                // bar keeps the one-tap rewrite. That also separates the two AI
                // controls, which `SuggestionBar`'s own comment records as having
                // been unreadable side by side: two brand-tinted buttons with no
                // rule between them, one wearing `sparkle` and the other
                // `sparkles`. This slot was that sparkle until the menu behind it
                // was deleted.
                layout.barTrailing = [SlotSpec(action: .quickTone)]
                layout.bottomRow = [
                    SlotSpec(action: .numbersPlane, width: .units(1.3)),
                    SlotSpec(action: .globe, width: .units(1.0)),
                    SlotSpec(action: .reply, width: .units(1.2)),
                    SlotSpec(action: .space, width: .fill),
                    SlotSpec(action: .dictation, width: .units(1.0)),
                    SlotSpec(action: .punctuation, width: .units(1.0)),
                    SlotSpec(action: .ret, width: .units(1.8))
                ]
                return layout
            }())
    ]

    /// The default layout, restamped with another preset's name and geometry.
    ///
    /// Every preset starts from the shipped one so that a change to the default's
    /// bottom row reaches all five rather than four of them and one that quietly
    /// froze.
    private static func base(_ id: String, geometry: LayoutGeometry) -> KeyboardCustomization {
        var layout = KeyboardCustomization.default
        layout.preset = id
        layout.basedOn = id
        layout.geometry = geometry
        return layout
    }
}
