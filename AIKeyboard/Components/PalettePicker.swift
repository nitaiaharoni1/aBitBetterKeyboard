import AIKeyboardCore
import SwiftUI

/// One implementation shared by onboarding and Keys › Look, because two
/// pickers for one setting drift.
///
/// The caller supplies the `Card`. Swatches each draw their own palette's
/// gradient. The preview strip reads `Theme.Brand` because it previews
/// the chosen one.
struct PalettePicker: View {
    @EnvironmentObject private var store: SharedStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: 0) {
                ForEach(BrandPalette.allCases, id: \.self) { palette in
                    swatch(palette)
                    if palette != BrandPalette.allCases.last {
                        Spacer()
                    }
                }
            }
            .padding(5)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.brandPalette.title)
                        .font(Theme.Fonts.callout.weight(.semibold))
                        .foregroundStyle(store.brandPalette.color(.solid))
                    Text(store.brandPalette.subtitle)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)

                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: "sparkles")
                        .font(Theme.Glyph.medium(14))
                        .foregroundStyle(Theme.Text.onBrand)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Theme.Brand.gradient)
                        )

                    Image(systemName: "return")
                        .font(Theme.Glyph.medium(13))
                        .foregroundStyle(Theme.Text.onBrand)
                        .frame(width: 40, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.key, style: .continuous)
                                .fill(Theme.Brand.action)
                        )

                    Text("Aa")
                        .font(Theme.Fonts.headline)
                        .foregroundStyle(Theme.Brand.solid)
                }
                .accessibilityHidden(true)
            }
        }
    }

    private func swatch(_ palette: BrandPalette) -> some View {
        let isSelected = palette == store.brandPalette
        return Button {
            guard palette != store.brandPalette else { return }
            Feedback.actionPress()
            withAnimation(Theme.Motion.quick) { store.brandPalette = palette }
        } label: {
            Circle()
                .fill(palette.gradient)
                .frame(width: 44, height: 44)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Theme.Text.onBrand)
                    }
                }
                .overlay {
                    if isSelected {
                        Circle()
                            .strokeBorder(palette.color(.solid), lineWidth: 2.5)
                            .padding(-5)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .pressable()
        .accessibilityLabel("\(palette.title). \(palette.subtitle)")
        .accessibilityIdentifier("palette-\(palette.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
