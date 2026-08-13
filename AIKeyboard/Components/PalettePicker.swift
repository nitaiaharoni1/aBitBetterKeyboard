import AIKeyboardCore
import SwiftUI

/// The four accent choices, as a list of rows.
///
/// One implementation for both places the choice is offered — the second
/// onboarding step and Keys › Look — because two pickers for one setting is
/// two things to keep agreeing about which palettes exist.
///
/// The caller supplies the container. Both current callers wrap this in a
/// `Card`, which is why the rows carry no background of their own.
struct PalettePicker: View {
    @EnvironmentObject private var store: SharedStore

    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            ForEach(Array(BrandPalette.allCases.enumerated()), id: \.element) { index, palette in
                if index > 0 { Divider.themed }
                row(palette)
            }
        }
    }

    private func row(_ palette: BrandPalette) -> some View {
        Button {
            guard palette != store.brandPalette else { return }
            Feedback.actionPress()
            withAnimation(Theme.Motion.quick) { store.brandPalette = palette }
        } label: {
            HStack(spacing: Theme.Space.sm) {
                swatch(palette)

                VStack(alignment: .leading, spacing: 2) {
                    Text(palette.title)
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.Text.primary)
                    Text(palette.subtitle)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Theme.Space.xs)

                tick(palette)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pressable()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("palette-\(palette.rawValue)")
        .accessibilityLabel("\(palette.title). \(palette.subtitle)")
        .accessibilityAddTraits(palette == store.brandPalette ? [.isButton, .isSelected] : .isButton)
    }

    /// The AI gradient under the glyph that actually wears it, at the size of an
    /// `IconBadge`, so the preview is the product rather than a colour chip.
    ///
    /// **Every row names its own palette rather than reading `Theme.Brand`**,
    /// which would give four identical swatches in whichever colour is currently
    /// chosen. It is still the honest preview: `BrandPalette.gradient` is built
    /// exactly the way `Theme.Brand.gradient` is, from the same two roles, so
    /// there is no second copy of a hex here to drift.
    private func swatch(_ palette: BrandPalette) -> some View {
        Image(systemName: "sparkles")
            .font(Theme.Glyph.medium(16))
            .foregroundStyle(Theme.Text.onBrand)
            .frame(width: 36, height: 36)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(palette.gradient)
            )
    }

    private func tick(_ palette: BrandPalette) -> some View {
        let isSelected = palette == store.brandPalette
        return Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22, weight: isSelected ? .semibold : .light))
            .foregroundStyle(isSelected ? palette.color(.solid) : Theme.Surface.separator)
    }
}
