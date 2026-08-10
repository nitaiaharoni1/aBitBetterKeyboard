import SwiftUI

extension KeyView {

    // MARK: Alternates

    /// What the popup offers: the key's own character first, then its alternates.
    ///
    /// The character itself leads so that lifting a finger that has not moved
    /// commits nothing new — a long press that the user did not follow through on
    /// must not silently swap the letter they already typed.
    ///
    /// A letter offers its own character and then its accents. The one-tap rewrite
    /// key offers the registers, which arrive already ordered with the default
    /// first — see `KeyboardController.toneAlternates` for why that order is not
    /// cosmetic.
    var alternateItems: [String] {
        if spec.cap == .quickTone { return toneAlternates }
        guard case .character(let value) = spec.cap else { return [] }
        let base = shift.isUppercase ? language.uppercased(value) : value
        return [base]
            + spec.alternates.map { shift.isUppercase ? language.uppercased($0) : $0 }
    }

    /// **Words stack, glyphs run along a row.** Seven registers at a readable size
    /// is about 1,000 points of width on a 393-point screen, so the strip that
    /// works for five accented `e`s cannot hold them. Stacking also puts the list
    /// where the thumb already is: this key is in the action row at the bottom of
    /// the keyboard, so the popup opens upward over the keys, which is empty space
    /// for as long as the finger is down.
    private var alternatesAreStacked: Bool { spec.cap == .quickTone }

    private var alternateItemWidth: CGFloat { alternatesAreStacked ? 156 : max(width, 34) }
    private var alternateItemHeight: CGFloat {
        alternatesAreStacked ? 34 : height * 1.15
    }

    private var alternatesWidth: CGFloat {
        alternatesAreStacked
            ? alternateItemWidth
            : alternateItemWidth * CGFloat(max(1, alternateItems.count))
    }

    private var alternatesHeight: CGFloat {
        alternatesAreStacked
            ? alternateItemHeight * CGFloat(max(1, alternateItems.count))
            : alternateItemHeight
    }

    /// Which item the finger is over, in the key's own coordinate space.
    ///
    /// A row is centred on the key, so its leading edge sits half its overhang to
    /// the left of x = 0. A stack sits directly above the key: its bottom edge is
    /// 6 points above the key's top, so it spans `-(6 + height)` to `-6` and the
    /// index runs downward from there.
    func alternateIndex(at point: CGPoint) -> Int {
        let index: Int
        if alternatesAreStacked {
            index = Int(((point.y + 6 + alternatesHeight) / alternateItemHeight).rounded(.down))
        } else {
            let overhang = (alternatesWidth - width) / 2
            index = Int(((point.x + overhang) / alternateItemWidth).rounded(.down))
        }
        return min(max(index, 0), max(0, alternateItems.count - 1))
    }

    @ViewBuilder
    var alternatesPopup: some View {
        if showsAlternates, alternateItems.count > 1 {
            Group {
                if alternatesAreStacked {
                    VStack(spacing: 0) {
                        ForEach(Array(alternateItems.enumerated()), id: \.offset) { index, item in
                            alternateItem(item, index: index)
                        }
                    }
                } else {
                    HStack(spacing: 0) {
                        ForEach(Array(alternateItems.enumerated()), id: \.offset) { index, item in
                            alternateItem(item, index: index)
                        }
                    }
                }
            }
            // Laid out left to right whatever the keyboard's direction, because
            // `alternateIndex(at:)` reads a raw coordinate and a mirrored stack
            // would put item 0 under the far end of it.
            .environment(\.layoutDirection, .leftToRight)
            .frame(width: alternatesWidth, height: alternatesHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(Theme.Keys.letter)
                    .shadow(color: Theme.Keys.shadow.opacity(0.35), radius: 5, y: 2)
            )
            .offset(y: -height - 6)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    private func alternateItem(_ item: String, index: Int) -> some View {
        Text(item)
            .font(
                alternatesAreStacked
                    ? .system(size: 15, weight: .regular) : .system(size: 24, weight: .light)
            )
            .foregroundStyle(index == selectedAlternate ? Theme.Text.onBrand : Theme.Keys.label)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: alternateItemWidth, height: alternateItemHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.key, style: .continuous)
                    .fill(index == selectedAlternate ? Theme.Brand.solid : Color.clear)
            )
    }
}
