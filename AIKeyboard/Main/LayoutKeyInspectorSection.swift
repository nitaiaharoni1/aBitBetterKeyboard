import AIKeyboardCore
import SwiftUI

/// The selected key, in the shelf band directly above the keyboard. Width is
/// the handle on the key itself; this row names the value and keeps fill,
/// action and remove without covering a single key.
///
/// **Sized to `LayoutView.contextBandHeight` rather than to its contents.** The
/// band is fixed so that selecting a key cannot shunt the spare-key tray under
/// the thumb that was reaching for it. That fixes the height budget for
/// everything in here: `xs` padding rather than `sm`, and a `minHeight: 44` on
/// each control so the row still clears the touch-target floor inside it.
///
/// **`Toggle` is greedy in an `HStack`** — its style puts a spacer between the
/// label and the switch and expands to whatever it is offered — so the Fill
/// switch is `fixedSize`d. Without it, it eats the width the key's name needs
/// and truncates a title the user just tapped to read.
struct LayoutKeyInspectorSection: View {
    @ObservedObject var model: LayoutEditorModel
    let slot: SlotSpec
    /// What this key measures on the canvas below, which is what decides whether
    /// its name fits. Read off the frames the keyboard published rather than
    /// derived from `slot.width`, for the reason `LayoutEditorModel.drawsLabel`
    /// gives: a slot is units, and whether units clear the caption floor depends
    /// on the phone and the language.
    let drawnWidth: CGFloat

    var body: some View {
        let verdict = model.canRemove(slot)
        let resizing = model.resize != nil
        return HStack(spacing: Theme.Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.action.title)
                    .font(Theme.Fonts.body.weight(.semibold))
                    .foregroundStyle(Theme.Text.primary)
                    .lineLimit(1)
                Text(widthLabel)
                    .font(Theme.Fonts.caption.monospaced())
                    .foregroundStyle(Theme.Text.secondary)
                    .accessibilityIdentifier("inspector-width")
            }
            Spacer(minLength: Theme.Space.sm)
            if model.canResize(slot) {
                Toggle(
                    "Fill",
                    isOn: Binding(
                        get: { slot.width == .fill },
                        set: { model.setWidth($0 ? .fill : .units(fallbackUnits), for: slot) })
                )
                .font(Theme.Fonts.callout)
                .fixedSize()
                .frame(minHeight: 44)
                .disabled(resizing)
                .accessibilityIdentifier("inspector-fill")
            }
            optionsMenu
                .frame(minWidth: 44, minHeight: 44)
                .disabled(resizing)
            if verdict.isAllowed {
                Button("Remove", role: .destructive) { model.remove(slot) }
                    .font(Theme.Fonts.callout)
                    .frame(minHeight: 44)
                    .disabled(resizing)
                    .accessibilityIdentifier("inspector-remove")
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.Text.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier("inspector-done")
        }
        .padding(.leading, Theme.Space.sm)
        // The close button carries its own 44 pt target, so the card's own
        // trailing gutter is what is left after that target's built-in margin.
        .padding(.trailing, Theme.Space.xxs)
        .padding(.vertical, Theme.Space.xs)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .fill(Theme.Keys.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .strokeBorder(Theme.Surface.separator, lineWidth: 1)
        )
    }

    private var widthLabel: String {
        if case .units(let value) = slot.width {
            return String(format: "%g×", value)
        }
        return "Fill"
    }

    private var fallbackUnits: CGFloat {
        if case .units(let value) = slot.width { return value }
        return 1
    }

    /// **The label switch lives in here rather than beside Fill, and the reason
    /// is arithmetic.** This band is `LayoutView.contextBandHeight` tall and one
    /// row wide: on a 375 pt phone the Fill toggle, the menu, Remove and Close
    /// already claim about 310 of the 327 points inside the card, which is why
    /// the key's own name is `lineLimit(1)` and why the file's header warns that
    /// a greedy `Toggle` truncates the title the user just tapped to read. A
    /// second switch of the same shape would leave nothing for the name at all.
    /// A `Toggle` inside a menu costs no width, and "what this key does" and
    /// "what this key says" belong to each other.
    private var optionsMenu: some View {
        let kind = model.rowKind(of: slot) ?? .bottom
        let options = model.catalogue(for: kind)
        let all = options.contains(slot.action) ? options : [slot.action] + options
        return Menu {
            // Only the six keys that draw a name under a glyph. Everywhere else
            // the cap *is* the label, and hiding it would leave a blank key.
            // Bare, with no identifier of its own: a menu accepts `Button`,
            // `Toggle`, `Picker`, `Divider`, `Section` and `Menu`, and a modifier
            // on one of them is at best erased. XCUITest addresses a menu item by
            // its label anyway.
            if slot.action.hasLabel {
                Toggle(
                    "Show label",
                    isOn: Binding(
                        get: { model.drawsLabel(slot, drawnWidth: drawnWidth) },
                        set: { model.setShowsLabel($0, for: slot) })
                )
            }
            Section("Action") {
                ForEach(all, id: \.self) { action in
                    Button(action.title) { model.setAction(action, for: slot) }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(Theme.Fonts.callout)
                .foregroundStyle(Theme.Brand.solid)
        }
        .accessibilityLabel("Options")
        .accessibilityIdentifier("inspector-options")
    }

    private func dismiss() {
        if let id = model.resize?.slotID { model.endResize(for: id) }
        model.selection = nil
    }
}
