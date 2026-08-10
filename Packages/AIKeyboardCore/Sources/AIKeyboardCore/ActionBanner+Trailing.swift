import SwiftUI

extension ActionBanner {

    // MARK: The button on the right

    @ViewBuilder
    var trailing: some View {
        switch state {
        case .hint, .context, .working:
            EmptyView()

        case .options(_, let options, let index):
            HStack(spacing: Theme.Space.xxs) {
                if options.count > 1 { pager(count: options.count, index: index) }
                button("Use", tint: Theme.Brand.gradient, filled: true) {
                    controller.useBannerOption()
                }
                .accessibilityIdentifier("banner-use")
            }

        case .failed:
            button("Dismiss", tint: nil, filled: false) { controller.clearBanner() }
                .accessibilityIdentifier("banner-dismiss")

        case .blocked(let block):
            switch block.remedy {
            case .none:
                button("Dismiss", tint: nil, filled: false) { controller.clearBanner() }
                    .accessibilityIdentifier("banner-blocked-dismiss")
            case .broadcastPicker:
                pickerChip(block)
            }

        case .dictating(_, let isListening):
            button(
                isListening ? "Stop" : "Cancel",
                tint: LinearGradient(
                    colors: [Theme.Semantic.record, Theme.Semantic.record],
                    startPoint: .top, endPoint: .bottom),
                filled: true
            ) {
                controller.stopDictation(insert: isListening)
            }
            .accessibilityIdentifier("banner-stop")

        case .dictationFailed:
            // `stopDictation(insert: false)` rather than `clearBanner`: the reason
            // lives on the session, not on the banner, so clearing this side of it
            // would leave the sentence to reappear on the next tick.
            button("Dismiss", tint: nil, filled: false) {
                controller.stopDictation(insert: false)
            }
            .accessibilityIdentifier("banner-dictation-dismiss")
        }
    }

    /// Which of the answers is showing. Tappable as well as swipeable, because a
    /// swipe on a 56pt strip sitting directly above the keys competes with the
    /// scroll of whatever the host app is showing, and because a dot is the only
    /// part of this a VoiceOver user can address.
    func pager(count: Int, index: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { slot in
                Button {
                    controller.showBannerOption(slot)
                } label: {
                    Circle()
                        .fill(
                            slot == index
                                ? Theme.Brand.solid : Theme.Keys.secondaryLabel.opacity(0.35)
                        )
                        .frame(width: 6, height: 6)
                        .frame(width: 16, height: 28)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Option \(slot + 1) of \(count)")
                .accessibilityAddTraits(slot == index ? [.isSelected] : [])
            }
        }
        .accessibilityIdentifier("banner-pager")
    }

    /// Apple's own broadcast picker, sized to the strip.
    ///
    /// **The tap target is 10pt smaller than this in each dimension**, because
    /// `-[RPSystemBroadcastPickerView addBroadcastPickerButton]` insets its real
    /// `UIButton` by 5 on every edge. So 42 here is a 32pt target, against the 42 the
    /// deleted setup panel could afford at 52 — and the strip cannot grow to buy it
    /// back, because `Theme.Metrics.bannerHeight` is capped by the frame fingerprint
    /// rather than by taste. See `.claude/rules/screen-context.md`.
    ///
    /// The white-then-brand circle behind it belongs to `BroadcastPickerButton`
    /// itself and is deliberately not repeated here: the system assigns the glyph's
    /// colour from `UIScreen.main.isCaptured` and never inherits one, so that
    /// underlay is a correctness requirement rather than styling, and it lives with
    /// the view that knows it.
    func pickerChip(_ block: BannerState.Block) -> some View {
        BroadcastPickerButton(size: 42)
            .accessibilityLabel("Start screen context")
            .accessibilityHint("Opens the iOS screen broadcast picker. \(block.detail)")
            .accessibilityIdentifier("banner-start-broadcast")
    }

    /// `LinearGradient?` rather than a generic `ShapeStyle`, because the one
    /// unfilled caller passes `nil` and a generic parameter cannot be inferred
    /// from it. Every filled caller has a gradient to hand anyway: the brand one,
    /// or the flat record red spelled as a gradient of itself.
    func button(
        _ title: String, tint: LinearGradient?, filled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(filled ? Theme.Text.onBrand : Theme.Keys.label)
                .lineLimit(1)
                .padding(.horizontal, Theme.Space.sm)
                .frame(height: 32)
                .background {
                    let shape = RoundedRectangle(
                        cornerRadius: Theme.Radius.chip, style: .continuous)
                    if filled, let tint {
                        shape.fill(tint)
                    } else {
                        shape.fill(Theme.Keys.card)
                    }
                }
                .contentShape(Rectangle())
        }
        .pressable()
    }
}
