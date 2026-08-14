import SwiftUI

extension KeyView {

    // MARK: Alternates

    /// What the popup offers: the key's own character first, then its alternates.
    ///
    /// The character itself leads so that lifting a finger that has not moved
    /// commits nothing new — a long press that the user did not follow through on
    /// must not silently swap the letter they already typed.
    ///
    /// A letter offers its own character and then its accents. The rewrite key
    /// offers the registers, Fix offers its passes, and CopyClip offers recent
    /// clips, all already ordered with the rest item first — see
    /// `KeyboardController.toneAlternates`, `fixAlternates` and
    /// `copyclipAlternates` for why that order is not cosmetic.
    ///
    /// The bottom-row full stop is the exception: its list is SwiftKey's order,
    /// with the period in the middle rather than first. Resting still keeps the
    /// period because `alternateRestIndex` names it, not slot 0.
    var alternateItems: [String] {
        switch spec.cap {
        case .quickTone: return toneAlternates
        case .aiFix: return fixAlternates
        case .copyclip: return copyclipAlternates
        default: break
        }
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
        var shown = item
        if spec.cap == .copyclip, item != KeyCap.copyclip.accessibilityLabel {
            shown = Self.collapsedClipLabel(item)
        }
        return shown.replacingOccurrences(of: "\u{200C}", with: "\u{2423}")
    }

    /// 156pt row at 15pt. A 4000-character clip would scale into a smear.
    private static let clipLabelLimit = 22

    private static func collapsedClipLabel(_ text: String) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if collapsed.count <= clipLabelLimit { return collapsed }
        return String(collapsed.prefix(clipLabelLimit - 1)) + "…"
    }

    /// What VoiceOver calls the action that picks one item out of the popup.
    func alternateActionLabel(_ item: String) -> String {
        switch spec.cap {
        case .quickTone: return "Rewrite as \(item)"
        case .aiFix: return "Fix as \(item)"
        default: return "Insert \(displayLabel(item))"
        }
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
    /// The rewrite key, Fix and CopyClip are the exception in the other
    /// direction: they deliberately run nothing on press (see `runsOnLift`),
    /// so their handler has nothing to undo and must not be given anything
    /// to undo. Replaying CopyClip would toggle the panel, then insert.
    func commitAlternate(_ item: String) {
        if spec.cap != .quickTone, spec.cap != .aiFix, spec.cap != .copyclip {
            onPress(spec.cap, CGPoint(x: 0.5, y: 0.5))
        }
        onAlternate?(item)
    }

    /// How long a letter or rewrite finger stays down before the popup opens.
    ///
    /// **Not zero, and that is the whole reason there is a number at all.**
    /// Opening on finger-down puts the popup on screen for the length of every
    /// ordinary keystroke, which is what showing Hebrew's two-item popup from the
    /// press looked like before it was pulled.
    ///
    /// The press callout now fills the wait — letters preview on finger-down
    /// even when they have alternates — so this is no longer covering a blank
    /// space above the key. 200ms is still under the quarter second a pause
    /// becomes visible at, and still well over the 60–120ms a deliberate tap
    /// lasts. Punctuation waits a different number; see `alternatesHoldDelay`.
    static let alternatesDelay: Duration = .milliseconds(200)

    /// How long the bottom-row punctuation key waits before its strip opens.
    ///
    /// **The key already wears its marks, it skips the callout, and a 200ms wait
    /// is the two-step open that was pulled.** Previewing a lone period for the
    /// letter delay looked like the strip arriving after a beat. 50ms is under a
    /// typical tap (60–120ms), so a period tap may flash the strip; that is
    /// accepted. Letters stay at `alternatesDelay` so a tap on `ח` does not
    /// flash Hebrew's geresh strip.
    static let punctuationAlternatesDelay: Duration = .milliseconds(50)

    /// The wait this key actually sleeps. Punctuation is the 50ms case; every
    /// other popup (letters, rewrite, Fix) is `alternatesDelay`.
    var alternatesHoldDelay: Duration {
        spec.addressableID == KeyboardLayout.punctuationKeyID
            ? Self.punctuationAlternatesDelay
            : Self.alternatesDelay
    }

    /// **Words stack, glyphs run along a row.** Seven registers at a readable size
    /// is about 1,000 points of width on a 393-point screen, so the strip that
    /// works for five accented `e`s cannot hold them.
    ///
    /// The stack grows *down* from the key: index 0 (the rest item) sits nearest
    /// the finger and the other names drop away from it. These keys sit in the
    /// action row above the letters, so the menu covers QWERTY on purpose.
    var alternatesAreStacked: Bool {
        spec.cap == .quickTone || spec.cap == .aiFix || spec.cap == .copyclip
    }

    private var alternateItemWidth: CGFloat { alternatesAreStacked ? 156 : max(width, 34) }
    private var alternateItemHeight: CGFloat {
        alternatesAreStacked ? 34 : height * 1.15
    }

    var alternatesWidth: CGFloat {
        alternatesAreStacked
            ? alternateItemWidth
            : alternateItemWidth * CGFloat(max(1, alternateItems.count))
    }

    /// A letter strip sits above its key. A stacked menu sits below: same
    /// 6-point gap, measured from the key's bottom so the list covers the
    /// letters rather than the suggestion bar.
    var alternatesPopupOffsetY: CGFloat {
        alternatesAreStacked ? alternatesHeight + 6 : -height - 6
    }

    var alternatesPopupAlignment: Alignment { .bottom }

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
    /// below the key: its top edge is 6 points below the key's bottom, so it
    /// spans `height + 6` to `height + 6 + stackHeight`. Index 0 is the near
    /// edge (just below the key); later items are further down.
    func alternateIndex(
        at point: CGPoint, keyMinX: CGFloat = 0, canvasWidth: CGFloat = 0
    ) -> Int {
        let index: Int
        if alternatesAreStacked {
            index = Int(((point.y - height - 6) / alternateItemHeight).rounded(.down))
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
                y: alternatesPopupOffsetY
            )
            .allowsHitTesting(false)
            .transition(
                Theme.Motion.pop(
                    reduceMotion: reduceMotion,
                    anchor: alternatesAreStacked ? .top : .bottom)
            )
        }
    }

    /// SF Symbol beside a stacked row, looked up from the title the popup
    /// already uses as its identity. Letters have none.
    func stackedItemIcon(_ item: String) -> String? {
        switch spec.cap {
        case .quickTone:
            if item == ToneSetting.customTitle { return ToneSetting.customIcon }
            return ToneStyle.allCases.first { $0.title == item }?.icon
        case .aiFix:
            return FixStyle.allCases.first { $0.title == item }?.icon
        case .copyclip:
            if item == KeyCap.copyclip.accessibilityLabel { return "clipboard" }
            return "doc.plaintext"
        default:
            return nil
        }
    }

    private func alternateItem(_ item: String, index: Int) -> some View {
        let isSelected = index == selectedAlternate
        let color = isSelected ? Theme.Text.onBrand : Theme.Keys.label
        return Group {
            if alternatesAreStacked {
                HStack(spacing: Theme.Space.xs) {
                    if let glyph = stackedItemIcon(item) {
                        Image(systemName: glyph)
                            .font(Theme.Glyph.font(14))
                            .frame(width: 18)
                    }
                    Text(displayLabel(item))
                        .font(.system(size: 15, weight: .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(color)
                .padding(.horizontal, Theme.Space.sm)
            } else {
                Text(displayLabel(item))
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(width: alternateItemWidth, height: alternateItemHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.key, style: .continuous)
                .fill(isSelected ? Theme.Brand.solid : Color.clear)
        )
    }
}
