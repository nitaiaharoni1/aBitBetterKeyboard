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
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Text.secondary)
                    Spacer()
                    Button("Reset") { model.reset() }
                        .font(Theme.Fonts.caption.weight(.semibold))
                        .accessibilityIdentifier("layout-reset")
                }
                .padding(.horizontal, Theme.Space.xxs)
            }
        }
    }

    private func presetCard(_ preset: LayoutPreset) -> some View {
        let isSelected = model.draft.preset == preset.id
        return Button {
            model.apply(preset: preset)
        } label: {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                LayoutThumbnail(layout: preset.customization)
                    .frame(width: 96, height: 58)
                Text(preset.name)
                    .font(Theme.Fonts.caption.weight(.semibold))
                    .foregroundStyle(Theme.Text.primary)
                Text(preset.summary)
                    .font(Theme.Fonts.micro)
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
                        isSelected ? Theme.Brand.solid : Theme.Surface.separator,
                        lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("preset-\(preset.id)")
        .accessibilityLabel(preset.name)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityHint(preset.summary)
    }
}
