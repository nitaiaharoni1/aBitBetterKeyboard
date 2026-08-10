import AIKeyboardCore
import SwiftUI

/// The per-row key lists: one card per row, each key showing name, width, and
/// move-left/move-right controls. VoiceOver users rearrange the keyboard here;
/// drag-and-drop on the canvas is an overlay over the same model.
struct LayoutRowsSection: View {
    @ObservedObject var model: LayoutEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            ForEach(model.visibleRows, id: \.self) { kind in
                rowEditor(kind)
            }
        }
    }

    private func rowEditor(_ kind: LayoutEditorModel.RowKind) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: kind.title)
            Card {
                VStack(spacing: Theme.Space.xs) {
                    if model.row(kind).isEmpty {
                        Text("No keys here.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Text.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(model.row(kind)) { slot in
                        keyRow(slot, in: kind)
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
                    SlotGlyphView(action: slot.action).frame(width: 22)
                    Text(slot.action.title)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Text.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(widthLabel(slot.width))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.Text.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(slot.action.title), key \(position) of \(keys.count)")
            .accessibilityValue(widthLabel(slot.width))
            .accessibilityHint("Opens this key's settings")

            // **Not only a drag.** These two buttons are the whole reason a
            // VoiceOver user can rearrange the keyboard at all.
            Button {
                model.move(slot, by: -1)
            } label: {
                Image(systemName: "arrow.left").font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(position == 1 ? Theme.Text.tertiary : Theme.Brand.solid)
            .disabled(position == 1)
            .accessibilityLabel("Move \(slot.action.title) left")

            Button {
                model.move(slot, by: 1)
            } label: {
                Image(systemName: "arrow.right").font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(position == keys.count ? Theme.Text.tertiary : Theme.Brand.solid)
            .disabled(position == keys.count)
            .accessibilityLabel("Move \(slot.action.title) right")
        }
        .accessibilityIdentifier("slot-\(slot.action.title)")
    }

    static func widthLabel(_ width: SlotWidth) -> String {
        switch width {
        case .fill: return "Fill"
        case .units(let value): return String(format: "%.1fx", value)
        }
    }

    private func widthLabel(_ width: SlotWidth) -> String {
        LayoutRowsSection.widthLabel(width)
    }
}
