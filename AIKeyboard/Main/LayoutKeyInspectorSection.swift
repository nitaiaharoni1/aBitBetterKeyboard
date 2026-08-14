import AIKeyboardCore
import SwiftUI

/// Slim dock under the canvas. Width is the handle on the key. This row
/// names the value and keeps fill, action, and remove without covering keys.
struct LayoutKeyInspectorSection: View {
    @ObservedObject var model: LayoutEditorModel
    let slot: SlotSpec

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
                .disabled(resizing)
                .accessibilityIdentifier("inspector-fill")
            }
            actionMenu
                .disabled(resizing)
            if verdict.isAllowed {
                Button("Remove", role: .destructive) { model.remove(slot) }
                    .font(Theme.Fonts.callout)
                    .disabled(resizing)
                    .accessibilityIdentifier("inspector-remove")
            }
            Button("Done") { dismiss() }
                .font(Theme.Fonts.caption.weight(.semibold))
                .accessibilityIdentifier("inspector-done")
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, Theme.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.key, style: .continuous)
                .fill(Theme.Surface.elevated)
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

    private var actionMenu: some View {
        let kind = model.rowKind(of: slot) ?? .bottom
        let options = model.catalogue(for: kind)
        let all = options.contains(slot.action) ? options : [slot.action] + options
        return Menu {
            ForEach(all, id: \.self) { action in
                Button(action.title) { model.setAction(action, for: slot) }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(Theme.Fonts.callout)
                .foregroundStyle(Theme.Brand.solid)
        }
        .accessibilityLabel("Action")
        .accessibilityIdentifier("inspector-action")
    }

    private func dismiss() {
        if let id = model.resize?.slotID { model.endResize(for: id) }
        model.selection = nil
    }
}
