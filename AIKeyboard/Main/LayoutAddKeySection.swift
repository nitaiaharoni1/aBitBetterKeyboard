import AIKeyboardCore
import SwiftUI

/// The "Add a key" drawer. Adds to whichever row the current selection is in,
/// defaulting to the bottom row when nothing is selected.
struct LayoutAddKeySection: View {
    @ObservedObject var model: LayoutEditorModel

    var body: some View {
        let target = model.selection.flatMap { model.rowKind(of: $0) } ?? .bottom
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "Add a key")
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text("Adds to the \(target.title.lowercased()).")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Text.secondary)
                    FlowRow(spacing: Theme.Space.xs) {
                        ForEach(model.catalogue(for: target), id: \.self) { action in
                            Button {
                                model.add(action, to: target)
                            } label: {
                                HStack(spacing: Theme.Space.xxs) {
                                    SlotGlyphView(action: action)
                                    Text(action.title)
                                        .font(Theme.Fonts.micro)
                                        .foregroundStyle(Theme.Text.primary)
                                }
                                .padding(.horizontal, Theme.Space.sm)
                                .padding(.vertical, Theme.Space.xs)
                                .background(Capsule().fill(Theme.Surface.background))
                                .overlay(Capsule().strokeBorder(Theme.Surface.separator, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("add-\(action.title)")
                            .accessibilityLabel("Add \(action.title)")
                        }
                    }
                }
            }
        }
    }
}
