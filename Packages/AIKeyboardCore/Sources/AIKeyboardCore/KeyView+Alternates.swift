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

    /// Whether holding this key offers anything. Most keys have nothing.
    var hasAlternates: Bool { onAlternate != nil && alternateItems.count > 1 }

    /// What the popup draws for an item, which is the item itself except once.
    ///
    /// **Persian's half-space is the only alternate with nothing to show.**
    /// U+200C has no width and does not join, so `ی` and `ی‌` are the same
    /// picture: the popup would offer the same glyph twice and the second chip
    /// would look like a bug. It is drawn as `␣`, the standard symbol for a
    /// space, because that is what the mark is called on a Persian keyboard —
    /// نیم‌فاصله, half-space — and what is *inserted* is still U+200C. Nothing
    /// else in any of the sixty-four layouts is invisible, so this is a
    /// substitution rather than a labelling system.
    func displayLabel(_ item: String) -> String {
        item.replacingOccurrences(of: "\u{200C}", with: "\u{2423}")
    }

    /// What VoiceOver calls the action that picks one item out of the popup.
    func alternateActionLabel(_ item: String) -> String {
        spec.cap == .quickTone ? "Rewrite as \(item)" : "Insert \(displayLabel(item))"
    }

    /// Picking an item without the press that normally precedes it.
    ///
    /// **The press has to be replayed, and leaving it out deletes the user's
    /// text.** `KeyboardView.alternateHandler` is written for the gesture, where
    /// the key has *already inserted* its character on finger-down, so picking an
    /// alternate is delete-then-retype. A VoiceOver action arrives with no
    /// finger-down behind it, so that delete would land on whatever the user
    /// wrote last. Replaying the press costs one insert nobody sees and keeps a
    /// single implementation of what an alternate means.
    ///
    /// The one-tap rewrite key is the exception in the other direction: it
    /// deliberately runs nothing on press (see `runsOnLift`), so its handler has
    /// nothing to undo and must not be given anything to undo.
    func commitAlternate(_ item: String) {
        if spec.cap != .quickTone { onPress(spec.cap) }
        onAlternate?(item)
    }

    /// How long the finger stays down before the popup opens.
    ///
    /// **One number for every key that has a popup, and it is short because
    /// nothing is on screen during it.** It used to be three, and the longest of
    /// them — 450ms for a letter — was paid for by the press callout filling the
    /// wait. A key with alternates has no callout now (`showsCharacterCallout`),
    /// so a long hold is a hold against a blank space above the key, which reads
    /// as a keyboard that has not noticed the finger. 200ms is under the quarter
    /// second a pause becomes visible at, and still well over the 60–120ms a
    /// deliberate tap lasts.
    ///
    /// **Not zero, and that is the whole reason there is a number at all.**
    /// Opening on finger-down puts the popup on screen for the length of every
    /// ordinary keystroke, which is what showing Hebrew's two-item popup from the
    /// press looked like before it was pulled.
    static let alternatesDelay: Duration = .milliseconds(200)

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
        let isSelected = index == selectedAlternate
        return Text(displayLabel(item))
            .font(
                alternatesAreStacked
                    ? .system(size: 15, weight: .regular) : .system(size: 24, weight: .light)
            )
            .foregroundStyle(isSelected ? Theme.Text.onBrand : Theme.Keys.label)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: alternateItemWidth, height: alternateItemHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.key, style: .continuous)
                    .fill(isSelected ? Theme.Brand.solid : Color.clear)
            )
    }
}
