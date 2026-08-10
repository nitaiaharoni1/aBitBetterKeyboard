import AIKeyboardCore
import SwiftUI

/// The horizontal preset strip and "Custom, from …" reset bar.
struct LayoutPresetSection: View {
    @ObservedObject var model: LayoutEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "Presets")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.sm) {
                    ForEach(LayoutPreset.all) { preset in
                        presetCard(preset)
                    }
                }
                .padding(2)
            }
            if model.draft.preset == nil, let base = LayoutPreset.named(model.draft.basedOn) {
                HStack {
                    Text("Custom, from \(base.name)")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Text.secondary)
                    Spacer()
                    Button("Reset") { model.reset() }
                        .font(.system(size: 13, weight: .semibold))
                        .accessibilityIdentifier("layout-reset")
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
                    .frame(width: 96, height: 58)
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
                    .fill(Theme.Surface.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? AnyShapeStyle(Theme.Brand.gradient) : AnyShapeStyle(Color.clear),
                        lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("preset-\(preset.id)")
        .accessibilityLabel(preset.name)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityHint(preset.summary)
    }
}
