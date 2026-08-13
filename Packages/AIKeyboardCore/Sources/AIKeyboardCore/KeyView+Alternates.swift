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
    ///
    /// The bottom-row full stop is the exception: its list is SwiftKey's order,
    /// with the period in the middle rather than first. Resting still keeps the
    /// period because `alternateRestIndex` names it, not slot 0.
    var alternateItems: [String] {
        if spec.cap == .quickTone { return toneAlternates }
        guard case .character(let value) = spec.cap else { return [] }
        if spec.addressableID == KeyboardLayout.punctuationKeyID {
            return spec.alternates
        }
        let base = shift.isUppercase ? language.uppercased(value) : value
        return [base]
            + spec.alternates.map { shift.isUppercase ? language.uppercased($0) : $0 }
    }

    /// The item a standing finger is choosing: the character this key already typed.
    ///
    /// Slot 0 for every letter and for the rewrite registers. The punctuation
    /// popup puts the period later in the strip so the question mark can sit to
    /// its right, so resting has to name that later slot or a hold-and-lift would
    /// swap `.` for `!`.
    var alternateRestIndex: Int {
        guard case .character(let value) = spec.cap else { return 0 }
        let base = shift.isUppercase ? language.uppercased(value) : value
        return alternateItems.firstIndex(of: base) ?? 0
    }

    /// Popup items a VoiceOver action can pick: everything except the rest item.
    ///
    /// Slot 0 is that item for letters, so this is `dropFirst` there. The period
    /// popup puts `.` later, and skipping slot 0 would hide `!` and offer a
    /// second period.
    var alternatePickerItems: [String] {
        zip(alternateItems.indices, alternateItems).compactMap { index, item in
            index == alternateRestIndex ? nil : item
        }
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
        if spec.cap != .quickTone { onPress(spec.cap, CGPoint(x: 0.5, y: 0.5)) }
        onAlternate?(item)
    }

    /// How long the finger stays down before the popup opens.
    ///
    /// **One number for every key that has a popup.** The press callout now
    /// fills the wait — letters preview on finger-down even when they have
    /// alternates — so this is no longer covering a blank space above the key.
    /// 200ms is still under the quarter second a pause becomes visible at, and
    /// still well over the 60–120ms a deliberate tap lasts.
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

    var alternatesWidth: CGFloat {
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
    /// A row is centred on the key, then shifted by `alternatesStripOffset` so a
    /// strip that would draw past the keyboard stays inside it. The period popup
    /// is also aligned so the period sits over the key. A stack sits directly
    /// above the key: its bottom edge is 6 points above the key's top, so it
    /// spans `-(6 + height)` to `-6` and the index runs downward from there.
    func alternateIndex(
        at point: CGPoint, keyMinX: CGFloat = 0, canvasWidth: CGFloat = 0
    ) -> Int {
        let index: Int
        if alternatesAreStacked {
            index = Int(((point.y + 6 + alternatesHeight) / alternateItemHeight).rounded(.down))
        } else {
            let overhang = (alternatesWidth - width) / 2
            let dx = alternatesStripOffset(keyMinX: keyMinX, canvasWidth: canvasWidth)
            index = Int(((point.x + overhang - dx) / alternateItemWidth).rounded(.down))
        }
        return min(max(index, 0), max(0, alternateItems.count - 1))
    }

    /// Extra x after SwiftUI centres a wider strip on the key.
    ///
    /// The period popup aligns the period to the key (SwiftKey's shape) rather
    /// than leaving it on the left of a centred strip. Every horizontal popup is
    /// then clamped so its rounded corners stay inside the keyboard. Hit-testing
    /// uses this same value; a visual shift that `alternateIndex` does not know
    /// about is how a lift on `.` used to pick `,`. `keyMinX` is the key's
    /// left edge in the same space as `canvasWidth` (screen x minus the grid's
    /// origin). A named-space x of 0 is how a Hebrew period key used to shove
    /// this strip off the right edge.
    func alternatesStripOffset(keyMinX: CGFloat, canvasWidth: CGFloat) -> CGFloat {
        guard !alternatesAreStacked else { return 0 }
        var dx: CGFloat = 0
        if spec.addressableID == KeyboardLayout.punctuationKeyID {
            dx = alternatesWidth / 2 - (CGFloat(alternateRestIndex) + 0.5) * alternateItemWidth
        }
        guard canvasWidth > 0 else { return dx }
        let margin = Theme.Radius.chip
        let centeredLeading = keyMinX + (width - alternatesWidth) / 2
        var leading = centeredLeading + dx
        if leading < margin {
            dx += margin - leading
            leading = centeredLeading + dx
        }
        let trailing = leading + alternatesWidth
        let limit = canvasWidth - margin
        if trailing > limit {
            dx -= trailing - limit
        }
        return dx
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
            .offset(
                x: alternatesStripOffset(keyMinX: keyMinXInCanvas, canvasWidth: keyboardCanvasWidth),
                y: -height - 6
            )
            .allowsHitTesting(false)
            .transition(Theme.Motion.pop(reduceMotion: reduceMotion))
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
