import AIKeyboardCore
import SwiftUI

/// Per-key inspector panel shown below the canvas when the user taps a key.
///
/// Owns width, action, move, and remove controls. Only reads `model` (no
/// canvas state) so it compiles cleanly without the `@State` vars that live on
/// `LayoutView` for the drag-and-drop overlay.
struct LayoutKeyInspectorSection: View {
    @ObservedObject var model: LayoutEditorModel
    let slot: SlotSpec

    var body: some View {
        let verdict = model.canRemove(slot)
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                SectionHeader(title: slot.action.title)
                Spacer()
                Button("Done") { model.selection = nil }
                    .font(Theme.Fonts.caption.weight(.semibold))
                    .accessibilityIdentifier("inspector-done")
            }
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    widthControl
                    Divider.themed
                    actionPicker
                    Divider.themed
                    HStack {
                        Button("Move left") { model.move(slot, by: -1) }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.Brand.solid)
                        Spacer()
                        Button("Move right") { model.move(slot, by: 1) }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.Brand.solid)
                        Spacer()
                        Button("Remove", role: .destructive) { model.remove(slot) }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.Semantic.record)
                            .opacity(verdict.isAllowed ? 1 : 0.4)
                            .disabled(!verdict.isAllowed)
                            .accessibilityIdentifier("inspector-remove")
                    }
                    .font(Theme.Fonts.callout)
                    if !verdict.isAllowed {
                        Text(verdict.reason)
                            .font(Theme.Fonts.micro)
                            .foregroundStyle(Theme.Semantic.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var widthControl: some View {
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
            .font(Theme.Fonts.body)
            .accessibilityIdentifier("inspector-fill")
            if !isFill {
                LayoutSlider(
                    title: "Width", value: units,
                    range: SlotWidth.minimumUnits...SlotWidth.maximumUnits, unit: "x",
                    identifier: "inspector-width"
                ) { model.setWidth(.units($0), for: slot) }
            }
        }
    }

    private var actionPicker: some View {
        let kind = model.rowKind(of: slot) ?? .bottom
        let options = model.catalogue(for: kind)
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
        .font(Theme.Fonts.body)
        .accessibilityIdentifier("inspector-action")
    }
}
